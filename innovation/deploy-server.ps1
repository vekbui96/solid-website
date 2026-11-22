<#
.SYNOPSIS
  ELEVATED. Move the live server to a commit on origin/main, verify, and roll back on failure. Normally
  started only by elevated-task.ps1; the owner may run it by hand from an elevated PowerShell.

.DESCRIPTION
  1. preconditions: elevated; live dir is a clean git checkout; after a fresh `git fetch origin main`,
     -TargetSha is on origin/main and the live HEAD is an ancestor of it (never moves backwards); no
     protected path that the server runs changes between them (lib.ps1 Split-ProtectedByLiveImpact; inert
     ones such as innovation/**, .github/** are logged); hooks-server.ps1 Test-ServerPreconditions agrees
  2. snapshot every server.dataDirs entry to server.backupDir\predeploy-<stamp>-<n>.zip (read-only on data;
     verified by entry count; newest server.keepSnapshots kept). Irreplaceable data is never restored
     automatically: the zip is named in the log for the owner.
  3. record PREV (live HEAD) in ProgramData state\server-last-deploy.json (admin-writable only)
  4. hooks-server.ps1 Invoke-ServerSwap (default: git reset --hard + restart; deps reinstall when the
     lockfile changed, keeping the previous deps dir for instant rollback)
  5. hooks-server.ps1 Test-ServerHealthy (GET only, repeated, stable pid, retries for flaky upstreams)
  6. on failure: rollback-server.ps1

  Never writes into data dirs, never touches .env / service settings / secrets. The revert on main is
  done by the non-elevated deploy.ps1 / rollback.ps1. Generic (kit): project behaviour is in hooks-server.ps1.

.EXIT CODES
  0 deployed and verified (or already at target) | 1 precondition failed, nothing changed
  2 verification failed, rolled back | 3 verification failed AND rollback failed (human needed)
  4 install/build failed (rolled back)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetSha,
    [int]$Issue = 0,
    [switch]$DryRun
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\hooks-server.ps1"
Start-ScriptLog 'deploy-server' -Dir (Join-Path $script:ElevHome 'logs')
$stateFile = Join-Path $script:ElevHome 'state\server-last-deploy.json'
$live = $script:LiveDir

try {
    if (-not $script:ServerEnabled) { throw 'server.enabled is false in loop.config.json' }
    if (-not (Test-IsElevated) -and -not $DryRun) { throw 'must run elevated (service restarts)' }
    if ($TargetSha -notmatch '^[0-9a-f]{40}$') { throw 'TargetSha must be a full 40-char sha' }
    if (-not (Test-Path -LiteralPath (Join-Path $live '.git'))) { throw "$live is not a git checkout" }
    $null = Get-Service -Name "$(Get-Cfg 'server.serviceName')"
    $dirty = @((Invoke-Git -Repo $live -Arguments @('status', '--porcelain', '--untracked-files=no') -Quiet).Output | Where-Object { $_.Trim() })
    if ($dirty.Count -gt 0) { throw "live checkout has local changes: $($dirty -join '; ')" }
    Invoke-Git -Repo $live -Arguments @('fetch', 'origin', 'main', '--quiet') | Out-Null
    $originMain = Get-GitValue -Repo $live -Arguments @('rev-parse', 'FETCH_HEAD')
    $exists = Invoke-Git -Repo $live -Arguments @('cat-file', '-e', "$TargetSha^{commit}") -AllowFail -Quiet
    if ($exists.Code -ne 0) { throw "$TargetSha is not a known commit after fetching origin/main" }
    $anc = Invoke-Git -Repo $live -Arguments @('merge-base', '--is-ancestor', $TargetSha, $originMain) -AllowFail -Quiet
    if ($anc.Code -ne 0) { throw "$TargetSha is not on origin/main ($originMain)" }
    $prev = Get-GitValue -Repo $live -Arguments @('rev-parse', 'HEAD')
    if ($prev -eq $TargetSha) { Write-Log "live checkout already at $TargetSha; nothing to deploy"; Write-Output 'DEPLOY-SERVER OK (already at target)'; exit $script:EXIT_OK }
    $fwd = Invoke-Git -Repo $live -Arguments @('merge-base', '--is-ancestor', $prev, $TargetSha) -AllowFail -Quiet
    if ($fwd.Code -ne 0) { throw "live HEAD $prev is not an ancestor of $TargetSha; refusing to move the server sideways/backwards" }
    $changed = Get-ChangedFiles -Repo $live -From $prev -To $TargetSha
    # Only protected paths that change what this server RUNS refuse (lib.ps1 Split-ProtectedByLiveImpact);
    # protected paths nothing on the server executes (innovation/**, .github/**, ...) are inert: logged only.
    # A loop change's OWN files never touch any protected path (merge-pr.ps1 refuses that before merging).
    $split = Split-ProtectedByLiveImpact -Protected @($changed | Where-Object { Test-ProtectedPath $_ })
    if ($split.Inert.Count -gt 0) { Write-Log "protected but inert on this server (not refused): $($split.Inert -join ', ')" }
    if ($split.Block.Count -gt 0) { throw "changes protected paths that the server runs (manual / needs the owner): $($split.Block -join ', ')" }
    $why = Test-ServerPreconditions -Prev $prev -Target $TargetSha -Changed $changed
    if ($why) { throw $why }
    Write-Log "prev=$prev target=$TargetSha files=$($changed.Count) issue=$Issue"
    foreach ($c in $changed) { Write-Log "  changed: $c" }
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    Write-Output "DEPLOY-SERVER PRECONDITION $_"
    exit $script:EXIT_PRECONDITION
}

if ($DryRun) { Write-Log 'DRY RUN: would snapshot data, swap, verify'; Write-Output 'DEPLOY-SERVER DRYRUN OK'; exit $script:EXIT_OK }

# ---- snapshot irreplaceable data (read-only on the data dirs) -------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snapshots = @()
try {
    $backupDir = "$(Get-Cfg 'server.backupDir' (Join-Path $script:ElevHome 'backups'))"
    $keep = [int](Get-Cfg 'server.keepSnapshots' 10)
    $n = 0
    foreach ($dataDir in @(Get-Cfg 'server.dataDirs' @())) {
        $n++
        if (-not (Test-Path -LiteralPath $dataDir)) { throw "data dir $dataDir does not exist" }
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = Join-Path $backupDir "predeploy-$stamp-$n.zip"
        $fileCount = @(Get-ChildItem -LiteralPath $dataDir -Recurse -File).Count
        [IO.Compression.ZipFile]::CreateFromDirectory($dataDir, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try { $entries = @($z.Entries | Where-Object { $_.Name }).Count } finally { $z.Dispose() }
        if ($entries -lt $fileCount) { throw "snapshot of $dataDir has $entries files, the dir has $fileCount" }
        Write-Log "data snapshot: $dataDir -> $zip ($entries files, $([int]((Get-Item -LiteralPath $zip).Length / 1KB)) KB)"
        $snapshots += $zip
    }
    if ($snapshots.Count -gt 0) {
        Get-ChildItem -LiteralPath $backupDir -Filter 'predeploy-*.zip' | Sort-Object Name -Descending | Select-Object -Skip ($keep * [Math]::Max(1, $n)) |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    }
} catch {
    Write-Log "data snapshot failed, nothing changed: $_" 'ERROR'
    Write-Output "DEPLOY-SERVER PRECONDITION snapshot failed: $_"
    exit $script:EXIT_PRECONDITION
}

$record = [ordered]@{ issue = $Issue; prevSha = $prev; targetSha = $TargetSha; snapshots = $snapshots; startedUtc = [DateTime]::UtcNow.ToString('o'); status = 'started' }
Save-JsonFile -Path $stateFile -Object $record

# ---- swap ------------------------------------------------------------------------------------------
$swapOk = $true
try { Invoke-ServerSwap -Prev $prev -Target $TargetSha -Changed $changed -Record $record -StateFile $stateFile }
catch { Write-Log "swap/restart failed: $_" 'ERROR'; $swapOk = $false }
Save-JsonFile -Path $stateFile -Object $record

$verified = $false
if ($swapOk) { Start-Sleep -Seconds 5; $verified = Test-ServerHealthy }

if ($verified) {
    $record.status = 'deployed'; $record.finishedUtc = [DateTime]::UtcNow.ToString('o'); Save-JsonFile -Path $stateFile -Object $record
    Write-Log "DEPLOYED and verified the server at $TargetSha (prev $prev)"
    Write-Output "DEPLOY-SERVER OK $TargetSha"
    exit $script:EXIT_OK
}

$record.status = 'failed'; Save-JsonFile -Path $stateFile -Object $record
Write-Log 'deploy FAILED; rolling back' 'ERROR'
& "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\rollback-server.ps1"
$rb = $LASTEXITCODE
if ($rb -eq 0) {
    Write-Log 'rolled back successfully'
    Write-Output 'DEPLOY-SERVER ROLLED-BACK'
    if ($record.installFailed) { exit $script:EXIT_BUILD_FAILED }
    exit $script:EXIT_ROLLED_BACK
}
Write-Log "ROLLBACK FAILED (exit $rb). Production needs a human. Data snapshots: $($snapshots -join ', ')" 'ERROR'
Write-Output 'DEPLOY-SERVER ROLLBACK-FAILED'
exit $script:EXIT_ROLLBACK_FAILED
