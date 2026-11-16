<#
.SYNOPSIS
  Test gate for solid-website-api changes: `mvnw -B verify` in the loop's API clone (or -RepoPath).
  No network calls to production, no secrets needed. Exit 0 = pass, 1 = fail.
#>
[CmdletBinding()]
param([string]$RepoPath = '', [string]$Issue = 'adhoc')
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog "test-api-$Issue"
if (-not $RepoPath) { $RepoPath = $script:ApiClone }
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'mvnw.cmd'))) { Write-Output "TEST-API FAIL: no mvnw.cmd in $RepoPath"; exit 1 }
$r = Invoke-Native -File 'cmd' -Arguments @('/c', '.\mvnw.cmd -B verify 2>&1') -WorkDir $RepoPath -AllowFail
$summary = @($r.Output | Where-Object { $_ -match 'Tests run:|BUILD (SUCCESS|FAILURE)|ERROR\]' } | Select-Object -Last 15)
if ($r.Code -eq 0 -and ($r.Output -match 'BUILD SUCCESS')) {
    Write-Output ("TEST-API PASS`n" + ($summary -join "`n"))
    exit 0
}
Write-Output ("TEST-API FAIL (exit $($r.Code))`n" + ($summary -join "`n"))
exit 1
