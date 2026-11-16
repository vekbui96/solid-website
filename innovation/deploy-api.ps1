<#
.SYNOPSIS
  ELEVATED SIDE. Deploy solid-website-api to the NSSM service on server-pc, verify, auto-rollback on failure.

.DESCRIPTION
  Normally started only by api-runner.ps1 (the elevated `innovation-loop-api` task) after it validated a
  request from the non-elevated loop. Ve can also run it by hand from an elevated shell.

  1. require elevation (Stop-/Start-Service on a LocalSystem service)
  2. git archive -MergeSha (must be on origin/main; default origin/main) of the API clone in THIS side's
     home (for api-runner: C:\ProgramData\innovation-loop-api, which the non-elevated loop cannot write)
     into a fresh staging dir outside D:\services
  3. build there: mvnw -B -DskipTests clean package   (tests already ran in the loop's Test phase).
     $env:INNOVATION_LOOP_MVN_EXTRA (set by api-runner) points Maven at settings and a local repository
     inside its own home, so nothing in the user-writable ~\.m2 feeds an elevated build.
  4. back up the live jar to <home>\api-backups\ (timestamped, newest 5 kept)
  5. Stop-Service -> copy the new jar over the live jar path -> Start-Service
  6. verify (health local + Funnel, actuator, 400 validation, honeypot-only contact POST, CORS preflight)
  7. on success: mirror the staged source into D:\services\solid-website-api (excludes .env and target\)
     on failure: rollback-api.ps1 with the backup jar.
  It never pushes to git. Reverting the merge on main (Render follows main) is the requesting side's job:
  exit 2 means "jar rolled back, main NOT reverted yet".

  Never touches .env, NSSM configuration, or application config. Never sends a real email.

.EXIT CODES
  0 deployed and verified | 1 precondition failed, nothing changed | 2 verify failed, jar rolled back
  3 verify failed AND rollback failed (human needed) | 4 build failed, nothing changed
#>
[CmdletBinding()]
param(
    [string]$MergeSha = '',
    [switch]$NoRollback
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog 'deploy-api'
$liveJar = Join-Path $script:ApiServiceDir $script:ApiJarRel

try {
    if (-not (Test-IsElevated)) { throw 'must run elevated (via the innovation-loop-api task or an elevated shell)' }
    if (-not (Test-Path -LiteralPath (Join-Path $script:ApiClone '.git'))) { throw "no API clone at $($script:ApiClone)" }
    if (-not (Test-Path -LiteralPath $liveJar)) { throw "live jar not found at $liveJar" }
    $null = Get-Service -Name $script:ApiServiceName
    Invoke-Git -Repo $script:ApiClone -Arguments @('fetch', 'origin', '--prune') | Out-Null
    $main = Get-GitValue -Repo $script:ApiClone -Arguments @('rev-parse', 'origin/main')
    $target = $main
    if ($MergeSha) {
        if ($MergeSha -notmatch '^[0-9a-f]{7,40}$') { throw "bad MergeSha '$MergeSha'" }
        $anc = Invoke-Git -Repo $script:ApiClone -Arguments @('merge-base', '--is-ancestor', $MergeSha, 'origin/main') -AllowFail
        if ($anc.Code -ne 0) { throw "MergeSha $MergeSha is not on origin/main" }
        $target = Get-GitValue -Repo $script:ApiClone -Arguments @('rev-parse', "$MergeSha^{commit}")
    }
    # The jar name is hardcoded in the NSSM service; a changed artifactId/version would deploy nothing.
    $pom = (Invoke-Git -Repo $script:ApiClone -Arguments @('show', "${target}:pom.xml")).Output -join "`n"
    if ($pom -notmatch '<artifactId>personal-site-api</artifactId>\s*<version>0\.0\.1-SNAPSHOT</version>') { throw 'pom artifactId/version changed; the service jar path would not match. Refusing.' }
    Write-Log "deploying solid-website-api $target (origin/main=$main)"
} catch {
    Write-Log "precondition failed: $_" 'ERROR'
    exit $script:EXIT_PRECONDITION
}

# ---- build in staging -------------------------------------------------------------
try {
    $staging = Export-ApiSource -Ref $target
    Write-Log "staging dir: $staging"
    $mvnCmd = '.\mvnw.cmd -B -DskipTests clean package'
    if ($env:INNOVATION_LOOP_MVN_EXTRA) { $mvnCmd += ' ' + $env:INNOVATION_LOOP_MVN_EXTRA }
    Invoke-Native -File 'cmd' -Arguments @('/c', "$mvnCmd 2>&1") -WorkDir $staging | Out-Null
    $newJar = Join-Path $staging $script:ApiJarRel
    if (-not (Test-Path -LiteralPath $newJar)) { throw "build produced no $($script:ApiJarRel)" }
    if ((Get-Item -LiteralPath $newJar).Length -lt 1MB) { throw 'built jar is suspiciously small' }
} catch {
    Write-Log "build failed: $_" 'ERROR'
    exit $script:EXIT_BUILD_FAILED
}

# ---- back up, swap, restart ---------------------------------------------------------
$backupDir = Join-Path $script:LoopHome 'api-backups'
$backup = Join-Path $backupDir ("personal-site-api-{0}.jar" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
try {
    Copy-Item -LiteralPath $liveJar -Destination $backup
    if ((Get-Item -LiteralPath $backup).Length -ne (Get-Item -LiteralPath $liveJar).Length) { throw 'backup size mismatch' }
    Get-ChildItem $backupDir -Filter 'personal-site-api-*.jar' | Sort-Object Name -Descending | Select-Object -Skip 5 |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    Save-State 'api-last-deploy' @{ backupJar = $backup; deployedSha = $target; mergeSha = $MergeSha; startedUtc = [DateTime]::UtcNow.ToString('o'); status = 'started' }
    Write-Log "backed up live jar to $backup"
} catch {
    Write-Log "backup failed, nothing changed: $_" 'ERROR'
    exit $script:EXIT_PRECONDITION
}

$swapOk = $true
try {
    Write-Log "stopping service $($script:ApiServiceName)"
    Stop-Service -Name $script:ApiServiceName -Force
    if (-not (Wait-ServiceState -Name $script:ApiServiceName -State 'Stopped' -TimeoutSec 90)) { throw 'service did not stop' }
    Start-Sleep -Seconds 2   # let the JVM release the jar handle
    Copy-Item -LiteralPath $newJar -Destination $liveJar -Force
    Write-Log 'new jar copied; starting service'
    Start-Service -Name $script:ApiServiceName
    if (-not (Wait-ServiceState -Name $script:ApiServiceName -State 'Running' -TimeoutSec 90)) { throw 'service did not start' }
} catch {
    Write-Log "swap/restart failed: $_" 'ERROR'
    $swapOk = $false
}

$verified = $false
if ($swapOk) { $verified = Test-Api -StartupTimeoutSec 120 }

if ($verified) {
    try { Sync-ApiSource -From $staging }
    catch { Write-Log "source mirror failed (the jar is live and verified; only the informational source copy is stale): $_" 'WARN' }
    Save-State 'api-last-deploy' @{ backupJar = $backup; deployedSha = $target; mergeSha = $MergeSha; finishedUtc = [DateTime]::UtcNow.ToString('o'); status = 'deployed' }
    Write-Log "DEPLOYED and verified solid-website-api $target"
    exit $script:EXIT_OK
}

Write-Log 'verification FAILED' 'ERROR'
if ($NoRollback) { Write-Log '-NoRollback given; leaving production as is' 'WARN'; exit $script:EXIT_ROLLBACK_FAILED }
& "$PSHOME\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PSScriptRoot\rollback-api.ps1" -BackupJar $backup
if ($LASTEXITCODE -eq 0) { Write-Log 'rolled back successfully (jar restored; main NOT reverted: the requesting side does that)'; exit $script:EXIT_ROLLED_BACK }
Write-Log "ROLLBACK FAILED (exit $LASTEXITCODE). Production needs a human." 'ERROR'
exit $script:EXIT_ROLLBACK_FAILED
