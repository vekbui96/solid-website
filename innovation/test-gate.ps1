<#
.SYNOPSIS
  Local test gate, run ONLY in one of the loop's clones. Last output line: TEST-GATE PASS|FAIL ...

.DESCRIPTION
  The session cannot run npm/node/cmd/mvn itself; every install, format, check, build and e2e goes through
  here. The steps are defined per project in hooks.ps1 (Invoke-TestStep); -Step all runs
  $script:TestStepsAll from there. Refuses any path outside ~\.innovation-loop-<project>\clones (never
  D:\projects or a live dir). Strips secret-looking env vars first. No secrets are needed or read.
  Steps that can exceed 10 minutes (e2e, big builds) must be started in the BACKGROUND by the session.

.EXIT CODES
  0 pass | 1 fail
#>
[CmdletBinding()]
param(
    [string]$Step = 'all',
    [string]$Repo = '',          # config repos[].name; default: the hub (repos[0])
    [string]$Issue = 'adhoc',
    [string]$UnitFilter = '',
    [string]$ExpectString = ''
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\hooks.ps1"
Start-ScriptLog "test-gate-$Issue-$Step"
$failures = New-Object System.Collections.ArrayList
$null = Clear-SecretEnv

try {
    $repoCfg = Get-RepoCfg $Repo
    $full = (Resolve-Path -LiteralPath (Get-ClonePath $repoCfg.name)).Path.TrimEnd('\')
    $loopRoot = (Join-Path $script:LoopHome 'clones').TrimEnd('\')
    if (-not $full.StartsWith($loopRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "refusing to test outside the loop's clones dir ($loopRoot): $full" }
    if ($Step -ne 'all' -and $script:TestStepsValid -notcontains $Step) { throw "unknown step '$Step' (valid: all, $($script:TestStepsValid -join ', '))" }
} catch {
    Write-Output "TEST-GATE FAIL: $_"
    exit 1
}

$steps = @($Step); if ($Step -eq 'all') { $steps = $script:TestStepsAll }
foreach ($s in $steps) {
    if ($failures.Count -gt 0) { break }
    Write-Log "---- step $s ($($repoCfg.name)) ----"
    try {
        $why = Invoke-TestStep -Step $s -RepoName $repoCfg.name -RepoPath $full -Issue $Issue -ExpectString $ExpectString -UnitFilter $UnitFilter
        if ($why) { [void]$failures.Add($why); Write-Log "FAIL: $why" 'ERROR' }
    } catch { [void]$failures.Add("error in step ${s}: $_"); Write-Log "FAIL: error in step ${s}: $_" 'ERROR' }
}

if ($failures.Count -gt 0) {
    Write-Output ("TEST-GATE FAIL ($($repoCfg.name): $($steps -join ',')): " + ($failures -join ' | '))
    exit 1
}
Write-Output "TEST-GATE PASS ($($repoCfg.name): $($steps -join ','))"
exit 0
