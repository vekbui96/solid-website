<#
.SYNOPSIS
  Entry point for this project's innovation loop daily scheduled task. Runs one headless `claude -p`
  session PER JOB, under a REDUCED token: one for each approved issue it builds (up to MaxBuilds, strictly
  one after another), then one for Phase B proposals, each following its sections of LOOP.md.

.DESCRIPTION
  Shared run setup happens ONCE, here in PowerShell (no tokens):
  - single-instance lock with stale-lock handling (~\.innovation-loop-<project>\lock\run.lock)
  - all state outside any repo: ~\.innovation-loop-<project>\{logs,clones,work,artifacts,state,elevated,scratch,lock}
  - preflight; if the project has a server: the elevated deploy task (installed, admin-only copy matches this
    checkout, selftest round trip). If not, build sessions are told SERVER_DEPLOY=unavailable and build only
    changes that need no server deploy
  - precheck: check-approval.ps1 -List; if nothing is buildable (FULL mode) and no proposal slot is free
    (gate-rules.ps1 Get-ProposalSlots), it writes a NOTHING-TO-DO summary and rundata.json with no session
  - strips secret-looking env vars (and ANTHROPIC_API_KEY, so the run stays on the subscription);
    generates the permission settings per session kind (dontAsk + allowlist + guard hook; a proposal
    session gets check-approval.ps1 only)

  Then one session per job, each with its own prompt (a header naming its one job + only the LOOP.md
  sections it needs), model, turn cap and time limit (innovation\sessions.json, gate-rules.ps1
  Get-SessionConfig; kept out of loop.config.json so a model change never stales the elevated copy):
  - build sessions (FULL): the loop's clones are reset to origin/main before each. The next build starts
    only when the previous one ended loop:deployed (or was skipped by the one-server-deploy rule), fewer than
    MaxBuilds were built and enough time is left (gate-rules.ps1 Get-NextBuildDecision). After each build
    session its issue is finalised here: left loop:in-progress -> loop:failed with a failure marker; and if
    the session merged something whose deploy was neither verified nor rolled back and verified
    (Get-DeployCertainty over the merge / deploy / rollback records) the RUN STOPS there: no further build,
    no proposals, LOOP-RESULT FAILED.
  - one proposal session (FULL and PROPOSE_ONLY), only when a proposal slot is free and enough time is left;
    approved specs' slices go first (check-approval.ps1 -List `slicesToOpen`)
  After the sessions: one combined summary whose last line is the run's LOOP-RESULT (Get-RunResult), and the
  spec checklists (Publish-SpecProgress below: an approved spec whose slices are all done is closed).
  The guard is told each session's kind through <PREFIX>_MODE = BUILD | PROPOSE.
  Every claude child is started through LowRights.cs (CreateRestrictedToken LUA filter, Medium integrity,
  created suspended and resumed only after its own token reads reduced) and fails closed otherwise. A
  scheduled task's RunLevel does NOT do this: Windows gives an admin account's non-interactive logons a
  full token whatever the RunLevel or logon type.

  The scripts and LOOP.md are read from THIS directory, the project checkout's innovation\ (the guard
  forbids the session from editing it). Keep that checkout on main and pull to update the loop.

.PARAMETER ProposeOnly
  Phase B only (observe + propose). Nothing is built, merged or deployed. Use for the supervised start.
.PARAMETER DryRun
  Everything up to the first claude call (lock, dirs, clones, task check without triggering it, settings),
  then the sessions the run would start (each build assumed deployed, for planning) with their prompts,
  models, caps and limits. -QueueFile <json> (dry run only) plans from a saved check-approval.ps1 -List output.
.PARAMETER SelfTest
  Only check the elevated deploy task from THIS process: installed, copy current, selftest round trip.
.PARAMETER MaxBuilds
  At most this many approved issues are built per run (default 4, range 1-6), one session each, strictly one
  after another. At most one server deploy happens per run; any failure or rollback ends Phase A (a scope refusal that merged nothing does not: the next approved issue is built).
