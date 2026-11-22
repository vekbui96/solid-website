<#
.SYNOPSIS
  Install (or update) this project's innovation loop scheduled tasks. Run from an ELEVATED PowerShell (an
  SSH session to server-pc is elevated). The OWNER runs this, not an agent: it may ask for a password.

.DESCRIPTION
  1. innovation-loop-<project>          daily at -At, runs run-loop.ps1 from this checkout. Created DISABLED.
                                         RunLevel Limited is only a statement of intent: Windows gives an admin
                                         account's non-interactive logon a FULL token whatever the RunLevel or
                                         logon type, so run-loop.ps1 drops rights itself (LowRights.cs) and
                                         fails closed. Check the run log for "reduced child pid ... token:
                                         elevated=0 ... adminState=deny-only".
  2. innovation-loop-<project>-deploy   (only if server.enabled) NO trigger, RunLevel Highest, fixed action:
                                           powershell -File C:\ProgramData\innovation-loop-<project>\bin\elevated-task.ps1
                                         Its DACL also lets the owner's NON-elevated token start (and read) it,
                                         nothing more. Only deploy.ps1 / rollback.ps1 / merge-pr.ps1 / run-loop.ps1
                                         start it (schtasks /run), and only with a request file it validates.
  3. Copies the elevated files (lib.ps1, loop.config.json, hooks-server.ps1, elevated-task.ps1,
     deploy-server.ps1, rollback-server.ps1) to C:\ProgramData\innovation-loop-<project>\bin and locks the
     folder to SYSTEM + Administrators (full) and Users (read/execute). The elevated task never runs a file
     a non-elevated process can edit; changing what runs elevated needs this script, elevated, again
     (-ElevatedOnly). run-loop.ps1 hash-compares the copy every run and refuses server deploys on a mismatch.

  Logon type (-LogonType): S4U (default; no stored password, runs while logged off; the loop reaches GitHub
  with SSH deploy keys and the gh token from the profile, not Windows network credentials) or Password
  (asks in the CONSOLE with Read-Host -AsSecureString: Get-Credential is a GUI dialog that never appears
  over SSH; an empty password is refused because Task Scheduler cannot store one).

  Afterwards, from a NORMAL (non-admin) PowerShell, prove the non-elevated trigger works:
     powershell -ExecutionPolicy Bypass -File <this dir>\run-loop.ps1 -SelfTest
  Enable when ready:  Enable-ScheduledTask -TaskName innovation-loop-<project>
  Remove the tasks:   .\install-task.ps1 -Uninstall
  Generic (from the innovation-loop kit).
#>
[CmdletBinding()]
param(
    [string]$At = '',
    [string]$User = '',
    [string]$ExtraArgs = '',                          # e.g. '-ProposeOnly' for the supervised start
    [ValidateSet('S4U', 'Password')][string]$LogonType = 'S4U',
    [switch]$Uninstall,
    [switch]$ElevatedOnly                             # only refresh the elevated copy + deploy task (after git pull)
)
$ErrorActionPreference = 'Stop'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'run this from an elevated PowerShell'
}
# $PSScriptRoot is empty in param() defaults under `powershell -File` on PS 5.1, so resolve everything here.
$Here = $PSScriptRoot; if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$cfg = [IO.File]::ReadAllText((Join-Path $Here 'loop.config.json')) | ConvertFrom-Json
$Project = "$($cfg.project)"
if ($Project -cnotmatch '^[a-z0-9][a-z0-9-]{1,40}$') { throw "bad project name '$Project' in loop.config.json" }
if (-not $At) { $At = "$($cfg.schedule)"; if (-not $At) { $At = '14:23' } }
if (-not $User) { $User = "$($cfg.windowsUser)"; if (-not $User) { $User = "$env:COMPUTERNAME\$env:USERNAME" } }
$ServerEnabled = [bool]($cfg.server -and $cfg.server.enabled)
$LoopTask = "innovation-loop-$Project"; if ($cfg.tasks -and "$($cfg.tasks.loop)") { $LoopTask = "$($cfg.tasks.loop)" }          # must match lib.ps1
$DeployTask = "innovation-loop-$Project-deploy"; if ($cfg.tasks -and "$($cfg.tasks.deploy)") { $DeployTask = "$($cfg.tasks.deploy)" }
$ElevHome = "C:\ProgramData\innovation-loop-$Project"   # must match lib.ps1
$Bin = Join-Path $ElevHome 'bin'
$Files = @('lib.ps1', 'loop.config.json', 'hooks-server.ps1', 'elevated-task.ps1', 'deploy-server.ps1', 'rollback-server.ps1')
$RunLoop = Join-Path $Here 'run-loop.ps1'

