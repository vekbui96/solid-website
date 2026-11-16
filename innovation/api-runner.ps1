<#
.SYNOPSIS
  ELEVATED SIDE. The only action of the `innovation-loop-api` scheduled task (highest privileges, no trigger).
  Reads ONE request written by the non-elevated loop, validates it as untrusted input, and runs
  deploy-api.ps1 or rollback-api.ps1 with arguments it builds itself.

.DESCRIPTION
  Trust boundary. Everything the non-elevated loop can write is untrusted: the request file, its own
  clones, ~\.gitconfig, ~\.ssh, ~\.m2, user-scope environment variables, D:\projects. So this script:
  - runs from a copy in <Root>\bin (C:\ProgramData\innovation-loop-api\bin), installed by install-task.ps1;
    <Root> is writable only by elevated admins and SYSTEM (DACL + High integrity label), so the loop
    cannot change the code that runs elevated
  - reads exactly <QueueDir>\request.json (fixed name; no path from the request is ever used), refusing
    reparse points and files over 4 KB; never echoes the file's content
  - schema: mode (deploy|rollback|noop), issue (int), sha (40 hex, deploy only), requestedAt (UTC ISO),
    nonce (GUID), dryRun (bool, optional). Unknown keys are rejected.
  - rejects stale requests (older than -MaxAgeMinutes or in the future) and replayed nonces
    (<Root>\state\nonces.log), takes a lock (<Root>\lock\runner.lock)
  - deploy: fetches the (private) API repo fresh over SSH with a pinned config into <Root>\clones and requires sha ==
    origin/main of vekbui96/solid-website-api
  - rollback: restores the jar recorded by the last deploy; the request cannot name a jar
  - noop: validation and a result only (used to test the trigger path)
  - dryRun: full validation, then stops before calling any deploy/rollback script
  - scrubs the environment before running git/Maven/java: machine PATH only, user-scope variables removed,
    JAVA_TOOL_OPTIONS / MAVEN_OPTS / GIT_* etc. removed, git global config, Maven settings, Maven repo and
    wrapper home, TEMP and USERPROFILE all pointed into <Root>
  - writes the result to <Root>\results\<nonce>.json (readable, not writable, by the loop). It never
    writes into the user-writable queue dir, so a planted link there cannot redirect an elevated write.

  It never pushes to git and holds no push credentials. Reverts on main are the requester's job.

  Residual risk: the deployed API runs as LocalSystem (NSSM). Code merged to API main therefore runs as
  SYSTEM once deployed; this split only guarantees that such code must first be on origin/main
  (a public, auditable commit) and that nothing else crosses the boundary.
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\ProgramData\innovation-loop-api',
    [string]$QueueDir = 'C:\Users\Ve Bui\.innovation-loop\api-queue',
    [int]$MaxAgeMinutes = 10
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1

# ---- 1. scrub the environment first (inherited by every child process) -------------------
$env:PSModulePath = "$PSHOME\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
foreach ($k in @([Environment]::GetEnvironmentVariables('User').Keys)) {
    if ($k -notin @('Path', 'TEMP', 'TMP')) { Remove-Item -LiteralPath "env:$k" -ErrorAction SilentlyContinue }
}
foreach ($v in @(Get-ChildItem env: | Where-Object { $_.Name -match '^(GIT_|MAVEN_|M2_|JAVA_TOOL_OPTIONS$|_JAVA_OPTIONS$|JDK_JAVA_OPTIONS$|CLASSPATH$|NODE_OPTIONS$|SSH_|INNOVATION_LOOP_)' })) {
    Remove-Item -LiteralPath "env:$($v.Name)" -ErrorAction SilentlyContinue
}
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$machineJava = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
if ($machineJava) { $env:JAVA_HOME = $machineJava } else { Remove-Item env:JAVA_HOME -ErrorAction SilentlyContinue }
$home2 = Join-Path $Root 'home'
$env:USERPROFILE = $home2; $env:HOME = $home2
$env:TEMP = Join-Path $Root 'tmp'; $env:TMP = $env:TEMP
$env:GIT_CONFIG_GLOBAL = Join-Path $Root 'gitconfig'
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_TERMINAL_PROMPT = '0'
# solid-website-api is private, so fetching needs the deploy key. ssh -F <Root>\ssh_config ignores the
# user-writable ~\.ssh\config (no ProxyCommand tricks); the config pins host, user, key path and an
# admin-owned known_hosts with StrictHostKeyChecking. Both files are written by install-task.ps1.
$gitSsh = 'C:/Program Files/Git/usr/bin/ssh.exe'
$sshCfg = (Join-Path $Root 'ssh_config') -replace '\\', '/'
$env:GIT_SSH_COMMAND = "'$gitSsh' -F '$sshCfg'"
$env:MAVEN_USER_HOME = Join-Path $Root 'm2'        # Maven wrapper distributions
$env:MAVEN_SKIP_RC = '1'                            # no %USERPROFILE%\mavenrc_pre.* scripts
$env:MAVEN_OPTS = "-Duser.home=$home2"
$env:INNOVATION_LOOP_MVN_EXTRA = "-s `"$(Join-Path $Root 'maven-settings.xml')`" -Dmaven.repo.local=`"$(Join-Path $Root 'm2\repository')`""
$env:INNOVATION_LOOP_HOME = $Root                   # lib.ps1 then keeps clones/backups/state/logs in <Root>

