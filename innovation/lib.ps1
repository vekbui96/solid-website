# Shared helpers for this project's innovation loop. Dot-source it:  . "$PSScriptRoot\lib.ps1"
# PowerShell 5.1 compatible, ASCII only (PS 5.1 reads BOM-less scripts as ANSI). Nothing here reads or
# prints a secret. Every project value comes from loop.config.json next to this file.
#
# Two trust levels use this file:
#   - the NON-elevated side (run-loop, check-approval, test-gate, merge-pr, deploy, rollback), run from
#     the project checkout's innovation\ directory;
#   - the ELEVATED side (elevated-task, deploy-server, rollback-server), run from the admin-only copy that
#     install-task.ps1 puts in C:\ProgramData\innovation-loop-<project>\bin, together with its own copy of
#     loop.config.json and hooks-server.ps1. That copy is the only code that ever runs elevated.
#
# Generated from the innovation-loop kit (~\.claude\skills\loop-scaffold). Generic: edit hooks.ps1 /
# hooks-server.ps1 / loop.config.json for project behaviour, not this file.

Set-StrictMode -Version 1
$script:LogFile = $null
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- configuration -------------------------------------------------------------------------------
$script:KitDir = $PSScriptRoot
if (-not $script:KitDir) { $script:KitDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:ConfigPath = Join-Path $script:KitDir 'loop.config.json'
if (-not (Test-Path -LiteralPath $script:ConfigPath)) { throw "missing $($script:ConfigPath)" }
$script:Config = [IO.File]::ReadAllText($script:ConfigPath) | ConvertFrom-Json
$script:Project = "$($script:Config.project)"
if ($script:Project -cnotmatch '^[a-z0-9][a-z0-9-]{1,40}$') { throw "loop.config.json: project '$($script:Project)' must be lowercase letters, digits and dashes" }
$script:EnvPrefix = 'INNOVATION_LOOP_' + ($script:Project.ToUpperInvariant() -replace '-', '_')

function Get-Cfg {
    # Get-Cfg 'server.serviceName' 'default'  (dotted path into the config; default when absent/empty)
    param([string]$Path, $Default = $null)
    $o = $script:Config
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $o) { return $Default }
        $prop = $o.PSObject.Properties[$part]
        if (-not $prop) { return $Default }
        $o = $prop.Value
    }
    if ($null -eq $o -or ($o -is [string] -and $o -eq '')) { return $Default }
    return $o
}