if ($Uninstall) {
    foreach ($t in $LoopTask, $DeployTask) { if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $t -Confirm:$false; Write-Host "removed $t" } }
    Write-Host "left $ElevHome in place (logs, deploy records, nonces); delete it by hand if wanted"
    Write-Host "if this loop is in C:\ProgramData\innovation-loop-watch\watch-approvals.ps1, remove its entry there too"
    return
}
if ($Here -match '\s') { throw "this checkout's path contains whitespace; the loop's permission rules need a path without spaces" }

$password = $null
if ($LogonType -eq 'Password') {
    $sec = Read-Host -AsSecureString "Password for $User (Task Scheduler stores it so the tasks run while logged off)"
    $password = (New-Object System.Net.NetworkCredential('', $sec)).Password
    if ([string]::IsNullOrEmpty($password)) { throw "empty password: Task Scheduler cannot store one. Set a password for $User, or use -LogonType S4U." }
}
function Register-LoopTask([string]$Name, $Task) {
    if ($LogonType -eq 'Password') { Register-ScheduledTask -TaskName $Name -InputObject $Task -User $User -Password $password -Force | Out-Null }
    else { Register-ScheduledTask -TaskName $Name -InputObject $Task -Force | Out-Null }
}
$settingsCommon = @{ MultipleInstances = 'IgnoreNew'; AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true }

