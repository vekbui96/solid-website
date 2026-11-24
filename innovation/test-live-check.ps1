<#
.SYNOPSIS
  Unit tests for live-check.ps1 (the chunk-graph walk the live front-end check searches) and the default
  hooks.ps1 Test-FrontendLive on top of it, against a fake site. No network, no git. verify-loop.ps1 runs it.
  powershell -ExecutionPolicy Bypass -File innovation\test-live-check.ps1
  Generic (from the innovation-loop kit).
#>
$ErrorActionPreference = 'Stop'
$cfg = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'loop.config.json')) | ConvertFrom-Json
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('loop-live-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
[Environment]::SetEnvironmentVariable('INNOVATION_LOOP_' + ("$($cfg.project)".ToUpperInvariant() -replace '-', '_') + '_HOME', $tmp, 'Process')
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\live-check.ps1"
. "$PSScriptRoot\hooks.ps1"
$script:fail = 0; $script:pass = 0
function Check { param([bool]$Cond, [string]$What) if ($Cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $What" } }

# ---- a fake Vite build: entry -> lazy screen -> nested lazy chunk -> panel --------------------------------
$pad = 'x' * 1200   # the entry must be >= 500 bytes for Test-FrontendLive
$fakeSite = @{
    'index-ENTRY111.js'       = @{ Status = 200; Body = "const __vite__mapDeps=(i,m=__vite__mapDeps,d=(m.f||(m.f=[`"assets/Screen-AAAAAA11.js`",`"assets/Workshop-CCCCCC33.css`"])))=>i.map(i=>d[i]);import{a}from`"./vendor-VVVVVV11.js`";const V=lazy(()=>import(`"./Screen-AAAAAA11.js`"));$pad" }
    'vendor-VVVVVV11.js'      = @{ Status = 200; Body = 'export const a=1;' }
    'index-STYLE111.css'      = @{ Status = 200; Body = '.root{color:red}' }
    'Workshop-CCCCCC33.css'   = @{ Status = 200; Body = '.w{}' }
    'Screen-AAAAAA11.js'      = @{ Status = 200; Body = 'const m=["assets/index-HOME0011.js"];const H=lazy(()=>import("./index-HOME0011.js"));' }
    'index-HOME0011.js'       = @{ Status = 200; Body = 'import"./Screen-AAAAAA11.js";import{P}from"./MoversPanel-MMMMMM11.js";h1("Overview")' }
    'MoversPanel-MMMMMM11.js' = @{ Status = 200; Body = 'export const P=()=>Panel({title:"Biggest movers"});' }
}
$roots = @('index-ENTRY111.js', 'index-STYLE111.css', 'vendor-VVVVVV11.js')
$script:fetched = New-Object System.Collections.ArrayList
$fetch = { param([string]$Name) [void]$script:fetched.Add($Name); if ($fakeSite.ContainsKey($Name)) { $fakeSite[$Name] } else { @{ Status = 404; Body = 'Not Found' } } }

# 1. string only in the great-grandchild (depth 3): found, nothing unreachable, every file once
$g = Find-InChunkGraph -Roots $roots -Fetch $fetch -ExpectString 'Biggest movers'
Check $g.Found 'nested string (depth 3) is found'
Check ($g.FoundIn -eq 'MoversPanel-MMMMMM11.js' -and $g.FoundDepth -eq 3) "found in the panel chunk at depth 3 (got '$($g.FoundIn)' $($g.FoundDepth))"
Check (@($g.Unreachable).Count -eq 0) "nothing unreachable (got $(@($g.Unreachable) -join ','))"
Check (@($g.Files).Count -eq 7) "every reachable file visited once (got $(@($g.Files).Count))"
Check (@($script:fetched | Group-Object | Where-Object { $_.Count -gt 1 }).Count -eq 0) 'no file fetched twice (the cycle is de-duplicated)'
Check (-not $g.Capped -and $g.MaxDepth -eq 3) 'not capped, maxDepth 3'
# 1b. regression: the old one-level set (index assets + what the entry names) misses it
$old = @($roots) + @(Get-ChunkRefs $fakeSite['index-ENTRY111.js'].Body)
Check (-not ($old -contains 'MoversPanel-MMMMMM11.js')) 'regression: the one-level set misses the nested chunk'
# 2. CSS named by a chunk is searched
$g = Find-InChunkGraph -Roots $roots -Fetch $fetch -ExpectString '.w{}'
Check ($g.Found -and $g.FoundIn -eq 'Workshop-CCCCCC33.css') 'CSS named by a chunk is searched'
# 3. missing string
Check (-not (Find-InChunkGraph -Roots $roots -Fetch $fetch -ExpectString 'Nope not here').Found) 'missing string is not found'
# 4. AbsentString in a nested chunk is a hit
Check ((Find-InChunkGraph -Roots $roots -Fetch $fetch -AbsentString 'Biggest movers').AbsentHit -eq 'MoversPanel-MMMMMM11.js') 'absent string in a nested chunk is reported'
# 5. unreachable nested chunk
$fakeSite['index-HOME0011.js'] = @{ Status = 200; Body = 'import"./Gone-GGGGGG11.js";import{P}from"./MoversPanel-MMMMMM11.js";' }
$g = Find-InChunkGraph -Roots $roots -Fetch $fetch -ExpectString 'Biggest movers'
Check (@($g.Unreachable) -contains 'Gone-GGGGGG11.js') 'unreachable nested chunk is reported'
$fakeSite['index-HOME0011.js'] = @{ Status = 200; Body = 'import"./Screen-AAAAAA11.js";import{P}from"./MoversPanel-MMMMMM11.js";' }
# 6. preloaded entry is not fetched again
$script:fetched.Clear()
$null = Find-InChunkGraph -Roots $roots -Fetch $fetch -Preloaded @{ 'index-ENTRY111.js' = $fakeSite['index-ENTRY111.js'] }
Check (-not ($script:fetched -contains 'index-ENTRY111.js')) 'preloaded entry is not refetched'
# 7. cap
$chain = @{}
for ($i = 0; $i -lt 30; $i++) { $chain["c$i-HASHHASH.js"] = @{ Status = 200; Body = "import`"./c$($i + 1)-HASHHASH.js`";" } }
$g = Find-InChunkGraph -Roots @('c0-HASHHASH.js') -Fetch { param($n) if ($chain.ContainsKey($n)) { $chain[$n] } else { @{ Status = 404; Body = '' } } } -MaxFiles 10
Check ($g.Capped -and @($g.Files).Count -le 10) 'a graph larger than MaxFiles is capped'
# 8. a 404 body is not walked
$g = Find-InChunkGraph -Roots @('a-AAAAAAAA.js') -Fetch { param($n) if ($n -eq 'a-AAAAAAAA.js') { @{ Status = 404; Body = 'import"./b-BBBBBBBB.js"' } } else { @{ Status = 200; Body = '' } } }
Check (@($g.Files).Count -eq 1 -and @($g.Unreachable).Count -eq 1) 'a 404 response is unreachable and not walked'

# ---- hooks.ps1 Test-FrontendLive end to end against the fake site (HTTP, logging, sleeping stubbed) --------
$siteUrl = "$(Get-Cfg 'frontend.siteUrl' '')"
$assetBase = "$(Get-Cfg 'frontend.assetBase' '/assets/')"
if ($siteUrl) {
    $assetDir = ([uri]::new([uri]$siteUrl, $assetBase)).AbsoluteUri
    $script:indexHtml = "<html><head><script type=`"module`" crossorigin src=`"${assetBase}index-ENTRY111.js`"></script><link rel=`"modulepreload`" crossorigin href=`"${assetBase}vendor-VVVVVV11.js`"><link rel=`"stylesheet`" crossorigin href=`"${assetBase}index-STYLE111.css`"></head><body><div id=`"root`"></div></body></html>"
    function Invoke-Http {
        param([string]$Url, [string]$Method = 'GET', [int]$TimeoutSec = 30)
        if ($Url.StartsWith($siteUrl) -and $Url -match '[?&]cb=') { return @{ Status = 200; Body = $script:indexHtml } }
        if ($Url.StartsWith($assetDir)) { $n = $Url.Substring($assetDir.Length); if ($fakeSite.ContainsKey($n)) { return $fakeSite[$n] } }
        return @{ Status = 404; Body = 'Not Found' }
    }
    function Test-FrontendExtraLive { return $null }
    $script:logLines = New-Object System.Collections.ArrayList
    function Write-Log { param([string]$Message, [string]$Level = 'INFO') [void]$script:logLines.Add("[$Level] $Message") }
    function Start-Sleep { param([int]$Seconds) }

    $v = Test-FrontendLive -ExpectString 'Biggest movers' -TimeoutSec 5
    Check ([bool]$v.Ok) "Test-FrontendLive passes when the string is only in a nested chunk ($($script:logLines -join ' | '))"
    Check (@($script:logLines | Where-Object { $_ -match 'files=7 maxDepth=3 unreachable=0 expect=True \(MoversPanel-MMMMMM11\.js, depth 3\)' }).Count -ge 1) 'log line names the file and depth'
    $v = Test-FrontendLive -AbsentString 'Biggest movers' -TimeoutSec 1
    Check (-not $v.Ok) 'Test-FrontendLive fails when the AbsentString is in a nested chunk'
    $fakeSite['index-HOME0011.js'] = @{ Status = 200; Body = 'import"./Gone-GGGGGG11.js";import{P}from"./MoversPanel-MMMMMM11.js";' }
    Check (-not (Test-FrontendLive -ExpectString 'Biggest movers' -TimeoutSec 1).Ok) 'Test-FrontendLive fails when a nested chunk is unreachable'
    $fakeSite['index-HOME0011.js'] = @{ Status = 200; Body = 'import"./Screen-AAAAAA11.js";import{P}from"./MoversPanel-MMMMMM11.js";' }
    $sig = Get-PageSignature $script:indexHtml
    Check (-not (Test-FrontendLive -ExpectString 'Biggest movers' -NotSignature $sig -TimeoutSec 1).Ok) 'Test-FrontendLive refuses the previous build (NotSignature unchanged)'
    # head-only change (#22, #39): same hashed bundles, new index.html -> a new build, string found in index.html
    $oldHtml = $script:indexHtml
    $oldSig = Get-PageSignature $oldHtml
    Check ((Get-PageSignature ($oldHtml -replace "`n", "`r`n")) -eq $oldSig) 'page signature ignores line endings'
    $script:indexHtml = $oldHtml.Replace('</head>', '<meta property="og:title" content="Head only XYZ"></head>')
    Check ((Get-PageSignature $script:indexHtml) -ne $oldSig) 'an index.html-only change gives a new page signature'
    $script:logLines.Clear()
    $v = Test-FrontendLive -ExpectString 'Head only XYZ' -NotSignature $oldSig -TimeoutSec 5
    Check ([bool]$v.Ok) "a head-only change verifies (string in index.html, same assets) ($($script:logLines -join ' | '))"
    Check (-not (Test-FrontendLive -AbsentString 'Head only XYZ' -TimeoutSec 1).Ok) 'rollback check fails while index.html still has the string'
    $script:indexHtml = $oldHtml
    Check ([bool](Test-FrontendLive -AbsentString 'Head only XYZ' -TimeoutSec 5).Ok) 'rollback check passes once index.html no longer has the string'
    Check (-not (Test-FrontendLive -ExpectString 'Head only XYZ' -NotSignature $oldSig -TimeoutSec 1).Ok) 'unchanged index.html is still refused as the previous build'
    function Test-FrontendExtraLive { return 'sub-site status=404' }
    Check (-not (Test-FrontendLive -ExpectString 'Biggest movers' -TimeoutSec 1).Ok) 'a failing Test-FrontendExtraLive fails the live check'
}

# ---- wiring: the callers load live-check.ps1; no elevated file depends on it ------------------------------
foreach ($f in 'deploy.ps1', 'rollback.ps1') {
    $t = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $f))
    $iLib = $t.IndexOf('. "$PSScriptRoot\lib.ps1"'); $iLive = $t.IndexOf('. "$PSScriptRoot\live-check.ps1"')
    Check ($iLib -ge 0 -and $iLive -gt $iLib) "$f dot-sources live-check.ps1 after lib.ps1"
}
foreach ($f in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1 | Where-Object { $script:ElevatedFiles -contains $_.Name })) {
    Check (-not ([IO.File]::ReadAllText($f.FullName)).Contains('live-check.ps1')) "elevated file $($f.Name) does not depend on live-check.ps1"
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail -gt 0) { Write-Host "TEST-LIVE-CHECK FAIL ($script:fail failed, $script:pass passed)"; exit 1 }
Write-Host "TEST-LIVE-CHECK PASS ($script:pass checks)"
exit 0
