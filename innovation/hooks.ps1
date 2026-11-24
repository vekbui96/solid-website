# PROJECT HOOKS, NON-ELEVATED side. Dot-sourced after lib.ps1 by test-gate.ps1, merge-pr.ps1, deploy.ps1
# and rollback.ps1. This is the file to edit per project (with loop.config.json and hooks-server.ps1).
# Every function below is called by the generic scripts; keep the names and return shapes.
#
# Portfolio: solid-website (yarn, Vite + Storybook, published by hand to gh-pages: frontend.mode = manual) and
# solid-website-api (Maven; deployed by the elevated side, hooks-server.ps1). Neither repo has CI, so
# merge-pr.ps1 runs repos[].localGate itself. Keep it PowerShell 5.1 and ASCII. Never read or print a secret here.

# ---- HOOK: test gate ---------------------------------------------------------------------------
# Steps the loop may run through test-gate.ps1 (and merge-pr.ps1's local gate: loop.config.json
# repos[].localGate, because neither repo has CI). 'all' expands to $script:TestStepsAll; a step that does
# not apply to the repo passes with a log line. Everything runs in the LOOP'S CLONE (or merge-pr's detached
# worktree of the PR head), never in D:\projects or a live dir. Nothing here calls the live API.
#   solid-website:      install (yarn --frozen-lockfile), typecheck (tsc errors must not exceed origin/main's
#                       count: main has known errors and TypeScript is loose), build (yarn build:all: dist +
#                       dist\storybook, the entry under ./assets/, -ExpectString in the built files), smoke
#                       (vite preview on 127.0.0.1:4173 + headless Edge: <main-page>'s shadow root renders)
#   solid-website-api:  verify (mvnw -B verify; no secrets, no network calls to production)
$script:TestStepsAll = @('install', 'typecheck', 'build', 'smoke', 'verify')
$script:TestStepsValid = @('install', 'typecheck', 'build', 'smoke', 'verify')
$script:FrontSteps = @('install', 'typecheck', 'build', 'smoke')
$script:ApiSteps = @('verify')
$script:PreviewPort = 4173

function Invoke-Cmd {
    # cmd /c with stderr folded into stdout (PS 5.1 turns native stderr into errors); .\ prefixes are needed
    # for files in the work dir (NoDefaultCurrentDirectoryInExePath=1 on this box).
    param([string]$Line, [string]$WorkDir, [switch]$Quiet)
    return (Invoke-Native -File 'cmd' -Arguments @('/c', "$Line 2>&1") -WorkDir $WorkDir -AllowFail -Quiet:$Quiet)
}

function Get-TscErrorCount {
    param([string]$Dir)
    $r = Invoke-Cmd -Line 'npx tsc --noEmit -p .' -WorkDir $Dir -Quiet
    return @($r.Output | Where-Object { $_ -match 'error TS\d+' }).Count
}

