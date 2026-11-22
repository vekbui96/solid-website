# PROJECT HOOKS, ELEVATED side. Dot-sourced after lib.ps1 by deploy-server.ps1 and rollback-server.ps1,
# which run ONLY from the admin-only copy in C:\ProgramData\innovation-loop-portfolio\bin (install-task.ps1
# copies this file there). After editing it, re-run `install-task.ps1 -ElevatedOnly` from an elevated
# PowerShell; until then run-loop.ps1 sees the copy differs and refuses server deploys.
#
# solid-website-api is a Spring Boot jar run by the NSSM service `solid-website-api` (LocalSystem) as
#   java -jar D:\services\solid-website-api\target\personal-site-api-0.0.1-SNAPSHOT.jar
# Its repo is PRIVATE, so server.liveDir is the elevated side's own clone under
# C:\ProgramData\innovation-loop-portfolio\clones (server.elevatedClone: install-task.ps1 clones it over SSH
# with an admin-only ssh_config). That clone's HEAD is the sha the live jar was built from: a deploy builds
# the target in a staging dir, swaps the jar (the previous one kept in <ElevHome>\backups), and moves the
# clone's HEAD; a restore puts the backup jar back and the HEAD with it.
#
# Never touches .env, NSSM settings or application config. Never sends a real email: the only contact POSTs
# (to localhost) are an empty one (validation 400) and a honeypot one (the API drops it and answers 200).

function Get-ArtifactCfg {
    $a = Get-Cfg 'server.artifact'
    return [pscustomobject]@{
        ServiceDir = "$($a.serviceDir)"
        JarRel     = "$($a.jarRel)"
        LiveJar    = (Join-Path "$($a.serviceDir)" "$($a.jarRel)")
        Keep       = [int]$(if ($a.keep) { $a.keep } else { 5 })
        BackupDir  = (Join-Path $script:ElevHome 'backups')
        StagingDir = (Join-Path $script:ElevHome 'staging')
    }
}

# git archive <sha> of the elevated clone into a fresh staging dir (outside D:\services); keeps the 3 newest.
function Export-ServerSource {
    param([string]$Sha)
    $a = Get-ArtifactCfg
    if (-not (Test-Path -LiteralPath $a.StagingDir)) { New-Item -ItemType Directory -Path $a.StagingDir | Out-Null }
    $dir = Join-Path $a.StagingDir ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Sha.Substring(0, 7))
    $zip = "$dir.zip"
    Invoke-Git -Repo $script:LiveDir -Arguments @('archive', '--format=zip', '-o', $zip, $Sha) -Quiet | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $dir
    Remove-Item -LiteralPath $zip -Force
    Get-ChildItem -LiteralPath $a.StagingDir -Directory | Sort-Object Name -Descending | Select-Object -Skip 3 | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    return $dir
}

