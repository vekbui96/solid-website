<#
.SYNOPSIS
  Undo a loop deploy. NON-elevated; the server part goes through the elevated task.
  Last output line: ROLLBACK OK | ROLLBACK FAILED <why> | ROLLBACK PRECONDITION <why>

.DESCRIPTION
  Default: if the loop's deploy record for -Issue/-Repo deployed the server, ask the elevated task to roll
  the server back (to the PREV it recorded itself), then roll the front end back (hooks.ps1
  Invoke-FrontendRollback: git revert of the merge on main, never a force-push) and verify -AbsentString
  is gone and the page renders. For a non-front-end repo it only reverts main.

  -RevertOnly: only the revert on main (+ front-end verification). Needs no elevation. For a merge whose
  server part never went live, or a front-end-only change.

  Only merges recorded by merge-pr.ps1 are reverted; the owner reverts anything else by hand.
  deploy.ps1 already does this on its own failures; this script is for a rollback decided later.

.EXIT CODES
  0 rolled back and verified | 1 precondition failed, nothing changed | 3 rollback failed (human needed)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [Parameter(Mandatory)][string]$MergeSha,
    [string]$Repo = '',
    [string]$AbsentString = '',
    [switch]$RevertOnly
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\hooks.ps1"
. "$PSScriptRoot\live-check.ps1"   # Find-InChunkGraph: the whole chunk graph, for hooks.ps1 Test-FrontendLive
Start-ScriptLog "rollback-$Issue"
Add-GhToPath
$null = Clear-SecretEnv
$repoCfg = Get-RepoCfg $Repo
$clone = Get-ClonePath $repoCfg.name
$isFrontRepo = ($script:FrontendMode -ne 'none') -and ("$(Get-Cfg 'frontend.repo')" -eq $repoCfg.name)
$art = Join-Path $script:LoopHome "artifacts\$Issue"
if (-not (Test-Path -LiteralPath $art)) { New-Item -ItemType Directory -Path $art | Out-Null }

try {
    if ($MergeSha -notmatch '^[0-9a-f]{40}$') { throw 'MergeSha must be the full 40-char sha' }
    $rec = Read-State "merge-$Issue-$($repoCfg.name)"
    if (-not $rec -or "$($rec.mergeSha)" -ne $MergeSha) { throw "$MergeSha is not the merge merge-pr.ps1 recorded for issue #$Issue in $($repoCfg.name)" }
    if (-not (Test-Path -LiteralPath (Join-Path $clone '.git'))) { throw "no clone at $clone" }
    Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') | Out-Null
    $anc = Invoke-Git -Repo $clone -Arguments @('merge-base', '--is-ancestor', $MergeSha, 'origin/main') -AllowFail -Quiet
    if ($anc.Code -ne 0) { throw "$MergeSha is not on origin/main" }
} catch {
    Write-Log "precondition failed: $_" 'ERROR'; Write-Output "ROLLBACK PRECONDITION $_"; exit 1
}

$ok = $true
if (-not $RevertOnly) {
    $st = Read-State "deploy-$Issue-$($repoCfg.name)"
    if ($st -and $st.serverDeployed -and $st.serverTarget -eq $MergeSha) {
        $r = Invoke-ElevatedRequest -Mode rollback -Issue $Issue -Sha $MergeSha
        Write-Log "server rollback: $($r.status) $($r.message)"
        if ($r.status -ne 'ok') { $ok = $false }
    } else {
        Write-Log 'no server deploy recorded for this issue and merge; server untouched'
    }
}
try {
    if ($isFrontRepo) {
        if (-not (Invoke-FrontendRollback -RepoName $repoCfg.name -MergeSha $MergeSha -AbsentString $AbsentString -ShotPath (Join-Path $art 'rollback.png'))) { $ok = $false }
    } else { $null = Invoke-RevertOnMain -Repo $clone -Sha $MergeSha }
} catch { Write-Log "revert failed: $_" 'ERROR'; $ok = $false }

# the runner reads this record (gate-rules.ps1 Get-DeployCertainty) to decide whether the next build may start
$status = 'ROLLBACK OK'; if (-not $ok) { $status = 'ROLLBACK FAILED' }
try { Save-State "rollback-$Issue-$($repoCfg.name)" @{ issue = $Issue; repo = $repoCfg.name; mergeSha = $MergeSha; status = $status; utc = [DateTime]::UtcNow.ToString('o') } } catch { Write-Log "could not save the rollback record: $_" 'WARN' }
if ($ok) { Write-Output 'ROLLBACK OK'; exit 0 }
Write-Output "ROLLBACK FAILED (PRODUCTION NEEDS THE OWNER: see $($script:LogFile))"
exit 3
