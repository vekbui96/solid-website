# Shared helpers for the innovation loop scripts. Dot-source it:  . "$PSScriptRoot\lib.ps1"
# PowerShell 5.1 compatible. No secrets are read or printed by anything in here.

Set-StrictMode -Version 1
$script:LogFile = $null
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- fixed locations -------------------------------------------------------
$script:LoopHome      = Join-Path $env:USERPROFILE '.innovation-loop'
if ($env:INNOVATION_LOOP_HOME) { $script:LoopHome = $env:INNOVATION_LOOP_HOME }
$script:GhExe         = 'C:\Program Files\GitHub CLI\gh.exe'
$script:FrontRepo     = 'vekbui96/solid-website'
$script:ApiRepo       = 'vekbui96/solid-website-api'
$script:FrontClone    = Join-Path $script:LoopHome 'clones\solid-website'
$script:ApiClone      = Join-Path $script:LoopHome 'clones\solid-website-api'
$script:SiteUrl       = 'https://vekbui96.github.io/solid-website/'
$script:ApiLocal      = 'http://localhost:8080'
$script:ApiFunnel     = 'https://server-pc.tail0e4194.ts.net'
$script:ApiServiceName = 'solid-website-api'
$script:ApiServiceDir = 'D:\services\solid-website-api'
$script:ApiJarRel     = 'target\personal-site-api-0.0.1-SNAPSHOT.jar'   # hardcoded in the NSSM service; never change pom artifactId/version

# Exit codes shared by deploy/rollback scripts
$script:EXIT_OK              = 0
$script:EXIT_PRECONDITION    = 1   # nothing was changed
$script:EXIT_ROLLED_BACK     = 2   # deploy failed verification, rollback succeeded
$script:EXIT_ROLLBACK_FAILED = 3   # production may be broken: human needed
$script:EXIT_BUILD_FAILED    = 4   # build failed before anything live was touched

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Initialize-LoopDirs {
    foreach ($d in 'logs','clones','lock','artifacts','api-backups','api-staging','state','work') {
        $p = Join-Path $script:LoopHome $d
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
    }
}

function Start-ScriptLog {
    param([string]$Name)
    Initialize-LoopDirs
    $script:LogFile = Join-Path $script:LoopHome ("logs\{0}-{1}.log" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Log "log file: $script:LogFile"
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-GhToPath {
    $dir = Split-Path $script:GhExe
    if (($env:PATH -split ';') -notcontains $dir) { $env:PATH = "$dir;$env:PATH" }
}

# Run a native command, stream output to the log, throw on nonzero exit.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [string]$WorkDir = $null, [switch]$AllowFail, [switch]$Quiet)
    $old = Get-Location
    try {
        if ($WorkDir) { Set-Location -LiteralPath $WorkDir }
        Write-Log ("> {0} {1}" -f $File, ($Arguments -join ' '))
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & $File @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        if (-not $Quiet -or $code -ne 0) { foreach ($l in $out) { Write-Log "  $l" 'OUT' } }
        if ($code -ne 0 -and -not $AllowFail) { throw "command failed (exit $code): $File $($Arguments -join ' ')" }
        return @{ Code = $code; Output = @($out) }
    } finally { Set-Location $old }
}

function Invoke-Git {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFail)
    return Invoke-Native -File 'git' -Arguments (@('-C', $Repo) + $Arguments) -AllowFail:$AllowFail
}

function Get-GitValue {
    param([string]$Repo, [string[]]$Arguments)
    $r = Invoke-Git -Repo $Repo -Arguments $Arguments
    return (($r.Output | Where-Object { $_ -ne '' }) | Select-Object -Last 1).Trim()
}

# Plain HTTP that never throws on 4xx/5xx and does not use IE parsing.
function Invoke-Http {
    param([string]$Url, [string]$Method = 'GET', [hashtable]$Headers = @{}, [string]$Body = $null, [int]$TimeoutSec = 30)
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.AllowAutoRedirect = $true
    $req.UserAgent = 'innovation-loop-verify'
    $req.Headers.Add('Cache-Control', 'no-cache')
    foreach ($k in $Headers.Keys) {
        switch ($k) {
            'Content-Type' { $req.ContentType = $Headers[$k] }
            'Accept'       { $req.Accept = $Headers[$k] }
            default        { $req.Headers.Add($k, $Headers[$k]) }
        }
    }
    if ($Body) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        if (-not $req.ContentType) { $req.ContentType = 'application/json' }
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
    }
    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) { $resp = $_.Exception.Response }
        else { return @{ Status = 0; Body = ''; Headers = @{}; Error = $_.Exception.Message } }
    }
    try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd(); $reader.Close()
        $h = @{}; foreach ($k in $resp.Headers.AllKeys) { $h[$k] = $resp.Headers[$k] }
        return @{ Status = [int]$resp.StatusCode; Body = $text; Headers = $h; Error = $null }
    } finally { $resp.Close() }
}

function Get-CacheBustedUrl { param([string]$Url) $sep = '?'; if ($Url.Contains('?')) { $sep = '&' }; return "$Url${sep}cb=$([DateTime]::UtcNow.Ticks)" }

