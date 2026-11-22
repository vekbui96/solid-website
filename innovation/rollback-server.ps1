<#
.SYNOPSIS
  ELEVATED. Put the live server back to the PREV recorded by the last deploy-server.ps1 run (hooks-server.ps1
  Invoke-ServerRestore), restart, re-verify.

.DESCRIPTION
  Takes no target from its caller: PREV comes only from C:\ProgramData\innovation-loop-<project>\state\
  server-last-deploy.json, which only the elevated side can write. Refuses if the live HEAD is neither the
  recorded target nor PREV (someone else moved it). Idempotent. Data is never restored automatically: the
  pre-deploy snapshot zips are named in the log for the owner. The revert on main is done by the
  non-elevated side. The owner may run it by hand from an elevated PowerShell:
     C:\ProgramData\innovation-loop-<project>\bin\rollback-server.ps1

.EXIT CODES
  0 rolled back and verified | 1 precondition failed | 3 rollback or verification failed (human needed)
#>
[CmdletBinding()]
param([switch]$DryRun)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\hooks-server.ps1"
Start-ScriptLog 'rollback-server' -Dir (Join-Path $script:ElevHome 'logs')
$stateFile = Join-Path $script:ElevHome 'state\server-last-deploy.json'
$live = $script:LiveDir

try {
    if (-not (Test-IsElevated) -and -not $DryRun) { throw 'must run elevated' }
    $st = Read-JsonFile -Path $stateFile
    if (-not $st) { throw "no $stateFile" }
    if ("$($st.prevSha)" -notmatch '^[0-9a-f]{40}$' -or "$($st.targetSha)" -notmatch '^[0-9a-f]{40}$') { throw 'state file has no valid prevSha/targetSha' }
    if ($st.status -eq 'rolled-back') { Write-Log 'state says this deploy was already rolled back; re-verifying only' }
    $head = Get-GitValue -Repo $live -Arguments @('rev-parse', 'HEAD')
    if ($head -ne $st.targetSha -and $head -ne $st.prevSha) { throw "live HEAD $head is neither the recorded target $($st.targetSha) nor prev $($st.prevSha); refusing" }
    Write-Log "rollback: live=$head -> prev=$($st.prevSha) (issue $($st.issue), snapshots=$(@($st.snapshots) -join ', '))"
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    Write-Output "ROLLBACK-SERVER PRECONDITION $_"
    exit $script:EXIT_PRECONDITION
}
if ($DryRun) { Write-Output 'ROLLBACK-SERVER DRYRUN OK'; exit $script:EXIT_OK }

try {
    Invoke-ServerRestore -Record $st
    Start-Sleep -Seconds 5
    if (-not (Test-ServerHealthy)) { throw 'restored server failed verification' }
} catch {
    Write-Log "ROLLBACK FAILED: $_ (data snapshots: $(@($st.snapshots) -join ', '))" 'ERROR'
    $st | Add-Member -NotePropertyName status -NotePropertyValue 'rollback-failed' -Force
    Save-JsonFile -Path $stateFile -Object $st
    Write-Output "ROLLBACK-SERVER FAILED $_"
    exit $script:EXIT_ROLLBACK_FAILED
}
$st | Add-Member -NotePropertyName status -NotePropertyValue 'rolled-back' -Force
$st | Add-Member -NotePropertyName rolledBackUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
Save-JsonFile -Path $stateFile -Object $st
Write-Log "ROLLBACK complete: live at $($st.prevSha)"
Write-Output "ROLLBACK-SERVER OK $($st.prevSha)"
exit $script:EXIT_OK
