# Live front-end chunk walk for the innovation loop (NON-elevated side only). Generic (from the kit).
# Dot-source it AFTER lib.ps1 (deploy.ps1 and rollback.ps1 do):  . "$PSScriptRoot\live-check.ps1"
# PowerShell 5.1 compatible, ASCII only.
#
# Why a separate file: lib.ps1 is one of the elevated side's files (install-task.ps1 copies it into
# C:\ProgramData\innovation-loop-<project>\bin) and any change to it makes that copy stale, which turns
# SERVER_DEPLOY off until the owner re-runs install-task.ps1 -ElevatedOnly. The elevated side never checks
# the live front end, so the walk lives here (the same reason gate-rules.ps1 exists).
#
# The bug this prevents (cardlens, Nov 2026): a live check that searched index.html's assets plus only the
# chunks the ENTRY names. Vite nests dynamic imports (entry -> lazy screen -> its own lazy chunks), so a
# string in a grandchild chunk was never searched, and four working builds were rolled back as "string not
# found" although the change was really served. hooks.ps1 Test-FrontendLive walks the WHOLE graph instead.

$script:LiveChunkCap = 400   # beyond the cap the check fails closed (an unvisited file could hold the AbsentString)

# Chunk references inside a JS chunk or the entry: "./x-hash.js" imports, "assets/x-hash.js" in Vite's
# __vite__mapDeps lists, and absolute "<assetBase>x-hash.css" names. Group 1 is the bare file name.
function Get-ChunkRefPattern {
    $base = "$(Get-Cfg 'frontend.assetBase' '/assets/')"
    $alts = @('\./', 'assets/')
    if ($base -and $base -ne '/assets/' -and $base -ne './assets/') { $alts = @([regex]::Escape($base)) + $alts }
    return '(?:' + ($alts -join '|') + ')?([A-Za-z0-9_\-\.]+-[A-Za-z0-9_\-]{6,}\.(?:js|css))'
}

