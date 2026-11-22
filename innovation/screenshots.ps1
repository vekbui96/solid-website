<#
.SYNOPSIS
  Before/after screenshots of the portfolio for a loop PR (LOOP.md section 3 "Screenshots"). Session script.
  Last output line: SCREENSHOTS OK ... | SCREENSHOTS FAIL <why>

.DESCRIPTION
  -Label before|after: serves the solid-website clone's current dist\ (built by `test-gate.ps1 -Step build`)
    with vite preview on 127.0.0.1:4173 and saves full-page screenshots at 390px and 1440px to
    ARTIFACTS\<issue>\<label>-390.png and <label>-1440.png. "before" is taken on main before branching,
    "after" on the branch after the change built.
  -Publish: commits the issue's PNGs to the `loop-screenshots` branch of vekbui96/solid-website (an orphan
    branch nothing builds or serves; plumbing only, no checkout, fast-forward push) and prints a markdown table
    whose image links are pinned to that commit's full sha (raw.githubusercontent.com; the repo is public).
    Paste that table into the PR body's ## Screenshots section and the success comment.
  Runs only in the loop's clone; never touches main, gh-pages or the live site. Project script (portfolio).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [ValidateSet('before', 'after')][string]$Label = '',
    [switch]$Publish
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\hooks.ps1"
Start-ScriptLog "screenshots-$Issue"
Add-GhToPath
$repoCfg = Get-RepoCfg 'solid-website'
$clone = Get-ClonePath 'solid-website'
$art = Join-Path $script:LoopHome "artifacts\$Issue"
if (-not (Test-Path -LiteralPath $art)) { New-Item -ItemType Directory -Path $art | Out-Null }
$branch = 'loop-screenshots'
$widths = @(390, 1440)

function Fail([string]$why) { Write-Log $why 'ERROR'; Write-Output "SCREENSHOTS FAIL $why"; exit 1 }

if ($Label -and $Publish) { Fail 'use -Label or -Publish, not both' }
if (-not $Label -and -not $Publish) { Fail 'pass -Label before|after or -Publish' }

if ($Label) {
    if (-not (Test-Path -LiteralPath (Join-Path $clone 'dist\index.html'))) { Fail "no dist\index.html in ${clone}: run test-gate.ps1 -Issue $Issue -Step build first" }
    $head = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'HEAD')
    try {
        $made = Invoke-WithPreview -RepoPath $clone -Body {
            param($url)
            $out = @()
            foreach ($w in $widths) {
                $png = Join-Path $art "$Label-$w.png"
                $s = Invoke-Native -File $script:NodeExe -Arguments @((Join-Path $script:KitDir 'smoke.mjs'), $clone, $url, $png, 'main-page', "$w", 'full') -AllowFail
                if ($s.Code -ne 0) { throw "render at ${w}px failed (exit $($s.Code)): $($s.Output -join ' ')" }
                $out += $png
            }
            return $out
        }
    } catch { Fail "$_" }
    Save-State "shots-$Issue-$Label" @{ issue = $Issue; label = $Label; head = $head; files = @($made); utc = [DateTime]::UtcNow.ToString('o') }
    Write-Output "SCREENSHOTS OK $Label at $($head.Substring(0, 7)): $(@($made) -join ', ')"
    exit 0
}

# ---- publish -------------------------------------------------------------------------------------------
try {
    $files = @(Get-ChildItem -LiteralPath $art -File -Filter '*.png' | Where-Object { $_.Name -match '^(before|after)-(390|1440)\.png$' })
    if ($files.Count -eq 0) { Fail "no before/after screenshots in $art (run -Label before and -Label after first)" }
    $fetch = Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', "+refs/heads/${branch}:refs/remotes/origin/$branch") -AllowFail -Quiet
    $parent = ''
    if ($fetch.Code -eq 0) { $parent = Get-GitValue -Repo $clone -Arguments @('rev-parse', "refs/remotes/origin/$branch") }
    $entries = @()
    if ($parent) {
        foreach ($l in @((Invoke-Git -Repo $clone -Arguments @('ls-tree', $parent) -Quiet).Output | Where-Object { $_ })) {
            $name = ($l -split "`t", 2)[1]
            if ($name -notlike "$Issue-*") { $entries += $l }
        }
    }
    foreach ($f in $files) {
        $blob = Get-GitValue -Repo $clone -Arguments @('hash-object', '-w', $f.FullName)
        $entries += "100644 blob $blob`t$Issue-$($f.Name)"
    }
    $tmp = Join-Path $script:LoopHome "work\shots-tree-$Issue.txt"
    [IO.File]::WriteAllText($tmp, (($entries | Sort-Object { ($_ -split "`t", 2)[1] }) -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    $mk = Invoke-Native -File 'cmd' -Arguments @('/c', "git -C `"$clone`" mktree < `"$tmp`" 2>&1") -AllowFail -Quiet
    $tree = "$(@($mk.Output | Where-Object { $_ }) | Select-Object -Last 1)".Trim()
    if ($tree -notmatch '^[0-9a-f]{40}$') { Fail "git mktree failed: $tree" }
    $msg = "Screenshots for #$Issue (innovation loop)`n`n$($script:CommitTrailer)"
    $msgFile = Join-Path $script:LoopHome "work\shots-msg-$Issue.txt"
    [IO.File]::WriteAllText($msgFile, $msg, (New-Object Text.UTF8Encoding $false))
    $ctArgs = @('commit-tree', $tree, '-F', $msgFile); if ($parent) { $ctArgs += @('-p', $parent) }
    $commit = Get-GitValue -Repo $clone -Arguments $ctArgs
    if ($commit -notmatch '^[0-9a-f]{40}$') { Fail "git commit-tree failed: $commit" }
    $push = Invoke-Git -Repo $clone -Arguments @('push', 'origin', "${commit}:refs/heads/$branch") -AllowFail
    if ($push.Code -ne 0) { Fail "push to $branch failed (exit $($push.Code)); another run may have pushed: run -Publish again" }
} catch { Fail "$_" }

$raw = "https://raw.githubusercontent.com/$($repoCfg.slug)/$commit"
$t = New-Object System.Collections.ArrayList
[void]$t.Add('| Width | Before | After |'); [void]$t.Add('| --- | --- | --- |')
foreach ($w in $widths) {
    $b = if (Test-Path -LiteralPath (Join-Path $art "before-$w.png")) { "![before, ${w}px]($raw/$Issue-before-$w.png)" } else { '(none)' }
    $a = if (Test-Path -LiteralPath (Join-Path $art "after-$w.png")) { "![after, ${w}px]($raw/$Issue-after-$w.png)" } else { '(none)' }
    [void]$t.Add("| ${w}px | $b | $a |")
}
$md = Join-Path $art 'screenshots.md'
[IO.File]::WriteAllText($md, ($t -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
$t | ForEach-Object { Write-Output $_ }
Write-Output "SCREENSHOTS OK published $($files.Count) image(s) at $commit; table in $md"
exit 0
