<#
.SYNOPSIS
  NON-ELEVATED SIDE. Ask the elevated `innovation-loop-api` task to deploy or roll back the API, wait for
  its result, and do the git half (revert on main) itself.

.DESCRIPTION
  The loop session is not elevated, so it cannot stop/start the service. Instead this script:
  1. writes ~\.innovation-loop\api-queue\request.json  {mode, issue, sha, requestedAt, nonce, dryRun}
     (atomically: temp file + rename). No paths, no script names, no arguments: just data.
  2. starts the pre-registered task:  schtasks /run /tn innovation-loop-api
     (the task's action is fixed: api-runner.ps1 from C:\ProgramData\innovation-loop-api\bin)
  3. polls C:\ProgramData\innovation-loop-api\results\<nonce>.json until it appears or -TimeoutMinutes
  4. deploy that ended "rolled back" (2): reverts -Sha on main here, non-elevated (Render follows main)
     rollback with -RevertSha: after the jar is restored, reverts that sha on main here
     revert-only: no elevated step at all; just the revert on main

  Modes: deploy (needs -Sha = the merge commit, which must be the tip of API origin/main),
         rollback (restores the jar backed up by the last deploy; optional -RevertSha),
         revert-only (needs -Sha), noop (tests the trigger path; nothing runs elevated but validation).

.EXIT CODES
  0 done | 1 rejected / precondition failed (nothing changed) | 2 deploy failed, jar rolled back AND main
  reverted | 3 rollback or revert failed: human needed | 4 build failed, nothing live changed
  5 no result in time (task disabled/missing or still running): check before retrying
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('deploy', 'rollback', 'revert-only', 'noop')][string]$Mode,
    [int]$Issue = 0,
    [string]$Sha = '',
    [string]$RevertSha = '',
    [switch]$DryRun,
    [int]$TimeoutMinutes = 45,
    [string]$TaskName = 'innovation-loop-api',
    [string]$ApiRoot = 'C:\ProgramData\innovation-loop-api'
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog "api-request-$Mode"
$EXIT_TIMEOUT = 5

function Invoke-LocalRevert {
    param([string]$What)
    try { Invoke-RevertOnMain -Repo $script:ApiClone -Sha $What; return $true }
    catch { Write-Log "revert of $What on API main failed: $_" 'ERROR'; return $false }
}
function Resolve-ApiSha {
    param([string]$S)
    if ($S -notmatch '^[0-9a-f]{7,40}$') { throw "bad sha '$S'" }
    Invoke-Git -Repo $script:ApiClone -Arguments @('fetch', 'origin', '--prune') | Out-Null
    return (Get-GitValue -Repo $script:ApiClone -Arguments @('rev-parse', "$S^{commit}"))
}

try {
    if ($Mode -eq 'revert-only') {
        if (-not $Sha) { throw '-Sha is required for revert-only' }
        if (Invoke-LocalRevert $Sha) { Write-Output 'API-REQUEST revert-only OK'; exit 0 }
        Write-Output 'API-REQUEST revert-only FAILED'; exit $script:EXIT_ROLLBACK_FAILED
    }
    if ($Mode -eq 'deploy') {
        if (-not $Sha) { throw '-Sha (the API merge commit) is required for deploy' }
        $Sha = Resolve-ApiSha $Sha
    } elseif ($Sha) { throw '-Sha is only for deploy and revert-only (use -RevertSha with rollback)' }
    if ($RevertSha) { $RevertSha = Resolve-ApiSha $RevertSha }

    $queue = Join-Path $script:LoopHome 'api-queue'
    if (-not (Test-Path -LiteralPath $queue)) { New-Item -ItemType Directory -Path $queue | Out-Null }
    $nonce = [guid]::NewGuid().ToString()
    $req = [ordered]@{ mode = $Mode; issue = $Issue; requestedAt = [DateTime]::UtcNow.ToString('o'); nonce = $nonce; dryRun = [bool]$DryRun }
    if ($Mode -eq 'deploy') { $req.sha = $Sha }
    $tmp = Join-Path $queue "request.$nonce.tmp"
    [IO.File]::WriteAllText($tmp, ($req | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination (Join-Path $queue 'request.json') -Force
    Write-Log "request written: mode=$Mode issue=$Issue sha=$Sha dryRun=$DryRun nonce=$nonce"
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    Write-Output "API-REQUEST FAIL: $_"
    exit $script:EXIT_PRECONDITION
}

# ---- trigger the elevated task (fixed action; no arguments can be passed) ----------------------
$t = Invoke-Native -File "$env:SystemRoot\System32\schtasks.exe" -Arguments @('/run', '/tn', $TaskName) -AllowFail
if ($t.Code -ne 0) {
    Write-Log "could not start task $TaskName (exit $($t.Code)); is it installed and enabled?" 'ERROR'
    Write-Output "API-REQUEST FAIL: task $TaskName could not be started (disabled or missing). Nothing ran."
    exit $script:EXIT_PRECONDITION
}

# ---- wait for the result -------------------------------------------------------------------------
$resultPath = Join-Path $ApiRoot "results\$nonce.json"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$result = $null
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $resultPath) {
        try { $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json; break } catch { }
    }
    Start-Sleep -Seconds 10
}
if (-not $result) {
    Write-Log "no result for $nonce after $TimeoutMinutes min" 'ERROR'
    Write-Output "API-REQUEST TIMEOUT: no result for nonce $nonce. The elevated task may still be running; check $ApiRoot\logs before doing anything else."
    exit $EXIT_TIMEOUT
}
Write-Log ("elevated result: status={0} exit={1} message={2} log={3}" -f $result.status, $result.exitCode, $result.message, $result.runnerLog)
$code = [int]$result.exitCode

# ---- git half, non-elevated --------------------------------------------------------------------
if ($Mode -eq 'deploy' -and $code -eq 2) {
    Write-Log "deploy failed and the jar was rolled back; reverting $Sha on API main"
    if (-not (Invoke-LocalRevert $Sha)) { $code = $script:EXIT_ROLLBACK_FAILED }
}
if ($Mode -eq 'rollback' -and $code -eq 0 -and $RevertSha -and -not $DryRun) {
    if (-not (Invoke-LocalRevert $RevertSha)) { $code = $script:EXIT_ROLLBACK_FAILED }
}
Write-Output ("API-REQUEST RESULT mode={0} status={1} exit={2} nonce={3} runnerLog={4} scriptLog={5}" -f $Mode, $result.status, $code, $nonce, $result.runnerLog, $result.scriptLog)
exit $code