# tsc error count of origin/main, cached per main sha (state\tsc-baseline.json). Computed in a detached
# worktree under work\ that borrows $RepoPath's node_modules through a junction (types only).
function Get-TscBaseline {
    param([string]$RepoPath)
    $base = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/main')
    $cache = Read-State 'tsc-baseline'
    if ($cache -and "$($cache.sha)" -eq $base) { return [int]$cache.count }
    $head = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'HEAD')
    if ($head -eq $base) { $n = Get-TscErrorCount $RepoPath }
    else {
        $wt = Join-Path $script:LoopHome 'work\tsc-baseline'
        if (Test-Path -LiteralPath $wt) { Invoke-Git -Repo $RepoPath -Arguments @('worktree', 'remove', '--force', $wt) -AllowFail -Quiet | Out-Null; if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force } }
        Invoke-Git -Repo $RepoPath -Arguments @('worktree', 'add', '--detach', $wt, $base) -Quiet | Out-Null
        try {
            $null = Invoke-Cmd -Line "mklink /J `"$wt\node_modules`" `"$RepoPath\node_modules`"" -WorkDir $RepoPath -Quiet
            $n = Get-TscErrorCount $wt
        } finally {
            if (Test-Path -LiteralPath "$wt\node_modules") { $null = Invoke-Cmd -Line "rmdir `"$wt\node_modules`"" -WorkDir $RepoPath -Quiet }   # the junction only
            Invoke-Git -Repo $RepoPath -Arguments @('worktree', 'remove', '--force', $wt) -AllowFail -Quiet | Out-Null
        }
    }
    Save-State 'tsc-baseline' @{ sha = $base; count = $n }
    return [int]$n
}

function Test-PortFree {
    param([int]$Port)
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', $Port); return $false } catch { return $true } finally { $c.Close() }
}

# Stop a process and every descendant (vite preview runs as cmd -> node -> cmd -> node). taskkill /T answers
# "Access denied" under the loop's reduced token, so walk the tree with CIM and stop each one; never throws.
function Stop-ProcessTree {
    param([int]$Id)
    try { foreach ($c in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$Id" -ErrorAction SilentlyContinue)) { Stop-ProcessTree -Id ([int]$c.ProcessId) } } catch { }
    Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue
}
# Serve $RepoPath\dist with vite preview on 127.0.0.1:<port>, run $Body with the URL, always stop the server.
function Invoke-WithPreview {
    param([string]$RepoPath, [scriptblock]$Body, [int]$Port = $script:PreviewPort)
    if (-not (Test-PortFree $Port)) { throw "port $Port is busy (refusing to reuse a server that may not be ours)" }
    $logDir = Join-Path $script:LoopHome 'logs'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # node runs vite directly (no cmd/npx in between): under the reduced token the loop can stop its direct child,
    # not grandchildren started through cmd/npx (they come up with a DACL the reduced token cannot open)
    $vite = Join-Path $RepoPath 'node_modules\vite\bin\vite.js'
    if (-not (Test-Path -LiteralPath $vite)) { throw 'vite is not installed in the clone (run the install step first)' }
    $proc = Start-Process -FilePath $script:NodeExe -ArgumentList @("`"$vite`"", 'preview', '--port', "$Port", '--strictPort', '--host', '127.0.0.1') -WorkingDirectory $RepoPath `
        -RedirectStandardOutput (Join-Path $logDir "preview-$stamp.out.log") -RedirectStandardError (Join-Path $logDir "preview-$stamp.err.log") -PassThru -WindowStyle Hidden
    try {
        $url = "http://127.0.0.1:$Port/"
        $html = $null
        for ($i = 0; $i -lt 40 -and -not $html; $i++) { Start-Sleep -Seconds 1; $r = Invoke-Http -Url $url -TimeoutSec 5; if ($r.Status -eq 200) { $html = $r.Body } }
        if (-not $html) { throw "vite preview did not answer on $url" }
        if ($html -notmatch '<main-page') { throw 'preview HTML has no <main-page>' }
        return (& $Body $url)
    } finally {
        Stop-ProcessTree -Id $proc.Id
    }
}

function Invoke-TestStep {
    param([string]$Step, [string]$RepoName, [string]$RepoPath, [string]$Issue, [string]$ExpectString, [string]$UnitFilter)
    $isFront = ($RepoName -eq 'solid-website')
    if ($isFront -and $script:FrontSteps -notcontains $Step) { Write-Log "step $Step does not apply to $RepoName"; return $null }
    if (-not $isFront -and $script:ApiSteps -notcontains $Step) { Write-Log "step $Step does not apply to $RepoName"; return $null }
    switch ($Step) {
        'install' {
            # lockfile install only: a change whose yarn.lock does not match package.json does not fit the loop
            $r = Invoke-Cmd -Line 'yarn install --frozen-lockfile --non-interactive' -WorkDir $RepoPath -Quiet
            if ($r.Code -ne 0) { return "yarn install --frozen-lockfile failed (exit $($r.Code)); package.json and yarn.lock must agree (never package-lock.json)" }
        }
        'typecheck' {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'node_modules'))) { return 'run the install step first' }
            $baseline = Get-TscBaseline -RepoPath $RepoPath
            $now = Get-TscErrorCount $RepoPath
            Write-Log "tsc errors: now=$now origin/main=$baseline"
            if ($now -gt $baseline) { return "typecheck: $now errors, origin/main has $baseline (new type errors introduced)" }
        }
        'build' {
            # build:all = vite build, THEN storybook into dist\storybook (the order is load-bearing). Build env is
            # set in PowerShell, never through Git Bash (it mangles paths).
            $r = Invoke-Cmd -Line 'yarn build:all' -WorkDir $RepoPath -Quiet
            if ($r.Code -ne 0) { return ("yarn build:all failed (exit $($r.Code)): " + (($r.Output | Select-Object -Last 6) -join ' | ')) }
            $dist = Join-Path $RepoPath 'dist'
            $idx = Join-Path $dist 'index.html'
            if (-not (Test-Path -LiteralPath $idx)) { return 'dist\index.html missing' }
            if (-not (Test-Path -LiteralPath (Join-Path $dist 'storybook\index.html'))) { return 'dist\storybook\index.html missing (build:all order broken?)' }
            $entry = Get-EntryAsset (Get-Content -LiteralPath $idx -Raw)
            if (-not $entry) { return 'built index.html does not reference ./assets/index-*.js (base must stay "")' }
            Write-Log "built entry: $entry"
            if ($ExpectString) {
                $hit = Get-ChildItem -LiteralPath (Join-Path $dist 'assets') -Recurse -File -Include *.js, *.css | Select-String -SimpleMatch -Pattern $ExpectString -List | Select-Object -First 1
                if (-not $hit) { $hit = Get-ChildItem -LiteralPath $dist -File -Filter *.html | Select-String -SimpleMatch -Pattern $ExpectString -List | Select-Object -First 1 }
                if (-not $hit) { return 'ExpectString not found in any built site file (dist\assets, dist\*.html)' }
                Write-Log "ExpectString found in $(Split-Path $hit.Path -Leaf)"
            }
        }
        'smoke' {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'dist\index.html'))) { return 'run the build step first' }
            try {
                $res = Invoke-WithPreview -RepoPath $RepoPath -Body {
                    param($url)
                    $s = Invoke-Native -File $script:NodeExe -Arguments @((Join-Path $script:KitDir 'smoke.mjs'), $RepoPath, $url, '-', 'main-page', '1280') -AllowFail
                    if ($s.Code -eq 1) { return ('render check failed: ' + ($s.Output -join ' ')) }
                    if ($s.Code -eq 2) { Write-Log 'render check could not run (playwright-core or browser missing); HTML check only' 'WARN' }
                    return $null
                }
                if ($res) { return $res }
            } catch { return "smoke: $_" }
        }
        'verify' {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'mvnw.cmd'))) { return "no mvnw.cmd in $RepoPath" }
            $r = Invoke-Cmd -Line '.\mvnw.cmd -B verify' -WorkDir $RepoPath -Quiet
            $tail = @($r.Output | Where-Object { $_ -match 'Tests run:|BUILD (SUCCESS|FAILURE)|ERROR\]' } | Select-Object -Last 12)
            foreach ($t in $tail) { Write-Log "  $t" }
            if ($r.Code -ne 0 -or -not ($r.Output -match 'BUILD SUCCESS')) { return ("mvnw -B verify failed (exit $($r.Code)): " + (($tail | Select-Object -Last 4) -join ' | ')) }
        }
        default { return "unknown step $Step" }
    }
    return $null
}