# Maven under the elevated task: settings, local repository and the wrapper's distribution inside ElevHome,
# so nothing in the user-writable ~\.m2 feeds an elevated build. Tests already ran in the loop.
function Invoke-ServerBuild {
    param([string]$Dir)
    $settings = Join-Path $script:ElevHome 'config\maven-settings.xml'
    $repo = Join-Path $script:ElevHome 'm2\repository'
    if (-not (Test-Path -LiteralPath $settings)) { [IO.File]::WriteAllText($settings, "<settings><localRepository>$repo</localRepository></settings>`n", (New-Object Text.UTF8Encoding $false)) }
    $env:MAVEN_USER_HOME = Join-Path $script:ElevHome 'm2'
    $r = Invoke-Native -File 'cmd' -Arguments @('/c', ".\mvnw.cmd -B -DskipTests -s `"$settings`" -Dmaven.repo.local=`"$repo`" clean package 2>&1") -WorkDir $Dir -AllowFail -Quiet
    if ($r.Code -ne 0) { throw ("mvnw package failed (exit $($r.Code)): " + (($r.Output | Select-Object -Last 6) -join ' | ')) }
    $jar = Join-Path $Dir (Get-ArtifactCfg).JarRel
    if (-not (Test-Path -LiteralPath $jar)) { throw "the build produced no $((Get-ArtifactCfg).JarRel)" }
    if ((Get-Item -LiteralPath $jar).Length -lt 1MB) { throw 'the built jar is suspiciously small' }
    return $jar
}

# Informational copy of the deployed source in the service dir (never .env, target\ or .git), as the old
# deploy-api.ps1 did. A failure is a warning: the jar is what runs.
function Sync-ServerSource {
    param([string]$From)
    try {
        $a = Get-ArtifactCfg
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $null = & robocopy $From $a.ServiceDir /MIR /XD target .git /XF .env /R:2 /W:2 /NP /NFL /NDL 2>&1
        $code = $LASTEXITCODE; $ErrorActionPreference = $prev
        if ($code -ge 8) { Write-Log "source mirror into $($a.ServiceDir) failed (robocopy $code); the jar is unaffected" 'WARN' }
    } catch { Write-Log "source mirror failed: $_ (the jar is unaffected)" 'WARN' }
}

function Restart-ServerService {
    param([string]$Jar, [string]$Svc)
    $a = Get-ArtifactCfg
    Stop-Service -Name $Svc -Force
    if (-not (Wait-ServiceState -Name $Svc -State 'Stopped' -TimeoutSec 90)) { throw 'service did not stop' }
    Start-Sleep -Seconds 2   # let the JVM release the jar
    Copy-Item -LiteralPath $Jar -Destination $a.LiveJar -Force
    Start-Service -Name $Svc
    if (-not (Wait-ServiceState -Name $Svc -State 'Running' -TimeoutSec 90)) { throw 'service did not reach Running' }
}

# One local request (POST/OPTIONS allowed, unlike lib.ps1 Invoke-Http): only for the contract checks below,
# only to the local API. Returns Status, Body and the Access-Control-Allow-Origin header.
function Invoke-ApiProbe {
    param([string]$Url, [string]$Method, [hashtable]$Headers = @{}, [string]$Body = '')
    if ($Url -notmatch '^http://(localhost|127\.0\.0\.1):8080/api/contact$') { throw "probe target not allowed: $Url" }
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method; $req.Timeout = 30000; $req.ReadWriteTimeout = 30000; $req.UserAgent = 'innovation-loop-verify'
    foreach ($k in $Headers.Keys) { if ($k -eq 'Content-Type') { $req.ContentType = $Headers[$k] } else { $req.Headers.Add($k, $Headers[$k]) } }
    if ($Body) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        if (-not $req.ContentType) { $req.ContentType = 'application/json' }
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
    }
    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] { if ($_.Exception.Response) { $resp = $_.Exception.Response } else { return @{ Status = 0; Body = ''; AllowOrigin = '' } } }
    try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd(); $reader.Close()
        return @{ Status = [int]$resp.StatusCode; Body = $text; AllowOrigin = "$($resp.Headers['Access-Control-Allow-Origin'])" }
    } finally { $resp.Close() }
}

# ---- HOOK: extra preconditions ----------------------------------------------------------------------
# The jar path is hardcoded in the NSSM service: a changed artifactId/version would deploy nothing.
function Test-ServerPreconditions {
    param([string]$Prev, [string]$Target, [string[]]$Changed)
    $a = Get-ArtifactCfg
    if (-not (Test-Path -LiteralPath $a.LiveJar)) { return "live jar not found at $($a.LiveJar)" }
    $pom = (Invoke-Git -Repo $script:LiveDir -Arguments @('show', "${Target}:pom.xml") -Quiet).Output -join "`n"
    if ($pom -notmatch '<artifactId>personal-site-api</artifactId>\s*<version>0\.0\.1-SNAPSHOT</version>') { return 'pom artifactId/version changed; the service jar path would not match (manual / needs Ve)' }
    return $null
}