# Extract "assets/index-XXXX.js" from an index.html string.
function Get-IndexAsset {
    param([string]$Html)
    $m = [regex]::Match($Html, 'assets/index-[A-Za-z0-9_\-]+\.js')
    if ($m.Success) { return $m.Value }
    return $null
}

function Invoke-Gh {
    param([string[]]$Arguments, [switch]$AllowFail)
    return Invoke-Native -File $script:GhExe -Arguments $Arguments -AllowFail:$AllowFail
}

# Wait for the GitHub Pages build for a gh-pages commit to succeed.
function Wait-PagesBuild {
    param([string]$Sha, [datetime]$NotBeforeUtc, [int]$TimeoutSec = 420)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Invoke-Native -File $script:GhExe -Arguments @('api', "repos/$($script:FrontRepo)/actions/runs?branch=gh-pages&per_page=10") -AllowFail -Quiet
        if ($r.Code -eq 0) {
            try {
                $json = ($r.Output -join "`n") | ConvertFrom-Json
                $runs = @($json.workflow_runs | Where-Object { $_.head_sha -eq $Sha -and ([datetime]::Parse($_.created_at).ToUniversalTime() -ge $NotBeforeUtc.AddSeconds(-30)) })
                if ($runs.Count -gt 0) {
                    $run = $runs[0]
                    Write-Log "pages run $($run.id): status=$($run.status) conclusion=$($run.conclusion)"
                    if ($run.status -eq 'completed') { return ($run.conclusion -eq 'success') }
                }
            } catch { Write-Log "could not parse actions response: $_" 'WARN' }
        }
        Start-Sleep -Seconds 15
    }
    Write-Log "timed out waiting for pages build of $Sha" 'ERROR'
    return $false
}