# ---- HOOK: what counts as front-end ----------------------------------------------------------------
# Changed files that ship in the public bundle. A merge touching any of them must be deployed with an
# -ExpectString (a string only the new build contains) so the live check can prove the new build is served.
function Test-IsFrontendFile {
    param([string]$Path)
    $p = $Path.Replace('\', '/')
    # src/ui is the Storybook exhibit, not imported by the site: it ships only to /storybook/, which the live
    # check covers as an extra URL (frontend.extraLive), not by an -ExpectString in the site bundle
    if ($p -match '^src/ui/|\.stories\.[jt]sx?$|^\.storybook/') { return $false }
    if ($p -match '\.test\.[jt]sx?$|/__tests__/|^e2e/|^test/') { return $false }
    foreach ($re in @(Get-Cfg 'frontend.paths' @('^src/', '^public/', '^index\.html$'))) { if ($p -match $re) { return $true } }
    return $false
}

# ---- HOOK: extra merge checks on added lines ----------------------------------------------------------
# merge-pr.ps1 calls this for every ADDED line of the PR diff. Return a refusal reason or $null.
function Test-MergeLine {
    param([string]$File, [string]$Line)
    foreach ($root in @(Get-Cfg 'liveRoots' @('D:\services'))) {
        if ($Line -match ('(?i)' + [regex]::Escape($root).Replace('\\', '[\\/]+'))) { return "$File adds a reference to $root (code and tests must never point at live data)" }
    }
    if ($Line -match 'VITE_[A-Z_]*(TOKEN|SECRET|KEY|PASSWORD)') { return "$File puts a secret-looking name in a VITE_ variable (ships in the public bundle)" }
    foreach ($rule in @(Get-Cfg 'mergeLineDeny' @())) {
        if ($Line -match $rule.pattern) { return "${File}: $($rule.why)" }
    }
    return $null
}

# ---- HOOK: front-end deploy (manual: yarn deploy -> gh-pages) ---------------------------------------
# The site is published by hand: `yarn deploy` = build:all + `gh-pages -d dist`, which pushes dist\ as a new
# commit on the gh-pages branch; GitHub Pages then serves it. From the loop's clone at origin/main:
#  - the clone's origin must be the repo's SSH alias, and gh-pages gets it explicitly (`--repo`): it otherwise
#    asks git for remote.origin.url inside its cached publish clone
#  - that cache (node_modules\.cache\gh-pages\<repo>) may have been left owned by Administrators by an older
#    elevated run; under the reduced token git calls that "dubious ownership" and gh-pages reports
#    "Failed to get remote.origin.url" (runs 20261116-140147 and 20261121-194352). loop.config.json
#    gitSafeExtra gives every git child a safe.directory entry for it; if git still cannot use it, it is
#    deleted here (gh-pages clones it again)
#  - the gh-pages sha before the push is recorded (state\ghpages-last.json): the instant rollback target
#  - success = gh-pages moved AND the Pages build of the new sha succeeded; the live content check follows in
#    Test-FrontendLive (deploy.ps1)
function Wait-PagesBuild {
    param([string]$Slug, [string]$Sha, [datetime]$NotBeforeUtc, [int]$TimeoutSec = 600)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $json = Get-GhJson @('api', "repos/$Slug/actions/runs?branch=gh-pages&per_page=10")
            $runs = @($json.workflow_runs | Where-Object { $_.head_sha -eq $Sha -and ([datetime]::Parse($_.created_at).ToUniversalTime() -ge $NotBeforeUtc.AddSeconds(-60)) })
            if ($runs.Count -gt 0) {
                $run = $runs[0]
                Write-Log "pages run $($run.id): status=$($run.status) conclusion=$($run.conclusion)"
                if ($run.status -eq 'completed') { return ($run.conclusion -eq 'success') }
            }
        } catch { Write-Log "could not read the Pages runs: $_" 'WARN' }
        Start-Sleep -Seconds 15
    }
    Write-Log "timed out waiting for the Pages build of $Sha" 'ERROR'
    return $false
}