# ---- HOOK: swap -------------------------------------------------------------------------------------
# Build first (a build failure throws BEFORE the service is touched, installFailed = true), back up the live
# jar, stop / copy / start, then move the clone's HEAD to the target.
function Invoke-ServerSwap {
    param([string]$Prev, [string]$Target, [string[]]$Changed, $Record, [string]$StateFile)
    $svc = "$(Get-Cfg 'server.serviceName')"
    $a = Get-ArtifactCfg
    try {
        $staging = Export-ServerSource -Sha $Target
        Write-Log "staging $staging"
        $newJar = Invoke-ServerBuild -Dir $staging
    } catch { $Record.installFailed = $true; throw "build failed, nothing changed: $_" }
    if (-not (Test-Path -LiteralPath $a.BackupDir)) { New-Item -ItemType Directory -Path $a.BackupDir | Out-Null }
    $backup = Join-Path $a.BackupDir ("personal-site-api-{0}-{1}.jar" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Prev.Substring(0, 7))
    Copy-Item -LiteralPath $a.LiveJar -Destination $backup
    if ((Get-Item -LiteralPath $backup).Length -ne (Get-Item -LiteralPath $a.LiveJar).Length) { throw 'backup size mismatch' }
    Get-ChildItem -LiteralPath $a.BackupDir -Filter 'personal-site-api-*.jar' | Sort-Object Name -Descending | Select-Object -Skip $a.Keep | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    $Record.backup = $backup; $Record.staging = $staging
    Save-JsonFile -Path $StateFile -Object $Record
    Write-Log "backed up the live jar to $backup"
    Restart-ServerService -Jar $newJar -Svc $svc
    Invoke-Git -Repo $script:LiveDir -Arguments @('reset', '--hard', $Target) -Quiet | Out-Null
    Sync-ServerSource -From $staging
}

# ---- HOOK: restore ----------------------------------------------------------------------------------
# Put the recorded backup jar back (from the record only, never from a request) and the clone's HEAD with it.
function Invoke-ServerRestore {
    param($Record)
    $svc = "$(Get-Cfg 'server.serviceName')"
    $a = Get-ArtifactCfg
    $backup = "$($Record.backup)"
    $head = Get-GitValue -Repo $script:LiveDir -Arguments @('rev-parse', 'HEAD')
    if ($backup) {
        if (-not (Test-Path -LiteralPath $backup)) { throw "backup jar not found: $backup" }
        $root = (Resolve-Path -LiteralPath $a.BackupDir).Path
        if (-not (Resolve-Path -LiteralPath $backup).Path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "backup jar must live under $root" }
        Write-Log "restoring $backup"
        Restart-ServerService -Jar $backup -Svc $svc
    } elseif ($Record.installFailed) {
        Write-Log 'the build failed before the swap: the live jar was never replaced'
        if ((Get-Service -Name $svc).Status -ne 'Running') { Start-Service -Name $svc }
    } else { throw 'no backup jar recorded for this deploy' }
    if ($head -ne $Record.prevSha) { Invoke-Git -Repo $script:LiveDir -Arguments @('reset', '--hard', $Record.prevSha) -Quiet | Out-Null }
    if (-not (Wait-ServiceState -Name $svc -State 'Running' -TimeoutSec 90)) { throw 'service did not reach Running' }
    if ($backup) { try { Sync-ServerSource -From (Export-ServerSource -Sha $Record.prevSha) } catch { Write-Log "source mirror of the previous sha failed: $_" 'WARN' } }
}

