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
    [string]$ExpectString = '',
    # Instead of -ExpectString for a front-end change that ships no new bytes (live-check.ps1 Get-NoVisibleStringDecision):
    # the branch diff must pass the git rule, and the built dist\index.html must carry the live site's signature.
    [string]$NoVisibleString = ''
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\live-check.ps1"
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
    $isFrontRepo = ($script:FrontendMode -ne 'none') -and ("$(Get-Cfg 'frontend.repo')" -eq $repoCfg.name)
    if ($ExpectString -and $NoVisibleString) { throw 'pass -ExpectString or -NoVisibleString, not both' }
    if ($NoVisibleString -and $isFrontRepo) {
        Invoke-Git -Repo $full -Arguments @('fetch', 'origin', '--prune') -Quiet | Out-Null
        $base = Get-GitValue -Repo $full -Arguments @('merge-base', 'origin/main', 'HEAD')
        $nvs = Get-NoVisibleStringVerdict -Repo $full -From $base -To 'HEAD'
        Write-Log "no-visible-string: allowed=$($nvs.Allowed) ($($nvs.Reason)); reason given: $NoVisibleString"
        if (-not $nvs.Allowed) { throw "-NoVisibleString refused: $($nvs.Reason); use -ExpectString <string only the new build contains>" }
    }
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

# -NoVisibleString: the build output proves it. Vite names assets by content hash, so a build whose index.html (asset
# set + html hash: hooks.ps1 Get-PageSignature) equals the live site's ships exactly what is served now.
if ($failures.Count -eq 0 -and $NoVisibleString -and $isFrontRepo -and ($steps -contains 'build')) {
    try {
        $built = Get-PageSignature ([IO.File]::ReadAllText((Join-Path $full "$(Get-Cfg 'frontend.distDir' 'dist')\index.html")))
        $live = Get-FrontendSignature
        Write-Log "no-visible-string: built signature $built; live $live"
        if (-not $live) { [void]$failures.Add('-NoVisibleString: could not read the live site signature (fail closed)') }
        elseif ($built -ne $live) { [void]$failures.Add("-NoVisibleString: the build differs from what the site serves (built $built, live $live): this change ships new bytes, so use -ExpectString") }
    } catch { [void]$failures.Add("-NoVisibleString: build-output check failed: $_") }
}

if ($failures.Count -gt 0) {
    Write-Output ("TEST-GATE FAIL ($($repoCfg.name): $($steps -join ',')): " + ($failures -join ' | '))
    exit 1
}
Write-Output "TEST-GATE PASS ($($repoCfg.name): $($steps -join ','))"
exit 0