# Live page must reference $Asset; asset must 200 (and contain $ExpectString if given);
# /storybook/ and the resume PDF must 200. Retries until $TimeoutSec.
function Test-LiveSite {
    param([string]$Asset, [string]$ExpectString = $null, [int]$TimeoutSec = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = ''
    while ((Get-Date) -lt $deadline) {
        $page = Invoke-Http -Url (Get-CacheBustedUrl $script:SiteUrl)
        $live = Get-IndexAsset $page.Body
        if ($page.Status -eq 200 -and $live -eq $Asset) {
            $js = Invoke-Http -Url (Get-CacheBustedUrl ($script:SiteUrl + $Asset))
            $sb = Invoke-Http -Url (Get-CacheBustedUrl ($script:SiteUrl + 'storybook/'))
            $pdf = Invoke-Http -Url (Get-CacheBustedUrl ($script:SiteUrl + 'Ve-Bui-Resume.pdf')) -Method 'HEAD'
            $hasString = (-not $ExpectString) -or ($js.Body.Contains($ExpectString))
            Write-Log ("live asset={0} js={1} expect={2} storybook={3} resume={4}" -f $live, $js.Status, $hasString, $sb.Status, $pdf.Status)
            if ($js.Status -eq 200 -and $js.Body.Length -gt 1000 -and $hasString -and $sb.Status -eq 200 -and $pdf.Status -eq 200) { return $true }
            $last = 'asset/storybook/resume/string check failed'
        } else {
            $last = "page status=$($page.Status) live asset=$live expected=$Asset"
        }
        Write-Log "live check not yet passing: $last"
        Start-Sleep -Seconds 20
    }
    Write-Log "live site verification failed: $last" 'ERROR'
    return $false
}

# All API checks. Never sends a real email: the only valid contact POST carries the honeypot.
function Test-Api {
    param([int]$StartupTimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
    $up = $false
    while ((Get-Date) -lt $deadline) {
        $h = Invoke-Http -Url "$($script:ApiLocal)/api/health" -TimeoutSec 10
        if ($h.Status -eq 200 -and $h.Body -match '"status"\s*:\s*"UP"') { $up = $true; break }
        Start-Sleep -Seconds 5
    }
    if (-not $up) { Write-Log 'local /api/health never reported UP' 'ERROR'; return $false }
    $ok = $true
    $act = Invoke-Http -Url "$($script:ApiLocal)/actuator/health" -TimeoutSec 10
    if (-not ($act.Status -eq 200 -and $act.Body -match '"status"\s*:\s*"UP"')) { Write-Log "actuator health failed: $($act.Status)" 'ERROR'; $ok = $false }

    $funnelOk = $false
    for ($i = 0; $i -lt 6 -and -not $funnelOk; $i++) {
        $f = Invoke-Http -Url "$($script:ApiFunnel)/api/health" -TimeoutSec 20
        if ($f.Status -eq 200 -and $f.Body -match '"status"\s*:\s*"UP"') { $funnelOk = $true } else { Start-Sleep -Seconds 10 }
    }
    if (-not $funnelOk) { Write-Log 'funnel /api/health failed' 'ERROR'; $ok = $false }

    $bad = Invoke-Http -Url "$($script:ApiLocal)/api/contact" -Method 'POST' -Headers @{ 'Content-Type' = 'application/json' } -Body '{"name":"","email":"","message":""}'
    if (-not ($bad.Status -eq 400 -and $bad.Body -match 'Validation failed')) { Write-Log "validation check failed: $($bad.Status) $($bad.Body)" 'ERROR'; $ok = $false }

    $hp = Invoke-Http -Url "$($script:ApiLocal)/api/contact" -Method 'POST' -Headers @{ 'Content-Type' = 'application/json' } `
        -Body '{"name":"Innovation Loop Verify","email":"verify@example.com","message":"Automated post-deploy honeypot check. Not a real message.","website":"x"}'
    if (-not ($hp.Status -eq 200 -and $hp.Body -match '"status"\s*:\s*"received"')) { Write-Log "honeypot check failed: $($hp.Status) $($hp.Body)" 'ERROR'; $ok = $false }

    $opt = Invoke-Http -Url "$($script:ApiLocal)/api/contact" -Method 'OPTIONS' -Headers @{ 'Origin' = 'https://vekbui96.github.io'; 'Access-Control-Request-Method' = 'POST' }
    if ($opt.Headers['Access-Control-Allow-Origin'] -ne 'https://vekbui96.github.io') { Write-Log "CORS preflight failed: $($opt.Status) allow-origin=$($opt.Headers['Access-Control-Allow-Origin'])" 'ERROR'; $ok = $false }

    Write-Log "API verification result: $ok"
    return $ok
}

function Wait-ServiceState {
    param([string]$Name, [string]$State, [int]$TimeoutSec = 90)
    $svc = Get-Service -Name $Name
    try { $svc.WaitForStatus($State, [TimeSpan]::FromSeconds($TimeoutSec)); return $true } catch { return $false }
}

# Mirror a source tree into the service dir, never touching .env or target\.
function Sync-ApiSource {
    param([string]$From)
    Write-Log "mirroring source $From -> $($script:ApiServiceDir) (excluding .env, target, .git)"
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & robocopy $From $script:ApiServiceDir /MIR /XD target .git /XF .env /R:2 /W:2 /NP /NFL /NDL 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    foreach ($l in $out) { if ("$l".Trim()) { Write-Log "  $l" 'OUT' } }
    if ($code -ge 8) { throw "robocopy failed with exit code $code" }
}

# git archive <ref> of the API clone into a fresh dir; returns the dir.
function Export-ApiSource {
    param([string]$Ref = 'origin/main')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $script:LoopHome "api-staging\$stamp"
    New-Item -ItemType Directory -Path $dir | Out-Null
    $zip = Join-Path $script:LoopHome "api-staging\$stamp.zip"
    Invoke-Git -Repo $script:ApiClone -Arguments @('archive', '--format=zip', '-o', $zip, $Ref) | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $dir
    Remove-Item -LiteralPath $zip
    # keep only the 3 newest staging dirs
    Get-ChildItem (Join-Path $script:LoopHome 'api-staging') -Directory | Sort-Object Name -Descending | Select-Object -Skip 3 |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    return $dir
}

# Revert a commit on main (merge or plain) and push. Idempotent: skips if already reverted.
function Invoke-RevertOnMain {
    param([string]$Repo, [string]$Sha)
    Invoke-Git -Repo $Repo -Arguments @('fetch', 'origin', '--prune') | Out-Null
    Invoke-Git -Repo $Repo -Arguments @('checkout', '-B', 'main', 'origin/main') | Out-Null
    Invoke-Git -Repo $Repo -Arguments @('reset', '--hard', 'origin/main') | Out-Null
    $full = Get-GitValue -Repo $Repo -Arguments @('rev-parse', $Sha)
    $already = Invoke-Git -Repo $Repo -Arguments @('log', 'origin/main', '--format=%H', "--grep=This reverts commit $full") -AllowFail
    if (@($already.Output | Where-Object { $_ -match '^[0-9a-f]{40}$' }).Count -gt 0) { Write-Log "$full is already reverted on main; nothing to do"; return }
    $isAncestor = Invoke-Git -Repo $Repo -Arguments @('merge-base', '--is-ancestor', $full, 'origin/main') -AllowFail
    if ($isAncestor.Code -ne 0) { throw "$full is not on origin/main; refusing to revert" }
    $parents = (Get-GitValue -Repo $Repo -Arguments @('rev-list', '--parents', '-n', '1', $full)).Split(' ').Count - 1
    if ($parents -gt 1) { Invoke-Git -Repo $Repo -Arguments @('revert', '--no-edit', '-m', '1', $full) | Out-Null }
    else { Invoke-Git -Repo $Repo -Arguments @('revert', '--no-edit', $full) | Out-Null }
    Invoke-Git -Repo $Repo -Arguments @('push', 'origin', 'HEAD:main') | Out-Null   # fast-forward only; never force main
    Write-Log "reverted $full on main and pushed"
}

function Save-State { param([string]$Name, $Object) $Object | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:LoopHome "state\$Name.json") -Encoding UTF8 }
function Read-State { param([string]$Name) $p = Join-Path $script:LoopHome "state\$Name.json"; if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }; return $null }
