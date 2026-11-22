<#
.SYNOPSIS
  Ship one merged loop change (one repo's merge) and verify it; roll back by itself on failure.
  NON-elevated: the server part goes through the pre-registered elevated task. Run it in the BACKGROUND
  and poll (it can take 30+ minutes).
  Last output line: DEPLOY OK | DEPLOY ROLLED-BACK <why> | DEPLOY ROLLBACK-FAILED <why> | DEPLOY PRECONDITION <why>

.DESCRIPTION
  1. preconditions: -MergeSha is the merge merge-pr.ps1 recorded for this issue and repo, and is on
     origin/main. If the repo is the server repo: the server plan (live HEAD..merge) has no protected path
     and no server change from commits outside this merge (undeployed work of the owner's). A precondition
     failing AFTER the merge still reverts main (main must never stay ahead of what was verified).
  2. server (only if the repo is the server repo and a server path changed): elevated request mode=deploy
     -> deploy-server.ps1 (data snapshot, swap, verify, auto-rollback)
  3. front end (only if the repo is the front-end repo): hooks.ps1 Invoke-FrontendDeploy (e.g. wait for
     THIS sha's workflow run), then Test-FrontendLive: served bytes (every chunk reachable from the entry, at any depth: live-check.ps1) contain -ExpectString, the build changed,
     the page renders. Status codes prove nothing (a blank SPA returns 200).
  4. on any failure: server rollback (elevated, if the server was deployed) + Invoke-FrontendRollback /
     git revert of the merge on main (never a force-push), then verify the old state is back

.EXIT CODES
  0 deployed and verified | 1 precondition failed BEFORE anything changed (nothing to undo)
  2 failed and rolled back (main reverted) | 3 failed AND rollback failed: PRODUCTION NEEDS THE OWNER
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [Parameter(Mandatory)][string]$MergeSha,
    [string]$Repo = '',
    # A string that exists only in the new front-end build (new UI copy is best). Required when the merge
    # changes anything that ships in the bundle; omit only for server-only changes.
    [string]$ExpectString = ''
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\live-check.ps1"   # Find-InChunkGraph: the whole chunk graph, for hooks.ps1 Test-FrontendLive
. "$PSScriptRoot\gate-rules.ps1"
. "$PSScriptRoot\hooks.ps1"
Start-ScriptLog "deploy-$Issue"
Add-GhToPath
$null = Clear-SecretEnv
$repoCfg = Get-RepoCfg $Repo
$clone = Get-ClonePath $repoCfg.name
$isServerRepo = $script:ServerEnabled -and ("$(Get-Cfg 'server.repo')" -eq $repoCfg.name)
$isFrontRepo = ($script:FrontendMode -ne 'none') -and ("$(Get-Cfg 'frontend.repo')" -eq $repoCfg.name)
$art = Join-Path $script:LoopHome "artifacts\$Issue"
if (-not (Test-Path -LiteralPath $art)) { New-Item -ItemType Directory -Path $art | Out-Null }
$state = [ordered]@{ issue = $Issue; repo = $repoCfg.name; mergeSha = $MergeSha; expectString = $ExpectString; startedUtc = [DateTime]::UtcNow.ToString('o'); serverDeployed = $false; status = 'started' }

function Finish([int]$code, [string]$line) {
    $state.status = $line; $state.finishedUtc = [DateTime]::UtcNow.ToString('o'); Save-State "deploy-$Issue-$($repoCfg.name)" $state
    Write-Log $line; Write-Output $line; exit $code
}

function Undo([string]$why) {
    Write-Log "rolling back: $why" 'ERROR'
    $ok = $true
    if ($state.serverDeployed) {
        $r = Invoke-ElevatedRequest -Mode rollback -Issue $Issue -Sha $state.serverTarget
        Write-Log "server rollback: $($r.status) $($r.message)"
        if ($r.status -ne 'ok') { $ok = $false }
    }
    try {
        if ($isFrontRepo) { $back = Invoke-FrontendRollback -RepoName $repoCfg.name -MergeSha $MergeSha -AbsentString $ExpectString -ShotPath (Join-Path $art 'rolled-back.png') }
        else { $null = Invoke-RevertOnMain -Repo $clone -Sha $MergeSha; $back = $true }
        if (-not $back) { $ok = $false }
    } catch { Write-Log "revert on main failed: $_" 'ERROR'; $ok = $false }
    if ($ok) { Finish 2 "DEPLOY ROLLED-BACK $why" }
    Finish 3 "DEPLOY ROLLBACK-FAILED $why (PRODUCTION NEEDS THE OWNER: see $($script:LogFile))"
}

# ---- 1. preconditions -------------------------------------------------------------------------
$plan = $null
$frontFiles = @()
try {
    if ($MergeSha -notmatch '^[0-9a-f]{40}$') { throw 'MergeSha must be the full 40-char merge commit sha' }
    # Only a merge made by merge-pr.ps1 for this issue can be deployed (its record lives in state\, which the
    # session cannot write). Not a loop merge = not ours to deploy OR to revert: exit 1 untouched.
    $rec = Read-State "merge-$Issue-$($repoCfg.name)"
    if (-not $rec -or "$($rec.mergeSha)" -ne $MergeSha) { Finish 1 "DEPLOY PRECONDITION $MergeSha is not the merge merge-pr.ps1 recorded for issue #$Issue in $($repoCfg.name) (nothing changed)" }
    Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') | Out-Null
    $anc = Invoke-Git -Repo $clone -Arguments @('merge-base', '--is-ancestor', $MergeSha, 'origin/main') -AllowFail -Quiet
    if ($anc.Code -ne 0) { Finish 1 "DEPLOY PRECONDITION $MergeSha is not on origin/main (nothing merged, nothing to undo)" }
    $parent = Get-GitValue -Repo $clone -Arguments @('rev-parse', "$MergeSha^1")
    $mergeFiles = Get-ChangedFiles -Repo $clone -From $parent -To $MergeSha
    if ($isFrontRepo) {
        $frontFiles = @($mergeFiles | Where-Object { Test-IsFrontendFile $_ })
        $state.prevSignature = Get-FrontendSignature
        if ($frontFiles.Count -gt 0 -and -not $ExpectString) { throw 'the merge changes the front end: pass -ExpectString <string only the new build contains>' }
    }
    Write-Log "merge $MergeSha changes $($mergeFiles.Count) file(s); front-end relevant: $($frontFiles.Count); server repo: $isServerRepo"
    if ($isServerRepo) {
        $plan = Get-ServerPlan -Repo $clone -Target $MergeSha -OwnCommitsFrom $parent
        $state.liveHeadBefore = $plan.LiveHead
        Write-Log "server plan: liveHead=$($plan.LiveHead) needed=$($plan.ServerNeeded) files=$($plan.ServerFiles -join ',') protected=$($plan.Protected -join ',') foreign=$($plan.Foreign -join ',')"
        # same rule as merge-pr (gate-rules.ps1 Get-GapDecision): the merge's own protected files, or gap ones
        # that change what the server runs, stop it; inert ones are listed; the owner's non-protected server
        # changes already on main go live with this deploy (logged)
        $gap = Get-GapDecision -Protected $plan.Protected -OwnFiles $mergeFiles
        if ($gap.Ignored.Count -gt 0) { Write-Log "protected but inert on the server, between live and the merge (ignored): $($gap.Ignored -join ', ')" }
        if ($plan.Foreign.Count -gt 0) { Write-Log "server changes already on main that go live with this deploy: $(@($plan.Foreign | ForEach-Object { "$_".Substring(0, 7) }) -join ', ')" }
        if ($gap.Refuse.Count -gt 0) { throw "protected paths between live and the merge (manual / needs the owner): $($gap.Refuse -join ', ')" }
    }
} catch {
    Undo "precondition failed after the merge: $_"
}

# ---- 2. server ---------------------------------------------------------------------------------
if ($plan -and $plan.ServerNeeded) {
    $state.serverTarget = $MergeSha
    $r = Invoke-ElevatedRequest -Mode deploy -Issue $Issue -Sha $MergeSha
    $state.serverResult = "$($r.status): $($r.message)"
    Write-Log "server deploy: $($r.status) (exit $($r.exitCode)) $($r.message)"
    switch ("$($r.status)") {
        'ok' { $state.serverDeployed = $true }
        'rolled-back' { Undo 'server deploy failed verification (server already rolled back by deploy-server.ps1)' }
        'rollback-failed' {
            Write-Log 'SERVER ROLLBACK FAILED' 'ERROR'
            try { $null = Invoke-RevertOnMain -Repo $clone -Sha $MergeSha } catch { }
            Finish 3 'DEPLOY ROLLBACK-FAILED server deploy and its rollback both failed (PRODUCTION NEEDS THE OWNER)'
        }
        default { Undo "server deploy did not run: $($r.status) $($r.message)" }   # rejected / not-started / precondition: server untouched
    }
} elseif ($isServerRepo) { Write-Log 'no server-relevant change: server not touched' }

# ---- 3. front end ------------------------------------------------------------------------------
$asset = ''
if ($isFrontRepo) {
    if (-not (Invoke-FrontendDeploy -RepoName $repoCfg.name -MergeSha $MergeSha -Issue $Issue)) { Undo "the front-end deploy for $MergeSha did not succeed" }
    $notSig = ''; if ($frontFiles.Count -gt 0) { $notSig = $state.prevSignature }
    $v = Test-FrontendLive -ExpectString $ExpectString -NotSignature $notSig -RepoForSmoke $clone -ShotPath (Join-Path $art 'live.png') -TimeoutSec 600
    if (-not $v.Ok) { Undo 'live front-end verification failed (string / chunks / render)' }
    $asset = $v.Asset
}

if ($state.serverDeployed) {
    # re-check the server after everything went live, cheaply (GET only)
    $pub = "$(Get-Cfg 'server.publicHealthUrl' (Get-Cfg 'server.healthUrl'))"
    $h = Invoke-HttpRetry -Url $pub -ExpectRegex "$(Get-Cfg 'server.healthExpect' '.')" -Attempts 3 -DelaySec 10
    if (-not $h.Ok) { Undo 'server health failed after the deploy completed' }
}
Finish 0 "DEPLOY OK repo=$($repoCfg.name) merge=$MergeSha asset=$asset server=$(if ($state.serverDeployed) { 'deployed' } else { 'unchanged' })"
