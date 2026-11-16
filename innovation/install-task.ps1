<#
.SYNOPSIS
  Register the innovation loop's two scheduled tasks, both DISABLED, and prepare the elevated API side.

.DESCRIPTION
  Run from an ELEVATED PowerShell. It does not run either task.

  1. "InnovationLoop": daily at -At (13:17), run whether logged on or not, as SERVER-PC\VeBui,
     RunLevel LIMITED (not elevated). Runs run-loop.ps1 -> claude -p. Asks once for VeBui's password
     (stored by Task Scheduler).
  2. "innovation-loop-api": NO trigger, RunLevel HIGHEST, as SERVER-PC\VeBui (S4U logon by default: no
     stored password; it needs only local files and SSH to GitHub). Its only action is
       powershell -File C:\ProgramData\innovation-loop-api\bin\api-runner.ps1 -Root ... -QueueDir ...
     The loop starts it with `schtasks /run` and talks to it only through a request file (api-request.ps1).
     The task's security descriptor also grants VeBui read+run, so a non-elevated process can start it.
  3. C:\ProgramData\innovation-loop-api (the API side's home): bin\ (copies of api-runner.ps1, lib.ps1,
     deploy-api.ps1, rollback-api.ps1), clones\, state\, logs\, results\, api-backups\, m2\, home\, tmp\.
     DACL: SYSTEM + Administrators full control; VeBui and OWNER RIGHTS read+execute only (OWNER RIGHTS
     removes the owner's implicit right to rewrite the DACL); owner Administrators; High integrity label
     (no write-up from medium-integrity processes). Net effect: the non-elevated loop can read results
     and logs but cannot change the code or state that runs elevated.

  Re-run this after pulling changes to the API-side scripts: the elevated task runs the COPIES in bin\,
  never the files in D:\projects (which the non-elevated loop could modify).

  Enable when ready (both):  Enable-ScheduledTask -TaskName InnovationLoop; Enable-ScheduledTask -TaskName innovation-loop-api
  Disable:                   Disable-ScheduledTask -TaskName InnovationLoop
  Remove:                    Unregister-ScheduledTask -TaskName InnovationLoop -Confirm:$false  (same for innovation-loop-api)
#>
[CmdletBinding()]
param(
    [string]$LoopTaskName = 'InnovationLoop',
    [string]$ApiTaskName = 'innovation-loop-api',
    [string]$At = '13:17',
    [string]$User = 'SERVER-PC\VeBui',
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'run-loop.ps1'),
    [string]$ExtraArgs = '',                                       # e.g. '-ProposeOnly'
    [string]$ApiRoot = 'C:\ProgramData\innovation-loop-api',
    [string]$QueueDir = 'C:\Users\Ve Bui\.innovation-loop\api-queue',
    [ValidateSet('S4U', 'Password')][string]$ApiLogonType = 'S4U',
    [string]$ApiSshAlias = 'github-solid-website-api',          # existing ~\.ssh\config alias for the API deploy key
    [switch]$ApiOnly,              # set up only the API side (used for testing the trigger path)
    [switch]$EnableApiTask         # testing only; by default both tasks are left disabled
)
$ErrorActionPreference = 'Stop'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'run this from an elevated PowerShell'
}
$userSid = (New-Object Security.Principal.NTAccount $User).Translate([Security.Principal.SecurityIdentifier]).Value

# ---- API side home ----------------------------------------------------------------------------
foreach ($d in '', 'bin', 'clones', 'state', 'logs', 'results', 'lock', 'api-backups', 'api-staging', 'm2', 'home', 'tmp', 'work', 'artifacts') {
    $p = Join-Path $ApiRoot $d
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}
foreach ($f in 'api-runner.ps1', 'lib.ps1', 'deploy-api.ps1', 'rollback-api.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination (Join-Path $ApiRoot "bin\$f") -Force
}
$utf8 = New-Object Text.UTF8Encoding $false
$cloneFwd = (Join-Path $ApiRoot 'clones\solid-website-api') -replace '\\', '/'
[IO.File]::WriteAllText((Join-Path $ApiRoot 'gitconfig'), "[safe]`n`tdirectory = $cloneFwd`n", $utf8)
$repo = (Join-Path $ApiRoot 'm2\repository')
[IO.File]::WriteAllText((Join-Path $ApiRoot 'maven-settings.xml'), "<settings><localRepository>$repo</localRepository></settings>`n", $utf8)