. "$PSScriptRoot\lib.ps1"
Start-ScriptLog 'api-runner'
$resultsDir = Join-Path $Root 'results'
$nonceLog = Join-Path $Root 'state\nonces.log'
$lockPath = Join-Path $Root 'lock\runner.lock'
foreach ($d in $resultsDir, (Split-Path $nonceLog), (Split-Path $lockPath), $home2, $env:TEMP, $env:MAVEN_USER_HOME) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

function Write-Result {
    param([string]$Nonce, [hashtable]$Data)
    $Data.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $Data.runnerLog = $script:LogFile
    $name = 'last-rejected.json'
    if ($Nonce -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { $name = "$Nonce.json" }
    $tmp = Join-Path $resultsDir "$name.tmp"
    [IO.File]::WriteAllText($tmp, ($Data | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination (Join-Path $resultsDir $name) -Force
    Write-Log "result: $($Data.status) exit=$($Data.exitCode) -> $name"
    # keep the newest 50 results
    Get-ChildItem $resultsDir -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 50 | Remove-Item -Force
}

function Reject {
    param([string]$Nonce, [string]$Why)
    Write-Log "REJECTED: $Why" 'ERROR'
    Write-Result -Nonce $Nonce -Data @{ nonce = $Nonce; status = 'rejected'; exitCode = 1; message = $Why }
    exit 1
}

# ---- 2. read and validate the request ------------------------------------------------------
if (-not (Test-IsElevated)) { Write-Log 'api-runner must run elevated' 'ERROR'; exit 1 }
$nonce = ''
try {
    $qd = Get-Item -LiteralPath $QueueDir -Force
    if ($qd.Attributes -band [IO.FileAttributes]::ReparsePoint) { Reject '' 'queue dir is a reparse point' }
    $reqPath = Join-Path $QueueDir 'request.json'
    $f = Get-Item -LiteralPath $reqPath -Force
    if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { Reject '' 'request.json is a reparse point' }
    if ($f.PSIsContainer -or $f.Length -gt 4096 -or $f.Length -lt 2) { Reject '' 'request.json has a bad size or type' }
    $raw = [IO.File]::ReadAllText($reqPath)
    $req = $raw | ConvertFrom-Json
} catch {
    Reject '' 'request.json missing or not valid JSON'
}

$allowedKeys = @('mode', 'issue', 'sha', 'requestedAt', 'nonce', 'dryRun')
$keys = @($req.PSObject.Properties.Name)
foreach ($k in $keys) { if ($k -notin $allowedKeys) { Reject '' "unknown key '$($k -replace '[^\w-]', '?')'" } }

$nonce = "$($req.nonce)".ToLowerInvariant()
if ($nonce -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { Reject '' 'nonce is not a GUID' }

# replay check + consume the nonce before doing anything else
$seen = @(); if (Test-Path -LiteralPath $nonceLog) { $seen = @(Get-Content -LiteralPath $nonceLog) }
if ($seen -contains $nonce) { Write-Log "REJECTED: replayed nonce $nonce" 'ERROR'; exit 1 }   # do not overwrite the original result
Add-Content -LiteralPath $nonceLog -Value $nonce
if ($seen.Count -gt 5000) { $seen | Select-Object -Last 2000 | Set-Content -LiteralPath $nonceLog; Add-Content -LiteralPath $nonceLog -Value $nonce }

$mode = "$($req.mode)"
if ($mode -notin @('deploy', 'rollback', 'noop')) { Reject $nonce 'mode must be deploy, rollback or noop' }

$requested = [DateTime]::MinValue
if (-not [DateTime]::TryParse("$($req.requestedAt)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$requested)) { Reject $nonce 'requestedAt is not a timestamp' }
$age = [DateTime]::UtcNow - $requested
if ($age.TotalMinutes -gt $MaxAgeMinutes) { Reject $nonce "stale request ($([int]$age.TotalMinutes) min old)" }
if ($age.TotalMinutes -lt -2) { Reject $nonce 'requestedAt is in the future' }

$issue = 0
if ($null -ne $req.issue -and -not [int]::TryParse("$($req.issue)", [ref]$issue)) { Reject $nonce 'issue is not an integer' }
if ($issue -lt 0 -or $issue -gt 1000000) { Reject $nonce 'issue out of range' }
$dryRun = $false
if ($null -ne $req.dryRun) { if ($req.dryRun -is [bool]) { $dryRun = $req.dryRun } else { Reject $nonce 'dryRun must be a boolean' } }

$sha = "$($req.sha)".ToLowerInvariant()
if ($mode -eq 'deploy' -and $sha -notmatch '^[0-9a-f]{40}$') { Reject $nonce 'deploy needs a full 40-hex sha' }
if ($mode -ne 'deploy' -and $req.sha) { Reject $nonce "sha is only accepted for deploy" }

Write-Log "request: mode=$mode issue=$issue sha=$sha dryRun=$dryRun age=$([int]$age.TotalSeconds)s nonce=$nonce"

# ---- 3. lock -----------------------------------------------------------------------------------
try {
    $fs = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $b = [Text.Encoding]::UTF8.GetBytes("$PID`n$([DateTime]::UtcNow.ToString('o'))"); $fs.Write($b, 0, $b.Length); $fs.Close()
} catch [IO.IOException] {
    $old = Get-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue
    $lines = @(Get-Content -LiteralPath $lockPath -ErrorAction SilentlyContinue)
    $lockPid = 0; if ($lines.Count -ge 1) { [void][int]::TryParse($lines[0], [ref]$lockPid) }
    $alive = $lockPid -gt 0 -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)
    if ($alive -and $old -and $old.LastWriteTime -gt (Get-Date).AddHours(-2)) { Reject $nonce "another api-runner (pid $lockPid) is running" }
    Remove-Item -LiteralPath $lockPath -Force
    $fs = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); $fs.Close()
    Write-Log 'cleared a stale runner lock' 'WARN'
}

$exitCode = 1
try {
    # ---- 4. mode-specific validation -------------------------------------------------------------
    if ($mode -eq 'deploy') {
        $clone = $script:ApiClone   # <Root>\clones\solid-website-api (lib.ps1 with INNOVATION_LOOP_HOME=<Root>)
        $apiUrl = 'git@github-solid-website-api:vekbui96/solid-website-api.git'   # host alias defined in <Root>\ssh_config
        foreach ($need in 'ssh_config', 'known_hosts') { if (-not (Test-Path -LiteralPath (Join-Path $Root $need))) { throw "missing $Root\$need (run install-task.ps1)" } }
        if (-not (Test-Path -LiteralPath (Join-Path $clone '.git'))) {
            Invoke-Native -File 'git' -Arguments @('clone', '--no-checkout', $apiUrl, $clone) | Out-Null
        }
        $url = (Get-GitValue -Repo $clone -Arguments @('remote', 'get-url', 'origin'))
        if ($url -ne $apiUrl) { throw "unexpected origin url $url" }
        Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') | Out-Null
        $tip = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'origin/main')
        if ($sha -ne $tip) { Reject $nonce "sha $sha is not the current tip of origin/main ($tip)" }
    }
    if ($mode -eq 'rollback') {
        $st = Read-State 'api-last-deploy'
        if (-not $st -or -not $st.backupJar) { Reject $nonce 'no recorded deploy to roll back (state\api-last-deploy.json)' }
    }

    if ($mode -eq 'noop' -or $dryRun) {
        Write-Result -Nonce $nonce -Data @{ nonce = $nonce; mode = $mode; issue = $issue; sha = $sha; status = 'validated'; exitCode = 0; message = 'request valid; nothing executed (noop or dryRun)' }
        $exitCode = 0
    } else {
        # ---- 5. run the hardcoded script with arguments built here ----------------------------------
        $ps = "$PSHOME\powershell.exe"
        if ($mode -eq 'deploy') {
            & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PSScriptRoot\deploy-api.ps1" -MergeSha $sha
        } else {
            & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PSScriptRoot\rollback-api.ps1"
        }
        $code = $LASTEXITCODE
        $scriptLog = Get-ChildItem (Join-Path $Root 'logs') -Filter "$(if ($mode -eq 'deploy') { 'deploy-api' } else { 'rollback-api' })-*.log" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $status = switch ($code) { 0 { 'ok' } 1 { 'precondition-failed' } 2 { 'rolled-back' } 3 { 'rollback-failed' } 4 { 'build-failed' } default { 'failed' } }
        Write-Result -Nonce $nonce -Data @{ nonce = $nonce; mode = $mode; issue = $issue; sha = $sha; status = $status; exitCode = $code; scriptLog = $(if ($scriptLog) { $scriptLog.FullName } else { '' }) }
        $exitCode = $code
    }
} catch {
    Write-Log "runner error: $_" 'ERROR'
    Write-Result -Nonce $nonce -Data @{ nonce = $nonce; mode = $mode; issue = $issue; status = 'failed'; exitCode = 1; message = "runner error: $_" }
    $exitCode = 1
} finally {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
exit $exitCode
