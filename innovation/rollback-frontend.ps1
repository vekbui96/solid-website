<#
.SYNOPSIS
  Put gh-pages back to a previous commit, verify the old bundle is live, optionally revert a commit on main.

.DESCRIPTION
  Idempotent: if gh-pages is already at -PrevSha the push is skipped; if -RevertSha is already reverted
  on main the revert is skipped. main is never force-pushed or rewritten: the revert is a new commit.
  With no -PrevSha it uses state\frontend-last-deploy.json written by deploy-frontend.ps1.

.EXIT CODES
  0 rolled back and verified | 1 precondition failed | 3 rollback push or verification failed
#>
[CmdletBinding()]
param(
    [string]$PrevSha = '',
    [string]$PrevAsset = '',
    [string]$RevertSha = '',
    [string]$RepoPath = '',
    # Only revert -RevertSha on main; leave gh-pages alone (for a merge that never reached production).
    [switch]$RevertOnly
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog 'rollback-frontend'
if (-not $RepoPath) { $RepoPath = $script:FrontClone }
Add-GhToPath

if ($RevertOnly) {
    if (-not $RevertSha) { Write-Log '-RevertOnly needs -RevertSha' 'ERROR'; exit $script:EXIT_PRECONDITION }
    try { Invoke-RevertOnMain -Repo $RepoPath -Sha $RevertSha; Write-Log 'REVERT-ONLY complete (gh-pages untouched)'; exit $script:EXIT_OK }
    catch { Write-Log "revert failed: $_" 'ERROR'; exit $script:EXIT_ROLLBACK_FAILED }
}

try {
    if (-not $PrevSha) {
        $st = Read-State 'frontend-last-deploy'
        if (-not $st) { throw 'no -PrevSha and no state\frontend-last-deploy.json' }
        $PrevSha = $st.prevGhPagesSha
        if (-not $PrevAsset) { $PrevAsset = $st.prevAsset }
        Write-Log "using state file: prevGhPagesSha=$PrevSha prevAsset=$PrevAsset status=$($st.status)"
        # A stale state file must never roll production back further than the last deploy.
        Invoke-Git -Repo $RepoPath -Arguments @('fetch', 'origin', '--prune') | Out-Null
        $cur = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/gh-pages')
        if ($st.status -eq 'deployed' -and $cur -ne $st.newGhPagesSha -and $cur -ne $st.prevGhPagesSha) {
            throw "gh-pages ($cur) moved since the recorded deploy; pass -PrevSha explicitly"
        }
    }
    if ($PrevSha -notmatch '^[0-9a-f]{7,40}$') { throw "bad PrevSha '$PrevSha'" }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { throw "no git clone at $RepoPath" }
    Invoke-Git -Repo $RepoPath -Arguments @('fetch', 'origin', '--prune') | Out-Null
    $PrevSha = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', "$PrevSha^{commit}")
    # gh-pages (the npm package) appends commits, so a real previous deploy is an ancestor of origin/gh-pages.
    # This stops anything else (e.g. a main commit) from being pushed onto gh-pages by mistake.
    $anc = Invoke-Git -Repo $RepoPath -Arguments @('merge-base', '--is-ancestor', $PrevSha, 'origin/gh-pages') -AllowFail
    if ($anc.Code -ne 0) { throw "$PrevSha is not in origin/gh-pages history" }
    if (-not $PrevAsset) {
        $html = (Invoke-Git -Repo $RepoPath -Arguments @('show', "${PrevSha}:index.html")).Output -join "`n"
        $PrevAsset = Get-IndexAsset $html
    }
    if (-not $PrevAsset) { throw "could not determine the asset name for $PrevSha" }
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    exit $script:EXIT_PRECONDITION
}

try {
    $current = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/gh-pages')
    $pushUtc = [DateTime]::UtcNow
    if ($current -eq $PrevSha) {
        Write-Log "gh-pages already at $PrevSha; skipping push"
        $live = Get-IndexAsset (Invoke-Http -Url (Get-CacheBustedUrl $script:SiteUrl)).Body
        if ($live -ne $PrevAsset) { Write-Log "live still serves $live; waiting for Pages" }
    } else {
        Write-Log "moving gh-pages $current -> $PrevSha"
        # lease on the exact sha we just fetched: refuses if someone else pushed meanwhile
        Invoke-Git -Repo $RepoPath -Arguments @('push', "--force-with-lease=gh-pages:$current", 'origin', "${PrevSha}:refs/heads/gh-pages") | Out-Null
        if (-not (Wait-PagesBuild -Sha $PrevSha -NotBeforeUtc $pushUtc)) { Write-Log 'Pages build for the rollback did not report success; checking live bytes anyway' 'WARN' }
    }
    if (-not (Test-LiveSite -Asset $PrevAsset)) { throw "old asset $PrevAsset is not live" }
    Write-Log "gh-pages rolled back; live serves $PrevAsset"
} catch {
    Write-Log "gh-pages rollback failed: $_" 'ERROR'
    exit $script:EXIT_ROLLBACK_FAILED
}

if ($RevertSha) {
    try { Invoke-RevertOnMain -Repo $RepoPath -Sha $RevertSha }
    catch { Write-Log "revert of $RevertSha on main failed: $_ (production is rolled back; main is not)" 'ERROR'; exit $script:EXIT_ROLLBACK_FAILED }
}
Save-State 'frontend-last-rollback' @{ ghPagesSha = $PrevSha; asset = $PrevAsset; revertedSha = $RevertSha; finishedUtc = [DateTime]::UtcNow.ToString('o') }
Write-Log 'ROLLBACK complete'
exit $script:EXIT_OK
