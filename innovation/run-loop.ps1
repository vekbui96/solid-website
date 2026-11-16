<#
.SYNOPSIS
  Entry point for the innovation loop's daily scheduled task. Runs one headless `claude -p` session that
  follows LOOP.md.

.DESCRIPTION
  - single-instance lock with stale-lock handling (~\.innovation-loop\lock\run.lock)
  - all state outside any repo: ~\.innovation-loop\{logs,clones,work,artifacts,state,api-backups,api-staging,lock}
  - refreshes the loop's own clones of both repos (never touches D:\projects\*, which hold Ve's work)
  - puts gh on PATH; strips secret-looking env vars (RESEND_API_KEY etc.) from the session
  - generates the permission settings (allowlist + guard hook) and runs claude with them
  - logs the full stream-json transcript; exits nonzero on failure

  The scripts and LOOP.md are read from THIS directory ($PSScriptRoot), which should be Ve's checkout
  (D:\projects\solid-website\innovation). The loop's guard hook forbids the session from editing them,
  so a run can never rewrite its own instructions; Ve updates them with git pull.

  DROPPING RIGHTS. The task is registered RunLevel Limited, but Windows gives a non-interactive (S4U or
  Password) logon of an admin account no UAC split token, so the task actually starts this script with a full
  admin token (TokenElevation=1, TokenElevationType=1). This script therefore drops its own rights first: the
  outer invocation does only one privileged thing (makes the loop's clones owned by the user, so git accepts
  them under the reduced token), then re-runs itself with -ReducedInner under a reduced token (reduced-token.ps1:
  UAC-style filtered copy of its own token, Administrators deny-only, no admin privileges, Medium integrity) and
  waits for it. Everything else (lock, clone refresh, preflight, claude and all its children) runs reduced. It
  fails closed: if the rights cannot be dropped, or the inner runner or claude still reports an elevated token,
  the run aborts. There is no override switch.

.PARAMETER ProposeOnly
  Phase B only (observe + propose). Nothing is built, merged or deployed. Use for the first supervised run.
.PARAMETER DryRun
  Do everything up to the claude call (drop rights, lock, dirs, clones, settings, prompt), print the command,
  then stop.
.PARAMETER MaxBuilds
  Most approved issues Phase A may build in one run (default 2, range 1-5). They are built strictly one after
  another, each through the full plan/build/test/PR/merge/deploy/verify cycle. Another one is started only after
  the previous one ended loop:deployed (never after a failure or rollback) and before the cutoff below.
.PARAMETER NextBuildCutoffPercent
  Phase A starts another build only while less than this share of -TimeoutMinutes has passed (default 50).
  Why 50: a worst-case front-end cycle (two test-frontend runs at their 10-minute tool limit, a deploy that
  waits out the Pages-build and served-bytes checks and then rolls back) is about an hour, and Phase B needs
  ~15 minutes after it. With the default 180-minute timeout, 50% leaves 90 minutes, so a build started just
  before the cutoff still finishes, rollback included, before claude is killed (killing it mid-deploy is the
  thing to avoid). Real runs so far took ~7 minutes per build, so the cutoff only bites when a run is already
  unusually slow.
.PARAMETER ReducedInner
  Internal: set by the outer invocation when it re-runs this script under the reduced token. Do not pass it.