# SSH for the elevated fetch of the PRIVATE API repo. `ssh -G` resolves the existing host alias to its key
# path (it reads the config, not the key). The elevated side then uses only <Root>\ssh_config (ssh -F), so
# later edits to the user-writable ~\.ssh\config cannot add a ProxyCommand or change the host.
$gitSsh = 'C:\Program Files\Git\usr\bin\ssh.exe'
if (-not (Test-Path -LiteralPath $gitSsh)) { throw "Git's ssh.exe not found at $gitSsh" }
$ErrorActionPreference = 'Continue'   # ssh writes notices to stderr; PS 5.1 would turn them into terminating errors
$resolved = @(& $gitSsh -G $ApiSshAlias 2>&1 | ForEach-Object { "$_" })
$hostName = ($resolved | Where-Object { $_ -like 'hostname *' } | Select-Object -First 1) -replace '^hostname ', ''
$keyPath = ($resolved | Where-Object { $_ -like 'identityfile *' } | Select-Object -First 1) -replace '^identityfile ', ''
if ($hostName -ne 'github.com') { throw "ssh alias $ApiSshAlias does not resolve to github.com (got '$hostName')" }
if ($keyPath -like '~*') { $keyPath = $env:USERPROFILE + $keyPath.Substring(1) }
$keyPath = $keyPath -replace '/', '\'
if (-not (Test-Path -LiteralPath $keyPath)) { throw "deploy key for $ApiSshAlias not found at $keyPath" }
# GitHub's published ed25519 host key (docs.github.com, "GitHub's SSH key fingerprints"), checked live below
$githubKey = 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
$scan = @(& 'C:\Program Files\Git\usr\bin\ssh-keyscan.exe' -t ed25519 github.com 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^github\.com ssh-ed25519 ' }) | Select-Object -First 1
$ErrorActionPreference = 'Stop'
if ($scan -ne $githubKey) { throw "github.com ed25519 host key from keyscan does not match the pinned key; refusing" }
[IO.File]::WriteAllText((Join-Path $ApiRoot 'known_hosts'), "$githubKey`n", $utf8)
$fwd = { param($x) $x -replace '\\', '/' }
$sshCfg = @"
Host $ApiSshAlias
  HostName github.com
  User git
  IdentityFile "$(& $fwd $keyPath)"
  IdentitiesOnly yes
  UserKnownHostsFile "$(& $fwd (Join-Path $ApiRoot 'known_hosts'))"
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
  ProxyCommand none
  ProxyJump none
"@
[IO.File]::WriteAllText((Join-Path $ApiRoot 'ssh_config'), ($sshCfg -replace "`r`n", "`n"), $utf8)
Write-Host "ssh config for the elevated side: alias $ApiSshAlias -> github.com with key $keyPath"

& icacls.exe $ApiRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*${userSid}:(OI)(CI)RX" '*S-1-3-4:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'icacls (DACL) failed' }
& icacls.exe "$ApiRoot\*" /reset /T /C /Q | Out-Null
& icacls.exe $ApiRoot /setowner '*S-1-5-32-544' /T /C /Q | Out-Null
& icacls.exe $ApiRoot /setintegritylevel '(OI)(CI)H' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'icacls (integrity label) failed' }
Write-Host "API side home ready: $ApiRoot"

# the user-writable request drop
if (-not (Test-Path -LiteralPath $QueueDir)) { New-Item -ItemType Directory -Path $QueueDir | Out-Null }

$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# ---- API task: highest, no trigger, fixed action ------------------------------------------------
$apiArg = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ApiRoot\bin\api-runner.ps1`" -Root `"$ApiRoot`" -QueueDir `"$QueueDir`""
$apiAction = New-ScheduledTaskAction -Execute "$PSHOME\powershell.exe" -Argument $apiArg -WorkingDirectory "$ApiRoot\bin"
$apiPrincipal = New-ScheduledTaskPrincipal -UserId $User -LogonType $ApiLogonType -RunLevel Highest
$apiTask = New-ScheduledTask -Action $apiAction -Settings $settings -Principal $apiPrincipal `
    -Description 'Innovation loop API deploy/rollback (elevated). Started by api-request.ps1 via a request file; validates it in api-runner.ps1.'
$cred = $null
if ($ApiLogonType -eq 'Password' -or -not $ApiOnly) {
    $cred = Get-Credential -UserName $User -Message "Password for $User (stored by Task Scheduler so the loop can run while logged off)"
}
if ($ApiLogonType -eq 'Password') {
    Register-ScheduledTask -TaskName $ApiTaskName -InputObject $apiTask -User $User -Password $cred.GetNetworkCredential().Password -Force | Out-Null
} else {
    Register-ScheduledTask -TaskName $ApiTaskName -InputObject $apiTask -Force | Out-Null
}
# let the non-elevated user start (and read) this one task
$svc = New-Object -ComObject Schedule.Service; $svc.Connect()
$t = $svc.GetFolder('\').GetTask($ApiTaskName)
$sddl = $t.GetSecurityDescriptor(4)
$ace = "(A;;GRGX;;;$userSid)"
if ($sddl -notmatch [regex]::Escape($ace)) { $t.SetSecurityDescriptor($sddl + $ace, 0) }
if ($EnableApiTask) { Enable-ScheduledTask -TaskName $ApiTaskName | Out-Null } else { Disable-ScheduledTask -TaskName $ApiTaskName | Out-Null }
Write-Host "Registered $ApiTaskName ($(if ($EnableApiTask) { 'ENABLED' } else { 'DISABLED' }), no trigger, highest)"

if ($ApiOnly) { return }

# ---- main loop task: daily, LIMITED --------------------------------------------------------------
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "not found: $ScriptPath" }
$argument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" $ExtraArgs".Trim()
$action = New-ScheduledTaskAction -Execute "$PSHOME\powershell.exe" -Argument $argument -WorkingDirectory (Split-Path $ScriptPath)
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$loopSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Password -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $loopSettings -Principal $principal `
    -Description 'Portfolio innovation loop (claude -p, LOOP.md), not elevated. See D:\projects\solid-website\innovation\README.md'
Register-ScheduledTask -TaskName $LoopTaskName -InputObject $task -User $User -Password $cred.GetNetworkCredential().Password -Force | Out-Null
Disable-ScheduledTask -TaskName $LoopTaskName | Out-Null
Get-ScheduledTask -TaskName $LoopTaskName, $ApiTaskName | Format-Table TaskName, State
Write-Host "Created $LoopTaskName (DISABLED, limited) and $ApiTaskName (DISABLED, highest, no trigger)."
Write-Host "Enable both when ready: Enable-ScheduledTask -TaskName $LoopTaskName; Enable-ScheduledTask -TaskName $ApiTaskName"