function Get-ChunkRefs {
    param([string]$Body, [string]$Pattern = '')
    if (-not $Body) { return @() }
    if (-not $Pattern) { $Pattern = Get-ChunkRefPattern }
    return @([regex]::Matches($Body, $Pattern) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

# Breadth-first walk of the chunk graph from the root asset names (index.html's assets). Pure apart from the
# fetcher, so it is unit-tested without HTTP (test-live-check.ps1).
#   -Fetch      scriptblock: param([string]$Name) -> @{ Status = <int>; Body = <string> }, called once per file
#   -Preloaded  name -> already fetched response (the entry), not fetched again
# Every file reached is fetched once (de-duplicated, cycles are fine); every fetched .js body is parsed for
# further references; CSS is searched but not parsed. A file that does not return 200 counts as
# unreachable. If more than -MaxFiles names are discovered the walk stops and Capped is set (the caller
# fails). Returns Files (visited, BFS order), Depth (name -> depth, roots 0), Unreachable, Found, FoundIn,
# FoundDepth, AbsentHit (first file containing AbsentString), Capped, MaxDepth.
function Find-InChunkGraph {
    param([string[]]$Roots, [scriptblock]$Fetch, [hashtable]$Preloaded = @{},
        [string]$ExpectString = '', [string]$AbsentString = '', [int]$MaxFiles = $script:LiveChunkCap, [string]$Pattern = '')
    if (-not $Pattern) { $Pattern = Get-ChunkRefPattern }
    $depth = @{}
    $order = New-Object System.Collections.ArrayList
    $queue = New-Object System.Collections.Queue
    $capped = $false
    foreach ($r in @($Roots)) {
        if (-not $r -or $depth.ContainsKey($r)) { continue }
        $depth[$r] = 0; $queue.Enqueue($r)
    }
    $res = [ordered]@{ Files = @(); Depth = $depth; Unreachable = @(); Found = $false; FoundIn = ''; FoundDepth = -1; AbsentHit = ''; Capped = $false; MaxDepth = 0 }
    $unreachable = New-Object System.Collections.ArrayList
    while ($queue.Count -gt 0) {
        $name = [string]$queue.Dequeue()
        [void]$order.Add($name)
        $resp = if ($Preloaded.ContainsKey($name)) { $Preloaded[$name] } else { & $Fetch $name }
        if (-not $resp -or [int]$resp.Status -ne 200) { [void]$unreachable.Add($name); continue }
        $body = [string]$resp.Body
        if ($depth[$name] -gt $res.MaxDepth) { $res.MaxDepth = $depth[$name] }
        if ($ExpectString -and -not $res.Found -and $body.Contains($ExpectString)) { $res.Found = $true; $res.FoundIn = $name; $res.FoundDepth = $depth[$name] }
        if ($AbsentString -and -not $res.AbsentHit -and $body.Contains($AbsentString)) { $res.AbsentHit = $name }
        if ($name -notlike '*.js') { continue }
        foreach ($c in (Get-ChunkRefs -Body $body -Pattern $Pattern)) {
            if ($depth.ContainsKey($c)) { continue }
            if ($depth.Count -ge $MaxFiles) { $capped = $true; break }
            $depth[$c] = $depth[$name] + 1
            $queue.Enqueue($c)
        }
        if ($capped) { break }
    }
    $res.Files = @($order)
    $res.Unreachable = @($unreachable)
    $res.Capped = $capped
    return [pscustomobject]$res
}

# ==================================================================================================
# -NoVisibleString (deploy.ps1 / test-gate.ps1): a front-end change that ships no new bytes
# ==================================================================================================
# Some approved changes touch front-end paths but cannot change what the site serves: a new module nothing imports
# yet (Vite only bundles what is imported), or a package.json change limited to its "scripts" (a new check script,
# e.g. #36's bundle budget). No -ExpectString can ever be found for them, so they were rolled back after a clean merge.
# -NoVisibleString "<reason>" replaces -ExpectString ONLY when git proves the served output cannot change:
#   - every changed front-end file (hooks.ps1 Test-IsFrontendFile) is either
#       * NEW (status A) under src/ (not public/: Vite copies public/ into dist verbatim), or
#       * package.json with only its "scripts" changed (dependencies, devDependencies and every other key identical);
#   - anything else that ships refuses it: a modified, deleted, renamed or type-changed src/ file, anything in public/,
#     index.html, vite.config.ts, yarn.lock;
#   - no shipped (non-test) src/ file uses import.meta.glob (a glob could bundle a new file without an import).
# The build-output check then proves it (test-gate.ps1: the built dist\index.html, whose asset names are content
# hashes, has the live site's signature; deploy.ps1: the served signature is unchanged after the deploy), together
# with the usual chunk walk, extra URLs and the headless render.

# Is the package.json change limited to "scripts"? Both texts parsed as JSON; any parse failure = no.
function Test-PackageJsonScriptsOnly {
    param([string]$Before, [string]$After)
    try { $b = "$Before".TrimStart([char]0xFEFF) | ConvertFrom-Json; $a = "$After".TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return $false }
    if ($null -eq $b -or $null -eq $a) { return $false }
    $strip = { param($o) $h = [ordered]@{}; foreach ($p in $o.PSObject.Properties) { if ($p.Name -ne 'scripts') { $h[$p.Name] = $p.Value } }; ($h | ConvertTo-Json -Depth 20 -Compress) }
    return ((& $strip $b) -eq (& $strip $a))
}

# The rule, pure. $Changes: @{ Status = 'A'|'M'|'D'|'R100'|'T'|...; Path = <new path>; OldPath = <for renames> } from
# git diff --name-status -M; $IsFront: scriptblock(path) -> bool (Test-IsFrontendFile); $GlobFiles: shipped src files
# that use import.meta.glob at the target; $PackageScriptsOnly: Test-PackageJsonScriptsOnly for package.json.
# Allowed + Reason + Added (new modules) + Front (front-end files seen).
function Get-NoVisibleStringDecision {
    param([object[]]$Changes = @(), [scriptblock]$IsFront, [string[]]$GlobFiles = @(), [bool]$PackageScriptsOnly = $false)
    $mk = { param([bool]$Ok, [string]$Why, [string[]]$Added = @(), [string[]]$Front = @()) [pscustomobject]@{ Allowed = $Ok; Reason = $Why; Added = @($Added); Front = @($Front) } }
    $added = @(); $front = @(); $bad = @()
    foreach ($c in @($Changes | Where-Object { $_ })) {
        $st = "$($c.Status)".Trim().ToUpperInvariant(); $p = "$($c.Path)".Replace('\', '/'); $old = "$($c.OldPath)".Replace('\', '/')
        $isF = (& $IsFront $p) -or ($old -and (& $IsFront $old))
        if (-not $isF) { continue }
        $front += $p
        if ($st -eq 'A' -and $p -match '^src/') { $added += $p; continue }
        if ($st -eq 'M' -and $p -eq 'package.json' -and $PackageScriptsOnly) { continue }
        $why = switch -regex ($st) { '^A' { 'added outside src/ (ships as is)' } '^M' { if ($p -eq 'package.json') { 'package.json changes more than "scripts"' } else { 'modified' } } '^D' { 'deleted' } '^R' { "renamed from $old" } default { "status $st" } }
        $bad += "$p ($why)"
    }
    if ($bad.Count -gt 0) { return (& $mk $false "the change can alter what the site serves: $($bad -join ', ')" $added $front) }
    $globs = @($GlobFiles | Where-Object { $_ -and "$_" -notmatch '\.(test|spec)\.[jt]sx?$|/__tests__/|^e2e/|^test/' })
    if ($added.Count -gt 0 -and $globs.Count -gt 0) { return (& $mk $false "shipped files use import.meta.glob, which could bundle a new file without an import: $($globs -join ', ')" $added $front) }
    if ($front.Count -eq 0) { return (& $mk $true 'no front-end file changed' $added $front) }
    return (& $mk $true "nothing served can change: new unreferenced module(s) [$($added -join ', ')]$(if ($front -contains 'package.json') { ', package.json scripts only' })" $added $front)
}

# The rule over git (From..To in a clone). Needs lib.ps1 and hooks.ps1 (Test-IsFrontendFile). Never throws: a git
# failure refuses (fail closed).
function Get-NoVisibleStringVerdict {
    param([string]$Repo, [string]$From, [string]$To)
    try {
        $r = Invoke-Git -Repo $Repo -Arguments @('diff', '--name-status', '-M', "$From..$To") -Quiet
        $changes = @($r.Output | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
                $f = "$_" -split "`t"
                if ($f.Count -ge 3) { @{ Status = $f[0]; OldPath = $f[1]; Path = $f[2] } } else { @{ Status = $f[0]; Path = $f[1]; OldPath = '' } } })
        $pkg = $false
        if (@($changes | Where-Object { $_.Path -eq 'package.json' -and "$($_.Status)" -eq 'M' }).Count -gt 0) {
            $b = (Invoke-Git -Repo $Repo -Arguments @('show', "${From}:package.json") -Quiet).Output -join "`n"
            $a = (Invoke-Git -Repo $Repo -Arguments @('show', "${To}:package.json") -Quiet).Output -join "`n"
            $pkg = Test-PackageJsonScriptsOnly -Before $b -After $a
        }
        $g = Invoke-Git -Repo $Repo -Arguments @('grep', '-l', 'import.meta.glob', $To, '--', 'src') -AllowFail -Quiet
        $globs = @(); if ($g.Code -eq 0) { $globs = @($g.Output | Where-Object { $_ } | ForEach-Object { ("$_" -replace "^$([regex]::Escape($To)):", '').Trim() }) }
        elseif ($g.Code -ne 1) { return [pscustomobject]@{ Allowed = $false; Reason = "git grep failed (exit $($g.Code))"; Added = @(); Front = @() } }
        return (Get-NoVisibleStringDecision -Changes $changes -IsFront { param($p) Test-IsFrontendFile $p } -GlobFiles $globs -PackageScriptsOnly $pkg)
    } catch { return [pscustomobject]@{ Allowed = $false; Reason = "could not read the change from git: $_"; Added = @(); Front = @() } }
}