if ($ServerEnabled) {
    # ---- 1. admin-only copy of the elevated scripts ---------------------------------------------------
    foreach ($d in $ElevHome, $Bin, (Join-Path $ElevHome 'results'), (Join-Path $ElevHome 'state'), (Join-Path $ElevHome 'logs'), (Join-Path $ElevHome 'lock'), (Join-Path $ElevHome 'config'), (Join-Path $ElevHome 'npm-cache')) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # no inherited rules
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [Security.AccessControl.PropagationFlags]::None
    foreach ($rule in @(
            (New-Object Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', $inherit, $none, 'Allow')),
            (New-Object Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators', 'FullControl', $inherit, $none, 'Allow')),
            (New-Object Security.AccessControl.FileSystemAccessRule('BUILTIN\Users', 'ReadAndExecute', $inherit, $none, 'Allow')))) { $acl.AddAccessRule($rule) }
    $acl.SetOwner((New-Object Security.Principal.NTAccount('BUILTIN\Administrators')))
    Set-Acl -LiteralPath $ElevHome -AclObject $acl
    foreach ($f in $Files) { Copy-Item -LiteralPath (Join-Path $Here $f) -Destination (Join-Path $Bin $f) -Force }
    Copy-Item -LiteralPath (Join-Path $Here 'LowRights.cs') -Destination (Join-Path $Bin 'LowRights.cs') -Force   # lib.ps1 may load it
    Get-ChildItem -LiteralPath $ElevHome -Recurse | ForEach-Object {
        $a = Get-Acl -LiteralPath $_.FullName; $a.SetAccessRuleProtection($false, $false); Set-Acl -LiteralPath $_.FullName -AclObject $a
    }
    # empty, admin-owned git/npm config for the elevated side (lib.ps1 points GIT_CONFIG_GLOBAL / NPM_CONFIG_USERCONFIG here)
    foreach ($c in 'gitconfig', 'npmrc') { $p = Join-Path $ElevHome "config\$c"; if (-not (Test-Path -LiteralPath $p)) { [IO.File]::WriteAllText($p, '') } }

    # ---- 1b. optional: the elevated side's own clone of a PRIVATE server repo (server.elevatedClone) -------
    # For an artifact service whose repo is private (no public fetch-only checkout to deploy from): server.liveDir
    # is then a clone under <ElevHome>\clones that only the elevated side writes, fetched over SSH with an
    # admin-only ssh_config (alias -> github.com, the deploy key's path, a pinned host key, no ProxyCommand), so
    # edits to the user-writable ~\.ssh\config cannot change what the elevated git runs. The admin-owned
    # gitconfig points core.sshCommand at it. The key file itself stays in the owner's profile (as before).
    $ec = $null; if ($cfg.server -and $cfg.server.elevatedClone) { $ec = $cfg.server.elevatedClone }
    if ($ec) {
        $live = "$($cfg.server.liveDir)"
        if (-not $live.StartsWith((Join-Path $ElevHome 'clones') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "server.elevatedClone needs server.liveDir under $ElevHome\clones (got '$live')" }
        $alias = "$($ec.sshAlias)"; $url = "$($ec.url)"
        if ($alias -notmatch '^[A-Za-z0-9._-]+$' -or $url -notmatch ('^git@' + [regex]::Escape($alias) + ':[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$')) { throw "server.elevatedClone: bad sshAlias/url ('$alias', '$url')" }
        $gitSsh = 'C:\Program Files\Git\usr\bin\ssh.exe'
        if (-not (Test-Path -LiteralPath $gitSsh)) { throw "Git's ssh.exe not found at $gitSsh" }
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # ssh writes notices to stderr
        $resolved = @(& $gitSsh -G $alias 2>&1 | ForEach-Object { "$_" })
        $scan = @(& 'C:\Program Files\Git\usr\bin\ssh-keyscan.exe' -t ed25519 github.com 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^github\.com ssh-ed25519 ' }) | Select-Object -First 1
        $ErrorActionPreference = $eap
        $hostName = ($resolved | Where-Object { $_ -like 'hostname *' } | Select-Object -First 1) -replace '^hostname ', ''
        $keyPath = ($resolved | Where-Object { $_ -like 'identityfile *' } | Select-Object -First 1) -replace '^identityfile ', ''
        if ($hostName -ne 'github.com') { throw "ssh alias $alias does not resolve to github.com (got '$hostName')" }
        if ($keyPath -like '~*') { $keyPath = $env:USERPROFILE + $keyPath.Substring(1) }
        $keyPath = $keyPath -replace '/', '\'
        if (-not (Test-Path -LiteralPath $keyPath)) { throw "deploy key for $alias not found at $keyPath" }
        # GitHub's published ed25519 host key (docs.github.com, "GitHub's SSH key fingerprints"), checked live
        $githubKey = 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
        if ($scan -ne $githubKey) { throw 'github.com ed25519 host key from ssh-keyscan does not match the pinned key; refusing' }
        $utf8 = New-Object Text.UTF8Encoding $false
        $fwd = { param($x) $x -replace '\\', '/' }
        [IO.File]::WriteAllText((Join-Path $ElevHome 'config\known_hosts'), "$githubKey`n", $utf8)
        $sshCfg = "Host $alias`n  HostName github.com`n  User git`n  IdentityFile `"$(& $fwd $keyPath)`"`n  IdentitiesOnly yes`n  UserKnownHostsFile `"$(& $fwd (Join-Path $ElevHome 'config\known_hosts'))`"`n  GlobalKnownHostsFile /dev/null`n  StrictHostKeyChecking yes`n  ProxyCommand none`n  ProxyJump none`n"
        [IO.File]::WriteAllText((Join-Path $ElevHome 'config\ssh_config'), $sshCfg, $utf8)
        $gc = "[core]`n`tsshCommand = `"$(& $fwd $gitSsh)`" -F `"$(& $fwd (Join-Path $ElevHome 'config\ssh_config'))`"`n[safe]`n`tdirectory = $(& $fwd $live)`n"
        [IO.File]::WriteAllText((Join-Path $ElevHome 'config\gitconfig'), $gc, $utf8)
        if (-not (Test-Path -LiteralPath (Join-Path $live '.git'))) {
            $env:GIT_CONFIG_GLOBAL = Join-Path $ElevHome 'config\gitconfig'; $env:GIT_CONFIG_NOSYSTEM = '1'
            $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            & git clone --quiet $url $live 2>&1 | ForEach-Object { Write-Host "  $_" }
            $code = $LASTEXITCODE; $ErrorActionPreference = $eap
            if ($code -ne 0) { throw "git clone $url -> $live failed (exit $code)" }
            Write-Host "cloned $url into $live (elevated side only)"
        } else { Write-Host "elevated clone present: $live" }
    }
    Write-Host "copied $($Files -join ', ') to $Bin (Users: read/execute only)"

    # ---- 2. elevated deploy task: no trigger, fixed action ----------------------------------------------
    $elevScript = Join-Path $Bin 'elevated-task.ps1'
    $action = New-ScheduledTaskAction -Execute "$PSHOME\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$elevScript`"" -WorkingDirectory $Bin
    $settings = New-ScheduledTaskSettingsSet @settingsCommon -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType $LogonType -RunLevel Highest
    $task = New-ScheduledTask -Action $action -Settings $settings -Principal $principal `
        -Description "Elevated half of the $Project innovation loop: validates the request file and deploys/rolls back the server. No trigger. See $Here\README.md"
    Register-LoopTask $DeployTask $task
    # Let the owner's NON-elevated token start it: append (A;;GRGX;;;<SID>) to the task's DACL.
    $sid = (New-Object Security.Principal.NTAccount($User)).Translate([Security.Principal.SecurityIdentifier]).Value
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $t = $svc.GetFolder('\').GetTask($DeployTask)
    $sddl = $t.GetSecurityDescriptor(4)   # DACL_SECURITY_INFORMATION
    $ace = "(A;;GRGX;;;$sid)"
    if ($sddl -notmatch [regex]::Escape($ace)) { $t.SetSecurityDescriptor($sddl + $ace, 0) }
    Write-Host "registered $DeployTask (no trigger, highest privileges, $LogonType); DACL: $($t.GetSecurityDescriptor(4))"
} else {
    Write-Host 'server.enabled is false: no elevated deploy task, no ProgramData copy'
}

# ---- 3. the daily loop, disabled -------------------------------------------------------------------
if (-not $ElevatedOnly) {
    if (-not (Test-Path -LiteralPath $RunLoop)) { throw "not found: $RunLoop" }
    $argument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RunLoop`" $ExtraArgs".Trim()
    $action = New-ScheduledTaskAction -Execute "$PSHOME\powershell.exe" -Argument $argument -WorkingDirectory $Here
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet @settingsCommon -ExecutionTimeLimit (New-TimeSpan -Hours 5) -StartWhenAvailable -RunOnlyIfNetworkAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType $LogonType -RunLevel Limited
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
        -Description "$Project innovation loop (claude -p, LOOP.md). run-loop.ps1 drops its own rights (RunLevel alone does not). See $Here\README.md"
    Register-LoopTask $LoopTask $task
    Disable-ScheduledTask -TaskName $LoopTask | Out-Null
    Write-Host "registered $LoopTask (DISABLED, daily $At, $LogonType logon; run-loop drops rights itself)"
}
$password = $null
Get-ScheduledTask -TaskName $LoopTask, $DeployTask -ErrorAction SilentlyContinue | Format-Table TaskName, State
Write-Host "Next, from a NORMAL PowerShell:  powershell -ExecutionPolicy Bypass -File $RunLoop -SelfTest"
