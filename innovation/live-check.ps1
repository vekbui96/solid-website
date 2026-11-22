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
