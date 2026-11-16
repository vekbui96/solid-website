<#
.SYNOPSIS
  Restore a backed-up jar into the solid-website-api service, verify, optionally revert a commit on main.

.DESCRIPTION
  Idempotent: restoring the same jar twice is harmless; an already-reverted commit is skipped.
  With no -BackupJar it uses the backup recorded in state\api-last-deploy.json.
  If -RevertSha is given, the revert is pushed to main (Render auto-deploys main, so main must match
  production) and the informational source copy in D:\services\solid-website-api is re-mirrored from it.

.EXIT CODES
  0 restored and verified | 1 precondition failed | 3 restore or verification failed (human needed)
#>
[CmdletBinding()]
param(
    [string]$BackupJar = '',
    [string]$RevertSha = '',
    # Only revert -RevertSha on main (Render follows main); leave the live jar alone.
    [switch]$RevertOnly
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog 'rollback-api'
$liveJar = Join-Path $script:ApiServiceDir $script:ApiJarRel

if ($RevertOnly) {
    if (-not $RevertSha) { Write-Log '-RevertOnly needs -RevertSha' 'ERROR'; exit $script:EXIT_PRECONDITION }
    try { Invoke-RevertOnMain -Repo $script:ApiClone -Sha $RevertSha; Write-Log 'REVERT-ONLY complete (live jar untouched)'; exit $script:EXIT_OK }
    catch { Write-Log "revert failed: $_" 'ERROR'; exit $script:EXIT_ROLLBACK_FAILED }
}

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
    if (-not (Resolve-Path -LiteralPath $BackupJar).Path.StartsWith($backupRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "backup jar must live under $backupRoot" }
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

if ($RevertSha) {
    try {
        Invoke-RevertOnMain -Repo $script:ApiClone -Sha $RevertSha
        $src = Export-ApiSource -Ref 'origin/main'
        try { Sync-ApiSource -From $src } catch { Write-Log "source re-mirror failed (jar is fine): $_" 'WARN' }
    } catch {
        Write-Log "revert of $RevertSha on main failed: $_ (production is restored; main and Render are not)" 'ERROR'
        exit $script:EXIT_ROLLBACK_FAILED
    }
}
Save-State 'api-last-rollback' @{ backupJar = $BackupJar; revertedSha = $RevertSha; finishedUtc = [DateTime]::UtcNow.ToString('o') }
Write-Log 'ROLLBACK complete'
exit $script:EXIT_OK
