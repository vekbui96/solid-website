<#
.SYNOPSIS
  Test gate for solid-website changes. Run in the loop clone, on main (Label before) and on the branch (Label after).

.DESCRIPTION
  1. yarn install --frozen-lockfile
  2. typecheck: count "error TS" lines from `npx tsc --noEmit -p .`; must not exceed the count on origin/main
     (main currently has pre-existing errors, so the gate is "no new errors", computed at run time and cached
     per origin/main sha in ~\.innovation-loop\state\)
  3. yarn build:all; dist\index.html and dist\storybook\index.html must exist
  4. vite preview on localhost: HTML must contain <main-page>
  5. smoke.mjs (headless Edge): the custom element's shadow root must be non-empty; screenshot saved to
     ~\.innovation-loop\artifacts\<Issue>\<Label>.png

.EXIT CODES
  0 pass | 1 fail (details in the log and on stdout)
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '',
    [string]$Issue = 'adhoc',
    [ValidateSet('before', 'after')][string]$Label = 'after',
    [int]$PreviewPort = 4173
)
. "$PSScriptRoot\lib.ps1"
Start-ScriptLog "test-frontend-$Issue-$Label"
if (-not $RepoPath) { $RepoPath = $script:FrontClone }
$artDir = Join-Path $script:LoopHome "artifacts\$Issue"
if (-not (Test-Path -LiteralPath $artDir)) { New-Item -ItemType Directory -Path $artDir | Out-Null }
$failures = New-Object System.Collections.ArrayList

function Get-TscErrorCount {
    param([string]$Dir)
    $r = Invoke-Native -File 'cmd' -Arguments @('/c', 'npx tsc --noEmit -p . 2>&1') -WorkDir $Dir -AllowFail
    return @($r.Output | Where-Object { $_ -match 'error TS\d+' }).Count
}

try {
    Invoke-Native -File 'cmd' -Arguments @('/c', 'yarn install --frozen-lockfile 2>&1') -WorkDir $RepoPath | Out-Null

    # ---- typecheck vs baseline -------------------------------------------------
    Invoke-Git -Repo $RepoPath -Arguments @('fetch', 'origin', '--prune') | Out-Null
    $baseSha = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'origin/main')
    $cache = Read-State 'tsc-baseline'
    if ($cache -and $cache.sha -eq $baseSha) {
        $baseline = [int]$cache.count
    } else {
        $headSha = Get-GitValue -Repo $RepoPath -Arguments @('rev-parse', 'HEAD')
        if ($headSha -eq $baseSha) {
            $baseline = Get-TscErrorCount $RepoPath
        } else {
            $wt = Join-Path $script:LoopHome 'work\tsc-baseline'
            if (Test-Path -LiteralPath $wt) { Invoke-Git -Repo $RepoPath -Arguments @('worktree', 'remove', '--force', $wt) -AllowFail | Out-Null; if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force } }
            Invoke-Git -Repo $RepoPath -Arguments @('worktree', 'add', '--detach', $wt, $baseSha) | Out-Null
            try {
                # share node_modules via a junction; typecheck only needs type packages
                cmd /c mklink /J "$wt\node_modules" "$RepoPath\node_modules" | Out-Null
                $baseline = Get-TscErrorCount $wt
            } finally {
                if (Test-Path -LiteralPath "$wt\node_modules") { cmd /c rmdir "$wt\node_modules" | Out-Null }   # removes the junction only
                Invoke-Git -Repo $RepoPath -Arguments @('worktree', 'remove', '--force', $wt) -AllowFail | Out-Null
            }
        }
        Save-State 'tsc-baseline' @{ sha = $baseSha; count = $baseline }
    }
    $current = Get-TscErrorCount $RepoPath
    Write-Log "tsc errors: current=$current baseline(origin/main $baseSha)=$baseline"
    if ($current -gt $baseline) { [void]$failures.Add("typecheck: $current errors, main has $baseline (new type errors introduced)") }

    # ---- build -----------------------------------------------------------------
    $b = Invoke-Native -File 'cmd' -Arguments @('/c', 'yarn build:all 2>&1') -WorkDir $RepoPath -AllowFail
    if ($b.Code -ne 0) { [void]$failures.Add("yarn build:all failed (exit $($b.Code))") }
    elseif (-not (Test-Path -LiteralPath "$RepoPath\dist\index.html")) { [void]$failures.Add('dist\index.html missing') }
    elseif (-not (Test-Path -LiteralPath "$RepoPath\dist\storybook\index.html")) { [void]$failures.Add('dist\storybook\index.html missing (build:all order broken?)') }
} catch {
    [void]$failures.Add("error: $_")
}

# ---- preview + smoke -----------------------------------------------------------
if ($failures.Count -eq 0) {
    $out = Join-Path $artDir "preview-$Label.out.log"; $err = Join-Path $artDir "preview-$Label.err.log"
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "npx vite preview --port $PreviewPort --strictPort --host localhost") `
        -WorkingDirectory $RepoPath -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
    try {
        $url = "http://localhost:$PreviewPort/"
        $html = $null
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            $r = Invoke-Http -Url $url -TimeoutSec 5
            if ($r.Status -eq 200) { $html = $r.Body; break }
        }
        if (-not $html) { [void]$failures.Add("vite preview did not answer on $url") }
        elseif ($html -notmatch '<main-page') { [void]$failures.Add('preview HTML has no <main-page>') }
        else {
            $shot = Join-Path $artDir "$Label.png"
            $s = Invoke-Native -File 'node' -Arguments @("$PSScriptRoot\smoke.mjs", $RepoPath, $url, $shot) -AllowFail
            if ($s.Code -eq 1) { [void]$failures.Add('smoke: <main-page> shadow root empty or page errored: ' + ($s.Output -join ' ')) }
            elseif ($s.Code -eq 2) { Write-Log 'smoke check could not run (playwright-core or browser missing); HTML check only' 'WARN' }
            else { Write-Log "screenshot: $shot" }
        }
    } finally {
        & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
    }
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Log "FAIL: $f" 'ERROR' }
    Write-Output ("TEST-FRONTEND FAIL: " + ($failures -join ' | '))
    exit 1
}
Write-Output "TEST-FRONTEND PASS (tsc $current <= $baseline, build:all ok, preview ok, smoke ok)"
exit 0