function Repair-GhPagesCache {
    param([string]$Clone)
    $cache = Join-Path $Clone 'node_modules\.cache\gh-pages'
    if (-not (Test-Path -LiteralPath $cache)) { return }
    foreach ($d in @(Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue)) {
        $ok = Invoke-Git -Repo $d.FullName -Arguments @('rev-parse', '--git-dir') -AllowFail -Quiet
        if ($ok.Code -ne 0) {
            Write-Log "gh-pages cache $($d.FullName) is unusable by git here (owner: $((Get-Acl -LiteralPath $d.FullName).Owner)); removing it (gh-pages re-clones it)" 'WARN'
            Remove-Item -LiteralPath $d.FullName -Recurse -Force
        }
    }
}

function Invoke-FrontendDeploy {
    param([string]$RepoName, [string]$MergeSha, [int]$Issue)
    $cfgRepo = Get-RepoCfg $RepoName
    $clone = Get-ClonePath $RepoName
    $url = "$($cfgRepo.cloneUrl)"
    try {
        Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') -Quiet | Out-Null
        Invoke-Git -Repo $clone -Arguments @('checkout', '-f', '-B', 'main', 'origin/main') -Quiet | Out-Null
        Invoke-Git -Repo $clone -Arguments @('reset', '--hard', 'origin/main') -Quiet | Out-Null
        $main = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'HEAD')
        $anc = Invoke-Git -Repo $clone -Arguments @('merge-base', '--is-ancestor', $MergeSha, $main) -AllowFail -Quiet
        if ($anc.Code -ne 0) { throw "$MergeSha is not in origin/main ($main)" }
        $origin = Get-GitValue -Repo $clone -Arguments @('remote', 'get-url', 'origin')
        if ($origin -ne $url) { throw "clone origin is '$origin', expected $url" }
        Repair-GhPagesCache -Clone $clone
        $prev = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'origin/gh-pages')
        Save-State 'ghpages-last' @{ issue = $Issue; mergeSha = $MergeSha; mainSha = $main; prevGhPagesSha = $prev; startedUtc = [DateTime]::UtcNow.ToString('o'); status = 'started' }
        Write-Log "front-end deploy: main=$main (contains $MergeSha); gh-pages before=$prev"
    } catch { Write-Log "front-end deploy precondition: $_" 'ERROR'; return $false }

    $pushUtc = [DateTime]::UtcNow
    $i = Invoke-Cmd -Line 'yarn install --frozen-lockfile --non-interactive' -WorkDir $clone -Quiet
    if ($i.Code -ne 0) { Write-Log "yarn install failed (exit $($i.Code)); nothing published" 'ERROR'; return $false }
    $d = Invoke-Cmd -Line "yarn deploy --repo $url" -WorkDir $clone
    if ($d.Code -ne 0) { Write-Log "yarn deploy failed (exit $($d.Code))" 'ERROR' }
    Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') -Quiet | Out-Null
    $new = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'origin/gh-pages')
    $st = Read-State 'ghpages-last'
    $rec = @{ issue = $Issue; mergeSha = $MergeSha; mainSha = "$($st.mainSha)"; prevGhPagesSha = "$($st.prevGhPagesSha)"; newGhPagesSha = $new; startedUtc = "$($st.startedUtc)"; status = 'pushed' }
    if ($new -eq "$($st.prevGhPagesSha)") {
        $rec.status = 'unchanged'; Save-State 'ghpages-last' $rec
        if ($d.Code -eq 0) {
            # gh-pages pushes nothing when dist\ is byte-identical (a change that ships nothing, e.g. docs): not a
            # failure; deploy.ps1's live check still requires -ExpectString when front-end files changed
            Write-Log "gh-pages did not move ($new): the build is identical to what is live, nothing to publish" 'WARN'
            return $true
        }
        Write-Log "gh-pages did not move ($new): nothing went live" 'ERROR'
        return $false
    }
    Save-State 'ghpages-last' $rec
    Write-Log "gh-pages moved $($st.prevGhPagesSha) -> $new$(if ($d.Code -ne 0) { ' despite the failed command' })"
    if ($d.Code -ne 0) { return $false }
    if (-not (Wait-PagesBuild -Slug $cfgRepo.slug -Sha $new -NotBeforeUtc $pushUtc)) { return $false }
    $rec.status = 'built'; Save-State 'ghpages-last' $rec
    return $true
}

