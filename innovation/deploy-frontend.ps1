<#
.SYNOPSIS
  Deploy solid-website (origin/main) to GitHub Pages, verify the served bytes, auto-rollback on failure.

.DESCRIPTION
  Runs in the loop's own clone (never in D:\projects\solid-website, which holds Ve's uncommitted work).
  1. clone must be clean and at origin/main
  2. record the current origin/gh-pages sha and live asset (state\frontend-last-deploy.json)
  3. yarn install --frozen-lockfile; yarn deploy   (build:all + gh-pages push)
  4. wait for the Pages build of the new gh-pages sha to succeed
  5. cache-busted live page must reference the exact new assets/index-*.js, which must 200 and contain
     -ExpectString; /storybook/ and /Ve-Bui-Resume.pdf must 200
  On failure in 4/5: rollback-frontend.ps1 (gh-pages back to the old sha; also reverts -MergeSha on main if given).

.EXIT CODES
  0 deployed and verified | 1 precondition failed, nothing changed | 2 verify failed, rolled back
  3 verify failed AND rollback failed (human needed) | 4 build/push failed before anything went live
#>
[CmdletBinding()]
param(
    # A string that only exists in the new bundle (e.g. new UI copy). Strongly recommended.
    [string]$ExpectString = '',
    # The merge (or squash) commit on main that introduced the change; reverted on rollback.
    [string]$MergeSha = '',
    [string]$RepoPath = '',
    # Skip the auto-rollback (for manual debugging only; the loop must never pass this).
    [switch]$NoRollback
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog 'deploy-frontend'
if (-not $RepoPath) { $RepoPath = $script:FrontClone }
Add-GhToPath

try {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { throw "no git clone at $RepoPath" }
    if ((Resolve-Path $RepoPath).Path.TrimEnd('\') -ieq 'D:\projects\solid-website') { throw 'refusing to deploy from Ve''s working checkout; use the loop clone' }
    Invoke-Git -Repo $RepoPath -Arguments @('fetch', 'origin', '--prune') | Out-Null
    $dirty = Invoke-Git -Repo $RepoPath -Arguments @('status', '--porcelain', '--untracked-files=no')
    if (@($dirty.Output | Where-Object { $_.Trim() }).Count -gt 0) { throw 'clone has uncommitted changes' }
    $head = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'HEAD')
    $main = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/main')
    if ($head -ne $main) { throw "clone HEAD $head is not origin/main $main (merge the PR and reset the clone first)" }
    if ($MergeSha) {
        $anc = Invoke-Git -Repo $RepoPath -Arguments @('merge-base', '--is-ancestor', $MergeSha, 'origin/main') -AllowFail
        if ($anc.Code -ne 0) { throw "MergeSha $MergeSha is not on origin/main" }
    }
    $prevSha = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/gh-pages')
    $prevPage = Invoke-Http -Url (Get-CacheBustedUrl $script:SiteUrl)
    $prevAsset = Get-IndexAsset $prevPage.Body
    Write-Log "previous gh-pages=$prevSha live asset=$prevAsset main=$main"
    Save-State 'frontend-last-deploy' @{ prevGhPagesSha = $prevSha; prevAsset = $prevAsset; mainSha = $main; mergeSha = $MergeSha; startedUtc = [DateTime]::UtcNow.ToString('o'); status = 'started' }
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    exit $script:EXIT_PRECONDITION
}

# ---- build + publish ----------------------------------------------------------
$pushUtc = [DateTime]::UtcNow
try {
    Invoke-Native -File 'cmd' -Arguments @('/c', 'yarn install --frozen-lockfile 2>&1') -WorkDir $RepoPath | Out-Null
    Invoke-Native -File 'cmd' -Arguments @('/c', 'yarn deploy 2>&1') -WorkDir $RepoPath | Out-Null
} catch {
    Write-Log "build/deploy command failed: $_" 'ERROR'
    # gh-pages only pushes after a successful build; check whether the remote moved anyway.
    Invoke-Git -Repo $RepoPath -Arguments @('fetch', 'origin', '--prune') -AllowFail | Out-Null
    $now = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/gh-pages')
    if ($now -eq $prevSha) { Write-Log 'gh-pages unchanged; nothing went live'; exit $script:EXIT_BUILD_FAILED }
    Write-Log "gh-pages moved to $now despite the failure; rolling back" 'ERROR'
}

$distIndex = Join-Path $RepoPath 'dist\index.html'
$newAsset = $null
if (Test-Path -LiteralPath $distIndex) { $newAsset = Get-IndexAsset (Get-Content -LiteralPath $distIndex -Raw) }
Invoke-Git -Repo $RepoPath -Arguments @('fetch', 'origin', '--prune') | Out-Null
$newSha = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/gh-pages')
Write-Log "new gh-pages=$newSha new asset=$newAsset"

$verified = $false
if ($newAsset -and $newSha -ne $prevSha) {
    if (Wait-PagesBuild -Sha $newSha -NotBeforeUtc $pushUtc) {
        $verified = Test-LiveSite -Asset $newAsset -ExpectString $ExpectString
    }
} elseif ($newSha -eq $prevSha) {
    Write-Log 'gh-pages did not change (identical build?). Treating as failure so the loop notices.' 'ERROR'
    Save-State 'frontend-last-deploy' @{ prevGhPagesSha = $prevSha; prevAsset = $prevAsset; mainSha = $main; mergeSha = $MergeSha; status = 'no-change' }
    exit $script:EXIT_BUILD_FAILED
}

if ($verified) {
    Save-State 'frontend-last-deploy' @{ prevGhPagesSha = $prevSha; prevAsset = $prevAsset; newGhPagesSha = $newSha; newAsset = $newAsset; mainSha = $main; mergeSha = $MergeSha; finishedUtc = [DateTime]::UtcNow.ToString('o'); status = 'deployed' }
    Write-Log "DEPLOYED and verified: $newAsset (gh-pages $newSha)"
    exit $script:EXIT_OK
}

Write-Log 'verification FAILED' 'ERROR'
if ($NoRollback) { Write-Log '-NoRollback given; leaving production as is' 'WARN'; exit $script:EXIT_ROLLBACK_FAILED }
$rbArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$PSScriptRoot\rollback-frontend.ps1", '-PrevSha', $prevSha, '-RepoPath', $RepoPath)
if ($prevAsset) { $rbArgs += @('-PrevAsset', $prevAsset) }
if ($MergeSha) { $rbArgs += @('-RevertSha', $MergeSha) }
& powershell.exe @rbArgs
if ($LASTEXITCODE -eq 0) { Write-Log 'rolled back successfully'; exit $script:EXIT_ROLLED_BACK }
Write-Log "ROLLBACK FAILED (exit $LASTEXITCODE). Production needs a human." 'ERROR'
exit $script:EXIT_ROLLBACK_FAILED
