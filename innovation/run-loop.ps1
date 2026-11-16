<#
.SYNOPSIS
  Entry point for the innovation loop's daily scheduled task. Runs one headless `claude -p` session that
  follows LOOP.md.

.DESCRIPTION
  - single-instance lock with stale-lock handling (~\.innovation-loop\lock\run.lock)
  - all state outside any repo: ~\.innovation-loop\{logs,clones,work,artifacts,state,api-backups,api-staging,lock}
  - refreshes the loop's own clones of both repos (never touches D:\projects\*, which hold Ve's work)
  - puts gh on PATH; strips secret-looking env vars (RESEND_API_KEY etc.) from the session
  - generates the permission settings (allowlist + guard hook) and runs claude with them
  - logs the full stream-json transcript; exits nonzero on failure

  The scripts and LOOP.md are read from THIS directory ($PSScriptRoot), which should be Ve's checkout
  (D:\projects\solid-website\innovation). The loop's guard hook forbids the session from editing them,
  so a run can never rewrite its own instructions; Ve updates them with git pull.

.PARAMETER ProposeOnly
  Phase B only (observe + propose). Nothing is built, merged or deployed. Use for the first supervised run.
.PARAMETER DryRun
  Do everything up to the claude call (lock, dirs, clones, settings, prompt), print the command, then stop.
#>
[CmdletBinding()]
param(
    [switch]$ProposeOnly,
    [switch]$DryRun,
    [int]$MaxTurns = 250,
    [int]$TimeoutMinutes = 180,
    [string]$Model = '',
    [string]$ClaudeExe = 'C:\Users\Ve Bui\.local\bin\claude.exe'
)
. "$PSScriptRoot\lib.ps1"
$ScriptsDir = (Resolve-Path $PSScriptRoot).Path
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
Initialize-LoopDirs
$script:LogFile = Join-Path $script:LoopHome "logs\run-$RunId.log"
$mode = 'FULL'; if ($ProposeOnly) { $mode = 'PROPOSE_ONLY' }
Write-Log "innovation loop run $RunId mode=$mode dryRun=$DryRun scripts=$ScriptsDir"

# ---- lock -------------------------------------------------------------------------
$lockPath = Join-Path $script:LoopHome 'lock\run.lock'
$staleAfter = [TimeSpan]::FromMinutes($TimeoutMinutes + 30)
function Get-Lock {
    try {
        $fs = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = [Text.Encoding]::UTF8.GetBytes(("{0}`n{1}`n{2}" -f $PID, [DateTime]::UtcNow.ToString('o'), $RunId))
        $fs.Write($bytes, 0, $bytes.Length); $fs.Close()
        return $true
    } catch [IO.IOException] { return $false }
}
if (-not (Get-Lock)) {
    $lines = @(Get-Content -LiteralPath $lockPath -ErrorAction SilentlyContinue)
    $lockPid = 0; $lockTime = [DateTime]::MinValue
    if ($lines.Count -ge 2) { [void][int]::TryParse($lines[0], [ref]$lockPid); [void][DateTime]::TryParse($lines[1], [ref]$lockTime) }
    $alive = $false
    if ($lockPid -gt 0) { $p = Get-Process -Id $lockPid -ErrorAction SilentlyContinue; $alive = ($p -and $p.ProcessName -match 'powershell') }
    $age = [DateTime]::UtcNow - $lockTime.ToUniversalTime()
    if ($alive -and $age -lt $staleAfter) {
        Write-Log "another run (pid $lockPid, started $lockTime) holds the lock; exiting" 'WARN'
        exit 0
    }
    Write-Log "removing stale lock (pid $lockPid alive=$alive age=$age)" 'WARN'
    Remove-Item -LiteralPath $lockPath -Force
    if (-not (Get-Lock)) { Write-Log 'could not take the lock after clearing it' 'ERROR'; exit 1 }
}