# ---- HOOK: verification -----------------------------------------------------------------------------
# Local /api/health UP, then N more checks with the service Running and the java pid stable (NSSM's restart
# can hide a crash loop); actuator health (smokeGets); Funnel /api/health; then the contract checks that
# cannot mutate anything: an empty contact POST must be a 400 "Validation failed", a honeypot-only POST must
# be the normal 200 "received" (dropped by the API, no email), and the CORS preflight from the Pages origin
# must echo exactly that origin.
function Test-ServerHealthy {
    $svc = "$(Get-Cfg 'server.serviceName')"
    $health = "$(Get-Cfg 'server.healthUrl')"
    $expect = "$(Get-Cfg 'server.healthExpect' '.')"
    $stable = [int](Get-Cfg 'server.stableChecks' 4)
    $interval = [int](Get-Cfg 'server.checkIntervalSec' 10)
    $deadline = (Get-Date).AddSeconds([int](Get-Cfg 'server.startupTimeoutSec' 120))
    $up = $false
    while ((Get-Date) -lt $deadline) {
        $h = Invoke-Http -Url $health -TimeoutSec 10
        if ($h.Status -eq 200 -and $h.Body -match $expect) { $up = $true; break }
        Start-Sleep -Seconds 3
    }
    if (-not $up) { Write-Log "local health ($health) never reported UP" 'ERROR'; return $false }
    $pid0 = Get-ServiceChildPid
    Write-Log "health ok; app pid $pid0; watching for $($stable * $interval)s"
    for ($i = 1; $i -le $stable; $i++) {
        Start-Sleep -Seconds $interval
        $st = (Get-Service -Name $svc).Status
        $h = Invoke-Http -Url $health -TimeoutSec 10
        $p = Get-ServiceChildPid
        Write-Log "check $i/${stable}: service=$st health=$($h.Status) pid=$p"
        if ("$st" -ne 'Running') { Write-Log "service is $st" 'ERROR'; return $false }
        if (-not ($h.Status -eq 200 -and $h.Body -match $expect)) { Write-Log "health failed: $($h.Status)" 'ERROR'; return $false }
        if ($pid0 -and $p -and $p -ne $pid0) { Write-Log "app pid changed ${pid0} -> ${p}: the service manager restarted a crashing app" 'ERROR'; return $false }
    }
    foreach ($g in @(Get-Cfg 'server.smokeGets' @())) {
        $attempts = 5; if ($g.attempts) { $attempts = [int]$g.attempts }
        $r = Invoke-HttpRetry -Url $g.url -ExpectRegex "$($g.expect)" -Attempts $attempts
        if (-not $r.Ok) { Write-Log "$($g.url) failed on every attempt ($($r.Status))" 'ERROR'; return $false }
    }
    $pub = "$(Get-Cfg 'server.publicHealthUrl' '')"
    if ($pub) {
        $r = Invoke-HttpRetry -Url $pub -ExpectRegex $expect -Attempts 6 -DelaySec 10 -TimeoutSec 20
        if (-not $r.Ok) { Write-Log "public health ($pub) failed" 'ERROR'; return $false }
    }
    $contact = 'http://localhost:8080/api/contact'
    $bad = Invoke-ApiProbe -Url $contact -Method 'POST' -Headers @{ 'Content-Type' = 'application/json' } -Body '{"name":"","email":"","message":""}'
    if (-not ($bad.Status -eq 400 -and $bad.Body -match 'Validation failed')) { Write-Log "validation check failed: $($bad.Status)" 'ERROR'; return $false }
    $hp = Invoke-ApiProbe -Url $contact -Method 'POST' -Headers @{ 'Content-Type' = 'application/json' } `
        -Body '{"name":"Innovation Loop Verify","email":"verify@example.com","message":"Automated post-deploy honeypot check. Not a real message.","website":"x"}'
    if (-not ($hp.Status -eq 200 -and $hp.Body -match '"status"\s*:\s*"received"')) { Write-Log "honeypot check failed: $($hp.Status)" 'ERROR'; return $false }
    $opt = Invoke-ApiProbe -Url $contact -Method 'OPTIONS' -Headers @{ 'Origin' = 'https://vekbui96.github.io'; 'Access-Control-Request-Method' = 'POST' }
    if ($opt.AllowOrigin -ne 'https://vekbui96.github.io') { Write-Log "CORS preflight failed: $($opt.Status) allow-origin=$($opt.AllowOrigin)" 'ERROR'; return $false }
    if ((Get-ServiceChildPid) -ne $pid0) { Write-Log 'app pid changed during the checks' 'ERROR'; return $false }
    Write-Log 'server verification passed (health, actuator, Funnel, validation 400, honeypot 200, CORS)'
    return $true
}