#>
[CmdletBinding()]
param(
    [switch]$ProposeOnly,
    [switch]$DryRun,
    [int]$MaxTurns = 250,
    [int]$TimeoutMinutes = 180,
    [string]$Model = '',
    [string]$ClaudeExe = 'C:\Users\Ve Bui\.local\bin\claude.exe',
    [ValidateRange(1, 5)][int]$MaxBuilds = 2,
    [ValidateRange(10, 90)][int]$NextBuildCutoffPercent = 50,
    [switch]$ReducedInner,
    [string]$RunId = ''
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\reduced-token.ps1"
. "$PSScriptRoot\reporting.ps1"   # run data + progress comments (functions only; used after claude exits)
$ScriptsDir = (Resolve-Path $PSScriptRoot).Path
if (-not $RunId) { $RunId = Get-Date -Format 'yyyyMMdd-HHmmss' }
Initialize-LoopDirs
$script:LogFile = Join-Path $script:LoopHome "logs\run-$RunId.log"
$mode = 'FULL'; if ($ProposeOnly) { $mode = 'PROPOSE_ONLY' }

# ---- outer: drop rights, then re-run reduced ----------------------------------------------
if (-not $ReducedInner) {
    Write-Log "innovation loop run $RunId mode=$mode dryRun=$DryRun scripts=$ScriptsDir"
    $outerExit = 1
    try {
        $runner = Get-TokenState
        if ($runner.Elevation -ne 0) {
            Write-Log "runner token: $runner. Elevated, as expected for a scheduled run: this logon gets no UAC split token, so the task's RunLevel does not apply. Dropping rights before doing anything else."
            # git refuses a repo whose owner is neither the current user nor (via an ENABLED membership) the
            # Administrators group. Clones made by earlier elevated runs are owned by Administrators, which the
            # reduced token holds deny-only, so hand the clone roots and .git dirs to the user. Only ownership
            # changes; nothing in the repos is executed or read here.
            $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            foreach ($cl in @($script:FrontClone, $script:ApiClone)) {
                foreach ($p in @($cl, (Join-Path $cl '.git'))) {
                    if ((Test-Path -LiteralPath $p) -and ((Get-Acl -LiteralPath $p).GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $me)) {
                        & icacls.exe $p /setowner "*$me" /C /Q | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw "could not make the user the owner of $p" }
                        Write-Log "made the user the owner of $p"
                    }
                }
            }
        } else {
            Write-Log "runner token: $runner (not elevated); running the inner runner under the reduced token anyway"
        }
        $fwd = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptsDir\run-loop.ps1`"",
            '-ReducedInner', '-RunId', $RunId, '-MaxTurns', "$MaxTurns", '-TimeoutMinutes', "$TimeoutMinutes", '-ClaudeExe', "`"$ClaudeExe`"",
            '-MaxBuilds', "$MaxBuilds", '-NextBuildCutoffPercent', "$NextBuildCutoffPercent")
        if ($ProposeOnly) { $fwd += '-ProposeOnly' }
        if ($DryRun) { $fwd += '-DryRun' }
        if ($Model) { $fwd += @('-Model', "`"$Model`"") }
        $innerOut = Join-Path $script:LoopHome "logs\run-$RunId.inner.out.log"
        $innerErr = Join-Path $script:LoopHome "logs\run-$RunId.inner.err.log"
        # throws (fail closed) if the token cannot be reduced or the started process's token is not reduced
        $inner = Start-ReducedProcess -FilePath "$PSHOME\powershell.exe" -ArgumentString ($fwd -join ' ') -WorkingDirectory $ScriptsDir `
            -StdoutPath $innerOut -StderrPath $innerErr
        try {
            Write-Log "reduced inner runner pid $($inner.Id); its token: $($inner.Token)"
            $limit = ($TimeoutMinutes + 45) * 60 * 1000
            if (-not $inner.WaitForExit($limit)) {
                Write-Log 'TIMEOUT: inner runner did not finish; killing its process tree' 'ERROR'
                & taskkill.exe /PID $inner.Id /T /F 2>&1 | Out-Null
                $inner.Kill()
                throw 'inner runner timed out'
            }
            $outerExit = $inner.ExitCode
        } finally { $inner.Dispose() }
        $errText = ''
        if (Test-Path -LiteralPath $innerErr) { $errText = ([IO.File]::ReadAllText($innerErr)).Trim() }
        if ($errText) { Write-Log "inner runner stderr: $errText" 'WARN' }
    } catch {
        Write-Log "could not run the loop with dropped rights (not falling back to the elevated token): $_" 'ERROR'
        $outerExit = 1
    }
    Write-Log "outer exit $outerExit"
    exit $outerExit
}

# ---- inner: everything below runs under the reduced token -----------------------------------
$self = Get-TokenState
Write-Log "inner runner pid $PID token: $self"
if (-not $self.IsReduced -or (Test-IsElevated)) {
    Write-Log 'inner runner still has an elevated token; refusing to run (fail closed)' 'ERROR'
    exit 1
}

# ---- lock -------------------------------------------------------------------------
$lockPath = Join-Path $script:LoopHome 'lock\run.lock'
$staleAfter = [TimeSpan]::FromMinutes($TimeoutMinutes + 30)
function Get-Lock {
    try {
        $fs = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = [Text.Encoding]::UTF8.GetBytes(("{0}`n{1}`n{2}" -f $PID, [DateTime]::UtcNow.ToString('o'), $RunId))
        $fs.Write($bytes, 0, $bytes.Length); $fs.Close()
        return $true
    } catch [IO.IOException] { return $false }
}
if (-not (Get-Lock)) {
    $lines = @(Get-Content -LiteralPath $lockPath -ErrorAction SilentlyContinue)
    $lockPid = 0; $lockTime = [DateTime]::MinValue
    if ($lines.Count -ge 2) { [void][int]::TryParse($lines[0], [ref]$lockPid); [void][DateTime]::TryParse($lines[1], [ref]$lockTime) }
    $alive = $false
    if ($lockPid -gt 0) { $p = Get-Process -Id $lockPid -ErrorAction SilentlyContinue; $alive = ($p -and $p.ProcessName -match 'powershell') }
    $age = [DateTime]::UtcNow - $lockTime.ToUniversalTime()
    if ($alive -and $age -lt $staleAfter) {
        Write-Log "another run (pid $lockPid, started $lockTime) holds the lock; exiting" 'WARN'
        exit 0
    }
    Write-Log "removing stale lock (pid $lockPid alive=$alive age=$age)" 'WARN'
    Remove-Item -LiteralPath $lockPath -Force
    if (-not (Get-Lock)) { Write-Log 'could not take the lock after clearing it' 'ERROR'; exit 1 }
}

$exitCode = 1
$outPath = $null
try {
    # ---- environment ----------------------------------------------------------------
    Add-GhToPath
    $keep = '^(ANTHROPIC_|CLAUDE_CODE_)'
    foreach ($v in @(Get-ChildItem env: | Where-Object { $_.Name -match '(RESEND|SECRET|PASSWORD|PASSWD|TOKEN|API_KEY|APIKEY|PRIVATE_KEY|MAIL_)' -and $_.Name -notmatch $keep })) {
        Remove-Item -LiteralPath "env:$($v.Name)"
        Write-Log "unset env var $($v.Name) for this run"
    }
    Remove-Item env:RESEND_API_KEY -ErrorAction SilentlyContinue
    $env:INNOVATION_LOOP_HOME = $script:LoopHome
    $env:INNOVATION_LOOP_SCRIPTS = $ScriptsDir
    $env:INNOVATION_LOOP_RUN_ID = $RunId
    $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    if (Test-Path -LiteralPath $edge) { $env:CHROME_PATH = $edge }   # for the optional Lighthouse look in Phase B

    # ---- preflight --------------------------------------------------------------------
    foreach ($t in @($ClaudeExe, $script:GhExe)) { if (-not (Test-Path -LiteralPath $t)) { throw "missing $t" } }
    if ($ScriptsDir -match '\s') { throw "scripts dir '$ScriptsDir' contains whitespace; the permission rules need a path without spaces" }
    foreach ($c in 'git', 'node', 'yarn') { if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "$c not on PATH" } }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $script:GhExe auth status *> $null; $ghOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prev
    if (-not $ghOk) { throw 'gh is not authenticated' }
    # This runner is NOT elevated (the outer invocation dropped rights; checked above). API deploys go
    # through the separate elevated innovation-loop-api task via api-request.ps1; check it is there.
    $apiTask = 'missing'
    $q = Invoke-Native -File "$env:SystemRoot\System32\schtasks.exe" -Arguments @('/query', '/tn', 'innovation-loop-api', '/fo', 'csv', '/nh') -AllowFail -Quiet
    if ($q.Code -eq 0) {
        $line = @($q.Output | Where-Object { $_ -match 'innovation-loop-api' }) | Select-Object -First 1
        if ($line -match '"Disabled"') { $apiTask = 'disabled' } else { $apiTask = 'registered' }
    }
    if ($apiTask -eq 'registered' -and -not $ProposeOnly -and -not $DryRun) {
        # prove the non-elevated -> elevated round trip works before Phase A relies on it (validation only)
        $nr = Invoke-Native -File "$PSHOME\powershell.exe" -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', "$ScriptsDir\api-request.ps1", '-Mode', 'noop', '-TimeoutMinutes', '3') -AllowFail -Quiet
        if ($nr.Code -eq 0) { $apiTask = 'ready' } else { $apiTask = 'unreachable'; Write-Log ("api noop round trip failed (exit {0}): {1}" -f $nr.Code, (($nr.Output | Select-Object -Last 2) -join ' ')) 'WARN' }
    }
    Write-Log "api task: $apiTask"
    if ($apiTask -ne 'ready' -and -not $ProposeOnly) { Write-Log 'innovation-loop-api task not ready: Phase A will skip area:backend and area:both issues' 'WARN' }

    # ---- loop clones (never Ve's checkouts) -------------------------------------------
    $clones = @(
        @{ Path = $script:FrontClone; Url = $script:FrontRepoUrl },
        @{ Path = $script:ApiClone;   Url = $script:ApiRepoUrl }
    )
    foreach ($cl in $clones) {
        if (-not (Test-Path -LiteralPath (Join-Path $cl.Path '.git'))) {
            Invoke-Native -File 'git' -Arguments @('clone', $cl.Url, $cl.Path) | Out-Null
        }
        Invoke-Git -Repo $cl.Path -Arguments @('fetch', 'origin', '--prune') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('checkout', '-f', '-B', 'main', 'origin/main') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('reset', '--hard', 'origin/main') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('clean', '-fdx', '-e', 'node_modules', '-e', 'target', '-e', '.cache') | Out-Null
        Invoke-Git -Repo $cl.Path -Arguments @('worktree', 'prune') | Out-Null
    }

    # ---- permission settings ----------------------------------------------------------
    # dontAsk: anything not allowlisted is denied (nobody is there to answer a prompt).
    # The guard hook (guard.mjs) then enforces the repo/secret/never-touch rules on every call.
    $readOnly = 'Get-ChildItem','Get-Content','Get-Item','Test-Path','Select-String','Get-Location','Set-Location','Push-Location','Pop-Location',
        'Get-Date','Start-Sleep','ConvertFrom-Json','ConvertTo-Json','Select-Object','Where-Object','ForEach-Object','Sort-Object',
        'Measure-Object','Group-Object','Format-List','Format-Table','Out-String','Write-Output','Write-Host','Join-Path','Split-Path',
        'Resolve-Path','Get-Service','Invoke-WebRequest','Invoke-RestMethod','New-Item','Remove-Item','cd','dir','ls','cat','echo','type'
    $allow = @('Read', 'Glob', 'Grep', 'Edit', 'Write', 'TodoWrite',
        'WebFetch(domain:vekbui96.github.io)', 'WebFetch(domain:server-pc.tail0e4194.ts.net)', 'WebFetch(domain:solid-website-api.onrender.com)',
        'PowerShell(git *)', 'PowerShell(gh *)',
        'PowerShell(npx --yes lighthouse@12 *)',
        # install/typecheck/build/maven all go through test-frontend.ps1 / test-api.ps1, so the session needs
        # no yarn/cmd/mvnw rules of its own. The guard also checks every .ps1 path in a command is inside
        # ScriptsDir and is not run-loop/install-task/lib.
        'PowerShell(Start-Sleep)')
    # Exactly these scripts, called by bare full path (no `&`, no quotes: Claude Code does not match
    # allow rules against the call operator, so the scripts dir must not contain spaces).
    foreach ($n in 'check-approval', 'test-frontend', 'test-api', 'deploy-frontend', 'rollback-frontend', 'api-request', 'progress') {
        $allow += "PowerShell($ScriptsDir\$n.ps1)"; $allow += "PowerShell($ScriptsDir\$n.ps1 *)"
    }
    foreach ($r in $readOnly) { $allow += "PowerShell($r)"; $allow += "PowerShell($r *)" }
    $deny = @('Bash', 'Agent', 'Task', 'NotebookEdit', 'WebSearch', 'PowerShell(yarn *)', 'PowerShell(cmd *)', 'PowerShell(powershell *)',
        'PowerShell(npm *)', 'PowerShell(git push --force*)', 'PowerShell(git push -f*)')
    $settings = [ordered]@{
        permissions = [ordered]@{ defaultMode = 'dontAsk'; allow = $allow; deny = $deny }
        hooks = @{ PreToolUse = @(@{ matcher = '*'; hooks = @(@{ type = 'command'; command = "node `"$ScriptsDir\guard.mjs`""; timeout = 30 }) }) }
    }
    $settingsPath = Join-Path $script:LoopHome 'state\claude-settings.json'
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), $utf8)

    # ---- prompt -------------------------------------------------------------------------
    $loopMd = [IO.File]::ReadAllText((Join-Path $ScriptsDir 'LOOP.md'))
    # FOCUS.md is Ve's steering file for Phase B, read from the pinned scripts dir like LOOP.md (the guard blocks
    # the session from writing anything under innovation/). It counts as empty when nothing but whitespace, HTML
    # comments and markdown headings is left; then the header says there is none and the session behaves as before.
    $focusPath = Join-Path $ScriptsDir 'FOCUS.md'
    $focusState = 'none'
    if (Test-Path -LiteralPath $focusPath) {
        $ft = [IO.File]::ReadAllText($focusPath)
        $ft = [regex]::Replace($ft, '(?s)<!--.*?-->', '')
        $ft = [regex]::Replace($ft, '(?m)^[ \t]*#.*$', '')
        if ($ft.Trim()) { $focusState = 'present' }
    }
    $focusNote = 'none (propose from your own judgment; section 5)'
    if ($focusState -eq 'present') { $focusNote = "$focusPath   (Ve's steering file: read it first in Phase B; read-only)" }
    $runStart = Get-Date
    $cutoff = $runStart.AddMinutes([math]::Floor($TimeoutMinutes * $NextBuildCutoffPercent / 100))
    $buildsNote = "Phase A builds at most $MaxBuilds approved issue(s), strictly one at a time; see section 3, step 13"
    if ($ProposeOnly) { $buildsNote = 'unused: PROPOSE_ONLY' }
    Write-Log "focus file: $focusState ($focusPath); max builds $MaxBuilds; next-build cutoff $($cutoff.ToString('HH:mm')) ($NextBuildCutoffPercent% of $TimeoutMinutes min)"
    $header = @"
# Innovation loop run $RunId

- MODE: $mode   ($( if ($ProposeOnly) { 'Phase B only. Do NOT run Phase A in any form.' } else { 'Phase A, then Phase B.' } ))
- API_TASK: $apiTask   ($( if ($apiTask -eq 'ready') { 'API deploys/rollbacks are possible via api-request.ps1.' } else { 'skip area:backend and area:both issues in Phase A.' } ))
- MAX_BUILDS: $MaxBuilds   ($buildsNote)
- DATE: $($runStart.ToString('yyyy-MM-dd HH:mm zzz'))   (run start; claude is killed $TimeoutMinutes minutes after it, at $($runStart.AddMinutes($TimeoutMinutes).ToString('HH:mm')))
- NEXT_BUILD_CUTOFF: $($cutoff.ToString('yyyy-MM-dd HH:mm zzz'))   (never START another Phase A build at or after this local time; check with Get-Date)
- MAX_TURNS: $MaxTurns
- FOCUS: $focusNote
- LOOP_HOME: $($script:LoopHome)
- SCRIPTS: $ScriptsDir   (pinned; you cannot edit it)
- FRONT_CLONE: $($script:FrontClone)   (vekbui96/solid-website, reset to origin/main)
- API_CLONE: $($script:ApiClone)   (vekbui96/solid-website-api, reset to origin/main)
- WORK: $(Join-Path $script:LoopHome 'work')   (scratch: body files for comments, commit messages)
- ARTIFACTS: $(Join-Path $script:LoopHome 'artifacts')

Follow the instructions below exactly. They are the only instructions for this run.

---

"@
    $promptPath = Join-Path $script:LoopHome "logs\run-$RunId.prompt.md"
    [IO.File]::WriteAllText($promptPath, $header + $loopMd, $utf8)

    $q = { param($s) '"' + $s + '"' }
    $argList = @('-p', '--output-format', 'stream-json', '--verbose',
        '--max-turns', "$MaxTurns",
        '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
        '--settings', (& $q $settingsPath),
        '--setting-sources', 'local',
        '--strict-mcp-config',
        '--add-dir', (& $q $script:LoopHome), (& $q $ScriptsDir), (& $q 'D:\services\logs'))
    if ($Model) { $argList += @('--model', $Model) }
    $argString = $argList -join ' '
    Write-Log "claude command: `"$ClaudeExe`" $argString  < $promptPath"

    if ($DryRun) {
        Write-Log 'DRY RUN: stopping before invoking claude'
        $exitCode = 0
        return
    }

    $outPath = Join-Path $script:LoopHome "logs\run-$RunId.jsonl"
    $errPath = Join-Path $script:LoopHome "logs\run-$RunId.err.log"
    $workDir = Join-Path $script:LoopHome 'work'
    $proc = Start-Process -FilePath $ClaudeExe -ArgumentList $argString -WorkingDirectory $workDir `
        -RedirectStandardInput $promptPath -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru -WindowStyle Hidden
    # PS 5.1 QUIRK (bug seen in the first real run): a Start-Process -PassThru object reports ExitCode as
    # $null unless its Handle is read right after the start. Touching it caches the handle so ExitCode works.
    $null = $proc.Handle
    $claudeToken = $null
    try { $claudeToken = [InnovationLoop.ReducedToken]::OfProcess($proc.Handle) } catch { }
    if ($claudeToken -and -not $claudeToken.IsReduced) {
        & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
        throw "claude started with an elevated token ($claudeToken); killed it (fail closed)"
    }
    Write-Log "claude pid $($proc.Id) token: $(if ($claudeToken) { $claudeToken } else { 'unreadable (exited already?)' }); timeout $TimeoutMinutes min"
    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        Write-Log 'TIMEOUT: killing claude process tree' 'ERROR'
        & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
        throw "claude exceeded $TimeoutMinutes minutes"
    }
    $proc.WaitForExit()
    $claudeExit = $proc.ExitCode
    if ($null -eq $claudeExit) {
        # should not happen now that the handle is cached; if it does, judge the run by the transcript alone
        Write-Log 'claude exit code unavailable (null) even with the cached handle; using the result message only' 'WARN'
    } else {
        Write-Log "claude exit code $claudeExit"
    }

    # ---- result -------------------------------------------------------------------------
    $result = $null
    foreach ($line in [IO.File]::ReadAllLines($outPath)) {
        if ($line -match '"type"\s*:\s*"result"') { try { $result = $line | ConvertFrom-Json } catch { } }
    }
    $summaryPath = Join-Path $script:LoopHome "logs\run-$RunId.summary.txt"
    if ($result) {
        $text = "$($result.result)"
        [IO.File]::WriteAllText($summaryPath, $text, $utf8)
        Write-Log ("result: subtype={0} is_error={1} turns={2} cost={3}" -f $result.subtype, $result.is_error, $result.num_turns, $result.total_cost_usd)
        $status = [regex]::Match($text, 'LOOP-RESULT:\s*([A-Z\-]+)').Groups[1].Value
        Write-Log "LOOP-RESULT: $status"
        $exitOk = ($claudeExit -eq 0) -or ($null -eq $claudeExit)   # null only if the handle trick failed (logged above)
        if ($exitOk -and -not $result.is_error -and $status -in @('OK', 'NOTHING-TO-DO')) { $exitCode = 0 }
        else { $exitCode = 1 }
    } else {
        Write-Log 'no result message in the transcript' 'ERROR'
        $exitCode = 1
    }
} catch {
    Write-Log "run failed: $_" 'ERROR'
    $exitCode = 1
} finally {
    # ---- reporting (after claude exited; never changes the exit code) ---------------------------
    # Still the reduced inner runner: same gh, same rights as above. The session gets no new permission: it
    # only printed the LOOP-ISSUE-START/END marker lines (LOOP.md section 3); the runner does the posting.
    if ($outPath -and (Test-Path -LiteralPath $outPath)) {
        try {
            $started = [DateTime]::ParseExact($RunId, 'yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
            $trigger = Get-LoopRunTrigger -TaskName 'InnovationLoop' -RunStart $started
            $ended = @(Complete-LoopProgress -LoopHome $script:LoopHome -RunId $RunId -GhExe $script:GhExe)
            if ($ended.Count -gt 0) { Write-Log "progress comments left mid-build, marked as ended: #$($ended -join ', #')" 'WARN' }
            $posted = Publish-LoopRunData -TranscriptPath $outPath -Repo $script:FrontRepo -GhExe $script:GhExe -RunId $RunId -Mode $mode -Trigger $trigger
            Write-Log "run data: $posted comment(s) posted"
        } catch { Write-Log "run data / progress reporting skipped: $_" 'WARN' }
    }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $script:LoopHome 'logs') -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-60) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "exit $exitCode"
}
exit $exitCode