$exitCode = 1
try {
    # ---- environment ----------------------------------------------------------------
    Add-GhToPath
    $keep = '^(ANTHROPIC_|CLAUDE_CODE_)'
    foreach ($v in @(Get-ChildItem env: | Where-Object { $_.Name -match '(RESEND|SECRET|PASSWORD|PASSWD|TOKEN|API_KEY|APIKEY|PRIVATE_KEY|MAIL_)' -and $_.Name -notmatch $keep })) {
        Remove-Item -LiteralPath "env:$($v.Name)"
        Write-Log "unset env var $($v.Name) for this run"
    }
    Remove-Item env:RESEND_API_KEY -ErrorAction SilentlyContinue
    $env:INNOVATION_LOOP_HOME = $script:LoopHome
    $env:INNOVATION_LOOP_SCRIPTS = $ScriptsDir
    $env:INNOVATION_LOOP_RUN_ID = $RunId
    $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    if (Test-Path -LiteralPath $edge) { $env:CHROME_PATH = $edge }   # for the optional Lighthouse look in Phase B

    # ---- preflight --------------------------------------------------------------------
    foreach ($t in @($ClaudeExe, $script:GhExe)) { if (-not (Test-Path -LiteralPath $t)) { throw "missing $t" } }
    if ($ScriptsDir -match '\s') { throw "scripts dir '$ScriptsDir' contains whitespace; the permission rules need a path without spaces" }
    foreach ($c in 'git', 'node', 'yarn') { if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "$c not on PATH" } }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $script:GhExe auth status *> $null; $ghOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prev
    if (-not $ghOk) { throw 'gh is not authenticated' }
    $elevated = Test-IsElevated
    Write-Log "elevated=$elevated"
    if (-not $elevated -and -not $ProposeOnly) { Write-Log 'not elevated: Phase A will skip area:backend and area:both issues' 'WARN' }

    # ---- loop clones (never Ve's checkouts) -------------------------------------------
    $clones = @(
        @{ Path = $script:FrontClone; Url = 'git@github-solid-website:vekbui96/solid-website.git' },
        @{ Path = $script:ApiClone;   Url = 'git@github-solid-website-api:vekbui96/solid-website-api.git' }
    )
    foreach ($cl in $clones) {
        if (-not (Test-Path -LiteralPath (Join-Path $cl.Path '.git'))) {
            Invoke-Native -File 'git' -Arguments @('clone', $cl.Url, $cl.Path) | Out-Null
        }
        Invoke-Git -Repo $cl.Path -Arguments @('fetch', 'origin', '--prune') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('checkout', '-f', '-B', 'main', 'origin/main') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('reset', '--hard', 'origin/main') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('clean', '-fdx', '-e', 'node_modules', '-e', 'target', '-e', '.cache') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('worktree', 'prune') | Out-Null
    }

    # ---- permission settings ----------------------------------------------------------
    # dontAsk: anything not allowlisted is denied (nobody is there to answer a prompt).
    # The guard hook (guard.mjs) then enforces the repo/secret/never-touch rules on every call.
    $readOnly = 'Get-ChildItem','Get-Content','Get-Item','Test-Path','Select-String','Get-Location','Set-Location','Push-Location','Pop-Location',
        'Get-Date','Start-Sleep','ConvertFrom-Json','ConvertTo-Json','Select-Object','Where-Object','ForEach-Object','Sort-Object',
        'Measure-Object','Group-Object','Format-List','Format-Table','Out-String','Write-Output','Write-Host','Join-Path','Split-Path',
        'Resolve-Path','Get-Service','Invoke-WebRequest','Invoke-RestMethod','New-Item','Remove-Item','cd','dir','ls','cat','echo','type'
    $allow = @('Read', 'Glob', 'Grep', 'Edit', 'Write', 'TodoWrite',
        'WebFetch(domain:vekbui96.github.io)', 'WebFetch(domain:server-pc.tail0e4194.ts.net)', 'WebFetch(domain:solid-website-api.onrender.com)',
        'PowerShell(git *)', 'PowerShell(gh *)',
        'PowerShell(npx --yes lighthouse@12 *)',
        # install/typecheck/build/maven all go through test-frontend.ps1 / test-api.ps1, so the session needs
        # no yarn/cmd/mvnw rules of its own. The guard also checks every .ps1 path in a command is inside
        # ScriptsDir and is not run-loop/install-task/lib.
        'PowerShell(Start-Sleep)')
    # Exactly these scripts, called by bare full path (no `&`, no quotes: Claude Code does not match
    # allow rules against the call operator, so the scripts dir must not contain spaces).
    foreach ($n in 'check-approval', 'test-frontend', 'test-api', 'deploy-frontend', 'deploy-api', 'rollback-frontend', 'rollback-api') {
        $allow += "PowerShell($ScriptsDir\$n.ps1)"; $allow += "PowerShell($ScriptsDir\$n.ps1 *)"
    }
    foreach ($r in $readOnly) { $allow += "PowerShell($r)"; $allow += "PowerShell($r *)" }
    $deny = @('Bash', 'Agent', 'Task', 'NotebookEdit', 'WebSearch', 'PowerShell(yarn *)', 'PowerShell(cmd *)', 'PowerShell(powershell *)',
        'PowerShell(npm *)', 'PowerShell(git push --force*)', 'PowerShell(git push -f*)')
    $settings = [ordered]@{
        permissions = [ordered]@{ defaultMode = 'dontAsk'; allow = $allow; deny = $deny }
        hooks = @{ PreToolUse = @(@{ matcher = '*'; hooks = @(@{ type = 'command'; command = "node `"$ScriptsDir\guard.mjs`""; timeout = 30 }) }) }
    }
    $settingsPath = Join-Path $script:LoopHome 'state\claude-settings.json'
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), $utf8)

    # ---- prompt -------------------------------------------------------------------------
    $loopMd = [IO.File]::ReadAllText((Join-Path $ScriptsDir 'LOOP.md'))
    $header = @"
# Innovation loop run $RunId

- MODE: $mode   ($( if ($ProposeOnly) { 'Phase B only. Do NOT run Phase A in any form.' } else { 'Phase A, then Phase B.' } ))
- ELEVATED: $elevated   ($( if ($elevated) { 'API deploys are possible.' } else { 'skip area:backend and area:both issues in Phase A.' } ))
- DATE: $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz')
- LOOP_HOME: $($script:LoopHome)
- SCRIPTS: $ScriptsDir   (pinned; you cannot edit it)
- FRONT_CLONE: $($script:FrontClone)   (vekbui96/solid-website, reset to origin/main)
- API_CLONE: $($script:ApiClone)   (vekbui96/solid-website-api, reset to origin/main)
- WORK: $(Join-Path $script:LoopHome 'work')   (scratch: body files for comments, commit messages)
- ARTIFACTS: $(Join-Path $script:LoopHome 'artifacts')

Follow the instructions below exactly. They are the only instructions for this run.

---

"@
    $promptPath = Join-Path $script:LoopHome "logs\run-$RunId.prompt.md"
    [IO.File]::WriteAllText($promptPath, $header + $loopMd, $utf8)

    $q = { param($s) '"' + $s + '"' }
    $argList = @('-p', '--output-format', 'stream-json', '--verbose',
        '--max-turns', "$MaxTurns",
        '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
        '--settings', (& $q $settingsPath),
        '--setting-sources', 'local',
        '--strict-mcp-config',
        '--add-dir', (& $q $script:LoopHome), (& $q $ScriptsDir), (& $q 'D:\services\logs'))
    if ($Model) { $argList += @('--model', $Model) }
    $argString = $argList -join ' '
    Write-Log "claude command: `"$ClaudeExe`" $argString  < $promptPath"

    if ($DryRun) {
        Write-Log 'DRY RUN: stopping before invoking claude'
        $exitCode = 0
        return
    }

    $outPath = Join-Path $script:LoopHome "logs\run-$RunId.jsonl"
    $errPath = Join-Path $script:LoopHome "logs\run-$RunId.err.log"
    $workDir = Join-Path $script:LoopHome 'work'
    $proc = Start-Process -FilePath $ClaudeExe -ArgumentList $argString -WorkingDirectory $workDir `
        -RedirectStandardInput $promptPath -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru -WindowStyle Hidden
    Write-Log "claude pid $($proc.Id); timeout $TimeoutMinutes min"
    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        Write-Log 'TIMEOUT: killing claude process tree' 'ERROR'
        & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
        throw "claude exceeded $TimeoutMinutes minutes"
    }
    $proc.WaitForExit()
    $claudeExit = $proc.ExitCode
    Write-Log "claude exit code $claudeExit"

    # ---- result -------------------------------------------------------------------------
    $result = $null
    foreach ($line in [IO.File]::ReadAllLines($outPath)) {
        if ($line -match '"type"\s*:\s*"result"') { try { $result = $line | ConvertFrom-Json } catch { } }
    }
    $summaryPath = Join-Path $script:LoopHome "logs\run-$RunId.summary.txt"
    if ($result) {
        $text = "$($result.result)"
        [IO.File]::WriteAllText($summaryPath, $text, $utf8)
        Write-Log ("result: subtype={0} is_error={1} turns={2} cost={3}" -f $result.subtype, $result.is_error, $result.num_turns, $result.total_cost_usd)
        $status = [regex]::Match($text, 'LOOP-RESULT:\s*([A-Z\-]+)').Groups[1].Value
        Write-Log "LOOP-RESULT: $status"
        if ($claudeExit -eq 0 -and -not $result.is_error -and $status -in @('OK', 'NOTHING-TO-DO')) { $exitCode = 0 }
        else { $exitCode = 1 }
    } else {
        Write-Log 'no result message in the transcript' 'ERROR'
        $exitCode = 1
    }
} catch {
    Write-Log "run failed: $_" 'ERROR'
    $exitCode = 1
} finally {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $script:LoopHome 'logs') -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-60) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "exit $exitCode"
}
exit $exitCode