# ---- HOOK: front-end live verification ----------------------------------------------------------------
# Verify by CONTENT, not status code: a blank SPA returns 200. Default: cache-busted index.html must name an
# entry asset under frontend.assetBase; with -NotSignature the signature (asset set + index.html hash) must
# differ from the previous build; every file reachable from index.html (its assets, then every chunk any
# fetched JS names, at ANY depth: live-check.ps1 Find-InChunkGraph) must load; -ExpectString must be in
# index.html or one of them (screens are
# code-split and nested: the entry alone, or one level of chunks, is a false negative) and -AbsentString in
# none; then a headless render (smoke.mjs) must show a non-empty root with no uncaught error.
# Asset names may be absolute ("/app/assets/x.js") or relative ("./assets/x.js"): both resolve against siteUrl.
function Get-EntryAsset {
    param([string]$Html)
    $base = [regex]::Escape("$(Get-Cfg 'frontend.assetBase' '/assets/')")
    $m = [regex]::Match($Html, "src=`"($base[A-Za-z0-9_\-\.]+\.js)`"")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}
function Get-AssetSet {
    param([string]$Html)
    $base = [regex]::Escape("$(Get-Cfg 'frontend.assetBase' '/assets/')")
    return @([regex]::Matches($Html, "`"($base[A-Za-z0-9_\-\.]+\.(?:js|css))`"") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
function Resolve-SiteUrl {
    param([string]$Site, [string]$Ref)
    return ([uri]::new([uri]$Site, $Ref)).AbsoluteUri
}
# The build's signature: its asset set plus a hash of index.html itself (line endings normalised), so a
# merge that only changes index.html (meta tags, the font link: same hashed bundles) still counts as a new
# build and is not refused as "still serving the previous build" forever (#22, #39).
function Get-PageSignature {
    param([string]$Html)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(("$Html" -replace "`r`n", "`n").Trim())) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
    return ((Get-AssetSet $Html) -join ',') + '|html:' + $h.Substring(0, 16)
}
function Get-FrontendSignature {
    $url = "$(Get-Cfg 'frontend.siteUrl' '')"
    if (-not $url) { return '' }
    return (Get-PageSignature (Invoke-Http -Url (Get-CacheBustedUrl $url)).Body)
}
function Test-FrontendLive {
    param([string]$ExpectString = '', [string]$AbsentString = '', [string]$NotSignature = '', [string]$RepoForSmoke = '', [string]$ShotPath = '', [int]$TimeoutSec = 600)
    $site = "$(Get-Cfg 'frontend.siteUrl' '')"
    if (-not $site) { Write-Log 'no frontend.siteUrl: nothing to verify'; return @{ Ok = $true; Asset = $null; Signature = $null } }
    $assetBase = "$(Get-Cfg 'frontend.assetBase' '/assets/')"
    $assetDir = Resolve-SiteUrl $site $assetBase
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = ''
    while ((Get-Date) -lt $deadline) {
        $page = Invoke-Http -Url (Get-CacheBustedUrl $site)
        $asset = Get-EntryAsset $page.Body
        $sig = Get-PageSignature $page.Body
        if ($page.Status -ne 200 -or -not $asset) { $last = "page status=$($page.Status) entry=$asset" }
        elseif ($NotSignature -and $sig -eq $NotSignature) { $last = "still serving the previous build ($asset)" }
        else {
            $entry = Invoke-Http -Url (Resolve-SiteUrl $site $asset)
            if ($entry.Status -ne 200 -or $entry.Body.Length -lt 500) { $last = "entry $asset status=$($entry.Status)" }
            else {
                $roots = @(Get-AssetSet $page.Body | ForEach-Object { $_.Substring($assetBase.Length) })
                $entryName = $asset.Substring($assetBase.Length)
                $fetch = { param([string]$Name) Invoke-Http -Url ($assetDir + $Name) }
                $g = Find-InChunkGraph -Roots $roots -Fetch $fetch -Preloaded @{ $entryName = $entry } -ExpectString $ExpectString -AbsentString $AbsentString
                # index.html is served bytes too: a head-only change (meta tags, link preview) can only be
                # seen there, and its rollback must find the string gone from there as well
                if ($ExpectString -and -not $g.Found -and $page.Body.Contains($ExpectString)) { $g.Found = $true; $g.FoundIn = 'index.html'; $g.FoundDepth = 0 }
                if ($AbsentString -and -not $g.AbsentHit -and $page.Body.Contains($AbsentString)) { $g.AbsentHit = 'index.html' }
                $bad = @($g.Unreachable).Count
                Write-Log ("live entry={0} files={1} maxDepth={2} unreachable={3}{4} expect={5}{6} absentHit={7}{8}" -f $asset, @($g.Files).Count, $g.MaxDepth, $bad,
                    $(if ($bad) { ' (' + ((@($g.Unreachable) | Select-Object -First 5) -join ', ') + ')' } else { '' }),
                    $g.Found, $(if ($g.FoundIn) { " ($($g.FoundIn), depth $($g.FoundDepth))" } else { '' }), $g.AbsentHit,
                    $(if ($g.Capped) { " CAPPED at $($script:LiveChunkCap) files" } else { '' }))
                $extra = Test-FrontendExtraLive
                if (((-not $ExpectString) -or $g.Found) -and (-not $g.AbsentHit) -and $bad -eq 0 -and -not $g.Capped -and -not $extra) {
                    if (-not $RepoForSmoke) { return @{ Ok = $true; Asset = $asset; Signature = $sig } }
                    $smokeArgs = @((Join-Path $script:KitDir 'smoke.mjs'), $RepoForSmoke, (Get-CacheBustedUrl $site), $(if ($ShotPath) { $ShotPath } else { '-' }), "$(Get-Cfg 'frontend.rootSelector' 'body')")
                    $s = Invoke-Native -File $script:NodeExe -Arguments $smokeArgs -AllowFail
                    if ($s.Code -eq 0) { return @{ Ok = $true; Asset = $asset; Signature = $sig } }
                    if ($s.Code -eq 2) { Write-Log 'render check could not run (no playwright-core or browser); served-bytes checks passed' 'WARN'; return @{ Ok = $true; Asset = $asset; Signature = $sig } }
                    $last = 'render check failed: ' + ($s.Output -join ' ')
                } elseif ($g.Capped) { $last = "chunk graph exceeds $($script:LiveChunkCap) files (raise `$script:LiveChunkCap in live-check.ps1 deliberately)" }
                elseif ($extra) { $last = $extra }
                else { $last = 'string/file checks not passing' }
            }
        }
        Write-Log "live check not yet passing: $last"
        Start-Sleep -Seconds 20
    }
    Write-Log "live site verification failed: $last" 'ERROR'
    return @{ Ok = $false; Asset = $null; Signature = $null }
}
# HOOK: other live URLs that must keep working after a front-end deploy: loop.config.json frontend.extraLive
# (the Storybook sub-site and the resume PDF), relative to siteUrl. GET only; $null when all answer 200.
function Test-FrontendExtraLive {
    $site = "$(Get-Cfg 'frontend.siteUrl' '')"
    foreach ($rel in @(Get-Cfg 'frontend.extraLive' @())) {
        $u = Get-CacheBustedUrl (Resolve-SiteUrl $site "$rel")
        $r = Invoke-Http -Url $u -TimeoutSec 30
        if ($r.Status -ne 200) { return "$rel status=$($r.Status)" }
    }
    return $null
}

# ---- HOOK: front-end rollback (manual: gh-pages back to the recorded sha, then revert main) -------------
# 1. if state\ghpages-last.json records a push for THIS merge and gh-pages is still at that push (or moved
#    exactly one deploy commit past the recorded previous sha), force-with-lease gh-pages back to the previous
#    sha (gh-pages only appends commits, so it must be an ancestor) and wait for its Pages build; if nothing
#    was pushed, gh-pages is left alone
# 2. git revert of the merge on main (never a force-push of main), so the next `yarn deploy` does not bring the
#    change back
# 3. live check: -AbsentString in no reachable chunk, the extra URLs answer, the page renders
function Invoke-FrontendRollback {
    param([string]$RepoName, [string]$MergeSha, [string]$AbsentString = '', [string]$ShotPath = '')
    $cfgRepo = Get-RepoCfg $RepoName
    $clone = Get-ClonePath $RepoName
    $st = Read-State 'ghpages-last'
    Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') -Quiet | Out-Null
    $cur = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'origin/gh-pages')
    if ($st -and "$($st.mergeSha)" -eq $MergeSha -and "$($st.prevGhPagesSha)" -match '^[0-9a-f]{40}$' -and $cur -ne "$($st.prevGhPagesSha)") {
        $prev = "$($st.prevGhPagesSha)"
        $known = ("$($st.newGhPagesSha)" -eq $cur)
        if (-not $known) {
            $parent = (Invoke-Git -Repo $clone -Arguments @('rev-parse', "$cur^1") -AllowFail -Quiet).Output | Select-Object -Last 1
            $known = ("$parent".Trim() -eq $prev)
        }
        if (-not $known) { Write-Log "gh-pages ($cur) moved beyond the recorded deploy of $MergeSha (prev $prev); not resetting it" 'ERROR'; return $false }
        $anc = Invoke-Git -Repo $clone -Arguments @('merge-base', '--is-ancestor', $prev, 'origin/gh-pages') -AllowFail -Quiet
        if ($anc.Code -ne 0) { Write-Log "$prev is not in origin/gh-pages history; refusing" 'ERROR'; return $false }
        $pushUtc = [DateTime]::UtcNow
        Write-Log "moving gh-pages $cur -> $prev"
        $p = Invoke-Git -Repo $clone -Arguments @('push', "--force-with-lease=gh-pages:$cur", 'origin', "${prev}:refs/heads/gh-pages") -AllowFail
        if ($p.Code -ne 0) { Write-Log 'gh-pages reset push failed' 'ERROR'; return $false }
        if (-not (Wait-PagesBuild -Slug $cfgRepo.slug -Sha $prev -NotBeforeUtc $pushUtc)) { Write-Log 'the Pages build for the rollback did not report success; checking the served bytes anyway' 'WARN' }
        $st | Add-Member -NotePropertyName status -NotePropertyValue 'rolled-back' -Force
        Save-State 'ghpages-last' $st
    } else {
        Write-Log "no gh-pages push recorded for $MergeSha (or gh-pages already at the previous build $cur): gh-pages untouched"
    }
    $null = Invoke-RevertOnMain -Repo $clone -Sha $MergeSha
    $v = Test-FrontendLive -AbsentString $AbsentString -RepoForSmoke $clone -ShotPath $ShotPath -TimeoutSec 600
    return [bool]$v.Ok
}