.PARAMETER NextBuildMinMinutes
  (alias SecondBuildMinMinutes) Minutes that must remain before the run's deadline (start + TimeoutMinutes) for
  another build session to START (default 100: one cycle has taken ~60-75 min and up to ~110 with a CI fix round; a
  session's own limit is cut to what is left). With the 360-min run, four builds of up to ~85 min fit.
.PARAMETER TimeoutMinutes
  The whole run's time limit (default 360), cut to end 30 min inside the scheduled task's ExecutionTimeLimit
  (gate-rules.ps1 Get-RunTimeBudget; install-task.ps1 sets 7 h).
.PARAMETER MaxTurns
  Overrides every session's turn cap (sessions.json: build 150, propose 80). 0 = use sessions.json.
.PARAMETER Model
  Overrides every session's model (sessions.json). Empty = use sessions.json.
.PARAMETER IgnoreBudget
  Do not consult the ops hub's plan budget (D:\hub\state\plan-budget.json) this run: for the owner's supervised
  runs. Without it the runner reads the verdict before every session: normal = as always; no-opus = no
  session on an Opus model (Opus builds wait, approved and untouched, for a later run); hold = no session at
  all (NOTHING-TO-DO, like the precheck). A missing, unreadable, unknown or stale file counts as normal (WARN).
.PARAMETER BudgetFile
  Where the plan budget is read from (default gate-rules.ps1 $PlanBudgetPath); for dry runs and tests.

  FOCUS.md (next to this script) is the owner's steering file for Phase B: priorities and things to avoid.
  Missing, empty, or only headings and comments = FOCUS: none, and the loop proposes from its own judgment.
#>
[CmdletBinding()]
param(
    [switch]$ProposeOnly,
    [switch]$DryRun,
    [switch]$SelfTest,
    [ValidateRange(1, 6)][int]$MaxBuilds = 4,
    [Alias('SecondBuildMinMinutes')][int]$NextBuildMinMinutes = 100,
    [int]$MaxTurns = 0,
    [int]$TimeoutMinutes = 360,
    [string]$Model = '',
    [string]$QueueFile = '',
    # with -DryRun only: plan as if the scheduled task's ExecutionTimeLimit were this many minutes (e.g. 420 before the
    # task is re-registered with 7 h), instead of reading it from the task
    [int]$AssumeTaskLimitMinutes = 0,
    # the ops hub's plan budget (gate-rules.ps1 Get-PlanBudgetVerdict): -IgnoreBudget for supervised runs
    [switch]$IgnoreBudget,
    [string]$BudgetFile = '',
    [string]$ClaudeExe = ''
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\gate-rules.ps1"  # slots, specs, retry rule, precheck, session planning (pure functions)
# $PSScriptRoot is empty in param() defaults under `powershell -File` on PS 5.1: resolve defaults here.
if (-not $ClaudeExe) { $ClaudeExe = "$(Get-Cfg 'tools.claude' (Join-Path $script:ProfileDir '.local\bin\claude.exe'))" }
$ScriptsDir = (Resolve-Path $script:KitDir).Path
$RunStart = Get-Date
$RunId = $RunStart.ToString('yyyyMMdd-HHmmss')
# the run must end inside the scheduled task's ExecutionTimeLimit, or Task Scheduler kills it mid-session
$taskLimitMin = 0
try {
    $tl = "$((Get-ScheduledTask -TaskName "$(Get-Cfg 'tasks.loop' 'InnovationLoop')" -ErrorAction Stop).Settings.ExecutionTimeLimit)"
    if ($tl -and $tl -ne 'PT0S') { $taskLimitMin = [Xml.XmlConvert]::ToTimeSpan($tl).TotalMinutes }
} catch { }
if ($DryRun -and $AssumeTaskLimitMinutes -gt 0) { $taskLimitMin = $AssumeTaskLimitMinutes }
$TimeBudget = Get-RunTimeBudget -Requested $TimeoutMinutes -TaskLimitMinutes $taskLimitMin
$TimeoutMinutes = $TimeBudget.Minutes
$Deadline = $RunStart.AddMinutes($TimeoutMinutes)
Initialize-LoopDirs
$script:LogFile = Join-Path $script:LoopHome "logs\run-$RunId.log"
# The needs-Ve flag (gate-rules.ps1 Get-NeedsVeBlock): set on an uncertain deploy, cleared only by the owner
$NeedsVePath = Join-Path $script:LoopHome "state\$($script:NeedsVeFileName)"
$NeedsVeClear = "powershell -ExecutionPolicy Bypass -File `"$ScriptsDir\clear-needs-ve.ps1`" -Clear -Note `"<what you checked>`""
$mode = 'FULL'; if ($ProposeOnly) { $mode = 'PROPOSE_ONLY' }
$title = "$(Get-Cfg 'title' $script:Project)"
$OwnerName = "$(Get-Cfg 'ownerName' 'the owner')"   # optional config key: how summaries name the owner ("Failed, waiting on <ownerName>")

# sessions.json: the owner's models, turn caps and time limits per session kind (defaults in gate-rules.ps1)
$sessionsJson = $null
$sessionsPath = Join-Path $ScriptsDir 'sessions.json'
if (Test-Path -LiteralPath $sessionsPath -PathType Leaf) {
    try { $sessionsJson = [IO.File]::ReadAllText($sessionsPath) | ConvertFrom-Json } catch { Write-Log "sessions.json is not valid JSON, using the defaults: $_" 'WARN' }
}
$Cfg = Get-SessionConfig $sessionsJson
$DesignOn = Get-DesignSkillsEnabled $sessionsJson   # sessions.json options.designSkills (gate-rules.ps1)
foreach ($k in 'build', 'propose', 'review') { if ($MaxTurns -gt 0) { $Cfg[$k].maxTurns = $MaxTurns } }
$cfgLine = @('build', 'propose' | ForEach-Object { $c = $Cfg[$_]; $m = "$($c.model)"; if ($_ -eq 'build') { $m += " (small: $($c.smallModel) for $(@($c.smallLabels) -join '/'))" }; "$_=$m turns=$($c.maxTurns) timeout=$($c.timeoutMinutes)m" }) -join '; '
Write-Log "$title innovation loop run $RunId mode=$mode dryRun=$DryRun maxBuilds=$MaxBuilds scripts=$ScriptsDir"
Write-Log "time: run budget $($TimeBudget.Reason); each build after the first needs $NextBuildMinMinutes min left"
Write-Log "sessions: $cfgLine$(if ($Model) { "; -Model $Model overrides all" })"

if ($SelfTest) {
    Write-Log "selftest: elevated=$(Test-IsElevated) (run this from a NORMAL PowerShell to prove the non-elevated trigger)"
    if (-not $script:ServerEnabled) { Write-Output 'SELFTEST OK (no server: nothing elevated to test)'; exit 0 }
    $stale = Get-StaleElevatedFiles -ScriptsDir $ScriptsDir
    if ($stale.Count -gt 0) { Write-Log "elevated copy differs from this checkout: $($stale -join ', ')" 'WARN' }
    $self = Invoke-ElevatedRequest -Mode selftest -TimeoutMinutes 3
    Write-Log "selftest result: $($self.status) $($self.message)"
    if ($self.status -eq 'ok' -and $stale.Count -eq 0) { Write-Output 'SELFTEST OK'; exit 0 }
    Write-Output "SELFTEST FAILED $($self.status) $($self.message) stale=$($stale -join ',')"; exit 1
}

# ---- lock ---------------------------------------------------------------------------------
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
    if ($alive -and $age -lt $staleAfter) { Write-Log "another run (pid $lockPid, started $lockTime) holds the lock; exiting" 'WARN'; exit 0 }
    Write-Log "removing stale lock (pid $lockPid alive=$alive age=$age)" 'WARN'
    Remove-Item -LiteralPath $lockPath -Force
    if (-not (Get-Lock)) { Write-Log 'could not take the lock after clearing it' 'ERROR'; exit 1 }
}

# The queue as check-approval.ps1 -List sees it (buildable, retry, labels, slots, specs, slicesToOpen,
# waitingOnOwner), or $null when that failed. Runs it as its own process, exactly like merge-pr.ps1 does.
function Get-LoopQueue {
    if ($DryRun -and $QueueFile) { Write-Log "dry run: queue read from $QueueFile"; return ([IO.File]::ReadAllText($QueueFile) | ConvertFrom-Json) }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'check-approval.ps1') -List 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE; $ErrorActionPreference = $prev
        $json = @($out | Where-Object { "$_".TrimStart().StartsWith('{') }) | Select-Object -Last 1
        if ($code -gt 1 -or -not $json) { Write-Log "queue check failed (check-approval exit $code): $((@($out) | Select-Object -Last 3) -join ' ')" 'WARN'; return $null }
        $q = $json | ConvertFrom-Json
        if ($q.PSObject.Properties.Name -contains 'error' -or -not ($q.PSObject.Properties.Name -contains 'slots')) { Write-Log "queue check failed: $json" 'WARN'; return $null }
        Publish-ViaSpecNotices $q
        Publish-SliceWaitNotices $q
        return $q
    } catch { Write-Log "queue check failed: $_" 'WARN'; return $null }
}
# The ONE comment on a slice the first time it is treated as auto-approved through its spec (check-approval.ps1
# -List `viaSpec`, noticed = false). Runner side (same gh and rights as the queue check), never in a dry run;
# a failure is a warning and is retried by the next queue check.
$script:ViaSpecNoticed = @{}
function Publish-ViaSpecNotices {
    param($Q)
    if ($DryRun -or $null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains 'viaSpec')) { return }
    foreach ($v in @($Q.viaSpec | Where-Object { $_ -and -not $_.noticed })) {
        $n = [int]$v.issue
        if ($script:ViaSpecNoticed.ContainsKey($n)) { continue }
        try {
            $body = Format-ViaSpecNotice -Spec ([int]$v.spec) -ApprovedAt "$($v.specApprovedAt)" -Who $OwnerName -Marker $script:Marker
            $tmp = Join-Path $script:LoopHome "state\viaspec-$n.json"
            [IO.File]::WriteAllText($tmp, (@{ body = $body } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $out = & $script:GhExe api "repos/$($script:HubRepo)/issues/$n/comments" -X POST --input $tmp 2>&1 | ForEach-Object { "$_" }
            $code = $LASTEXITCODE; $ErrorActionPreference = $prev
            if ($code -eq 0) { $script:ViaSpecNoticed[$n] = $true; Write-Log "#${n}: auto-approved via spec #$($v.spec); notice posted" }
            else { Write-Log "#${n}: could not post the auto-approval notice: $((@($out) | Select-Object -Last 1))" 'WARN' }
        } catch { Write-Log "#${n}: auto-approval notice failed: $_" 'WARN' }
    }
}
# Slices that wait on an open Manual earlier slice of their spec (check-approval.ps1 -List `waitingOnSlice`,
# gate-rules.ps1 Get-SliceWaitDecision). They are not in `buildable`, so no session starts for them ($0); their
# labels stay as they are (never loop:failed). The ONE "Waiting on slice k" comment per slice is posted here
# (noticed = false), never in a dry run; a failure is a warning and is retried by the next queue check.
$script:SliceWaitNoticed = @{}
function Publish-SliceWaitNotices {
    param($Q)
    if ($null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains 'waitingOnSlice')) { return }
    foreach ($w in @(Select-SliceWaitNotices -Waiting @($Q.waitingOnSlice) -Posted $script:SliceWaitNoticed)) {
        $n = [int]$w.issue
        if ($DryRun) { Write-Log "#${n}: waiting-on-slice $(Format-SliceWaitList @($w.blockers)) (dry run: notice not posted)"; $script:SliceWaitNoticed[$n] = $true; continue }
        try {
            $body = Format-SliceWaitNotice -Blockers @($w.blockers) -Marker $script:Marker
            $tmp = Join-Path $script:LoopHome "state\slicewait-$n.json"
            [IO.File]::WriteAllText($tmp, (@{ body = $body } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $out = & $script:GhExe api "repos/$($script:HubRepo)/issues/$n/comments" -X POST --input $tmp 2>&1 | ForEach-Object { "$_" }
            $code = $LASTEXITCODE; $ErrorActionPreference = $prev
            if ($code -eq 0) { $script:SliceWaitNoticed[$n] = $true; Write-Log "#${n}: waiting-on-slice $(Format-SliceWaitList @($w.blockers)); notice posted" }
            else { Write-Log "#${n}: could not post the waiting-on-slice notice: $((@($out) | Select-Object -Last 1))" 'WARN' }
        } catch { Write-Log "#${n}: waiting-on-slice notice failed: $_" 'WARN' }
    }
}
# 'Waiting on a Manual earlier slice: #117 (slice 2 (#111, Manual))', or '' when none (summary, run data, log).
function Format-SliceWaitLine {
    param($Q)
    if ($null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains 'waitingOnSlice')) { return '' }
    $w = @($Q.waitingOnSlice | Where-Object { $_ })
    if ($w.Count -eq 0) { return '' }
    return "Waiting on a Manual earlier slice (skipped, labels unchanged): $(@($w | ForEach-Object { "#$($_.issue) ($(Format-SliceWaitList @($_.blockers)))" }) -join '; ')"
}
# The run-data form of the same: {issue, spec, k, blockers[{k, issue}], noticed}, status waiting-on-slice.
function Get-SliceWaitRunData {
    param($Q)
    if ($null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains 'waitingOnSlice')) { return @() }
    return @($Q.waitingOnSlice | Where-Object { $_ } | ForEach-Object {
            [ordered]@{ issue = [int]$_.issue; status = 'waiting-on-slice'; spec = [int]$_.spec; k = [int]$_.k
                blockers = @($_.blockers | ForEach-Object { [ordered]@{ k = [int]$_.k; issue = [int]$_.issue } }) } })
}
# The ONE comment on a slice the first time it is treated as auto-approved through its spec (check-approval.ps1
# -List `viaSpec`, noticed = false). Runner side (same gh and rights as the queue check), never in a dry run;
# a failure is a warning and is retried by the next queue check.
$script:ViaSpecNoticed = @{}
function Publish-ViaSpecNotices {
    param($Q)
    if ($DryRun -or $null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains 'viaSpec')) { return }
    foreach ($v in @($Q.viaSpec | Where-Object { $_ -and -not $_.noticed })) {
        $n = [int]$v.issue
        if ($script:ViaSpecNoticed.ContainsKey($n)) { continue }
        try {
            $body = Format-ViaSpecNotice -Spec ([int]$v.spec) -ApprovedAt "$($v.specApprovedAt)" -Who 'Ve' -Marker $script:Marker
            $tmp = Join-Path $script:LoopHome "state\viaspec-$n.json"
            [IO.File]::WriteAllText($tmp, (@{ body = $body } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $out = & $script:GhExe api "repos/$($script:HubRepo)/issues/$n/comments" -X POST --input $tmp 2>&1 | ForEach-Object { "$_" }
            $code = $LASTEXITCODE; $ErrorActionPreference = $prev
            if ($code -eq 0) { $script:ViaSpecNoticed[$n] = $true; Write-Log "#${n}: auto-approved via spec #$($v.spec); notice posted" }
            else { Write-Log "#${n}: could not post the auto-approval notice: $((@($out) | Select-Object -Last 1))" 'WARN' }
        } catch { Write-Log "#${n}: auto-approval notice failed: $_" 'WARN' }
    }
}
# 'via-spec #<spec>' when the queue says the issue is auto-approved through its spec, else 'label'.
function Get-QueueApproval {
    param($Q, [int]$Issue)
    if ($null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains 'approvals') -or $null -eq $Q.approvals) { return 'label' }
    $p = $Q.approvals.PSObject.Properties | Where-Object { $_.Name -eq "$Issue" } | Select-Object -First 1
    if ($p -and "$($p.Value)") { return "$($p.Value)" }
    return 'label'
}
function Format-QueueLine {
    param($Q)
    if ($null -eq $Q) { return 'unknown (queue check failed)' }
    $b = @($Q.buildable | Where-Object { $null -ne $_ }); $r = @($Q.retry | Where-Object { $null -ne $_ })
    $s = "buildable [$(@($b | ForEach-Object { "#$_" }) -join ' ')]"
    if ($r.Count -gt 0) { $s += " (automatic retry: $(@($r | ForEach-Object { "#$_" }) -join ' '))" }
    $vs = @($b | Where-Object { (Get-QueueApproval $Q ([int]$_)) -ne 'label' })
    if ($vs.Count -gt 0) { $s += " (approval: $(@($vs | ForEach-Object { "#$_ $(Get-QueueApproval $Q ([int]$_))" }) -join ', '))" }
    $s += "; proposal slots free $($Q.slots.free) of $($Q.slots.cap) (awaiting review: $(@($Q.slots.awaitingReview | ForEach-Object { "#$_" }) -join ' '))"
    $sp = @($Q.specs | Where-Object { $_ -and $_.approved })
    if ($sp.Count -gt 0) { $s += "; approved specs: $(@($sp | ForEach-Object { "#$($_.issue) ($(@($_.toOpen).Count) of $($_.of) slices still to open)" }) -join ', ')" }
    $w = Format-WaitingOnOwner -Waiting @($Q.waitingOnOwner) -Who $OwnerName
    if ($w) { $s += "; $w" }
    $ws = Format-SliceWaitLine $Q
    if ($ws) { $s += "; $ws" }
    return $s
}
function Get-QueueLabels {
    param($Q, [int]$Issue)
    if ($null -eq $Q -or $null -eq $Q.labels) { return @() }
    $p = $Q.labels.PSObject.Properties | Where-Object { $_.Name -eq "$Issue" } | Select-Object -First 1
    if ($p) { return @($p.Value) }
    return @()
}

# Records a session left for issue $n in one repo (merge-pr / deploy / rollback write them as <kind>-<n>-<repo>).
function Read-RepoState { param([string]$Kind, [int]$Issue, [string]$RepoName) return (Read-State "$Kind-$Issue-$RepoName") }

# The ops hub's plan-budget verdict, read now (the runner reads it, never claude; before every session, so a
# verdict that changes mid-run is respected). Fails open: see gate-rules.ps1 Get-PlanBudgetVerdict.
function Get-PlanBudget {
    $path = $BudgetFile; if (-not $path) { $path = $script:PlanBudgetPath }
    $text = $null; $err = ''
    if (-not $IgnoreBudget) {
        try { if (Test-Path -LiteralPath $path -PathType Leaf) { $text = [IO.File]::ReadAllText($path) } } catch { $err = "$($_.Exception.Message)" }
    }
    $b = Get-PlanBudgetVerdict -Text $text -ReadError $err -Ignore:$IgnoreBudget
    if ($b.Warn) { Write-Log "budget: $($b.Reason) [$path]" 'WARN' } else { Write-Log "budget: $($b.Reason)" }
    return $b
}
# Phase A's buildable issues split by the budget verdict (Allowed / Deferred), from a queue.
function Split-QueueByBudget {
    param($Q, [string]$Verdict)
    $b = @($Q.buildable | Where-Object { $null -ne $_ })
    $lo = @{}; foreach ($n in $b) { $lo[[int]$n] = @(Get-QueueLabels $Q ([int]$n)) }
    return (Split-BuildableByBudget -Buildable $b -LabelsOf $lo -Config $Cfg -Override $Model -Verdict $Verdict -OpusRetry (Get-QueueInts $Q 'opusRetry') -ServerDeploy (Get-QueueInts $Q 'serverDeploy'))
}
# An issue-number list of the queue (check-approval.ps1 -List), @() when absent (an older queue file).
function Get-QueueInts {
    param($Q, [string]$Name)
    if ($null -eq $Q -or -not ($Q.PSObject.Properties.Name -contains $Name)) { return @() }
    return @($Q.$Name | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
}
# The model of the build session for #$Issue and why (gate-rules.ps1 Get-BuildModelChoice).
function Get-QueueBuildModel {
    param($Q, [int]$Issue, [string]$Override = $Model)
    return (Get-BuildModelChoice -Labels @(Get-QueueLabels $Q $Issue) -Config $Cfg -Override $Override -OpusRetry ((Get-QueueInts $Q 'opusRetry') -contains $Issue) -ServerDeploy ((Get-QueueInts $Q 'serverDeploy') -contains $Issue))
}
function Format-Deferred {
    param([object[]]$Deferred, [string]$Verdict)
    return "plan budget ${Verdict}: deferred $(@($Deferred | ForEach-Object { "#$($_.Issue) ($($_.Model))" }) -join ', '); still approved, built by a later run once the verdict allows"
}

# After a build session: an issue it took that still carries loop:in-progress was left mid-build (the
# session was killed at its time limit, hit max turns, or just stopped). Mark it loop:failed with a failure
# marker (gate-rules.ps1 Get-UnfinishedFailure: timeout / max-turns are retried once; anything merged in
# that session is not). Never throws.
function Close-UnfinishedIssues {
    param([int[]]$Issues, [string]$EndClass, [datetime]$Since, [int]$LimitMinutes, [string]$SessionModel = '')
    $closed = @()
    foreach ($n in @($Issues | Where-Object { $_ -gt 0 } | Sort-Object -Unique)) {
        try {
            $i = Get-GhJson @('api', "repos/$($script:HubRepo)/issues/$n")
            $labels = @($i.labels | ForEach-Object { $_.name })
            if ($i.state -ne 'open' -or $labels -notcontains 'loop:proposal' -or $labels -notcontains 'loop:in-progress') { continue }
            $mergeSha = ''
            foreach ($repo in $script:Repos) {
                $rec = Read-RepoState 'merge' $n $repo.name
                if ($rec -and $rec.mergedUtc -and ([datetime]$rec.mergedUtc).ToUniversalTime() -ge $Since.ToUniversalTime()) { $mergeSha = (@($mergeSha, "$($repo.name)@$($rec.mergeSha)") | Where-Object { $_ }) -join ', ' }
            }
            $f = Get-UnfinishedFailure -EndClass $EndClass -MergeSha $mergeSha -TimeoutMinutes $LimitMinutes -Who $OwnerName
            $body = "$($script:Marker)`n$(Format-FailureMarker -Class $f.Class -Outcome 'failed' -Model $SessionModel)`n## Synopsis`n`n$($f.Synopsis)`n`n## Details`n`n" +
                "Run ``$RunId`` ended its build session with ``$EndClass`` while this issue still carried loop:in-progress. Failure class ``$($f.Class)``: $(Get-FailureDescription $f.Class). " +
                "Posted by run-loop.ps1 after the session stopped; see logs\run-$RunId.log and the session transcript.`n"
            $bp = Join-Path $script:LoopHome "work\unfinished-$RunId-$n.md"
            [IO.File]::WriteAllText($bp, $body, (New-Object Text.UTF8Encoding $false))
            Invoke-Gh -Arguments @('issue', 'comment', "$n", '-R', $script:HubRepo, '--body-file', $bp) -Quiet | Out-Null
            Invoke-Gh -Arguments @('issue', 'edit', "$n", '-R', $script:HubRepo, '--add-label', 'loop:failed', '--remove-label', 'loop:in-progress') -Quiet | Out-Null
            Write-Log "unfinished #${n}: marked loop:failed, class $($f.Class)$(if ($mergeSha) { " (merged as $mergeSha, not verified)" })" 'WARN'
            $closed += $n
        } catch { Write-Log "unfinished #${n}: could not mark it failed: $_" 'WARN' }
    }
    return $closed
}

# The loop's clones (never the owner's checkout, never a live dir), reset to origin/main before each session.
function Reset-Clones {
    $lines = @()
    foreach ($repo in $script:Repos) {
        $clone = Get-ClonePath $repo.name
        if (-not (Test-Path -LiteralPath (Join-Path $clone '.git'))) {
            Invoke-Native -File 'git' -Arguments @('clone', $repo.cloneUrl, $clone) | Out-Null
        }
        Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') -Quiet | Out-Null
        Invoke-Git -Repo $clone -Arguments @('checkout', '-f', '-B', 'main', 'origin/main') -Quiet | Out-Null
        Invoke-Git -Repo $clone -Arguments @('reset', '--hard', 'origin/main') -Quiet | Out-Null
        $keep = @(); foreach ($k in @(Get-Cfg 'cleanKeep' @('node_modules', '.cache', 'target'))) { $keep += @('-e', $k) }
        Invoke-Git -Repo $clone -Arguments (@('clean', '-fdx') + $keep) -Quiet | Out-Null
        $sha = Get-GitValue -Repo $clone -Arguments @('rev-parse', 'origin/main')
        $lines += "- CLONE[$($repo.name)]: $clone   ($($repo.slug), reset to origin/main $sha)"
    }
    return $lines
}

# Spec progress (runner side): ONE "## Spec progress" checklist comment per approved spec, created and then
# edited in place (re-read and marker-checked before every edit, so the loop only ever edits its own
# checklist on the hub repo), and the spec closed once every slice is done. $Specs: the `specs` array of
# check-approval.ps1 -List (approval verified there). -NoPost writes the bodies to state\spec only. Never throws.
function Publish-SpecProgress {
    param([object[]]$Specs = @(), [switch]$NoPost)
    $done = @()
    foreach ($s in @($Specs | Where-Object { $_ -and $_.approved })) {
        try {
            $n = [int]$s.issue
            $plan = [pscustomobject]@{ Issue = $n; Of = [int]$s.of; Valid = [bool]$s.valid; Problem = "$($s.problem)"; Complete = [bool]$s.complete; Duplicates = @()
                Slices = @(@($s.slices) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ K = [int]$_.k; Title = "$($_.title)"; Issue = [int]$_.issue; Status = "$($_.status)"; Done = [bool]$_.done } }) }
            $body = Format-SpecProgress -Plan $plan -RunId $RunId -Marker $script:Marker -Who $OwnerName
            $dir = Join-Path $script:LoopHome 'state\spec'
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $sp = Join-Path $dir "spec-$n.json"
            $st = $null; if (Test-Path -LiteralPath $sp) { $st = [IO.File]::ReadAllText($sp) | ConvertFrom-Json }
            $key = (($body -split "`n") | Where-Object { $_ -notmatch '^<sub>Updated by the runner' }) -join "`n"
            $hash = [BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($key))) -replace '-', ''
            if ($NoPost) { [IO.File]::WriteAllText((Join-Path $dir "spec-$n.md"), $body, (New-Object Text.UTF8Encoding $false)); $done += $n; continue }
            if ($st -and "$($st.hash)" -eq $hash -and -not $plan.Complete) { continue }
            $iss = Get-GhJson @('api', "repos/$($script:HubRepo)/issues/$n")
            $labels = @($iss.labels | ForEach-Object { $_.name })
            if ($iss.state -ne 'open' -or $labels -notcontains 'loop:spec' -or $labels -notcontains 'loop:proposal') { Write-Log "spec progress: #$n is not an open loop:spec issue; not touching it" 'WARN'; continue }
            $tmp = Join-Path $dir "spec-$n.body.json"
            [IO.File]::WriteAllText($tmp, (@{ body = $body } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            $cid = [long]0; if ($st) { $cid = [long]$st.commentId }
            if ($cid -gt 0) {
                $own = $false
                try { $c = Get-GhJson @('api', "repos/$($script:HubRepo)/issues/comments/$cid"); $own = ("$($c.issue_url)" -like "*/repos/$($script:HubRepo)/issues/$n") -and "$($c.body)".Contains($script:Marker) -and "$($c.body)".Contains($script:SpecProgressMarker) } catch { }
                if ($own) { $null = Invoke-Gh -Arguments @('api', "repos/$($script:HubRepo)/issues/comments/$cid", '-X', 'PATCH', '--input', $tmp) -Quiet }
                else { Write-Log "spec progress: comment $cid is not this loop's checklist on #$n; posting a new one" 'WARN'; $cid = 0 }
            }
            if ($cid -le 0) {
                $r = Invoke-Gh -Arguments @('api', "repos/$($script:HubRepo)/issues/$n/comments", '-X', 'POST', '--input', $tmp) -Quiet
                $cid = [long]((($r.Output -join "`n") | ConvertFrom-Json).id)
            }
            [IO.File]::WriteAllText($sp, (@{ issue = $n; commentId = $cid; hash = $hash; runId = $RunId } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            Write-Log "spec progress: #$n checklist updated ($(@($plan.Slices | Where-Object { $_.Done }).Count) of $($plan.Slices.Count) slices done)"
            if ($plan.Complete) {
                Invoke-Gh -Arguments @('issue', 'close', "$n", '-R', $script:HubRepo, '--reason', 'completed') -Quiet | Out-Null
                Write-Log "spec progress: every slice of #$n is done; closed the spec"
            }
            $done += $n
        } catch { Write-Log "spec progress: #$($s.issue): $_" 'WARN' }
    }
    return @($done)
}

# The run header + the LOOP.md sections one session needs. Returns the prompt path.
function New-SessionPrompt {
    param([string]$Kind, [int]$Issue = 0, [string]$SessionModel, [int]$Turns, [datetime]$SessionDeadline, $Q, [string[]]$CloneLines, [string]$LiveHead,
        [string]$ServerUsed = '', [string]$BuiltLine = '', [string[]]$ExtraLines = @())
    $loopMd = [IO.File]::ReadAllText((Join-Path $ScriptsDir 'LOOP.md'))
    $name = $Kind; if ($Issue -gt 0) { $name = "$Kind-$Issue" }
    $lines = @()
    if ($Kind -eq 'build') {
        # sections 1 (labels) and 4 (gates summary) are left out: section 3 has every command a build needs
        $sections = @(0, 2, 3, 6)
        $retry = 'no'; if (@($Q.retry) -contains $Issue) { $retry = 'yes: the ONE automatic retry (section 3 steps 4 and 6)' }
        $lines += "# $title innovation loop run ${RunId}: build session for issue #$Issue"
        $lines += ''
        $lines += "- JOB: build issue #$Issue, and only it (section 3). Then end (section 6). This session opens no proposals: a separate session does that."
        $lines += "- ISSUE: $Issue   (retry: $retry)"
        $ap = Get-QueueApproval $Q $Issue
        if ($ap -ne 'label') { $lines += "- APPROVAL: $ap   (a slice auto-approved by $OwnerName's approval of its spec: it has no `approved` label of its own and needs none; check-approval.ps1 -Issue $Issue shows approval via-spec. Say `approval: $ap` in your summary.)" }
        else { $lines += "- APPROVAL: label ($OwnerName added `approved`)" }
        $sdNote = ''; if ($script:ServerEnabled -and $serverDeploy -notlike 'available*') { $sdNote = "($serverWhy) -> if this change needs a server deploy, skip it (section 3 step 3)" }
        $lines += "- SERVER_DEPLOY: $serverDeploy   $sdNote"
        $su = 'no'; if ($ServerUsed) { $su = "yes ($ServerUsed): at most one server deploy per run, so if this change needs one, skip it (section 3 step 3)" }
        $lines += "- SERVER_DEPLOYED_THIS_RUN: $su"
        if ($BuiltLine) { $lines += "- EARLIER_THIS_RUN: $BuiltLine" }
        $lines += @($ExtraLines)
    } else {
        $sections = @(0, 1, 2, 5, 6)
        $lines += "# $title innovation loop run ${RunId}: proposal session (Phase B)"
        $lines += ''
        $lines += '- JOB: Phase B only (section 5): open the approved specs'' next slices, then new proposals, within the slots. Build, merge and deploy nothing. Then end (section 6).'
        if ($BuiltLine) { $lines += "- BUILT_THIS_RUN: $BuiltLine   (separate build sessions; mention them in your summary)" }
        $lines += "- FOCUS: $focus"
        $slot = 'unknown (queue check failed): run check-approval.ps1 -Slots'
        if ($Q) { $slot = "newThisRun $($Q.slots.newThisRun) (free $($Q.slots.free) of $($Q.slots.cap)); a new spec allowed: $(if ($Q.slots.mayOpenSpec) { 'yes' } else { 'no' })" }
        $lines += "- SLOTS: $slot   (check-approval.ps1 -Slots stays the authority)"
        $sl = @($Q.slicesToOpen | Where-Object { $_ })
        if ($sl.Count -gt 0) {
            $items = @($sl | ForEach-Object { '#{0} slice {1} of {2} "{3}"' -f $_.spec, $_.k, $_.of, $_.title })
            $lines += '- SLICES_TO_OPEN (before any new idea, in this order): ' + ($items -join '; ')
        } else { $lines += '- SLICES_TO_OPEN: none' }
    }
    $lines += "- MODE: $mode"
    $lines += "- MODEL: $SessionModel"
    $lines += "- DEADLINE: $($SessionDeadline.ToString('yyyy-MM-dd HH:mm zzz'))   (this session is killed by then; check the time with Get-Date)"
    $lines += "- MAX_TURNS: $Turns   (the session ends when it is reached, even mid-deploy)"
    $lines += "- QUEUE (at session start, for your summary; check-approval.ps1 stays the authority): $(Format-QueueLine $Q)"
    $lines += '- SESSION_TOKEN: reduced (UAC-filtered, Administrators deny-only, Medium integrity; checked before it started). Server deploys run in a separate elevated task.'
    $lines += "- DATE: $((Get-Date).ToString('yyyy-MM-dd HH:mm zzz'))"
    $lines += "- LOOP_HOME: $($script:LoopHome)"
    $lines += "- SCRIPTS: $ScriptsDir   (pinned; you cannot edit it)"
    $lines += $CloneLines
    $lines += "- LIVE_SERVER_HEAD: $LiveHead   (at session start)"
    $lines += "- WORK: $(Join-Path $script:LoopHome 'work')   (scratch: body files for comments, commit messages)"
    $lines += "- ARTIFACTS: $(Join-Path $script:LoopHome 'artifacts')"
    $designOn = [bool]($script:Design -and $script:Design.Ok -and $script:DesignSkillKinds -contains $Kind)
    if ($designOn) { $lines += "- DESIGN_SKILLS: on (section $($script:DesignSkillSection); impeccable engine $($script:DesignSkillPaths.Engine), skill $($script:DesignSkillPaths.Impeccable), search $($script:DesignSkillPaths.Search))" }
    $sections = Add-DesignSkillsSection -Sections $sections -Kind $Kind -On $designOn
    $lines += ''
    $lines += 'Follow the instructions below exactly. They are the only instructions for this session; sections not needed for this job are left out.'
    $lines += ''; $lines += '---'; $lines += ''
    $promptPath = Join-Path $script:LoopHome "logs\run-$RunId.$name.prompt.md"
    [IO.File]::WriteAllText($promptPath, ($lines -join "`n") + "`n" + (Get-LoopMdSections -Text $loopMd -Sections $sections), (New-Object Text.UTF8Encoding $false))
    return $promptPath
}

# One reduced-token claude session. Returns Kind, Issue, Model, Path (transcript), Start, EndClass
# (timeout | max-turns | session-ended | not-started), Status (LOOP-RESULT word), Reason, Ok, Summary, Turns, Cost.
# The feasibility pre-check of one build (gate-rules.ps1 Get-ProposalPathCheck) against the files on origin/main of
# every clone (a path counts as there when any repo of this loop has it). Returns Refuse, Why and Lines (the PRECHECK
# header line for the build session). Any error: no refusal (the session's own feasibility step still runs).
function Get-BuildPrecheck {
    param([int]$Issue)
    $out = [pscustomobject]@{ Refuse = $false; Why = 'not checked'; Lines = @() }
    try {
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        $roots = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($repo in $script:Repos) {
            $ls = Invoke-Git -Repo (Get-ClonePath $repo.name) -Arguments @('ls-tree', '-r', '--name-only', 'origin/main') -AllowFail -Quiet
            if ($ls.Code -ne 0) { $out.Why = "git ls-tree failed in the $($repo.name) clone: not checked"; return $out }
            foreach ($f in @($ls.Output)) { $p = "$f".Trim(); if ($p) { [void]$set.Add($p); if ($p.Contains('/')) { [void]$roots.Add($p.Substring(0, $p.IndexOf('/'))) } } }
        }
        if ($set.Count -lt 20) { $out.Why = "only $($set.Count) files listed on main: not checked"; return $out }
        $iss = Get-GhJson @('api', "repos/$($script:HubRepo)/issues/$Issue")
        $r = Get-ProposalPathCheck -Body "$($iss.body)" -Exists { param($p) $set.Contains($p) } -Roots @($roots)
        $out.Refuse = [bool]$r.Refuse; $out.Why = $r.Why
        if (@($r.Paths).Count -gt 0) {
            $st = @($r.Paths | ForEach-Object { if (@($r.Missing) -contains $_) { "$_ (NOT on main)" } else { "$_ (on main)" } })
            $out.Lines = @("- PRECHECK: $($r.Why). Named files: $($st -join ', ')   (the runner checked origin/main of every clone; section 3 step 3 'Feasibility first')")
        } else { $out.Lines = @('- PRECHECK: the issue names no repo file; find what it means before planning (section 3 step 3 "Feasibility first")') }
    } catch { $out.Refuse = $false; $out.Why = "pre-check failed ($_): not checked" }
    return $out
}
# A build refused by the pre-check: failure comment (class scope, outcome skipped) and loop:failed, like a session's
# step 3 refusal, without spending a session.
function Set-PrecheckRefused {
    param([int]$Issue, [string]$Why, [string]$SessionModel = '')
    if ($DryRun) { Write-Log "dry run: #$Issue would be refused by the pre-check ($Why)"; return }
    try {
        $body = "$($script:Marker)`n$(Format-FailureMarker -Class 'scope' -Outcome 'skipped' -Model $SessionModel)`n## Synopsis`n`nNot built: the change it describes does not match the code on main any more, so a build session would only search and give up. Nothing was changed. Close this issue, or edit it to point at today's code and approve it again.`n`n## Details`n`nPre-check by run-loop.ps1 (run ``$RunId``), before any session: $(ConvertTo-SafeLine $Why 400).`n"
        $bp = Join-Path $script:LoopHome "work\precheck-$RunId-$Issue.md"
        [IO.File]::WriteAllText($bp, $body, (New-Object Text.UTF8Encoding $false))
        Invoke-Gh -Arguments @('issue', 'comment', "$Issue", '-R', $script:HubRepo, '--body-file', $bp) -Quiet | Out-Null
        Invoke-Gh -Arguments @('issue', 'edit', "$Issue", '-R', $script:HubRepo, '--add-label', 'loop:failed') -Quiet | Out-Null
    } catch { Write-Log "pre-check: could not mark #${Issue}: $_" 'WARN' }
}

# $BudgetUsd > 0 is passed as --max-budget-usd (a size:small build: gate-rules.ps1 Get-BuildCaps); a stop there is
# EndClass max-budget (retried once, like max-turns).
function Invoke-Session {
    param([string]$Kind, [int]$Issue = 0, [string]$SessionModel, [int]$Turns, [int]$Minutes, [string]$PromptPath, [double]$BudgetUsd = 0)
    $name = $Kind; if ($Issue -gt 0) { $name = "$Kind-$Issue" }
    $s = [pscustomobject]@{ Kind = $Kind; Issue = $Issue; Model = $SessionModel; Path = (Join-Path $script:LoopHome "logs\run-$RunId.$name.jsonl"); Start = (Get-Date)
        EndClass = 'session-ended'; Status = ''; Reason = ''; Ok = $false; Summary = ''; Turns = 0; Cost = $null; ExitCode = $null }
    $guardMode = 'PROPOSE'; if ($Kind -eq 'build') { $guardMode = 'BUILD' }
    [Environment]::SetEnvironmentVariable("$($script:EnvPrefix)_MODE", $guardMode, 'Process')   # the guard narrows each kind
    $settingsPath = Join-Path $script:LoopHome "state\claude-settings-$Kind.json"
    $q = { param($x) '"' + $x + '"' }
    $addDirs = @((& $q $script:LoopHome), (& $q $ScriptsDir))
    foreach ($d in @(Get-Cfg 'readableLogDirs' @())) { $addDirs += (& $q $d) }
    $argList = @('-p', '--output-format', 'stream-json', '--verbose', '--model', $SessionModel, '--max-turns', "$Turns",
        '--permission-mode', 'dontAsk', '--permission-prompts', 'none', '--settings', (& $q $settingsPath), '--setting-sources', 'local',
        '--strict-mcp-config', '--add-dir') + $addDirs
    if ($BudgetUsd -gt 0) { $argList += @('--max-budget-usd', (Format-BudgetUsd $BudgetUsd)) }
    $argString = $argList -join ' '
    Write-Log "session $name start: model=$SessionModel maxTurns=$Turns timeout=${Minutes}m guardMode=$guardMode"
    Write-Log "claude command: `"$ClaudeExe`" $argString  < $PromptPath"
    $errPath = Join-Path $script:LoopHome "logs\run-$RunId.$name.err.log"
    try {
        Write-Log "run-loop token: $(Get-TokenState)"
        $run = Start-ReducedAndWait -File $ClaudeExe -ArgumentString $argString -WorkDir (Join-Path $script:LoopHome 'work') -StdIn $PromptPath -StdOut $s.Path -StdErr $errPath -TimeoutMinutes $Minutes
        $s.ExitCode = $run.ExitCode
        if ($run.TimedOut) { $s.EndClass = 'timeout'; Write-Log "session $name exceeded $Minutes minutes (process tree killed)" 'ERROR' }
        else { Write-Log "session $name claude pid $($run.Pid) exit code $($run.ExitCode)" }
    } catch { Write-Log "session ${name}: $_" 'ERROR'; $s.Reason = "could not run: $_"; $s.EndClass = 'not-started' }
    # every session needs the PowerShell tool; claude drops it silently for some environment variables (DO_NOT_TRACK did:
    # cardlens run 20261122-133356, this loop until the fix): say so loudly instead of a mysterious failure
    if (Test-Path -LiteralPath $s.Path) {
        foreach ($line in [IO.File]::ReadAllLines($s.Path)) { if ($line -match '"subtype"\s*:\s*"init"') { try { $ini = $line | ConvertFrom-Json; if (@($ini.tools) -notcontains 'PowerShell') { Write-Log "session ${name}: claude offered NO PowerShell tool (tools: $(@($ini.tools) -join ','))" 'ERROR'; [void]$problems.Add("session ${name} had no PowerShell tool (an environment variable hid it); its result is not trustworthy") } } catch { }; break } }
    }
    $result = $null
    if (Test-Path -LiteralPath $s.Path) { foreach ($line in [IO.File]::ReadAllLines($s.Path)) { if ($line -match '"type"\s*:\s*"result"') { try { $result = $line | ConvertFrom-Json } catch { } } } }
    if ($result) {
        $s.Summary = "$($result.result)"; $s.Turns = $result.num_turns; $s.Cost = $result.total_cost_usd
        # cost is the API-equivalent figure claude reports; on a Max subscription it is usage, not a bill.
        Write-Log ("result: session={0} subtype={1} is_error={2} turns={3} cost={4}" -f $name, $result.subtype, $result.is_error, $result.num_turns, $result.total_cost_usd)
        if ("$($result.subtype)" -eq 'error_max_turns') { $s.EndClass = 'max-turns' }
        if ("$($result.subtype)" -eq 'error_max_budget_usd') { $s.EndClass = 'max-budget'; Write-Log "session $name stopped at its USD cap ($(Format-BudgetUsd $BudgetUsd))" 'WARN' }
        $m = [regex]::Match($s.Summary, 'LOOP-RESULT:\s*([A-Z\-]+)[ \t]*([^\r\n]*)')
        $s.Status = $m.Groups[1].Value; $s.Reason = $m.Groups[2].Value.Trim()
        $s.Ok = ($s.ExitCode -eq 0 -and -not $result.is_error)
    } elseif (-not $s.Reason) {
        $s.Reason = "no result message in the transcript ($($s.EndClass))"; Write-Log "session ${name}: no result message in the transcript" 'ERROR'
    }
    Write-Log "session $name end: LOOP-RESULT $($s.Status) $($s.Reason)"
    return $s
}

# An uncertain deploy: set the needs-Ve flag (never overwritten while set) and say so on the issue, once. Never throws.
$script:NeedsVeSetThisRun = ''
function Set-LoopNeedsVe {
    param([int]$Issue, [string]$Reason)
    try {
        $rec = New-NeedsVeRecord -RunId $RunId -Loop $script:Project -Reason $Reason -Issues @($Issue) -ClearCommand $NeedsVeClear
        $r = Set-NeedsVeFlag -Path $NeedsVePath -Record $rec
        Write-Log "needs-ve: flag $r [$NeedsVePath]: every automatic run is skipped until $OwnerName clears it ($NeedsVeClear)" $(if ($r -like 'error*') { 'ERROR' } else { 'WARN' })
        $script:NeedsVeSetThisRun = $Reason
        if ($r -like 'error*') { [void]$problems.Add("the needs-Ve flag could not be written ($r): drain.json still stops the queue drain, but refill and approval runs would not be stopped") }
        if ($r -eq 'set' -and $Issue -gt 0 -and -not $DryRun) {
            $bp = Join-Path $script:LoopHome "work\needs-ve-$RunId-$Issue.md"
            [IO.File]::WriteAllText($bp, (Format-NeedsVeComment -Issue $Issue -RunId $RunId -Reason $Reason -ClearCommand $NeedsVeClear -Marker $script:Marker -Who $OwnerName), (New-Object Text.UTF8Encoding $false))
            Invoke-Gh -Arguments @('issue', 'comment', "$Issue", '-R', $script:HubRepo, '--body-file', $bp) -Quiet | Out-Null
        }
    } catch { Write-Log "needs-ve: could not set the flag: $_" 'ERROR' }
}

$exitCode = 1
$queue = $null; $finalQueue = $null; $res = $null
$sessions = New-Object System.Collections.ArrayList
$problems = New-Object System.Collections.ArrayList
$runNotes = New-Object System.Collections.ArrayList
$serverDeploy = 'none (this project has no server target)'; $serverWhy = ''
$focus = ''
try {
    # ---- the needs-Ve flag: an uncertain deploy stops EVERY run (FULL and PROPOSE_ONLY) until the owner clears it --------
    # Checked before the queue, the clones and any session: nothing is built, merged, deployed or proposed, $0. Not even the
    # read-only Phase B: the owner asked for every automatic run to stop, and a proposal run would refill the queue the next
    # runs build from. drain.json is not rewritten (no queue is read), so the watcher's drain stays off too.
    $nv = Get-NeedsVeState -Path $NeedsVePath -Kind "$mode run"
    if ($nv.Blocked) {
        Write-Log "needs-ve: $($nv.Reason) [$NeedsVePath]" 'ERROR'
        if ($DryRun) { Write-Log 'needs-ve: a real run would stop here with no claude session (dry run: carrying on to show the plan)' 'WARN' }
        else {
            $nvWhy = $nv.Reason -replace '^.*? skipped: ', ''
            $resLine = "LOOP-RESULT: FAILED NEEDS VE: the needs-Ve flag is set ($nvWhy); no session started, nothing built, merged, deployed or proposed until $OwnerName clears it"
            $sumLines = @("Needs-Ve stop (no claude session started): the loop is stopped until $OwnerName clears the flag.",
                "- $nvWhy.",
                "- Flag: $NeedsVePath",
                "- Check production (README ""Needs Ve: an uncertain deploy""), then clear it from a normal PowerShell: $NeedsVeClear",
                $resLine)
            $utf8 = New-Object Text.UTF8Encoding $false
            [IO.File]::WriteAllText((Join-Path $script:LoopHome "logs\run-$RunId.summary.txt"), ($sumLines -join "`r`n"), $utf8)
            $nvRec = $null; try { $nvRec = [IO.File]::ReadAllText($NeedsVePath) | ConvertFrom-Json } catch { }
            $rd = [ordered]@{ runId = $RunId; mode = $mode; status = 'FAILED'; precheck = 'needs-ve flag set'; claudeStarted = $false
                needsVe = [ordered]@{ set = $true; key = $nv.Key; reason = $nvWhy; path = $NeedsVePath; clear = $NeedsVeClear; record = $nvRec }
                totals = [ordered]@{ Turns = 0; Input = 0; Output = 0; CacheRead = 0; CacheWrite = 0; Cost = 0 }; sessions = @() }
            [IO.File]::WriteAllText((Join-Path $script:LoopHome "logs\run-$RunId.rundata.json"), ($rd | ConvertTo-Json -Depth 6), $utf8)
            Write-Log 'result: subtype=precheck is_error=False turns=0 cost=0 (needs-Ve flag set: no claude session)'
            Write-Log $resLine
            $exitCode = 1
            return
        }
    }

    # ---- environment ------------------------------------------------------------------------
    Add-GhToPath
    foreach ($n in (Clear-SecretEnv)) { Write-Log "unset env var $n for this run" }
    # Started from inside another Claude Code session (a supervised run by an agent), the parent's session markers
    # leak into the child claude. The scheduled task never has them; drop them so every launch gets the same
    # environment. Auth variables are kept.
    foreach ($v in @(Get-ChildItem env: | Where-Object { $_.Name -match '^(CLAUDECODE|CLAUDE_PID|CLAUDE_EFFORT|CLAUDE_CODE_(ENTRYPOINT|CHILD_SESSION|SESSION_ID|SESSION_ATTENDED|ENVIRONMENT_KIND|EXECPATH|WORKER_EPOCH|MESSAGING_\w+|BRIDGE_\w+))$' })) {
        Remove-Item -LiteralPath "env:$($v.Name)"; Write-Log "unset parent-session variable $($v.Name) (launched from a Claude Code session)"
    }
    [Environment]::SetEnvironmentVariable("$($script:EnvPrefix)_HOME", $script:LoopHome, 'Process')
    [Environment]::SetEnvironmentVariable("$($script:EnvPrefix)_SCRIPTS", $ScriptsDir, 'Process')
    $env:INNOVATION_LOOP_RUN_ID = $RunId
    $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    if (Test-Path -LiteralPath $edge) { $env:CHROME_PATH = $edge }
    # design skills (options.designSkills): pinned copies, engine re-hashed every run; off on any doubt
    $script:Design = $null
    try { $script:Design = Get-DesignSkillsSetup -Enabled $DesignOn -EnvPrefix $script:EnvPrefix } catch { $script:Design = [pscustomobject]@{ Ok = $false; Reason = "check failed: $_"; Allow = @(); Env = [ordered]@{ "$($script:EnvPrefix)_DESIGN_SKILLS" = '' }; PathPrepend = '' } }
    foreach ($k in $script:Design.Env.Keys) { Set-Item -Path "Env:$k" -Value $script:Design.Env[$k] }
    if ($script:Design.Ok -and $script:Design.PathPrepend -and (($env:PATH -split ';') -notcontains $script:Design.PathPrepend)) { $env:PATH = "$($script:Design.PathPrepend);$env:PATH" }
    if ($DesignOn -and -not $script:Design.Ok) { Write-Log "design skills: OFF for this run: $($script:Design.Reason)" 'WARN' }
    else { Write-Log "design skills: $($script:Design.Reason)$(if ($script:Design.Ok) { " (kinds $($script:DesignSkillKinds -join '/'); engine $($script:DesignSkillPaths.Engine))" })" }

    # ---- preflight ----------------------------------------------------------------------------
    foreach ($t in @($ClaudeExe, $script:GhExe, $script:NodeExe)) { if (-not (Test-Path -LiteralPath $t)) { throw "missing $t" } }
    if ($ScriptsDir -match '\s') { throw "scripts dir '$ScriptsDir' contains whitespace; the permission rules need a path without spaces" }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git not on PATH' }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $script:GhExe auth status *> $null; $ghOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prev
    if (-not $ghOk) { throw 'gh is not authenticated' }
    $elevated = Test-IsElevated
    Write-Log "elevated=$elevated"
    if ($elevated) { Write-Log 'run-loop itself holds an admin token (normal for a scheduled task of an admin account); every claude session is started with a reduced token' }

    # ---- precheck: anything to do at all? (no session, so it costs nothing) -----------------------
    $queue = Get-LoopQueue
    # plan budget (the ops hub): which sessions may start at all
    $budget = Get-PlanBudget
    $deferred = @()
    if ($mode -eq 'FULL' -and $null -ne $queue -and $budget.Verdict -ne 'hold') { $deferred = @((Split-QueueByBudget $queue $budget.Verdict).Deferred) }
    $pbKind = 'propose'
    $pbOk = Test-BudgetAllowsModel -Verdict $budget.Verdict -Model (Get-SessionModel -Kind $pbKind -Config $Cfg -Override $Model)
    $pre = Get-PrecheckDecision -Queue $queue -Mode $mode -Budget $budget -Deferred @($deferred | ForEach-Object { $_.Issue }) -PhaseBAllowed $pbOk
    Write-Log "queue: $(Format-QueueLine $queue)"
    if ($deferred.Count -gt 0) { Write-Log "Phase A: $(Format-Deferred $deferred $budget.Verdict)"; [void]$runNotes.Add("Phase A: $(Format-Deferred $deferred $budget.Verdict)") }
    if ($mode -eq 'FULL' -and (Format-SliceWaitLine $queue)) { [void]$runNotes.Add("Phase A: $(Format-SliceWaitLine $queue)") }
    Write-Log "precheck: launch=$($pre.Launch) ($($pre.Reason))"
    if (-not $pre.Launch) {
        $waitLine = Format-WaitingOnOwner -Waiting @($queue.waitingOnOwner) -Who $OwnerName
        if ($pre.Hold) {
            $sumLines = @("Precheck (no claude session started): plan budget hold.",
                "- $($budget.Reason). Approved issues stay approved and proposals are not refilled until the verdict is normal or no-opus again.",
                "- Queue: $(Format-QueueLine $queue).")
        } else {
            $sumLines = @("Precheck (no claude session started): nothing to do.",
                "- Phase A: $(if ($mode -ne 'FULL') { "not run ($mode)" } elseif ($deferred.Count -gt 0) { Format-Deferred $deferred $budget.Verdict } else { 'no buildable approved issue' }).",
                "- Phase B: $(if (-not $pbOk) { "the $pbKind model is not allowed by the $($budget.Reason)" } else { "no free proposal slot ($(@($queue.slots.awaitingReview).Count) proposals awaiting review, cap $($queue.slots.cap); approved and failed proposals do not count)" }).")
        }
        if ($waitLine) { $sumLines += "- $waitLine" }
        $sliceWaitLine = Format-SliceWaitLine $queue
        if ($sliceWaitLine) { $sumLines += "- $sliceWaitLine" }
        $resLine = 'LOOP-RESULT: NOTHING-TO-DO'
        if ($pre.Hold) { $resLine += ' plan budget hold (no claude session)' }
        elseif ($deferred.Count -gt 0 -or -not $pbOk) { $resLine += " plan budget $($budget.Verdict) (Opus sessions deferred)" }
        $sumLines += $resLine
        if ($DryRun) {
            Write-Log 'precheck: a real run would end here with NOTHING-TO-DO and no claude session (dry run: carrying on to show the plan)'
        } else {
            $utf8 = New-Object Text.UTF8Encoding $false
            [IO.File]::WriteAllText((Join-Path $script:LoopHome "logs\run-$RunId.summary.txt"), ($sumLines -join "`r`n"), $utf8)
            $rd = [ordered]@{ runId = $RunId; mode = $mode; status = 'NOTHING-TO-DO'; precheck = $pre.Reason; claudeStarted = $false
                totals = [ordered]@{ Turns = 0; Input = 0; Output = 0; CacheRead = 0; CacheWrite = 0; Cost = 0 }; sessions = @(); waitingOnOwner = $waitLine; waitingOnSlice = @(Get-SliceWaitRunData $queue)
                budget = [ordered]@{ verdict = $budget.Verdict; reason = $budget.Reason; failedOpen = $budget.Warn; deferred = @($deferred | ForEach-Object { $_.Issue }) } }
            [IO.File]::WriteAllText((Join-Path $script:LoopHome "logs\run-$RunId.rundata.json"), ($rd | ConvertTo-Json -Depth 5), $utf8)
            Write-Log 'result: subtype=precheck is_error=False turns=0 cost=0 (no claude session)'
            Write-Log $resLine
            $exitCode = 0
            return
        }
    }

    # ---- the loop's clones (never the owner's checkout, never a live dir) ------------------------
    $cloneLines = @(Reset-Clones)

    # ---- server deploy availability ------------------------------------------------------------
    $liveHead = ''
    if ($script:ServerEnabled) {
        $serverDeploy = 'unavailable'
        try { $liveHead = Get-LiveHead } catch { $serverWhy = "cannot read the live checkout's HEAD: $_" }
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & schtasks.exe /query /tn $script:DeployTaskName *> $null; $taskExists = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        if (-not $taskExists) { $serverWhy = "scheduled task $($script:DeployTaskName) is not installed (install-task.ps1)" }
        else {
            $stale = Get-StaleElevatedFiles -ScriptsDir $ScriptsDir
            if ($stale.Count -gt 0) { $serverWhy = "the elevated copy differs from this checkout ($($stale -join ', ')); re-run install-task.ps1 -ElevatedOnly elevated" }
            elseif ($DryRun) { $serverDeploy = 'available (not selftested: dry run)' }
            elseif ($ProposeOnly) { $serverDeploy = 'not needed'; $serverWhy = "$mode builds nothing" }
            else {
                $self = Invoke-ElevatedRequest -Mode selftest -TimeoutMinutes 3
                if ($self.status -eq 'ok') { $serverDeploy = 'available' } else { $serverWhy = "elevated selftest: $($self.status) $($self.message)" }
            }
        }
    }
    Write-Log "SERVER_DEPLOY=$serverDeploy $serverWhy liveHead=$liveHead"

    # ---- permission settings, one file per session kind ----------------------------------------
    # dontAsk: anything not allowlisted is denied (nobody is there to answer a prompt). guard.mjs then
    # enforces the repo/secret/never-touch/one-command rules on every call, narrowed by the session kind.
    $readOnly = 'Get-ChildItem', 'Get-Content', 'Get-Item', 'Test-Path', 'Select-String', 'Get-Date', 'Start-Sleep', 'ConvertFrom-Json',
        'ConvertTo-Json', 'Select-Object', 'Where-Object', 'Sort-Object', 'Measure-Object', 'Format-List', 'Format-Table', 'Out-String',
        'Write-Output', 'Join-Path', 'Split-Path', 'Resolve-Path', 'Get-Service', 'Get-FileHash', 'Invoke-WebRequest', 'Invoke-RestMethod',
        'New-Item', 'Remove-Item'
    $baseAllow = @('Read', 'Glob', 'Grep', 'Edit', 'Write', 'TodoWrite', 'PowerShell(git *)', 'PowerShell(gh *)')
    foreach ($d in @(Get-Cfg 'web.fetchDomains' @())) { $baseAllow += "WebFetch(domain:$d)" }
    foreach ($r in $readOnly) { $baseAllow += "PowerShell($r)"; $baseAllow += "PowerShell($r *)" }
    $deny = @('Bash', 'Agent', 'Task', 'NotebookEdit', 'WebSearch', 'Skill',
        'PowerShell(npm *)', 'PowerShell(npm.cmd *)', 'PowerShell(npx *)', 'PowerShell(yarn *)', 'PowerShell(node *)', 'PowerShell(cmd *)',
        'PowerShell(powershell *)', 'PowerShell(pwsh *)', 'PowerShell(schtasks *)', 'PowerShell(schtasks.exe *)', 'PowerShell(mvn *)', 'PowerShell(mvnw *)',
        'PowerShell(Start-ScheduledTask *)', 'PowerShell(Restart-Service *)', 'PowerShell(docker *)',
        'PowerShell(git push --force*)', 'PowerShell(git push -f*)', 'PowerShell(gh pr merge *)', 'PowerShell(gh auth *)')
    # Exactly these scripts, called by bare full path (no `&`, no quotes). The elevated task is triggered
    # ONLY from inside the scripts (fixed task name); the session has no schtasks rule and the guard blocks it.
    $scriptsFor = @{
        build   = @(Get-Cfg 'sessionScripts' @('check-approval', 'test-gate', 'wait-ci', 'merge-pr', 'deploy', 'rollback'))
        propose = @('check-approval')
    }
    $utf8 = New-Object Text.UTF8Encoding $false
    foreach ($kind in $scriptsFor.Keys) {
        $allow = @($baseAllow)
        foreach ($n in $scriptsFor[$kind]) { $allow += "PowerShell($ScriptsDir\$n.ps1)"; $allow += "PowerShell($ScriptsDir\$n.ps1 *)" }
        if ($script:Design -and $script:Design.Ok -and $script:DesignSkillKinds -contains $kind) { $allow += @($script:Design.Allow) }
        $settings = [ordered]@{
            permissions = [ordered]@{ defaultMode = 'dontAsk'; allow = $allow; deny = $deny }
            hooks       = @{ PreToolUse = @(@{ matcher = '*'; hooks = @(@{ type = 'command'; command = "node `"$ScriptsDir\guard.mjs`""; timeout = 30 }) }) }
        }
        [IO.File]::WriteAllText((Join-Path $script:LoopHome "state\claude-settings-$kind.json"), ($settings | ConvertTo-Json -Depth 10), $utf8)
    }

    # ---- FOCUS.md (the owner's, read-only): present only if something is left after removing HTML comments,
    # headings and blank lines ------------------------------------------------------------------------
    $focusPath = Join-Path $ScriptsDir 'FOCUS.md'
    $focus = 'none (no FOCUS.md, or it is empty) -> propose from your own judgment'
    if (Test-Path -LiteralPath $focusPath -PathType Leaf) {
        $ft = [regex]::Replace([IO.File]::ReadAllText($focusPath), '(?s)<!--.*?-->', '')
        $left = @($ft -split "`r?`n" | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' })
        if ($left.Count -gt 0) { $focus = "$focusPath   (the owner's priorities and things to avoid; read it first in Phase B; read-only)" }
    }
    Write-Log "FOCUS: $focus"

    $stopRun = $false
    $proposeRan = $false
    $built = @()            # {Issue; Outcome} per build session
    $serverUsed = ''
    $simMinutes = 0         # dry run: minutes a build is assumed to take, for planning the next one
    $minutesLeft = { ($Deadline - (Get-Date)).TotalMinutes - $simMinutes }

    $approvalOf = @{}      # issue -> 'label' | 'via-spec #<spec>', for the summary and run data
    # ---- Phase A: one session per approved issue ------------------------------------------------
    # A block, dot-sourced (same scope): it runs again after Phase B when that session opened slices that are
    # auto-approved through their spec, so they are built in the same run (MaxBuilds and the time rules still
    # count every build of the run).
    $phaseA = {
        $q = $queue
        while ($true) {
            if ($built.Count -gt 0 -and -not $DryRun) { $q = Get-LoopQueue }
            if ($null -eq $q) { Write-Log 'Phase A: the queue check failed; no build session' 'WARN'; [void]$runNotes.Add('Phase A: queue check failed, nothing built'); break }
            # the plan budget, re-read before every build session (a verdict that changes mid-run counts)
            if ($built.Count -gt 0) { $budget = Get-PlanBudget }
            if ($budget.Verdict -eq 'hold') { Write-Log "Phase A: stop: $($budget.Reason)"; [void]$runNotes.Add("Phase A stopped: $($budget.Reason)"); break }
            $split = Split-QueueByBudget $q $budget.Verdict
            if (@($split.Deferred).Count -gt 0) {
                $dl = "Phase A: $(Format-Deferred @($split.Deferred) $budget.Verdict)"
                if ($runNotes -notcontains $dl) { Write-Log $dl; [void]$runNotes.Add($dl) }
            }
            $dec = Get-NextBuildDecision -Buildable @($split.Allowed) -Done @($built | Where-Object { -not $_.Precheck }) -MaxBuilds $MaxBuilds -RemainingMinutes (& $minutesLeft) -NextBuildMinMinutes $NextBuildMinMinutes
            Write-Log "Phase A: $(if ($dec.Start) { 'starting' } else { 'stop:' }) $($dec.Reason)"
            if (-not $dec.Start) { [void]$runNotes.Add("Phase A stopped: $($dec.Reason)"); break }
            $n = $dec.Issue
            $labels = Get-QueueLabels $q $n
            $approvalOf[$n] = Get-QueueApproval $q $n
            if ($approvalOf[$n] -ne 'label') { Write-Log "Phase A: #$n approval: $($approvalOf[$n])" }
            $bm = Get-QueueBuildModel $q $n
            $sm = $bm.Model
            $caps = Get-BuildCaps -Labels $labels -Model $sm -Config $Cfg; $bTurns = [int]$caps.Turns; $bUsd = [double]$caps.BudgetUsd
            if ($MaxTurns -gt 0) { $bTurns = [int]$Cfg.build.maxTurns }   # run-loop -MaxTurns overrides every session
            Write-Log "Phase A: #$n model $sm ($($bm.Why)); caps $bTurns turns$(if ($bUsd -gt 0) { ", `$$(Format-BudgetUsd $bUsd)" }) ($($caps.Why))"
            $minutes = [int][math]::Floor([math]::Min([double]$Cfg.build.timeoutMinutes, (& $minutesLeft)))
            if ($built.Count -gt 0 -and -not $DryRun) { $cloneLines = @(Reset-Clones); if ($script:ServerEnabled) { try { $liveHead = Get-LiveHead } catch { } } }
            $builtLine = @($built | ForEach-Object { "#$($_.Issue) $($_.Outcome)" }) -join ', '
            # the feasibility pre-check (no session): the files the issue names that are not on main
            $pcx = Get-BuildPrecheck -Issue $n
            if ($pcx.Refuse) {
                Write-Log "Phase A: #$n refused before any session: $($pcx.Why)" 'WARN'
                Set-PrecheckRefused -Issue $n -Why $pcx.Why -SessionModel $sm
                $built += [pscustomobject]@{ Issue = $n; Outcome = 'skipped'; Precheck = $true }
                if ($approvalOf[$n] -eq 'via-policy') { $script:ViaPolicyOutcomes[[int]$n] = 'skipped'; Save-ViaPolicyState }
                [void]$runNotes.Add("#${n}: refused by the pre-check, no session: $($pcx.Why)")
                continue
            }
            $pp = New-SessionPrompt -Kind 'build' -Issue $n -SessionModel $sm -Turns $bTurns -SessionDeadline ((Get-Date).AddMinutes($minutes)) -Q $q -CloneLines $cloneLines -LiveHead $liveHead -ServerUsed $serverUsed -BuiltLine $builtLine -ExtraLines @($pcx.Lines)
            if ($DryRun) {
                Write-Log "DRY RUN plan: build session #$n model=$sm ($($bm.Why); labels: $($labels -join ',')) maxTurns=$bTurns$(if ($bUsd -gt 0) { " maxBudgetUsd=$(Format-BudgetUsd $bUsd)" }) timeout=${minutes}m precheck=($($pcx.Why)) prompt=$pp ($((Get-Item -LiteralPath $pp).Length) bytes)"
                $built += [pscustomobject]@{ Issue = $n; Outcome = 'deployed' }; $simMinutes += 75   # assume it deploys in ~75 min, to show the plan
                continue
            }
            $s = Invoke-Session -Kind 'build' -Issue $n -SessionModel $sm -Turns $bTurns -Minutes $minutes -PromptPath $pp -BudgetUsd $bUsd
            [void]$sessions.Add($s)
            if ($s.EndClass -eq 'not-started') {
                # e.g. the reduced token could not be verified (fail closed): nothing else may run either
                [void]$problems.Add("build #${n}: the session could not be started ($($s.Reason)); the run stopped"); $stopRun = $true; break
            }
            $closed = @(Close-UnfinishedIssues -Issues @($n) -EndClass $s.EndClass -Since $s.Start -LimitMinutes $minutes -SessionModel $sm)
            $lbl = @(); try { $lbl = @((Get-GhJson @('api', "repos/$($script:HubRepo)/issues/$n")).labels | ForEach-Object { $_.name }) } catch { Write-Log "cannot read #$n labels: $_" 'WARN' }
            # not $marker: PowerShell names are case-insensitive and this scope is the script's, so $marker here
            # overwrote $script:Marker (the loop's comment marker) and every later comment began with the outcome word
            $endOutcome = [regex]::Match($s.Summary, "LOOP-ISSUE-END\s+#?$n\s+([a-z-]+)").Groups[1].Value
            $uncertain = @(); $mergedHere = $false
            foreach ($repo in $script:Repos) {
                $cert = Get-DeployCertainty -SessionStart $s.Start -MergeRec (Read-RepoState 'merge' $n $repo.name) -DeployRec (Read-RepoState 'deploy' $n $repo.name) -RollbackRec (Read-RepoState 'rollback' $n $repo.name)
                Write-Log "build #$n [$($repo.name)]: deploy=$($cert.State) ($($cert.Reason))"
                if ($cert.State -ne 'none') { $mergedHere = $true }
                if (-not $cert.Certain) { $uncertain += "$($repo.name): $($cert.Reason)" }
                $dr = Read-RepoState 'deploy' $n $repo.name
                if ($dr -and $dr.serverDeployed -and $dr.startedUtc -and ([datetime]$dr.startedUtc).ToUniversalTime() -ge $s.Start.ToUniversalTime()) { $serverUsed = "#$n" }
            }
            # a scope refusal that merged nothing is a skip (the next approved issue is built); anything merged is not
            $outcome = Get-BuildOutcome -Labels $lbl -MarkerOutcome $endOutcome -Merged $mergedHere
            $built += [pscustomobject]@{ Issue = $n; Outcome = $outcome }
            Write-Log "build #$n ended: outcome=$outcome$(if ($closed.Count) { '; marked loop:failed by the runner' })$(if ($outcome -eq 'skipped' -and $lbl -contains 'loop:failed') { ' (refused on scope, nothing merged: Phase A goes on)' })"
            if ($uncertain.Count -gt 0) {
                [void]$problems.Add("#${n}: $($uncertain -join '; '). DEPLOY STATE UNCERTAIN, NEEDS $($OwnerName.ToUpperInvariant()): the run stopped here (no further build, no proposals)")
                Write-Log "build #${n}: deploy state uncertain; stopping the run" 'ERROR'
                Set-LoopNeedsVe -Issue $n -Reason "#${n}: $($uncertain -join '; ')"
                $stopRun = $true; break
            }
        }
    }
    if ($mode -eq 'FULL') { . $phaseA }

    # ---- Phase B: one proposal session, only when a slot is free ---------------------------------
    if (-not $stopRun) {
        $qb = $queue; if ($built.Count -gt 0 -and -not $DryRun) { $qb = Get-LoopQueue }
        $builtLine = @($built | ForEach-Object { "#$($_.Issue) $($_.Outcome)" }) -join ', '
        $left = & $minutesLeft
        $why = ''
        $kind = 'propose'
        if ($built.Count -gt 0) { $budget = Get-PlanBudget }   # re-read: a build may have moved the verdict
        if ($kind -eq 'propose') {
            if ($null -ne $qb -and [int]$qb.slots.newThisRun -le 0) { $why = "no free proposal slot ($(@($qb.slots.awaitingReview).Count) awaiting review, cap $($qb.slots.cap))" }
            elseif ($left -lt [double]$Cfg.propose.minMinutes) { $why = "$([int]$left) min left before the deadline (a proposal session needs $($Cfg.propose.minMinutes))" }
        }
        if (-not $why) {
            $pm = Get-SessionModel -Kind $kind -Config $Cfg -Override $Model
            if (-not (Test-BudgetAllowsModel -Verdict $budget.Verdict -Model $pm)) { $why = "$($budget.Reason) does not allow a $kind session on $pm" }
        }
        if ($why) {
            Write-Log "Phase B: no proposal session: $why"; [void]$runNotes.Add("Phase B: no proposal session ($why)")
        } else {
            $c = $Cfg['propose']
            $sm = Get-SessionModel -Kind 'propose' -Config $Cfg -Override $Model
            $minutes = [int][math]::Floor([math]::Min([double]$c.timeoutMinutes, $left))
            if ($built.Count -gt 0 -and -not $DryRun) { $cloneLines = @(Reset-Clones); if ($script:ServerEnabled) { try { $liveHead = Get-LiveHead } catch { } } }
            $pp = New-SessionPrompt -Kind 'propose' -SessionModel $sm -Turns ([int]$c.maxTurns) -SessionDeadline ((Get-Date).AddMinutes($minutes)) -Q $qb -CloneLines $cloneLines -LiveHead $liveHead -BuiltLine $builtLine
            if ($DryRun) {
                Write-Log "DRY RUN plan: propose session model=$sm maxTurns=$($c.maxTurns) timeout=${minutes}m slots newThisRun=$($qb.slots.newThisRun) slicesToOpen=$(@($qb.slicesToOpen).Count) prompt=$pp"
            } else {
                [void]$sessions.Add((Invoke-Session -Kind $kind -SessionModel $sm -Turns ([int]$c.maxTurns) -Minutes $minutes -PromptPath $pp))
                $proposeRan = ($kind -eq 'propose')
            }
        }
    }

    # ---- Phase A again: slices the proposal session just opened that are auto-approved via their spec ----
    if ($mode -eq 'FULL' -and -not $stopRun -and -not $DryRun -and $proposeRan) {
        $q2 = Get-LoopQueue
        $tried = @($built | ForEach-Object { [int]$_.Issue })
        $fresh = @(@($q2.buildable) | Where-Object { $null -ne $_ -and $tried -notcontains [int]$_ -and (Get-QueueApproval $q2 ([int]$_)) -ne 'label' })
        if ($null -ne $q2 -and $fresh.Count -gt 0) {
            Write-Log "Phase A (after Phase B): auto-approved slice(s) now buildable: $(@($fresh | ForEach-Object { "#$_" }) -join ' ')"
            $queue = $q2; $cloneLines = @(Reset-Clones); if ($script:ServerEnabled) { try { $liveHead = Get-LiveHead } catch { } }
            $budget = Get-PlanBudget
            . $phaseA
        }
    }

    if ($DryRun) {
        Write-Log "DRY RUN: $(@($built).Count) build session(s) and $(if (@($runNotes | Where-Object { $_ -like 'Phase B: no*' }).Count) { 'no' } else { 'one' }) proposal session planned; stopping before invoking claude"
        $exitCode = 0
        return
    }

    # ---- the run's result and summary ------------------------------------------------------------
    $res = Get-RunResult -Sessions @($sessions) -Problems @($problems)
    $sum = New-Object System.Collections.ArrayList
    [void]$sum.Add("Run $RunId ($mode): $($sessions.Count) session(s), one per job.")
    foreach ($s in $sessions) {
        $nm = $s.Kind; if ($s.Issue) { $nm += " #$($s.Issue)" }
        $c = 'n/a'; if ($null -ne $s.Cost) { $c = '$' + ([double]$s.Cost).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture) }
        [void]$sum.Add("- $nm ($($s.Model), $($s.Turns) turns, $c, ended: $($s.EndClass)): LOOP-RESULT $($s.Status) $($s.Reason)".TrimEnd())
    }
    foreach ($b in $built) {
        $ap = ''; if ($approvalOf.ContainsKey([int]$b.Issue) -and $approvalOf[[int]$b.Issue] -ne 'label') { $ap = " (approval: $($approvalOf[[int]$b.Issue]))" }
        [void]$sum.Add("- build #$($b.Issue): $($b.Outcome)$ap")
    }
    foreach ($r in $runNotes) { [void]$sum.Add("- $r") }
    foreach ($p in $problems) { [void]$sum.Add("- RUNNER: $p") }
    if ($script:NeedsVeSetThisRun) { [void]$sum.Add("- NEEDS $($OwnerName.ToUpperInvariant()): the needs-Ve flag is set ($NeedsVePath). Every automatic run of this loop (daily, approval, request, refill, drain) is skipped until $OwnerName checks production and clears it: $NeedsVeClear") }
    foreach ($s in $sessions) {
        $nm = $s.Kind; if ($s.Issue) { $nm += " #$($s.Issue)" }
        [void]$sum.Add(''); [void]$sum.Add("=== $nm session summary ===")
        $txt = ($s.Summary -replace '(?m)^\s*LOOP-RESULT:.*$', '').Trim(); if (-not $txt) { $txt = '(none)' }
        [void]$sum.Add($txt)
    }
    $finalQueue = Get-LoopQueue
    $waitLine = Format-WaitingOnOwner -Waiting @($finalQueue.waitingOnOwner) -Who $OwnerName
    [void]$sum.Add(''); if ($waitLine) { [void]$sum.Add($waitLine) } else { [void]$sum.Add("Failed, waiting on ${OwnerName}: none") }
    $sliceWaitLine = Format-SliceWaitLine $finalQueue
    if ($sliceWaitLine) { [void]$sum.Add($sliceWaitLine) }
    [void]$sum.Add($res.Line)
    [IO.File]::WriteAllText((Join-Path $script:LoopHome "logs\run-$RunId.summary.txt"), ($sum -join "`r`n"), $utf8)
    $tc = [double]0; $tt = 0; foreach ($s in $sessions) { if ($null -ne $s.Cost) { $tc += [double]$s.Cost }; $tt += [int]$s.Turns }
    # never a second `cost=` key: tooling sums cost= over the per-session result lines
    Write-Log ("run total: sessions={0} turns={1} usd={2}" -f $sessions.Count, $tt, $tc.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture))
    $rd = [ordered]@{ runId = $RunId; mode = $mode; status = $res.Status; claudeStarted = ($sessions.Count -gt 0); waitingOnOwner = $waitLine; waitingOnSlice = @(Get-SliceWaitRunData $finalQueue)
        sessions = @($sessions | ForEach-Object { [ordered]@{ kind = $_.Kind; issue = $_.Issue; model = $_.Model; endClass = $_.EndClass; status = $_.Status; turns = $_.Turns; cost = $_.Cost } })
        totals = [ordered]@{ Turns = $tt; Cost = $tc } }
    if ($script:NeedsVeSetThisRun) { $rd.needsVe = [ordered]@{ set = $true; reason = $script:NeedsVeSetThisRun; path = $NeedsVePath; clear = $NeedsVeClear } }
    [IO.File]::WriteAllText((Join-Path $script:LoopHome "logs\run-$RunId.rundata.json"), ($rd | ConvertTo-Json -Depth 5), $utf8)
    Write-Log $res.Line
    $allOk = (@($sessions | Where-Object { -not $_.Ok }).Count -eq 0)
    if ($allOk -and $res.Status -in @('OK', 'NOTHING-TO-DO')) { $exitCode = 0 } else { $exitCode = 1 }
} catch {
    Write-Log "run failed: $_" 'ERROR'
    $exitCode = 1
} finally {
    # spec checklists: every run (also NOTHING-TO-DO), so a slice deployed or closed by hand is ticked off
    try {
        $sq = $finalQueue; if (-not $sq) { $sq = $queue }
        if ($sq -and @($sq.specs).Count -gt 0) {
            $upd = @(Publish-SpecProgress -Specs @($sq.specs) -NoPost:$DryRun)
            if ($upd.Count -gt 0) { Write-Log "spec progress: $(if ($DryRun) { 'would update (dry run, written to state\spec only)' } else { 'updated' }) #$($upd -join ', #')" }
        }
    } catch { Write-Log "spec progress skipped: $_" 'WARN' }
    # the queue drain (gate-rules.ps1 New-DrainState / Get-DrainDecision): what is still buildable after this FULL run,
    # read by the approval watcher (as data) to start the next run while approved work is left. Not on a dry run; a
    # queue check that fails leaves the previous file (whose run was already drained): no drain, fail closed.
    if ($mode -eq 'FULL' -and -not $DryRun) {
        try {
            # Get-Variable: under StrictMode 1 a variable an early exit never set must not throw here
            $gv = { param([string]$N) Get-Variable -Name $N -ValueOnly -ErrorAction SilentlyContinue }
            $dq = & $gv 'finalQueue'; if (-not $dq) { $dq = & $gv 'queue' }
            if ($dq -and ($dq.PSObject.Properties.Name -contains 'buildable')) {
                $dPath = Join-Path $script:LoopHome 'state\drain.json'
                $prevD = $null; try { if (Test-Path -LiteralPath $dPath -PathType Leaf) { $prevD = [IO.File]::ReadAllText($dPath) | ConvertFrom-Json } } catch { }
                $db = @(Get-QueueInts $dq 'buildable')
                $dOpus = @($db | Where-Object { (Get-QueueBuildModel $dq ([int]$_) '').Opus })
                # Get-Variable -ValueOnly emits an array as ONE object: unroll it, or every count is 0 or 1
                $dBuilt = @(& $gv 'built' | ForEach-Object { $_ } | Where-Object { $_ })
                $dRes = & $gv 'res'; $dStatus = 'FAILED'; if ($dRes) { $dStatus = "$($dRes.Status)" } elseif ((& $gv 'exitCode') -eq 0) { $dStatus = 'NOTHING-TO-DO' }
                $dProb = @(& $gv 'problems' | ForEach-Object { $_ } | Where-Object { $_ })
                $ds = New-DrainState -RunId $RunId -Result $dStatus -Buildable $db -NeedsOpus $dOpus -Progress @($dBuilt | Where-Object { $_.Outcome -eq 'deployed' }).Count `
                    -RolledBack (@($dBuilt | Where-Object { $_.Outcome -eq 'rolled-back' }).Count -gt 0) -NeedsVe (@($dProb | Where-Object { "$_" -match 'UNCERTAIN' }).Count -gt 0) -Previous $prevD
                [IO.File]::WriteAllText($dPath, ($ds | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
                Write-Log "drain state: $(@($db).Count) buildable after this run [$(@($db | ForEach-Object { "#$_" }) -join ' ')], $(@($dOpus).Count) need Opus, progress $($ds.progress)"
            }
        } catch { Write-Log "drain state not written: $_" 'WARN' }
    }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $script:LoopHome 'logs') -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-60) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "exit $exitCode"
    if ($exitCode -ne 0) { exit $exitCode }   # a return inside try (the needs-Ve stop) skips the exit below
}
exit $exitCode
