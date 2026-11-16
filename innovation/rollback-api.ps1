<#
.SYNOPSIS
  ELEVATED SIDE. Restore a backed-up jar into the solid-website-api service and verify it.

.DESCRIPTION
  Runs from the elevated `innovation-loop-api` task (api-runner.ps1) or by Ve from an elevated shell.
  The loop's own session is not elevated and reaches this only through api-request.ps1 -> api-runner.ps1.

  It never touches git: reverting the merge on main is done by the non-elevated side (api-request.ps1)
  after this succeeds, so the elevated side needs no push credentials.

  Idempotent: restoring the same jar twice is harmless. With no -BackupJar it uses the backup recorded in
  <home>\state\api-last-deploy.json (written by deploy-api.ps1). -BackupJar must live under
  <home>\api-backups.

.EXIT CODES
  0 restored and verified | 1 precondition failed | 3 restore or verification failed (human needed)
#>
[CmdletBinding()]
param(
    [string]$BackupJar = ''
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog 'rollback-api'
$liveJar = Join-Path $script:ApiServiceDir $script:ApiJarRel

try {
    if (-not (Test-IsElevated)) { throw 'must run elevated' }
    if (-not $BackupJar) {
        $st = Read-State 'api-last-deploy'
        if (-not $st) { throw 'no -BackupJar and no state\api-last-deploy.json' }
        $BackupJar = $st.backupJar
        Write-Log "using state file: backupJar=$BackupJar"
    }
    if (-not (Test-Path -LiteralPath $BackupJar)) { throw "backup jar not found: $BackupJar" }
    $backupRoot = (Resolve-Path (Join-Path $script:LoopHome 'api-backups')).Path
    if (-not (Resolve-Path -LiteralPath $BackupJar).Path.StartsWith($backupRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "backup jar must live under $backupRoot" }
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    exit $script:EXIT_PRECONDITION
}

try {
    Write-Log "restoring $BackupJar"
    Stop-Service -Name $script:ApiServiceName -Force
    if (-not (Wait-ServiceState -Name $script:ApiServiceName -State 'Stopped' -TimeoutSec 90)) { throw 'service did not stop' }
    Start-Sleep -Seconds 2
    Copy-Item -LiteralPath $BackupJar -Destination $liveJar -Force
    Start-Service -Name $script:ApiServiceName
    if (-not (Wait-ServiceState -Name $script:ApiServiceName -State 'Running' -TimeoutSec 90)) { throw 'service did not start' }
    if (-not (Test-Api -StartupTimeoutSec 120)) { throw 'restored service failed verification' }
    Write-Log 'backup jar restored and verified'
} catch {
    Write-Log "restore failed: $_" 'ERROR'
    exit $script:EXIT_ROLLBACK_FAILED
}

Save-State 'api-last-rollback' @{ backupJar = $BackupJar; finishedUtc = [DateTime]::UtcNow.ToString('o') }
Write-Log 'ROLLBACK complete (jar restored; main is reverted by the requesting side)'
exit $script:EXIT_OK