# ---- fixed locations ---------------------------------------------------------------------------
# The profile dir comes from the token, not from USERPROFILE (an environment variable can be redefined).
$script:ProfileDir = [Environment]::GetFolderPath('UserProfile')
$script:ElevHomeReal = "C:\ProgramData\innovation-loop-$($script:Project)"
# Running from the admin-only copy = the elevated task. A task's environment partly comes from
# HKCU\Environment, which a non-elevated process can write, so nothing user-controlled is trusted there:
# no path overrides, machine PATH / PSModulePath only, user-scope variables dropped, user dotfiles
# (~\.gitconfig, ~\.npmrc, ~\.m2) replaced by empty admin-owned ones.
$script:IsProtectedCopy = ("$($script:KitDir)".TrimEnd('\') -ieq (Join-Path $script:ElevHomeReal 'bin'))
if ($script:IsProtectedCopy) {
    foreach ($k in @([Environment]::GetEnvironmentVariables('User').Keys)) {
        if ($k -notin @('Path', 'TEMP', 'TMP')) { Remove-Item -LiteralPath "env:$k" -ErrorAction SilentlyContinue }
    }
    foreach ($v in @(Get-ChildItem env: | Where-Object { $_.Name -match '^(GIT_|MAVEN_|M2_|NPM_CONFIG_|JAVA_TOOL_OPTIONS$|_JAVA_OPTIONS$|JDK_JAVA_OPTIONS$|CLASSPATH$|NODE_OPTIONS$|NODE_PATH$|SSH_|INNOVATION_LOOP_)' })) {
        Remove-Item -LiteralPath "env:$($v.Name)" -ErrorAction SilentlyContinue
    }
    $env:PATH = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
    $machineJava = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
    if ($machineJava) { $env:JAVA_HOME = $machineJava } else { Remove-Item env:JAVA_HOME -ErrorAction SilentlyContinue }
    $env:GIT_CONFIG_GLOBAL = Join-Path $script:ElevHomeReal 'config\gitconfig'
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:NPM_CONFIG_USERCONFIG = Join-Path $script:ElevHomeReal 'config\npmrc'
    $env:NPM_CONFIG_CACHE = Join-Path $script:ElevHomeReal 'npm-cache'
}
$script:LoopHome = Join-Path $script:ProfileDir ".innovation-loop-$($script:Project)"
$script:ElevHome = $script:ElevHomeReal
if (-not $script:IsProtectedCopy) {
    # Test-only overrides (validation runs against scratch dirs); the protected copy ignores them.
    $h = [Environment]::GetEnvironmentVariable("$($script:EnvPrefix)_HOME", 'Process')
    if ($h) { $script:LoopHome = $h }
    $e = [Environment]::GetEnvironmentVariable("$($script:EnvPrefix)_ELEVHOME", 'Process')
    if ($e) { $script:ElevHome = $e }
}

$script:Owner          = "$(Get-Cfg 'owner')"
$script:HubRepo        = "$(Get-Cfg 'hubRepo')"
$script:Marker         = '<!-- innovation-loop -->'
$script:CommitTrailer  = "$(Get-Cfg 'commitTrailer' 'Co-Authored-By: Claude <noreply@anthropic.com>')"
$script:GhExe          = "$(Get-Cfg 'tools.gh' 'C:\Program Files\GitHub CLI\gh.exe')"
$script:NodeExe        = "$(Get-Cfg 'tools.node' 'C:\Program Files\nodejs\node.exe')"
$script:NpmCmd         = "$(Get-Cfg 'tools.npm' 'C:\Program Files\nodejs\npm.cmd')"   # npm.ps1 is blocked by execution policy: always npm.cmd
# Task names: innovation-loop-<project>[-deploy] unless loop.config.json tasks.loop / tasks.deploy keep the names of a
# loop that predates the kit (the approval watcher and the owner's habits refer to them). install-task.ps1 reads the same keys.
$script:DeployTaskName = "$(Get-Cfg 'tasks.deploy' "innovation-loop-$($script:Project)-deploy")"
$script:LoopTaskName   = "$(Get-Cfg 'tasks.loop' "innovation-loop-$($script:Project)")"
$script:RequestPath    = Join-Path $script:LoopHome 'elevated\request.json'
$script:ResultDir      = Join-Path $script:ElevHome 'results'
$script:ServerEnabled  = [bool](Get-Cfg 'server.enabled' $false)
$script:FrontendMode   = "$(Get-Cfg 'frontend.mode' 'none')"     # workflow | manual | none
$script:LiveDir        = "$(Get-Cfg 'server.liveDir' '')"
if (-not $script:IsProtectedCopy) {
    $l = [Environment]::GetEnvironmentVariable("$($script:EnvPrefix)_LIVEDIR", 'Process')
    if ($l) { $script:LiveDir = $l }
}

# Repos this loop may touch. repos[0] is normally the hub (issues live there).
$script:Repos = @(Get-Cfg 'repos' @())
if ($script:Repos.Count -eq 0) { throw 'loop.config.json: repos is empty' }
function Get-RepoCfg {
    param([string]$Name = '')
    if (-not $Name) { return $script:Repos[0] }
    $r = @($script:Repos | Where-Object { $_.name -eq $Name })
    if ($r.Count -ne 1) { throw "unknown repo name '$Name' (known: $(@($script:Repos | ForEach-Object { $_.name }) -join ', '))" }
    return $r[0]
}
function Get-ClonePath { param([string]$Name = '') return (Join-Path $script:LoopHome ("clones\" + (Get-RepoCfg $Name).name)) }
$script:Clone = Get-ClonePath     # hub clone

if (-not $script:IsProtectedCopy) {
    # git refuses repositories owned by someone else ("dubious ownership"). run-loop.ps1 may hold an admin
    # token (scheduled tasks of an admin account do), so Administrators can own the clones while the session
    # runs reduced. GIT_CONFIG_COUNT/KEY/VALUE is command-line scope, which git honours for safe.directory,
    # and it changes no config file.
    $safe = @($script:Repos | ForEach-Object { Join-Path $script:LoopHome ("clones\" + $_.name) })
    if ($script:LiveDir) { $safe += $script:LiveDir }
    # gitSafeExtra: more repos git children must accept (paths under LoopHome; a trailing \* is git's dir/* prefix form,
    # git 2.46+). E.g. gh-pages' publish clone in clones\<repo>\node_modules\.cache\gh-pages\*, which an earlier
    # elevated run may have left owned by Administrators (the reduced token then sees "dubious ownership").
    foreach ($x in @(Get-Cfg 'gitSafeExtra' @())) { if ("$x" -and "$x" -notmatch '^\*$' -and "$x" -notmatch '\.\.') { $safe += (Join-Path $script:LoopHome "$x") } }
    $env:GIT_CONFIG_COUNT = "$($safe.Count)"
    for ($i = 0; $i -lt $safe.Count; $i++) {
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$i", 'safe.directory', 'Process')
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$i", $safe[$i].Replace('\', '/'), 'Process')
    }
}

# Files the elevated task runs; install-task.ps1 copies exactly these into ElevHome\bin.
$script:ElevatedFiles = @('lib.ps1', 'loop.config.json', 'hooks-server.ps1', 'elevated-task.ps1', 'deploy-server.ps1', 'rollback-server.ps1')

# Exit codes shared by deploy/rollback scripts (same meaning in every loop)
$script:EXIT_OK              = 0
$script:EXIT_PRECONDITION    = 1   # nothing was changed
$script:EXIT_ROLLED_BACK     = 2   # deploy failed verification, rollback succeeded
$script:EXIT_ROLLBACK_FAILED = 3   # production may be broken: human needed
$script:EXIT_BUILD_FAILED    = 4   # failed before anything live was touched

# Paths the loop must never change on its own (repo-relative regexes, forward slashes). A PR touching
# one is refused by merge-pr.ps1 and the guard blocks edits to them. The four defaults protect the loop
# itself and secrets; the project adds its out-of-scope paths in loop.config.json protectedPaths.
$script:ProtectedPathPatterns = @('^\.github/', '^\.claude/', '^innovation/', '(^|/)\.env') + @(Get-Cfg 'protectedPaths' @())

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Initialize-LoopDirs {
    foreach ($d in 'logs', 'clones', 'lock', 'artifacts', 'state', 'work', 'elevated', 'scratch') {
        $p = Join-Path $script:LoopHome $d
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

function Start-ScriptLog {
    param([string]$Name, [string]$Dir = '')
    if (-not $Dir) { Initialize-LoopDirs; $Dir = Join-Path $script:LoopHome 'logs' }
    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $script:LogFile = Join-Path $Dir ("{0}-{1}.log" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

# Remove secret-looking variables from this process (and so from children). ANTHROPIC_API_KEY is removed
# too: with it set, claude bills the API instead of using the Max subscription.
function Clear-SecretEnv {
    $names = @(Get-Cfg 'secretEnvNames' @())
    $removed = @()
    foreach ($v in @(Get-ChildItem env:)) {
        $n = $v.Name
        $hit = ($n -match '(SECRET|PASSWORD|PASSWD|TOKEN|API_KEY|APIKEY|PRIVATE_KEY|CREDENTIAL)') -or ($names -contains $n)
        if ($n -match '^CLAUDE_CODE_' -and $n -notmatch 'TOKEN|KEY') { $hit = $false }
        if ($hit) { Remove-Item -LiteralPath "env:$n"; $removed += $n }
    }
    return $removed
}

# Run a native command, stream output to the log, throw on nonzero exit. PS 5.1 turns native stderr into
# error records; collecting with 2>&1 under ErrorActionPreference=Continue keeps them as plain lines.
# For .cmd tools that write a lot to stderr (Maven), prefer: Invoke-Native cmd @('/c', 'mvnw.cmd ... 2>&1').
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
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFail, [switch]$Quiet)
    return Invoke-Native -File 'git' -Arguments (@('-C', $Repo) + $Arguments) -AllowFail:$AllowFail -Quiet:$Quiet
}

function Get-GitValue {
    param([string]$Repo, [string[]]$Arguments)
    $r = Invoke-Git -Repo $Repo -Arguments $Arguments -Quiet
    return (($r.Output | Where-Object { $_ -ne '' }) | Select-Object -Last 1).Trim()
}

function Invoke-Gh {
    param([string[]]$Arguments, [switch]$AllowFail, [switch]$Quiet)
    return Invoke-Native -File $script:GhExe -Arguments $Arguments -AllowFail:$AllowFail -Quiet:$Quiet
}

function Get-GhJson {
    param([string[]]$GhArgs)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $script:GhExe @GhArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "gh $($GhArgs -join ' ') failed: $($out -join ' ')" }
    $text = ($out -join "`n").Trim()
    if (-not $text) { return $null }
    return ($text | ConvertFrom-Json)
}

# Start a process and wait for it. PS 5.1 gotcha: Start-Process -PassThru returns an object whose ExitCode
# stays $null unless the process handle is opened right after start, so touch .Handle first.
function Start-AndWait {
    param([string]$File, [string]$ArgumentString, [string]$WorkDir, [string]$StdIn = $null, [string]$StdOut, [string]$StdErr, [int]$TimeoutMinutes)
    $sp = @{ FilePath = $File; ArgumentList = $ArgumentString; WorkingDirectory = $WorkDir; RedirectStandardOutput = $StdOut; RedirectStandardError = $StdErr; PassThru = $true; WindowStyle = 'Hidden' }
    if ($StdIn) { $sp.RedirectStandardInput = $StdIn }
    $proc = Start-Process @sp
    $null = $proc.Handle   # required for a real ExitCode under PS 5.1
    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
        return @{ TimedOut = $true; ExitCode = $null; Pid = $proc.Id }
    }
    $proc.WaitForExit()
    return @{ TimedOut = $false; ExitCode = $proc.ExitCode; Pid = $proc.Id }
}

# ---- reduced-token launcher (run-loop.ps1) ---------------------------------------------------------
# Windows does NOT drop admin rights for scheduled tasks of an admin account: RunLevel Limited with S4U or
# Password logon still yields a full token (no UAC split token for non-interactive logons). So the claude
# session is started under a filtered (LUA), Medium-integrity token (LowRights.cs), its real token is read
# back and logged, and anything that still looks elevated is killed (fail closed).
# Launcher: CreateRestrictedToken(LUA_TOKEN) + Medium integrity + user owner/default DACL, child created
# SUSPENDED and resumed only after its token passes the check (see LowRights.cs for why not SAFER).
function Initialize-LowRights {
    if (-not ('InnovationLoopLowRights' -as [type])) { Add-Type -Path (Join-Path $script:KitDir 'LowRights.cs') }
}
function Get-TokenState { param([int]$ProcessId = 0) Initialize-LowRights; return [InnovationLoopLowRights]::Inspect($ProcessId) }
# Reduced = TokenElevation 0 AND Administrators deny-only/absent AND integrity Medium or lower AND no privilege
# beyond a standard user's. (A SAFER token reads TokenElevation=1 even when reduced; the LUA token used here
# reads 0, so all four checks apply.) LowRights.cs runs the same test before resuming the child.
$script:StandardUserPrivileges = @('SeChangeNotifyPrivilege', 'SeShutdownPrivilege', 'SeUndockPrivilege', 'SeIncreaseWorkingSetPrivilege', 'SeTimeZonePrivilege')
function Test-TokenReduced {
    param([string]$State)
    if ($State -notmatch '^elevated=0 ') { return $false }
    if ($State -notmatch 'adminState=(deny-only|absent)\b' -or $State -notmatch 'integrity=0x(2000|1000)\b') { return $false }
    $m = [regex]::Match($State, 'privileges=(\S*)')
    if (-not $m.Success) { return $false }
    foreach ($p in ($m.Groups[1].Value -split ',' | Where-Object { $_ })) { if ($script:StandardUserPrivileges -notcontains $p) { return $false } }
    return $true
}

# Start $File under the reduced token with stdio redirected to files; verify the child's token (fail closed:
# kill it and throw if it is not reduced); wait up to -TimeoutMinutes (kill the tree on timeout).
function Start-ReducedAndWait {
    param([string]$File, [string]$ArgumentString, [string]$WorkDir, [string]$StdIn = '', [string]$StdOut, [string]$StdErr, [int]$TimeoutMinutes)
    Initialize-LowRights
    $cmdLine = '"' + $File + '" ' + $ArgumentString
    $r = [InnovationLoopLowRights]::Start($File, $cmdLine, $WorkDir, $StdIn, $StdOut, $StdErr) -split '\|', 3
    $childPid = [int]$r[0]; $h = [long]$r[1]
    try {
        $state = ''
        try { $state = Get-TokenState -ProcessId $childPid } catch { $state = "unreadable: $_" }
        Write-Log "reduced child pid $childPid via $($r[2]); token: $state"
        if (-not (Test-TokenReduced $state)) {
            & taskkill.exe /PID $childPid /T /F 2>&1 | Out-Null
            throw "child token is not reduced ($state); killed it (failing closed)"
        }
        $code = [InnovationLoopLowRights]::Wait($h, [uint32]($TimeoutMinutes * 60 * 1000))
        if ($code -eq -1) { & taskkill.exe /PID $childPid /T /F 2>&1 | Out-Null; return @{ TimedOut = $true; ExitCode = $null; Pid = $childPid; Token = $state } }
        return @{ TimedOut = $false; ExitCode = [int]$code; Pid = $childPid; Token = $state }
    } finally { [InnovationLoopLowRights]::CloseProcess($h) }
}

# Plain HTTP GET/HEAD that never throws on 4xx/5xx. The loop never sends anything but GET/HEAD to prod.
function Invoke-Http {
    param([string]$Url, [ValidateSet('GET', 'HEAD')][string]$Method = 'GET', [int]$TimeoutSec = 30)
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.AllowAutoRedirect = $true
    $req.UserAgent = 'innovation-loop-verify'
    $req.Headers.Add('Cache-Control', 'no-cache')
    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) { $resp = $_.Exception.Response }
        else { return @{ Status = 0; Body = ''; Error = $_.Exception.Message } }
    }
    try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd(); $reader.Close()
        return @{ Status = [int]$resp.StatusCode; Body = $text; Error = $null }
    } finally { $resp.Close() }
}

# GET with retries: for flaky upstreams, so a burst of upstream failures does not cause a false rollback
# (a false rollback is also an outage). Returns the last response; .Ok says whether -ExpectRegex matched.
function Invoke-HttpRetry {
    param([string]$Url, [string]$ExpectRegex = '', [int]$Attempts = 5, [int]$DelaySec = 10, [int]$TimeoutSec = 30)
    $last = $null
    for ($i = 1; $i -le $Attempts; $i++) {
        $last = Invoke-Http -Url $Url -TimeoutSec $TimeoutSec
        $ok = ($last.Status -eq 200) -and ((-not $ExpectRegex) -or ($last.Body -match $ExpectRegex))
        if ($ok) { $last.Ok = $true; return $last }
        Write-Log "GET $Url attempt ${i}/${Attempts}: status=$($last.Status)" 'WARN'
        if ($i -lt $Attempts) { Start-Sleep -Seconds ($DelaySec * $i) }
    }
    $last.Ok = $false
    return $last
}

function Get-CacheBustedUrl { param([string]$Url) $sep = '?'; if ($Url.Contains('?')) { $sep = '&' }; return "$Url${sep}cb=$([DateTime]::UtcNow.Ticks)" }

function Test-ProtectedPath {
    param([string]$Path)
    $p = $Path.Replace('\', '/')
    foreach ($re in $script:ProtectedPathPatterns) { if ($p -match $re) { return $re } }
    return $null
}

function Get-ChangedFiles {
    param([string]$Repo, [string]$From, [string]$To)
    $r = Invoke-Git -Repo $Repo -Arguments @('diff', '--name-only', "$From..$To") -Quiet
    return @($r.Output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
}

# Files whose change means the SERVER needs deploying (config server.paths: dir prefixes or exact files).
function Test-IsServerPath {
    param([string]$Path)
    $p = $Path.Replace('\', '/')
    foreach ($s in @(Get-Cfg 'server.paths' @())) {
        $s = "$s".Replace('\', '/').TrimEnd('/')
        if ($p -eq $s -or $p.StartsWith("$s/")) { return $true }
    }
    return $false
}

# Does a file in the live checkout change what the server RUNS? server.paths (Test-IsServerPath) minus
# server.inertPaths (regexes: e.g. build/test configs listed among server.paths only to be typechecked), plus
# server.liveExtraPaths (regexes: data the server or a sibling service reads from its checkout, e.g. a search
# index) and .env* files. Everything else in the live checkout (innovation/, .github/, docs, e2e, client-only
# source) is never executed on the server: moving the live checkout across it is inert.
function Test-LiveAffectingPath {
    param([string]$Path)
    $p = $Path.Replace('\', '/')
    if ($p -match '(^|/)\.env') { return $true }
    foreach ($re in @(Get-Cfg 'server.liveExtraPaths' @())) { if ($re -and $p -match $re) { return $true } }
    foreach ($re in @(Get-Cfg 'server.inertPaths' @())) { if ($re -and $p -match $re) { return $false } }
    return (Test-IsServerPath $p)
}

# Protected paths changed between the live HEAD and a target, split by what they would do to the live server.
#   Block  protected AND live-affecting: the live checkout never moves across these without the owner
#   Inert  protected but never executed on the server (innovation/, .github/, ...): listed, never refused
# Shared by merge-pr / deploy (gate-rules.ps1 Get-GapDecision) and the elevated deploy-server.ps1. Learned on
# cardlens: refusing every protected path in the gap blocked merges twice over files the server never runs.
function Split-ProtectedByLiveImpact {
    param([string[]]$Protected)
    $block = New-Object System.Collections.ArrayList; $inert = New-Object System.Collections.ArrayList
    foreach ($f in @($Protected | Where-Object { $_ } | ForEach-Object { "$_".Replace('\', '/') } | Select-Object -Unique)) {
        if (Test-LiveAffectingPath $f) { [void]$block.Add($f) } else { [void]$inert.Add($f) }
    }
    return [pscustomobject]@{ Block = @($block); Inert = @($inert) }
}

# Wait for the GitHub Actions run of -Workflow for commit -Sha in repo -Slug. Reports (and, after
# -StuckMinutes, cancels) an OLDER run stuck in `waiting`, which can block a whole concurrency group
# (GitHub Pages environments do this). Returns $true only for conclusion=success.
function Wait-WorkflowRun {
    param([string]$Slug, [string]$Workflow, [string]$Sha, [int]$TimeoutSec = 1500, [int]$StuckMinutes = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $seen = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $json = Get-GhJson @('api', "repos/$Slug/actions/workflows/$Workflow/runs?per_page=20")
            $runs = @($json.workflow_runs)
            $mine = @($runs | Where-Object { $_.head_sha -eq $Sha } | Sort-Object { [datetime]$_.created_at } -Descending)
            foreach ($r in @($runs | Where-Object { $_.status -in @('waiting', 'queued', 'pending') -and $_.head_sha -ne $Sha })) {
                $age = [DateTime]::UtcNow - ([datetime]$r.created_at).ToUniversalTime()
                Write-Log "older $Workflow run $($r.id) ($($r.head_sha.Substring(0,7))) is $($r.status) for $([int]$age.TotalMinutes) min" 'WARN'
                if ($r.status -eq 'waiting' -and $age.TotalMinutes -ge $StuckMinutes -and $mine.Count -gt 0 -and ([datetime]$r.created_at) -lt [datetime]$mine[0].created_at) {
                    Write-Log "cancelling stuck run $($r.id) (blocks the concurrency group)" 'WARN'
                    Invoke-Gh -Arguments @('run', 'cancel', "$($r.id)", '-R', $Slug) -AllowFail | Out-Null
                }
            }
            if ($mine.Count -gt 0) {
                $seen = $true
                $run = $mine[0]
                Write-Log "$Workflow run $($run.id) for $($Sha.Substring(0,7)): status=$($run.status) conclusion=$($run.conclusion)"
                if ($run.status -eq 'completed') { return ($run.conclusion -eq 'success') }
            } else { Write-Log "no $Workflow run for $($Sha.Substring(0,7)) yet" }
        } catch { Write-Log "could not read Actions runs: $_" 'WARN' }
        Start-Sleep -Seconds 20
    }
    Write-Log "timed out waiting for the $Workflow run of $Sha (seen=$seen)" 'ERROR'
    return $false
}

# Revert a commit on main (merge or plain) in a loop clone and push. Idempotent: skips if already reverted.
# Never force-pushes: main is only ever fast-forwarded. Returns the sha now at the tip of main.
function Invoke-RevertOnMain {
    param([string]$Repo, [string]$Sha)
    Invoke-Git -Repo $Repo -Arguments @('fetch', 'origin', '--prune') | Out-Null
    Invoke-Git -Repo $Repo -Arguments @('checkout', '-f', '-B', 'main', 'origin/main') | Out-Null
    Invoke-Git -Repo $Repo -Arguments @('reset', '--hard', 'origin/main') | Out-Null
    $full = Get-GitValue -Repo $Repo -Arguments @('rev-parse', $Sha)
    $already = Invoke-Git -Repo $Repo -Arguments @('log', 'origin/main', '--format=%H', "--grep=This reverts commit $full") -AllowFail -Quiet
    if (@($already.Output | Where-Object { $_ -match '^[0-9a-f]{40}$' }).Count -gt 0) {
        Write-Log "$full is already reverted on main; nothing to do"
        return (Get-GitValue -Repo $Repo -Arguments @('rev-parse', 'origin/main'))
    }
    $isAncestor = Invoke-Git -Repo $Repo -Arguments @('merge-base', '--is-ancestor', $full, 'origin/main') -AllowFail
    if ($isAncestor.Code -ne 0) { throw "$full is not on origin/main; refusing to revert" }
    $parents = (Get-GitValue -Repo $Repo -Arguments @('rev-list', '--parents', '-n', '1', $full)).Split(' ').Count - 1
    $msgFile = Join-Path $script:LoopHome 'work\revert-msg.txt'
    $subject = Get-GitValue -Repo $Repo -Arguments @('log', '-1', '--format=%s', $full)
    $msg = "Revert `"$subject`"`n`nThis reverts commit $full.`n`nAutomatic rollback by the innovation loop: the change failed post-deploy verification.`n`n$($script:CommitTrailer)`n"
    [IO.File]::WriteAllText($msgFile, $msg, (New-Object Text.UTF8Encoding $false))
    if ($parents -gt 1) { Invoke-Git -Repo $Repo -Arguments @('revert', '--no-commit', '-m', '1', $full) | Out-Null }
    else { Invoke-Git -Repo $Repo -Arguments @('revert', '--no-commit', $full) | Out-Null }
    Invoke-Git -Repo $Repo -Arguments @('commit', '-F', $msgFile) | Out-Null
    Invoke-Git -Repo $Repo -Arguments @('push', 'origin', 'HEAD:main') | Out-Null
    $tip = Get-GitValue -Repo $Repo -Arguments @('rev-parse', 'HEAD')
    Write-Log "reverted $full on main with $tip and pushed"
    return $tip
}

function Save-JsonFile { param([string]$Path, $Object) $dir = Split-Path $Path; if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }; [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false)) }
function Read-JsonFile { param([string]$Path) if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }; return $null }
function Save-State { param([string]$Name, $Object) Save-JsonFile -Path (Join-Path $script:LoopHome "state\$Name.json") -Object $Object }
function Read-State { param([string]$Name) return (Read-JsonFile -Path (Join-Path $script:LoopHome "state\$Name.json")) }

function New-Nonce {
    $bytes = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (-join ($bytes | ForEach-Object { $_.ToString('x2') }))
}

# ======================================================================================
# Server side helpers (used by the elevated scripts and hooks-server.ps1)
# ======================================================================================

function Wait-ServiceState {
    param([string]$Name, [string]$State, [int]$TimeoutSec = 90)
    $svc = Get-Service -Name $Name
    try { $svc.WaitForStatus($State, [TimeSpan]::FromSeconds($TimeoutSec)); return $true } catch { return $false }
}

# NSSM's own pid is stable across app restarts; the app child's is not. A changing child pid during
# verification means NSSM restarted a crashing app, which a single health check misses.
function Get-ServiceChildPid {
    $name = "$(Get-Cfg 'server.serviceName' '')"
    $pattern = "$(Get-Cfg 'server.childProcessPattern' '.')"
    if (-not $name) { return 0 }
    $svc = Get-CimInstance Win32_Service -Filter "Name='$name'"
    if (-not $svc -or -not $svc.ProcessId) { return 0 }
    $child = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($svc.ProcessId)" | Where-Object { $_.Name -match $pattern -and $_.Name -notmatch '^conhost' })
    if ($child.Count -gt 0) { return [int]$child[0].ProcessId }
    return [int]$svc.ProcessId
}

# The live checkout's HEAD, readable from a NON-elevated process (safe.directory on the command line).
function Get-LiveHead {
    if (-not $script:LiveDir) { throw 'server.liveDir is not configured' }
    $sd = 'safe.directory=' + $script:LiveDir.Replace('\', '/')
    return (Get-GitValue -Repo $script:LiveDir -Arguments @('-c', $sd, 'rev-parse', 'HEAD'))
}

# What a deploy of $Target means for the server, judged against the LIVE checkout's HEAD.
#   ServerNeeded  a server path (config server.paths) changed
#   Protected     protected paths changed (never auto-deployed)
#   Foreign       server files changed by commits NOT in -OwnCommitsFrom..$Target (undeployed work of Ve's
#                 already on main, which the loop would otherwise ship by accident)
function Get-ServerPlan {
    param([string]$Repo, [string]$Target, [string]$OwnCommitsFrom = '')
    $liveHead = Get-LiveHead
    $known = Invoke-Git -Repo $Repo -Arguments @('cat-file', '-e', "$liveHead^{commit}") -AllowFail -Quiet
    if ($known.Code -ne 0) { throw "live HEAD $liveHead is not in the loop clone (fetch?)" }
    $fwd = Invoke-Git -Repo $Repo -Arguments @('merge-base', '--is-ancestor', $liveHead, $Target) -AllowFail -Quiet
    if ($fwd.Code -ne 0) { throw "live HEAD $liveHead is not an ancestor of $Target" }
    $changed = Get-ChangedFiles -Repo $Repo -From $liveHead -To $Target
    $serverFiles = @($changed | Where-Object { Test-IsServerPath $_ })
    $protected = @($changed | Where-Object { Test-ProtectedPath $_ })
    $foreign = @()
    if ($serverFiles.Count -gt 0) {
        $own = @()
        if ($OwnCommitsFrom) { $own = @((Invoke-Git -Repo $Repo -Arguments @('rev-list', "$OwnCommitsFrom..$Target") -Quiet).Output | Where-Object { $_ }) }
        $touching = @((Invoke-Git -Repo $Repo -Arguments (@('rev-list', "$liveHead..$Target", '--') + $serverFiles) -Quiet).Output | Where-Object { $_ })
        $foreign = @($touching | Where-Object { $own -notcontains $_ })
    }
    return [pscustomobject]@{ LiveHead = $liveHead; Changed = $changed; ServerFiles = $serverFiles; ServerNeeded = ($serverFiles.Count -gt 0); Protected = $protected; Foreign = $foreign }
}

# ======================================================================================
# Non-elevated side: asking the elevated task to act
# ======================================================================================

# Write a request for the elevated task, start the task (exactly this one task name), poll for the result.
# Returns the result object; .status is ok | rejected | failed | rolled-back | rollback-failed | not-started | timeout.
function Invoke-ElevatedRequest {
    param([ValidateSet('deploy', 'rollback', 'selftest')][string]$Mode, [int]$Issue = 1, [string]$Sha = ('0' * 40), [int]$TimeoutMinutes = 45, [int]$PickupSeconds = 120)
    Initialize-LoopDirs
    $nonce = New-Nonce
    $req = [ordered]@{ mode = $Mode; issue = $Issue; sha = $Sha.ToLowerInvariant(); requestedAt = [DateTime]::UtcNow.ToString('o'); nonce = $nonce }
    Save-JsonFile -Path $script:RequestPath -Object $req
    $resultPath = Join-Path $script:ResultDir "$nonce.json"
    Write-Log "elevated request: mode=$Mode issue=$Issue sha=$Sha nonce=$nonce"
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & schtasks.exe /run /tn $script:DeployTaskName 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE; $ErrorActionPreference = $prev
    Write-Log "schtasks /run: exit $code $($out -join ' ')"
    if ($code -ne 0) {
        Remove-Item -LiteralPath $script:RequestPath -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ nonce = $nonce; status = 'not-started'; exitCode = -1; message = "could not start task $($script:DeployTaskName): $($out -join ' ')" }
    }
    $pickupDeadline = (Get-Date).AddSeconds($PickupSeconds)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $last = ''
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $r = $null
        try { $r = Read-JsonFile -Path $resultPath } catch { }
        if (-not $r) {
            if ((Get-Date) -gt $pickupDeadline) {
                Remove-Item -LiteralPath $script:RequestPath -Force -ErrorAction SilentlyContinue
                return [pscustomobject]@{ nonce = $nonce; status = 'not-started'; exitCode = -1; message = "task did not pick up the request within $PickupSeconds s (already running? not installed? disabled?)" }
            }
            continue
        }
        if ($r.status -ne $last) { Write-Log "elevated status: $($r.status) $($r.message)"; $last = $r.status }
        if ($r.status -ne 'started') { return $r }
    }
    return [pscustomobject]@{ nonce = $nonce; status = 'timeout'; exitCode = -1; message = "no final result after $TimeoutMinutes min; see $($script:ElevHome)\logs" }
}

# Hash-compare the admin-only copy with this checkout. Returns the list of stale file names.
function Get-StaleElevatedFiles {
    param([string]$ScriptsDir)
    $stale = @()
    foreach ($f in $script:ElevatedFiles) {
        $a = Join-Path $ScriptsDir $f; $b = Join-Path $script:ElevHome "bin\$f"
        if (-not (Test-Path -LiteralPath $b) -or (Get-FileHash -LiteralPath $a).Hash -ne (Get-FileHash -LiteralPath $b).Hash) { $stale += $f }
    }
    return $stale
}
