<#
.SYNOPSIS
  Create (or update) the "InnovationLoop" scheduled task. The task is created DISABLED.

.DESCRIPTION
  Daily at -At (default 13:17 local, deliberately off the hour), runs whether the user is logged on or
  not, with highest privileges, as SERVER-PC\VeBui. Windows asks for VeBui's password once (stored by
  Task Scheduler, needed for "run whether logged on or not" with network access).

  Enable when ready:   Enable-ScheduledTask -TaskName InnovationLoop
  Disable:             Disable-ScheduledTask -TaskName InnovationLoop
  Run once now:        Start-ScheduledTask -TaskName InnovationLoop
  Remove:              Unregister-ScheduledTask -TaskName InnovationLoop -Confirm:$false

  Must be run from an elevated PowerShell. It does not run the loop.
#>
[CmdletBinding()]
param(
    [string]$TaskName = 'InnovationLoop',
    [string]$At = '13:17',
    [string]$User = 'SERVER-PC\VeBui',
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'run-loop.ps1'),
    [string]$ExtraArgs = ''   # e.g. '-ProposeOnly'
)
$ErrorActionPreference = 'Stop'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'run this from an elevated PowerShell'
}
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "not found: $ScriptPath" }

$cred = Get-Credential -UserName $User -Message "Password for $User (stored by Task Scheduler so the loop can run while logged off)"
$argument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" $ExtraArgs".Trim()
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument -WorkingDirectory (Split-Path $ScriptPath)
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Password -RunLevel Highest

$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description 'Portfolio innovation loop (claude -p, LOOP.md). See D:\projects\solid-website\innovation\README.md'
Register-ScheduledTask -TaskName $TaskName -InputObject $task -User $User -Password $cred.GetNetworkCredential().Password -Force | Out-Null
Disable-ScheduledTask -TaskName $TaskName | Out-Null
Get-ScheduledTask -TaskName $TaskName | Format-List TaskName, State
Write-Host "Created $TaskName (DISABLED). Enable with: Enable-ScheduledTask -TaskName $TaskName"
