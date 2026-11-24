<#
.SYNOPSIS
  Unit tests for the queue and session rules in gate-rules.ps1: proposal slots (the ONE cap rule shared with
  the approval watcher, specs included), specs and their slices, failure markers and the one automatic retry,
  the precheck before claude, issues left mid-build, one session per job (prompt sections, models, the next
  build, outcomes, the run's result), wait-ci's line and whether a build left the deploy state certain. No network, no git. verify-loop.ps1 runs it.
  powershell -ExecutionPolicy Bypass -File innovation\test-queue-rules.ps1
#>
$ErrorActionPreference = 'Stop'
$cfg = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'loop.config.json')) | ConvertFrom-Json
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('loop-queue-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
[Environment]::SetEnvironmentVariable('INNOVATION_LOOP_' + ("$($cfg.project)".ToUpperInvariant() -replace '-', '_') + '_HOME', $tmp, 'Process')
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\gate-rules.ps1"
$script:fail = 0; $script:pass = 0
function Check { param([bool]$Cond, [string]$What) if ($Cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $What" } }
$cap = $script:ProposalCap; $maxNew = $script:MaxNewPerRun

# ---- proposal slots ----------------------------------------------------------------------------------
function Iss { param([int]$N, [string[]]$L) [pscustomobject]@{ number = $N; labels = @($L | ForEach-Object { [pscustomobject]@{ name = $_ } }) } }
$open = @((Iss 33 'loop:proposal', 'approved', 'loop:failed'), (Iss 45 'loop:proposal'), (Iss 50 'loop:proposal', 'approved', 'loop:in-progress'), (Iss 57 'loop:proposal', 'area:x'))
$s = Get-ProposalSlots -Issues $open
Check (($s.AwaitingReview -join ',') -eq '45,57' -and $s.Free -eq [math]::Max(0, $cap - 2) -and $s.Open -eq 4) "approved and failed do not hold slots (got $($s.AwaitingReview -join ','), free $($s.Free))"
$s = Get-ProposalSlots -Issues @(1..($cap + 2) | ForEach-Object { Iss $_ 'loop:proposal' })
Check ($s.Free -eq 0 -and $s.NewThisRun -eq 0) 'at or over the cap -> no slot, never negative'
$s = Get-ProposalSlots -Issues @()
Check ($s.Free -eq $cap -and $s.NewThisRun -eq [math]::Min($maxNew, $cap)) 'none open -> all free, at most maxNewPerRun'
$s = Get-ProposalSlots -Issues @((Iss 1 'loop:product-review'), [pscustomobject]@{ number = 9; labels = @('loop:proposal') })
Check ($s.Open -eq 1 -and $s.AwaitingReview -contains 9) 'only loop:proposal issues count; plain-string labels work'

# ---- failure markers + the one automatic retry ------------------------------------------------------
$mk = $script:Marker; $owner = $script:Owner
function Cm { param([string]$Body, [string]$At, [string]$By = $owner) [pscustomobject]@{ id = 1; body = $Body; created_at = $At; user = [pscustomobject]@{ login = $By } } }
Check ((Format-FailureMarker 'ci-infra') -eq '<!-- innovation-loop:failure class=ci-infra outcome=failed -->') 'marker format'
Check ((Format-FailureMarker 'made-up' 'weird') -eq '<!-- innovation-loop:failure class=other outcome=failed -->') 'unknown class/outcome normalised'
$cs = @((Cm "$mk`n$(Format-FailureMarker 'tests')" '2026-11-15T10:00:00Z'), (Cm "$mk`n$(Format-FailureMarker 'gap-refused')" '2026-11-16T12:00:00Z'),
    (Cm "$(Format-FailureMarker 'ci-infra')" '2026-11-16T12:30:00Z'), (Cm "$mk`n$(Format-FailureMarker 'ci-infra')" '2026-11-16T13:00:00Z' -By 'someone-else'))
$fr = @(Get-FailureRecords -Comments $cs -Owner $owner -Marker $mk -Since '2026-11-16T10:00:00Z')
Check ($fr.Count -eq 1 -and $fr[0].Class -eq 'gap-refused') "only the owner's loop comments after the approval count (got $($fr.Count))"
function Fr { param([string]$Class, [string]$Outcome = 'failed') [pscustomobject]@{ Class = $Class; Outcome = $Outcome } }
$L = @('loop:proposal', 'approved', 'loop:failed')
foreach ($c in @($script:RetryableFailures.Keys)) { Check ((Get-RetryDecision -Labels $L -Failures @(Fr $c)).Retry) "$c -> one retry" }
foreach ($c in @($script:ChangeFailures.Keys) + 'unknown-x') { Check (-not (Get-RetryDecision -Labels $L -Failures @(Fr $c)).Retry) "$c -> not retried" }
Check (-not (Get-RetryDecision -Labels $L -Failures @(Fr 'ci-infra' 'rolled-back')).Retry) 'rolled back -> not retried'
Check (-not (Get-RetryDecision -Labels ($L + 'loop:retried') -Failures @(Fr 'ci-infra')).Retry) 'loop:retried -> never a second retry'
Check (-not (Get-RetryDecision -Labels $L -Failures @((Fr 'ci-infra'), (Fr 'ci-timeout'))).Retry) 'two failures since the approval -> not retried'
Check (-not (Get-RetryDecision -Labels $L -Failures @()).Retry) 'no marker -> not retried'
$d = Get-RetryDecision -Labels @('loop:proposal', 'approved') -Failures @(Fr 'ci-infra')
Check (-not $d.Failed -and -not $d.Retry) 'not loop:failed -> no retry decision'

# ---- precheck before claude -------------------------------------------------------------------------
function Q { param([int[]]$B, [int]$Free) [pscustomobject]@{ buildable = @($B); slots = [pscustomobject]@{ free = $Free; cap = $cap; awaitingReview = @() } } }
Check (-not (Get-PrecheckDecision -Queue (Q @() 0) -Mode 'FULL').Launch) 'nothing buildable, no slot -> skip'
Check ((Get-PrecheckDecision -Queue (Q @(3) 0) -Mode 'FULL').Launch) 'buildable -> launch'
Check ((Get-PrecheckDecision -Queue (Q @() 1) -Mode 'FULL').Launch) 'free slot -> launch'
Check (-not (Get-PrecheckDecision -Queue (Q @(3) 0) -Mode 'PROPOSE_ONLY').Launch) 'PROPOSE_ONLY ignores buildable issues'
Check ((Get-PrecheckDecision -Queue $null -Mode 'FULL').Launch) 'queue check failed -> launch as before'
Check ((Format-WaitingOnOwner @([pscustomobject]@{ issue = 3; reason = 'tests: x' }) 'Ve') -eq 'Failed, waiting on Ve: #3 (tests: x).') 'waiting line'

# ---- issues left mid-build ---------------------------------------------------------------------------
Check ((Get-UnfinishedFailure -EndClass 'timeout' -TimeoutMinutes 240).Class -eq 'timeout') 'killed at the time limit -> timeout'
Check ((Get-UnfinishedFailure -EndClass 'max-turns').Class -eq 'max-turns') 'turn limit -> max-turns'
Check ((Get-UnfinishedFailure -EndClass 'timeout' -MergeSha 'abc').Class -eq 'session-ended') 'merged but not verified -> session-ended'

# ---- specs hold slots like proposals ------------------------------------------------------------------
$s = Get-ProposalSlots -Issues @((Iss 70 'loop:proposal', 'loop:spec'), (Iss 71 'loop:proposal')) -Cap 3
Check ($s.Free -eq 1 -and ($s.SpecsAwaiting -join ',') -eq '70' -and -not $s.MayOpenSpec) 'an unapproved spec takes ONE slot; a second spec is not allowed while it waits'
$s = Get-ProposalSlots -Issues @((Iss 70 'loop:proposal', 'loop:spec', 'approved'), (Iss 72 'loop:proposal')) -Cap 3
Check ($s.Free -eq 2 -and $s.SpecsAwaiting.Count -eq 0 -and $s.MayOpenSpec) 'an approved spec holds no slot; a new spec is allowed again'
Check ($script:MaxOpenSpecs -eq 1 -and $script:SpecLabel -eq 'loop:spec') 'at most one unapproved spec'

# ---- spec bodies, slice links, the spec plan ----------------------------------------------------------
function Iss2 { param([int]$N, [string[]]$L, [string]$State = 'OPEN', [string]$Body = '', [string]$By = $owner)
    [pscustomobject]@{ number = $N; state = $State; body = $Body; author = [pscustomobject]@{ login = $By }; labels = @($L | ForEach-Object { [pscustomobject]@{ name = $_ } }) } }
$specBody = "$mk`n## Problem and evidence`nx`n## User flow`n1. Not a slice`n## Slices`n1. **Store a daily total**: one number a day.`n2. **Show the trend**: a sparkline.`n3. Alert badge: when a value moves - glasses only`n   4. nested, not a slice`n## Notes`n1. not a slice either"
$sl = @(Get-SpecSlices -Body $specBody)
Check ($sl.Count -eq 3 -and $sl[0].Title -eq 'Store a daily total' -and $sl[2].Title -eq 'Alert badge') "slices parsed from ## Slices only ($(@($sl | ForEach-Object { $_.Title }) -join ' | '))"
Check (@(Get-SpecSlices -Body "## Slices`n1. **x <!-- innovation-loop --> @someone**: y")[0].Title -notmatch '<!--|@someone') 'a slice title cannot forge a marker or a mention'
$lk = Get-SliceLink -Body "$mk`nPart of #70 (slice 2 of 3)"
Check ($lk.Spec -eq 70 -and $lk.K -eq 2 -and $lk.Of -eq 3) 'slice link parsed'
Check ($null -eq (Get-SliceLink -Body 'see #70, part of the plan')) 'prose is not a link'
$spec = Iss2 70 'loop:proposal', 'loop:spec', 'approved' -Body $specBody
$all = @($spec, (Iss2 81 'loop:proposal', 'loop:deployed' -State 'CLOSED' -Body "$mk`nPart of #70 (slice 1 of 3)"),
    (Iss2 82 'loop:proposal', 'approved' -Body "$mk`nPart of #70 (slice 2 of 3)"),
    (Iss2 83 'loop:proposal' -Body 'Part of #70 (slice 3 of 3)'),
    (Iss2 84 'loop:proposal' -Body "$mk`nPart of #70 (slice 3 of 3)" -By 'someone-else'))
$pl = Get-SpecPlan -Spec $spec -Issues $all -Owner $owner -Marker $mk
Check ($pl.Valid -and $pl.Of -eq 3 -and -not $pl.Complete -and $pl.Slices[0].Done -and $pl.Slices[1].Issue -eq 82) 'plan: slice 1 deployed, slice 2 open'
Check ((@($pl.ToOpen | ForEach-Object { $_.K }) -join ',') -eq '3') 'slice 3 still to open (no marker / not the owner do not count)'
$done = @($spec, (Iss2 81 'loop:proposal', 'loop:deployed' -State 'CLOSED' -Body "$mk`nPart of #70 (slice 1 of 3)"),
    (Iss2 82 'loop:proposal' -State 'CLOSED' -Body "$mk`nPart of #70 (slice 2 of 3)"), (Iss2 86 'loop:proposal', 'loop:deployed' -State 'CLOSED' -Body "$mk`nPart of #70 (slice 3 of 3)"))
Check ((Get-SpecPlan -Spec $spec -Issues $done -Owner $owner -Marker $mk).Complete) 'every slice deployed or closed -> complete'
$bad = Get-SpecPlan -Spec (Iss2 90 'loop:proposal', 'loop:spec' -Body "$mk`nno slices") -Issues @() -Owner $owner
Check (-not $bad.Valid -and -not $bad.Complete) 'no Slices list -> invalid, never complete'
$fp = Format-SpecProgress -Plan $pl -RunId 'R1' -Marker $mk
Check ($fp.Contains($script:SpecProgressMarker) -and $fp -match '- \[x\] 1\. Store a daily total: #81 deployed' -and $fp -match '- \[ \] 3\. Alert badge: not opened yet') 'checklist rendered with both markers'

# ---- one session per job ---------------------------------------------------------------------------
$md = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'LOOP.md'))
$b = Get-LoopMdSections -Text $md -Sections @(0, 1, 2, 3, 4, 6)
Check ($b -match '(?m)^## 3\. ' -and $b -notmatch '(?m)^## 5\. ') 'build prompt: Phase A, no Phase B'
$pp = Get-LoopMdSections -Text $md -Sections @(0, 1, 2, 5, 6)
Check ($pp -match '(?m)^## 5\. ' -and $pp -notmatch '(?m)^## 3\. ') 'proposal prompt: Phase B, no Phase A'
$cfgS = Get-SessionConfig $null
Check ($cfgS.build.model -eq 'claude-sonnet-5-5' -and $cfgS.build.opusModel -eq 'claude-opus-5-5' -and $cfgS.propose.model -eq 'claude-sonnet-5-5' -and $cfgS.build.maxTurns -eq 150 -and $cfgS.propose.maxTurns -eq 80) 'session defaults'
$sj = Join-Path $PSScriptRoot 'sessions.json'
if (Test-Path $sj) { $c3 = Get-SessionConfig ([IO.File]::ReadAllText($sj) | ConvertFrom-Json); Check ($c3.build.maxTurns -gt 0 -and $c3.propose.model) 'sessions.json parses' }
Check ((Get-SessionModel -Kind 'build' -Labels @('size:small') -Config $cfgS) -eq 'claude-sonnet-5-5' -and (Get-SessionModel -Kind 'build' -Labels @('approved') -Config $cfgS) -eq 'claude-sonnet-5-5' -and (Get-SessionModel -Kind 'build' -Labels @('approved', 'model:opus') -Config $cfgS) -eq 'claude-opus-5-5') 'build model: Sonnet by default, model:opus -> Opus'
Check ((Get-SessionModel -Kind 'build' -Config $cfgS -Override 'x') -eq 'x') '-Model overrides'
function D { param([int]$I, [string]$O) [pscustomobject]@{ Issue = $I; Outcome = $O } }
Check ((Get-NextBuildDecision -Buildable @(12, 14) -Done @() -RemainingMinutes 240).Issue -eq 12) 'first build: the oldest buildable'
Check ((Get-NextBuildDecision -Buildable @(12, 14) -Done @(D 12 'deployed') -MaxBuilds 2 -RemainingMinutes 150).Issue -eq 14) 'after a deploy: the next'
Check (-not (Get-NextBuildDecision -Buildable @(14) -Done @(D 12 'deployed') -MaxBuilds 2 -RemainingMinutes 90).Start) 'next build needs NextBuildMinMinutes (100)'
Check (-not (Get-NextBuildDecision -Buildable @(14) -Done @(D 12 'failed') -RemainingMinutes 200).Start) 'a failure stops Phase A'
Check ((Get-NextBuildDecision -Buildable @(12, 14) -Done @(D 12 'skipped') -MaxBuilds 1 -RemainingMinutes 200).Issue -eq 14) 'a skipped issue does not count'
Check ((Get-BuildOutcome -Labels @('loop:deployed')) -eq 'deployed' -and (Get-BuildOutcome -Labels @('loop:failed') -MarkerOutcome 'rolled-back') -eq 'rolled-back' -and (Get-BuildOutcome -Labels @('approved')) -eq 'skipped' -and (Get-BuildOutcome -Labels @('loop:in-progress')) -eq 'unknown') 'build outcomes from labels'
function S { param([string]$K, [string]$St = 'OK', [bool]$Ok = $true) [pscustomobject]@{ Kind = $K; Issue = 0; Status = $St; Reason = ''; Ok = $Ok } }
Check ((Get-RunResult -Sessions @((S 'build'), (S 'propose' 'NOTHING-TO-DO'))).Status -eq 'OK') 'run result OK'
Check ((Get-RunResult -Sessions @((S 'build' ''))).Status -eq 'FAILED') 'a session without a summary -> FAILED'
Check ((Get-RunResult -Sessions @((S 'build')) -Problems @('x')).Status -eq 'FAILED') 'a runner problem -> FAILED'

# ---- wait-ci line, deploy certainty ------------------------------------------------------------------
$sha = '0123456789abcdef0123456789abcdef01234567'
$fv = [pscustomobject]@{ State = 'failed'; Summary = 's'; Failed = @('e2e: failure https://x/actions/runs/5/job/6', 'lint: failure u'); Refuse = @() }
Check ((Format-WaitCiLine -Verdict $fv -Sha $sha -WaitedMinutes 7) -match '^WAIT-CI FAIL 0123456 .*failed jobs: e2e, lint') 'wait-ci FAIL line names the jobs'
Check ((Format-WaitCiLine -Verdict ([pscustomobject]@{ State = 'ok'; Summary = 's' }) -Sha $sha) -match '^WAIT-CI PASS') 'wait-ci PASS'
Check ((Format-WaitCiLine -Verdict ([pscustomobject]@{ State = 'pending'; Summary = 's' }) -Sha $sha -WaitedMinutes 50 -TimeoutMinutes 45) -match '^WAIT-CI TIMEOUT') 'wait-ci TIMEOUT past the cap'
$tail = @(Get-CiLogTail -Log ((@(1..30 | ForEach-Object { "e2e`tstep`t2026-11-17T10:00:00.0Z line $_" })) -join "`n") -Lines 5)
Check ($tail.Count -eq 6 -and $tail[-1] -eq 'line 30') 'log tail per job, timestamps stripped'
$t0 = [datetime]'2026-11-17T10:00:00Z'; $m = [pscustomobject]@{ mergeSha = $sha; mergedUtc = '2026-11-17T11:00:00Z' }
Check ((Get-DeployCertainty -SessionStart $t0 -MergeRec $null).Certain) 'nothing merged -> certain'
Check ((Get-DeployCertainty -SessionStart $t0 -MergeRec $m -DeployRec ([pscustomobject]@{ mergeSha = $sha; status = 'DEPLOY OK x' })).Certain) 'DEPLOY OK -> certain'
Check ((Get-DeployCertainty -SessionStart $t0 -MergeRec $m -RollbackRec ([pscustomobject]@{ mergeSha = $sha; status = 'ROLLBACK OK' })).Certain) 'ROLLBACK OK -> certain'
Check (-not (Get-DeployCertainty -SessionStart $t0 -MergeRec $m).Certain) 'merged, no deploy record -> UNCERTAIN'
Check (-not (Get-DeployCertainty -SessionStart $t0 -MergeRec $m -DeployRec ([pscustomobject]@{ mergeSha = $sha; status = 'DEPLOY ROLLBACK-FAILED x' })).Certain) 'rollback failed -> UNCERTAIN'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

# ---- slices auto-approved through their approved spec (Get-ViaSpecDecision) ---------------------------------
$vsSpecBody = @"
$mk
## Problem and evidence
x
## Slices
1. **Since you last looked (device-local)**: Home line. Size S, Pages only.
2. **Value history design and storage decision**: decision note.
3. **Snapshot writer**: records one row a day.
4. **Value over time chart on Home**: reads the history.
"@
function VsIss { param([int]$N, [string]$Title, [string[]]$L = @('loop:proposal'), [string]$Body, [string]$State = 'OPEN', [string]$By = $owner, [string]$Created = '2026-11-20T18:57:17Z')
    [pscustomobject]@{ number = $N; title = $Title; state = $State; body = $Body; createdAt = $Created; author = [pscustomobject]@{ login = $By }; labels = @($L | ForEach-Object { [pscustomobject]@{ name = $_ } }) } }
function VsBody { param([int]$K, [int]$Of = 4, [int]$Spec = 108, [string]$Extra = '') "$mk`nPart of #$Spec (slice $K of $Of)`n## What`nthe slice.$Extra" }
function VsCmt { param([string]$Body, [string]$At = '2026-11-21T10:00:00Z', [string]$By = $owner, [int]$Id = 5) [pscustomobject]@{ id = $Id; body = $Body; created_at = $At; user = [pscustomobject]@{ login = $By } } }
$vsSpec = VsIss 108 'Spec: Collection value over time' @('loop:proposal', 'approved', 'loop:spec') $vsSpecBody -Created '2026-11-20T16:39:09Z'
$vsOk = [pscustomobject]@{ buildable = $true; approvedAt = '2026-11-20T17:00:00Z'; reasons = @() }
$s1 = VsIss 110 'Since you last looked (device-local)' -Body (VsBody 1)
$s2 = VsIss 111 'Value history design and storage decision' -Body (VsBody 2)
$s3 = VsIss 112 'Snapshot writer' -Body (VsBody 3)
$s4 = VsIss 117 'Home (phone/desktop): Value over time chart on Home' -Body (VsBody 4) -Created '2026-11-22T00:24:55Z'
function Vs { param($Slice, [object[]]$Issues = @($vsSpec, $s1, $s2, $s3, $s4), $Check = $vsOk, $Spec = $vsSpec, [string]$Edited = '', [object[]]$Comments = @(), [object[]]$SpecComments = @(), [int]$Ev = 0)
    Get-ViaSpecDecision -Slice $Slice -SliceEditedAt $Edited -SliceComments $Comments -SliceApprovalEvents $Ev -Spec $Spec -SpecCheck $Check -SpecComments $SpecComments -Issues $Issues -Owner $owner -Marker $mk }
function Why { param($D) ($D.Reasons -join ' | ') }

$d = Vs $s4
Check ($d.Linked -and $d.Eligible -and $d.Spec -eq 108 -and $d.K -eq 4 -and $d.Of -eq 4 -and $d.SpecApprovedAt -eq '2026-11-20T17:00:00Z') "approved spec, loop slice, earlier slices fine -> auto-approved (got: $(Why $d))"
$d = Vs $s1
Check ($d.Eligible) "first slice, nothing earlier -> auto-approved (got: $(Why $d))"
# 1. the spec's approval
$d = Vs $s4 -Check ([pscustomobject]@{ buildable = $false; approvedAt = $null; reasons = @('no labeled-approved event found') })
Check (-not $d.Eligible -and (Why $d) -match 'not approved') 'unapproved spec -> not auto-approved'
$d = Vs $s4 -Check ([pscustomobject]@{ buildable = $false; approvedAt = '2026-11-20T17:00:00Z'; reasons = @('approved label was removed after it was added') })
Check (-not $d.Eligible -and (Why $d) -match 'removed') 'spec approval removed -> not auto-approved'
$d = Vs $s4 -Check ([pscustomobject]@{ buildable = $false; approvedAt = '2026-11-20T17:00:00Z'; reasons = @('issue body edited at x, after approval') })
Check (-not $d.Eligible -and (Why $d) -match 'edited') 'spec edited after approval -> not auto-approved'
$d = Vs $s4 -Spec (VsIss 108 'Spec' @('loop:proposal', 'approved', 'loop:spec') $vsSpecBody -State 'CLOSED')
Check (-not $d.Eligible -and (Why $d) -match 'spec #108 is closed') 'closed spec -> not auto-approved'
$d = Vs $s4 -Spec (VsIss 108 'Spec' @('loop:proposal', 'approved') $vsSpecBody)
Check (-not $d.Eligible -and (Why $d) -match 'not a loop:spec') 'linked issue is not a loop:spec -> not auto-approved'
$d = Vs $s4 -Spec $null
Check (-not $d.Eligible -and (Why $d) -match 'not found') 'spec missing -> not auto-approved'
$d = Vs $s4 -SpecComments @((VsCmt '/hold until I look at the chart' -At '2026-11-21T09:00:00Z'))
Check (-not $d.Eligible -and (Why $d) -match 'put spec #108 on hold') '/hold on the spec after its approval -> every slice held'
$d = Vs $s4 -SpecComments @((VsCmt '/hold' -At '2026-11-20T16:50:00Z'))
Check ($d.Eligible) "a hold on the spec BEFORE its (re-)approval no longer counts (got: $(Why $d))"
$early = VsIss 117 'Value over time chart on Home' -Body (VsBody 4) -Created '2026-11-20T16:59:00Z'
$d = Vs $early -Issues @($vsSpec, $s1, $s2, $s3, $early)
Check (-not $d.Eligible -and (Why $d) -match 'opened before spec #108') 'slice opened before the spec approval -> not auto-approved'
# 2. opened by the loop, in the loop's format, in the spec's list
$d = Vs (VsIss 117 'Value over time chart on Home' -Body (VsBody 4) -By 'someone') -Issues @($vsSpec, $s1, $s2, $s3)
Check (-not $d.Eligible -and (Why $d) -match 'opened by someone') 'slice not opened by the owner account -> not auto-approved'
$noMark = VsIss 117 'Value over time chart on Home' -Body "Part of #108 (slice 4 of 4)`n$mk`nbody" -Created '2026-11-22T00:24:55Z'
$d = Vs $noMark -Issues @($vsSpec, $s1, $s2, $s3, $noMark)
Check (-not $d.Eligible -and (Why $d) -match 'does not start with the loop marker') 'marker not the first line -> not auto-approved (and the plan ignores it)'
$d = Vs (VsIss 117 'Value over time chart on Home' @('size:small') -Body (VsBody 4) -Created '2026-11-22T00:24:55Z')
Check (-not $d.Eligible -and (Why $d) -match 'missing label loop:proposal') 'no loop:proposal -> not auto-approved'
$k9 = VsIss 120 'Value over time chart on Home' -Body (VsBody 9 -Of 4) -Created '2026-11-22T00:24:55Z'
$d = Vs $k9 -Issues @($vsSpec, $s1, $s2, $s3, $k9)
Check (-not $d.Eligible -and (Why $d) -match 'slice 9 is not in spec') 'slice index not in the spec -> not auto-approved'
$of5 = VsIss 120 'Value over time chart on Home' -Body (VsBody 4 -Of 5) -Created '2026-11-22T00:24:55Z'
$d = Vs $of5 -Issues @($vsSpec, $s1, $s2, $s3, $of5)
Check (-not $d.Eligible -and (Why $d) -match 'says 5 slices') 'slice count differs from the spec -> not auto-approved'
$bt = VsIss 117 'Delete every binder' -Body (VsBody 4) -Created '2026-11-22T00:24:55Z'
$d = Vs $bt -Issues @($vsSpec, $s1, $s2, $s3, $bt)
Check (-not $d.Eligible -and (Why $d) -match 'title does not match') 'title unlike the spec slice -> not auto-approved'
$d = Vs $s1 -Spec (VsIss 108 'Spec' @('loop:proposal', 'approved', 'loop:spec') "$mk`n## Problem`nno slices")
Check (-not $d.Eligible -and (Why $d) -match 'nothing to open') 'spec without a ## Slices list -> not auto-approved'
$dup = VsIss 116 'Value over time chart on Home' -Body (VsBody 4) -Created '2026-11-21T00:00:00Z'
$d = Vs $s4 -Issues @($vsSpec, $s1, $s2, $s3, $dup, $s4)
Check (-not $d.Eligible -and (Why $d) -match 'counts #116 as slice 4') 'a duplicate that the plan counts instead -> this one is not auto-approved'
$d = Vs (VsIss 999 'x' -Body "$mk`nno link")
Check (-not $d.Linked -and -not $d.Eligible) 'not a slice at all -> Linked false'
Check (Test-SliceTitleMatch 'Since you last looked (device-local)' 'Home (phone/desktop): since you last looked, device local') 'title match tolerates case, punctuation and a screen prefix'
Check (Test-SliceTitleMatch 'Value over time chart on Home' 'Value-over-time chart on the Home screen') 'title match tolerates minor rewording'
Check (-not (Test-SliceTitleMatch 'Snapshot writer' 'Binder undo')) 'unrelated titles do not match'
Check (-not (Test-SliceTitleMatch 'Home' 'Home (phone/desktop): Biggest movers strip')) 'a very short title is not matched by containment alone'
# 3. Manual, failed, build order
$man = VsIss 110 'Since you last looked (device-local)' -Body (VsBody 1 -Extra "`n**Manual / needs Ve** because it adds a storage key.")
$d = Vs $man -Issues @($vsSpec, $man, $s2, $s3, $s4)
Check (-not $d.Eligible -and (Why $d) -match 'marked Manual') 'Manual / needs Ve slice -> never auto-approved'
$d = Vs $s4 -Issues @($vsSpec, $man, $s2, $s3, $s4)
Check (-not $d.Eligible -and (Why $d) -match 'earlier slice 1 \(#110\) is Manual') 'an open Manual earlier slice holds the later ones'
$manClosed = VsIss 110 'Since you last looked (device-local)' -Body (VsBody 1 -Extra "`n**Manual / needs Ve**") -State 'CLOSED'
$d = Vs $s4 -Issues @($vsSpec, $manClosed, $s2, $s3, $s4)
Check ($d.Eligible) "an earlier Manual slice that Ve closed releases the later ones (got: $(Why $d))"
$f = VsIss 117 'Value over time chart on Home' @('loop:proposal', 'loop:failed') -Body (VsBody 4) -Created '2026-11-22T00:24:55Z'
$d = Vs $f -Issues @($vsSpec, $s1, $s2, $s3, $f)
Check (-not $d.Eligible -and (Why $d) -match 'loop:failed') 'failed slice -> not auto-approved (no automatic retry)'
$f2 = VsIss 111 'Value history design and storage decision' @('loop:proposal', 'loop:failed') -Body (VsBody 2)
$d = Vs $s4 -Issues @($vsSpec, $s1, $f2, $s3, $s4)
Check (-not $d.Eligible -and (Why $d) -match 'earlier slice 2 \(#111\) failed') 'an open failed earlier slice holds the later ones'
$d = Vs $s4 -Issues @($vsSpec, $s1, $s2, $s4)
Check (-not $d.Eligible -and (Why $d) -match 'earlier slice 3 is not opened yet') 'an earlier slice not opened yet holds the later ones'
# 4. veto
$d = Vs (VsIss 117 'Value over time chart on Home' -Body (VsBody 4) -State 'CLOSED' -Created '2026-11-22T00:24:55Z')
Check (-not $d.Eligible -and (Why $d) -match 'slice is closed') 'closed slice -> not auto-approved'
$d = Vs $s4 -Comments @((VsCmt '/hold' -At '2026-11-22T01:00:00Z'))
Check (-not $d.Eligible -and (Why $d) -match 'put this slice on hold') '/hold comment from Ve -> vetoed'
$d = Vs $s4 -Comments @((VsCmt 'Hold: let me check the colours first' -At '2026-11-22T01:00:00Z'))
Check (-not $d.Eligible) '"hold ..." (no slash, any case) also vetoes'
$d = Vs $s4 -Comments @((VsCmt '/hold' -At '2026-11-22T01:00:00Z' -By 'stranger'))
Check ($d.Eligible) "a /hold from anyone else is data, not a veto (got: $(Why $d))"
$d = Vs $s4 -Comments @((VsCmt "$mk`n/hold" -At '2026-11-22T01:00:00Z'))
Check ($d.Eligible) 'a loop comment (marker) never counts as a hold'
$d = Vs $s4 -Comments @((VsCmt 'looks good, but keep the chart small' -At '2026-11-22T01:00:00Z'))
Check ($d.Eligible) 'an ordinary adjustment comment is not a hold'
$d = Vs $s4 -Comments @((VsCmt 'I will withhold judgement' -At '2026-11-22T01:00:00Z'))
Check ($d.Eligible) 'the word hold inside a sentence is not a hold'
$d = Vs $s4 -Ev 2
Check (-not $d.Eligible -and (Why $d) -match 'added to and removed') '`approved` added and removed on the slice by hand -> that decision stands'
# 5. edited
$d = Vs $s4 -Edited '2026-11-22T02:00:00Z'
Check (-not $d.Eligible -and (Why $d) -match 'body edited') 'slice body edited after it was opened -> not auto-approved'
# slots and the notice
$sv = Get-ProposalSlots -Issues @((Iss 108 'loop:proposal', 'loop:spec', 'approved'), (Iss 117 'loop:proposal'), (Iss 118 'loop:proposal')) -ApprovedViaSpec @(117)
Check (($sv.AwaitingReview -join ',') -eq '118' -and $sv.Free -eq ($cap - 1)) "an auto-approved slice holds no proposal slot (got awaiting $($sv.AwaitingReview -join ','))"
$nt = Format-ViaSpecNotice -Spec 108 -ApprovedAt '2026-11-20T17:00:00Z' -Who 'Owner' -Marker $mk
Check ($nt.StartsWith($mk) -and $nt.Contains($script:ViaSpecMarker) -and $nt -match 'Auto-approved via spec #108 \(approved by Owner on 2026-11-20\)\. Comment `/hold` to stop\.') "notice text (got: $nt)"
Check (-not ($nt -match $script:HoldRx)) 'the notice itself does not read as a hold'
Check ((Format-SpecProgress -Plan $pl -Who 'Owner') -match 'Approving this spec approves its slices' -and (Format-SpecProgress -Plan $pl) -match '/hold') 'the spec checklist explains auto-approval and /hold'

# ---- plan budget (the ops hub's plan-budget.json; fails open) and the precheck under it ----------------
$now = [datetime]::Parse('2026-11-20T18:00:00Z', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal')
function Bj { param([string]$V = 'normal', [string]$Gen = '2026-11-20T17:50:00Z', $Schema = 1, $Stale = 30, [string[]]$Reasons = @('5h 91% >= 85'))
    ([ordered]@{ schema = $Schema; generatedAt = $Gen; verdict = $V; reasons = @($Reasons); fiveHour = [ordered]@{ pct = 91; resetsAt = '2026-11-20T20:00:00Z'; observedAt = $Gen }; weekly = $null; thresholds = @{}; staleAfterMinutes = $Stale } | ConvertTo-Json -Depth 5) }
foreach ($v in 'normal', 'no-opus', 'hold') {
    $b = Get-PlanBudgetVerdict -Text (Bj $v) -NowUtc $now
    Check ($b.Verdict -eq $v -and -not $b.Warn -and $b.Reason -match "plan budget $v" -and $b.Reason -match '5h 91%' -and $b.Reason -match '10 min ago') "fresh $v -> $v ($($b.Reason))"
}
$b = Get-PlanBudgetVerdict -Text (Bj 'NO-OPUS ') -NowUtc $now
Check ($b.Verdict -eq 'no-opus') 'verdict is case/space tolerant'
foreach ($c in @(
        @{ T = $null; W = 'missing' }, @{ T = ''; W = 'missing' }, @{ T = '{not json'; W = 'not valid JSON' },
        @{ T = (Bj 'hold' -Schema 2); W = 'schema' }, @{ T = '{"verdict":"hold","generatedAt":"2026-11-20T17:59:00Z"}'; W = 'schema' },
        @{ T = (Bj 'pause'); W = 'unknown' }, @{ T = (Bj 'hold' -Gen 'yesterday'); W = 'generatedAt' },
        @{ T = (Bj 'hold' -Gen '2026-11-20T17:29:00Z'); W = 'stale' })) {
    $b = Get-PlanBudgetVerdict -Text $c.T -NowUtc $now
    Check ($b.Verdict -eq 'normal' -and $b.Warn -and $b.Reason -match $c.W -and $b.Reason -match 'fail open') "fails open: $($c.W) -> normal + WARN ($($b.Reason))"
}
$b = Get-PlanBudgetVerdict -Text (Bj 'hold' -Gen '2026-11-20T17:31:00Z') -NowUtc $now
Check ($b.Verdict -eq 'hold') '29 min old with staleAfterMinutes 30 -> still used'
$b = Get-PlanBudgetVerdict -Text (Bj 'hold' -Gen '2026-11-20T17:00:00Z' -Stale 90) -NowUtc $now
Check ($b.Verdict -eq 'hold') 'staleAfterMinutes from the file is honoured (60 min old, stale after 90)'
$b = Get-PlanBudgetVerdict -Text (Bj 'hold' -Gen '2026-11-20T17:20:00Z' -Stale 0) -NowUtc $now
Check ($b.Verdict -eq 'normal' -and $b.Warn) 'staleAfterMinutes missing/0 -> default 30 (40 min old is stale)'
$b = Get-PlanBudgetVerdict -Text (Bj 'hold' -Gen '2026-11-20T10:50:00-07:00') -NowUtc $now
Check ($b.Verdict -eq 'hold') 'generatedAt with an offset is converted to UTC'
$b = Get-PlanBudgetVerdict -Text $null -ReadError 'access denied' -NowUtc $now
Check ($b.Verdict -eq 'normal' -and $b.Warn -and $b.Reason -match 'unreadable') 'unreadable -> normal + WARN'
$b = Get-PlanBudgetVerdict -Text (Bj 'hold') -NowUtc $now -Ignore
Check ($b.Verdict -eq 'normal' -and -not $b.Warn -and $b.Reason -match 'IgnoreBudget') '-IgnoreBudget -> normal, no warning, even on hold'
$b = Get-PlanBudgetVerdict -Text (Bj 'hold' -Reasons @('x <!-- innovation-loop --> @someone')) -NowUtc $now
Check ($b.Reason -notmatch '<!--' -and $b.Reason -notmatch '@') 'reasons are made safe (no markers, no mentions)'

# verdict x model
$opus = 'claude-opus-5-5'; $son = 'claude-sonnet-5-5'
Check ((Test-BudgetAllowsModel 'normal' $opus) -and (Test-BudgetAllowsModel 'normal' $son)) 'normal: every model'
Check (-not (Test-BudgetAllowsModel 'no-opus' $opus) -and (Test-BudgetAllowsModel 'no-opus' $son)) 'no-opus: Sonnet yes, Opus no'
Check (-not (Test-BudgetAllowsModel 'no-opus' 'opus') -and -not (Test-BudgetAllowsModel 'no-opus' 'claude-opus-5-5[1m]')) 'no-opus: aliases and suffixes still count as Opus'
Check (-not (Test-BudgetAllowsModel 'no-opus' '')) 'no-opus: an empty model (claude default) counts as Opus'
Check (-not (Test-BudgetAllowsModel 'hold' $son) -and -not (Test-BudgetAllowsModel 'hold' $opus)) 'hold: nothing'

# verdict x session kind (sessions.json shape: builds Opus unless size:small / test-only; propose + review Sonnet)
$cfg = Get-SessionConfig $null
$lo = @{ 12 = @('loop:proposal', 'approved', 'model:opus'); 13 = @('loop:proposal', 'approved', 'size:small'); 14 = @('approved', 'test-only'); 15 = @('loop:proposal', 'approved') }
$sp = Split-BuildableByBudget -Buildable @(12, 13, 14) -LabelsOf $lo -Config $cfg -Verdict 'normal'
Check ((@($sp.Allowed) -join ',') -eq '12,13,14' -and @($sp.Deferred).Count -eq 0) 'normal: every build allowed'
$sp = Split-BuildableByBudget -Buildable @(12, 13, 14) -LabelsOf $lo -Config $cfg -Verdict 'no-opus'
Check ((@($sp.Allowed) -join ',') -eq '13,14' -and (@($sp.Deferred | ForEach-Object { $_.Issue }) -join ',') -eq '12' -and $sp.Deferred[0].Model -eq $opus) 'no-opus: the Opus build is deferred, small/test-only builds run'
$sp = Split-BuildableByBudget -Buildable @(12, 13) -LabelsOf $lo -Config $cfg -Verdict 'no-opus' -Override $son
Check (@($sp.Deferred).Count -eq 0) 'no-opus + run-loop -Model sonnet: every build runs on Sonnet, nothing deferred'
$sp = Split-BuildableByBudget -Buildable @(13) -LabelsOf $lo -Config $cfg -Verdict 'no-opus' -Override $opus
Check (@($sp.Allowed).Count -eq 0) 'no-opus + run-loop -Model opus: even a small build is deferred'
$sp = Split-BuildableByBudget -Buildable @(12, 13) -LabelsOf $lo -Config $cfg -Verdict 'hold'
Check (@($sp.Allowed).Count -eq 0 -and @($sp.Deferred).Count -eq 2) 'hold: no build'
$sp = Split-BuildableByBudget -Buildable @(15, 16, 17) -LabelsOf $lo -Config $cfg -Verdict 'no-opus' -ServerDeploy @(16) -OpusRetry @(17)
Check ((@($sp.Allowed) -join ',') -eq '15' -and (@($sp.Deferred | ForEach-Object { $_.Issue }) -join ',') -eq '16,17') 'no-opus: a plain build runs on Sonnet; the API build and the Opus retry wait'
Check ((Test-BudgetAllowsModel 'no-opus' (Get-SessionModel -Kind 'propose' -Config $cfg)) -and (Test-BudgetAllowsModel 'no-opus' (Get-SessionModel -Kind 'review' -Config $cfg))) 'no-opus: proposal and review sessions (Sonnet) may run'

# the precheck under the budget
function Qb { param([int[]]$B, [int]$Free) [pscustomobject]@{ buildable = @($B); retry = @(); slots = [pscustomobject]@{ free = $Free; cap = 5; awaitingReview = @() }; waitingOnOwner = @() } }
$hold = [pscustomobject]@{ Verdict = 'hold'; Reason = 'plan budget hold (5h 97%)'; Warn = $false }
$noop = [pscustomobject]@{ Verdict = 'no-opus'; Reason = 'plan budget no-opus (5h 88%)'; Warn = $false }
$p = Get-PrecheckDecision -Queue (Qb @(12) 3) -Mode 'FULL' -Budget $hold
Check (-not $p.Launch -and $p.Hold -and $p.Reason -match 'hold') "hold: no launch even with work queued ($($p.Reason))"
Check (-not (Get-PrecheckDecision -Queue $null -Mode 'FULL' -Budget $hold).Launch) 'hold: no launch even when the queue check failed'
Check (-not (Get-PrecheckDecision -Queue (Qb @() 0) -Mode 'PRODUCT_REVIEW' -Budget $hold).Launch) 'hold: not even the product review'
$p = Get-PrecheckDecision -Queue (Qb @(12) 0) -Mode 'FULL' -Budget $noop -Deferred @(12)
Check (-not $p.Launch -and -not $p.Hold -and $p.Reason -match '0 buildable' -and $p.Reason -match 'deferred by the plan budget \(#12\)') "no-opus, only an Opus build, no slot -> no launch ($($p.Reason))"
Check ((Get-PrecheckDecision -Queue (Qb @(12, 13) 0) -Mode 'FULL' -Budget $noop -Deferred @(12)).Launch) 'no-opus + a small build -> launch'
Check ((Get-PrecheckDecision -Queue (Qb @(12) 2) -Mode 'FULL' -Budget $noop -Deferred @(12)).Launch) 'no-opus + a free slot -> launch for proposals'
Check (-not (Get-PrecheckDecision -Queue (Qb @() 2) -Mode 'FULL' -Budget $noop -PhaseBAllowed $false).Launch) 'no-opus + proposals configured on Opus -> no launch'
Check (-not (Get-PrecheckDecision -Queue (Qb @() 0) -Mode 'PRODUCT_REVIEW' -Budget $noop -PhaseBAllowed $false).Launch) 'no-opus + review on Opus -> no launch'
$p = Get-PrecheckDecision -Queue (Qb @(12) 0) -Mode 'FULL'
Check ($p.Launch -and -not $p.Hold) 'no budget given -> behaves as before'
$fo = Get-PlanBudgetVerdict -Text $null -NowUtc $now
Check ((Get-PrecheckDecision -Queue (Qb @(12) 0) -Mode 'FULL' -Budget $fo).Launch) 'missing file -> normal -> launch as before'
# ---- a slice waits on an open Manual earlier slice (Get-SliceWaitDecision): skipped, never failed ------------
$man = "`n## Scope`n**Manual / needs Ve**: new stored data (rule 8). The loop will not build this."
$m2 = VsIss 111 'Value history design and storage decision' @('loop:proposal', 'approved') -Body (VsBody 2 -Extra $man)
$m3 = VsIss 112 'Snapshot writer' @('loop:proposal', 'approved') -Body (VsBody 3 -Extra $man)
$a4 = VsIss 117 'Value over time chart on Home' @('loop:proposal', 'approved') -Body (VsBody 4) -Created '2026-11-22T00:24:55Z'
function Sw { param($I, [object[]]$Issues) Get-SliceWaitDecision -Issue $I -Issues $Issues -Owner $owner -Marker $mk }
$w = Sw $a4 @($vsSpec, $s1, $m2, $m3, $a4)
Check ($w.Linked -and $w.Waiting -and $w.Spec -eq 108 -and $w.K -eq 4 -and (@($w.Blockers | ForEach-Object { "$($_.K):$($_.Issue)" }) -join ',') -eq '2:111,3:112') "label-approved slice 4 with open Manual slices 2 and 3 -> waits on both, in order (got $(@($w.Blockers | ForEach-Object { "$($_.K):$($_.Issue)" }) -join ','))"
Check ($w.Reason -match 'waiting on slices 2 \(#111, Manual\) and 3 \(#112, Manual\) of spec #108') "wait reason names the blockers (got: $($w.Reason))"
Check (-not ($w.Reason -match 'loop:failed|fail')) 'waiting is not a failure'
$w = Sw $a4 @($vsSpec, $s1, (VsIss 111 'x' @('loop:proposal', 'approved') -Body (VsBody 2 -Extra $man) -State 'CLOSED'), $m3, $a4)
Check ($w.Waiting -and (@($w.Blockers | ForEach-Object { $_.Issue }) -join ',') -eq '112') 'slice 2 closed, slice 3 still open and Manual -> still waits, on slice 3 only'
$w = Sw $a4 @($vsSpec, $s1, (VsIss 111 'x' -Body (VsBody 2 -Extra $man) -State 'CLOSED'), (VsIss 112 'x' -Body (VsBody 3 -Extra $man) -State 'CLOSED'), $a4)
Check ($w.Linked -and -not $w.Waiting -and @($w.Blockers).Count -eq 0) 'every earlier Manual slice closed -> builds (no wait)'
$w = Sw $a4 @($vsSpec, $s1, $s2, $s3, $a4)
Check (-not $w.Waiting) 'earlier slices open but NOT Manual -> existing behaviour (no wait for a label-approved slice)'
$w = Sw $m2 @($vsSpec, $s1, $m2, $m3, $a4)
Check (-not $w.Waiting) 'only EARLIER slices count: a later Manual slice never blocks an earlier one'
$w = Sw $a4 @($vsSpec, $s1, (VsIss 111 'x' -Body (VsBody 2 -Extra $man) -By 'stranger'), (VsIss 112 'x' -Body ("Part of #108 (slice 3 of 4)" + $man)), $a4)
Check (-not $w.Waiting) 'a "Manual" slice opened by someone else, or without the loop marker, is data and blocks nothing'
$w = Sw $a4 @($vsSpec, (VsIss 140 'x' -Body (VsBody 2 -Spec 139 -Extra $man)), $a4)
Check (-not $w.Waiting) 'a Manual slice of ANOTHER spec does not block'
$plain = VsIss 130 'Faster binder grid' @('loop:proposal', 'approved') -Body "$mk`n## What`nno spec."
$w = Sw $plain @($vsSpec, $m2, $m3, $plain)
Check (-not $w.Linked -and -not $w.Waiting) 'a non-slice issue is unaffected'
# the via-spec path already holds a later slice behind an open Manual one (rule 3); unchanged
$d = Vs $s4 -Issues @($vsSpec, $s1, $m2, $m3, $s4)
Check (-not $d.Eligible -and (Why $d) -match 'earlier slice 2 \(#111\) is Manual') 'auto-approved slices: an open Manual earlier slice still holds them (rule 3, unchanged)'
# the one notice
$nt = Format-SliceWaitNotice -Blockers @([pscustomobject]@{ K = 2; Issue = 111 }) -Marker $mk
Check ($nt.StartsWith($mk) -and $nt.Contains($script:SliceWaitMarker) -and $nt -match 'Waiting on slice 2 \(#111, Manual\)\. It will build once that slice is closed\.') "notice text, one blocker (got: $nt)"
$nt2 = Format-SliceWaitNotice -Blockers @([ordered]@{ k = 2; issue = 111 }, [ordered]@{ k = 3; issue = 112 }) -Marker $mk
Check ($nt2 -match 'Waiting on slices 2 \(#111, Manual\) and 3 \(#112, Manual\)\. It will build once those slices are closed\.') "notice text, two blockers (queue JSON shape k/issue) (got: $nt2)"
Check (-not ($nt -match $script:HoldRx)) 'the notice does not read as a hold'
Check (-not (Test-SliceWaitNoticed -Comments @() -Owner $owner -Marker $mk)) 'no comment yet -> not noticed'
Check (Test-SliceWaitNoticed -Comments @((VsCmt $nt)) -Owner $owner -Marker $mk) 'the runner''s notice on the slice -> noticed (never posted again)'
Check (-not (Test-SliceWaitNoticed -Comments @((VsCmt $nt -By 'stranger')) -Owner $owner -Marker $mk)) 'a copy of the notice by someone else does not count'
$qw = @([pscustomobject]@{ issue = 117; noticed = $false; blockers = @() }, [pscustomobject]@{ issue = 118; noticed = $true; blockers = @() })
$posted = @{}
$first = @(Select-SliceWaitNotices -Waiting $qw -Posted $posted)
Check ((@($first | ForEach-Object { $_.issue }) -join ',') -eq '117') 'notice goes only to a waiting slice not noticed yet'
$posted[117] = $true
Check (@(Select-SliceWaitNotices -Waiting $qw -Posted $posted).Count -eq 0) 'posted once: a second queue check in the same run posts nothing'
Check (@(Select-SliceWaitNotices -Waiting @([pscustomobject]@{ issue = 117; noticed = $true }) -Posted @{}).Count -eq 0) 'a later run sees noticed = true: posts nothing'
Check (@(Select-SliceWaitNotices -Waiting @() -Posted @{}).Count -eq 0) 'nothing waiting -> nothing posted'
# waiting slices are not buildable, so they start no session ($0) and never reach the build outcome rules
$pre = Get-PrecheckDecision -Queue (Q @() 0) -Mode 'FULL'
Check (-not $pre.Launch) "only a waiting slice (not in buildable) and no free slot -> no claude session (got: $($pre.Reason))"

# ---- design skills (sessions.json options.designSkills) ---------------------------------------------
Check (-not (Get-DesignSkillsEnabled $null)) 'designSkills: no sessions.json -> off'
Check (-not (Get-DesignSkillsEnabled ('{"build":{}}' | ConvertFrom-Json))) 'designSkills: no options -> off'
Check (Get-DesignSkillsEnabled ('{"options":{"designSkills":true}}' | ConvertFrom-Json)) 'designSkills: true -> on'
Check (-not (Get-DesignSkillsEnabled ('{"options":{"designSkills":"no"}}' | ConvertFrom-Json))) 'designSkills: "no" -> off'
$dsPrefix = 'INNOVATION_LOOP_' + ("$($cfg.project)".ToUpperInvariant() -replace '-', '_')
$d = Get-DesignSkillsSetup -Enabled $false -EnvPrefix $dsPrefix
Check (-not $d.Ok -and @($d.Allow).Count -eq 0 -and $d.Env["$($dsPrefix)_DESIGN_SKILLS"] -eq '') 'design off -> no rules, guard flag cleared'
$dtmp = Join-Path $tmp 'design'
New-Item -ItemType Directory -Force (Join-Path $dtmp 'imp\reference'), (Join-Path $dtmp 'py') | Out-Null
foreach ($f in 'engine.exe', 'search.py', 'imp\reference\craft-floor.md', 'py\python.exe') { [IO.File]::WriteAllText((Join-Path $dtmp $f), 'x') }
$tp = @{ Engine = (Join-Path $dtmp 'engine.exe'); EngineSha256 = 'AB12'; Impeccable = (Join-Path $dtmp 'imp'); Search = (Join-Path $dtmp 'search.py'); PythonDir = (Join-Path $dtmp 'py') }
$d = Get-DesignSkillsSetup -Enabled $true -EnvPrefix $dsPrefix -Paths $tp -EngineHash 'ab12'
$rules = @($d.Allow) -join ' | '
Check ($d.Ok -and $d.Env["$($dsPrefix)_DESIGN_SKILLS"] -eq '1' -and $d.Env['IMPECCABLE_BIN'] -eq $tp.Engine -and $d.PathPrepend -eq $tp.PythonDir) "design on -> guard flag, IMPECCABLE_BIN, python on PATH ($($d.Reason))"
Check ($d.Env['IMPECCABLE_NO_TELEMETRY'] -eq '1' -and $d.Env['IMPECCABLE_NO_UPDATE_CHECK'] -eq '1' -and $d.Env['IMPECCABLE_HOOK_DISABLED'] -eq '1') 'design on -> engine off the network, hook disabled'
Check (-not $d.Env.Contains('DO_NOT_TRACK')) 'design on never sets DO_NOT_TRACK (claude then offers no PowerShell tool; cardlens PR #188)'
$rlT = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run-loop.ps1')); $grT = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'gate-rules.ps1'))
Check ($grT -notmatch "DO_NOT_TRACK = '1'" -and $rlT -notmatch "DO_NOT_TRACK = '1'|env:DO_NOT_TRACK =") 'no loop script sets DO_NOT_TRACK'
Check ($rlT -match 'claude offered NO PowerShell tool') 'run-loop.ps1 flags a session whose init tool list lacks PowerShell'
Check ($rules -match ' context\)' -and $rules -match ' shot \*' -and $rules -match ' detect \*' -and $rules -match 'python .*search\.py \*') "design on -> context/shot/detect/search rules"
Check ($rules -notmatch 'hooks|pin|live|doctor|foundations|persist|\(python \*\)') 'design: no rule for hooks/pin/live/doctor/foundations or bare python'
Check (-not (Get-DesignSkillsSetup -Enabled $true -EnvPrefix $dsPrefix -Paths $tp -EngineHash 'ffff').Ok) 'design: engine hash mismatch -> off'
Remove-Item -LiteralPath (Join-Path $dtmp 'py\python.exe')
Check (-not (Get-DesignSkillsSetup -Enabled $true -EnvPrefix $dsPrefix -Paths $tp -EngineHash 'ab12').Ok) 'design: missing python.exe -> off'
Check ((Add-DesignSkillsSection -Sections @(0, 1, 2, 3, 4, 6) -Kind 'build' -On $true) -contains 7) 'design: build + on -> section 7'
Check ((Add-DesignSkillsSection -Sections @(0, 1, 2, 5, 6) -Kind 'propose' -On $true) -contains 7) 'design: propose + on -> section 7'
Check (-not ((Add-DesignSkillsSection -Sections @(0, 1, 2, 5, 6) -Kind 'propose' -On $false) -contains 7)) 'design: off -> no section 7'
$dmd = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'LOOP.md'))
Check ((Get-LoopMdSections -Text $dmd -Sections @(0, 7)) -match '## 7\. Design skills') 'LOOP.md has the design skills section 7'
Check ((Get-LoopMdSections -Text $dmd -Sections @(0, 1, 2, 5, 6)) -notmatch 'impeccable') 'a prompt without section 7 never mentions the skills'
$gm = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'guard.mjs'))
foreach ($k in 'Engine', 'Search') { Check ($gm.Contains('"' + $script:DesignSkillPaths[$k].ToLowerInvariant().Replace('\', '\\') + '"')) "guard.mjs pins the same design $k path as gate-rules.ps1" }
Check ($dmd.Contains($script:DesignSkillPaths.Engine)) 'LOOP.md names the pinned engine path'

# ---- bare commands: every session is told how the allow rules match (cardlens run 20261122-124809) -------------
foreach ($secs in @(@(0, 1, 2, 3, 4, 6), @(0, 1, 2, 5, 6))) {
    $t = Get-LoopMdSections -Text $dmd -Sections $secs
    Check ($t -match 'Bare commands' -and $t -match 'never wrap it in `\( \.\.\. \)`' -and $t -match 'retry ONCE') "prompt for sections $($secs -join ',') carries the bare-commands rule"
}

# ---- comments by the owner's interactive agents (<!-- claude-agent -->) ------------------------------------------
function AgC { param([long]$Id, [string]$Body, [string]$By = $owner, [string]$At = '2026-11-22T10:00:00Z') [pscustomobject]@{ id = $Id; body = $Body; created_at = $At; user = [pscustomobject]@{ login = $By } } }
$agc = @((AgC 11 'Please keep the old colours.'), (AgC 12 "<!-- claude-agent -->`nUnblocked for a rebuild."), (AgC 13 "$mk`nloop progress"), (AgC 14 'drive-by' -By 'stranger'))
Check ((@(Get-OwnerAdjustmentIds -Comments $agc -Owner $owner -Marker $mk) -join ',') -eq '11') 'adjustments: the owner''s own comments only (no agent, loop or stranger comments)'
Check (@(Get-FailureRecords -Comments @((AgC 15 "<!-- claude-agent -->`n$mk`n$(Format-FailureMarker 'tests')" -At '2026-11-17T10:00:00Z')) -Owner $owner -Marker $mk -Since '2026-11-16T10:00:00Z').Count -eq 0) 'an agent comment quoting a failure marker is not a loop failure record'
Check (-not (Test-SliceWaitNoticed -Comments @((AgC 16 "<!-- claude-agent -->`n$mk`n$($script:SliceWaitMarker)")) -Owner $owner -Marker $mk)) 'an agent comment quoting the waiting notice does not count as the loop''s notice'
Check (Test-SliceWaitNoticed -Comments @((AgC 17 "$mk`n$($script:SliceWaitMarker)")) -Owner $owner -Marker $mk) 'the loop''s own notice still counts'
$cfg = Get-SessionConfig $null
# ---- four builds per run (2026-11-23): MaxBuilds 4, a 360-min run, 100 min left for each build after the first ------
$n = Get-NextBuildDecision -Buildable @(1, 2, 3, 4, 5) -Done @() -RemainingMinutes 360
Check ($n.Start -and $n.Reason -match 'of at most 4') "default MaxBuilds is 4 ($($n.Reason))"
# simulate builds of 75 min (typical) and 85 min (slow) against the 360-min budget: all four start
foreach ($len in 75, 85) {
    $done = @(); $left = 360.0; $started = 0
    while ($true) {
        $n = Get-NextBuildDecision -Buildable @(1, 2, 3, 4, 5) -Done $done -RemainingMinutes $left
        if (-not $n.Start) { break }
        $started++; $done += (D $n.Issue 'deployed'); $left -= $len
    }
    Check ($started -eq 4 -and $n.Reason -match 'MaxBuilds \(4\) reached') "360-min run, builds of $len min: 4 builds, then MaxBuilds ($started started; $($n.Reason))"
}
$done = @(); $left = 360.0; $started = 0
while ($true) { $n = Get-NextBuildDecision -Buildable @(1, 2, 3, 4, 5) -Done $done -RemainingMinutes $left; if (-not $n.Start) { break }; $started++; $done += (D $n.Issue 'deployed'); $left -= 110 }
Check ($started -eq 3 -and $n.Reason -match 'min left') "builds of 110 min (CI fix rounds): the fourth is not started with $([int]$left) min left ($started started)"
$n = Get-NextBuildDecision -Buildable @(1, 2, 3, 4) -Done @((D 1 'deployed'), (D 2 'deployed'), (D 3 'deployed')) -RemainingMinutes 99
Check (-not $n.Start -and $n.Reason -match 'needs 100') 'a later build needs 100 min left'
$n = Get-NextBuildDecision -Buildable @(1, 2, 3, 4) -Done @((D 1 'deployed'), (D 2 'rolled-back')) -RemainingMinutes 300
Check (-not $n.Start -and $n.Reason -match 'rolled-back') 'a rollback still ends Phase A with time and builds left'
$n = Get-NextBuildDecision -Buildable @(1, 2) -Done @(D 1 'deployed') -RemainingMinutes 130 -SecondBuildMinMinutes 120
Check ($n.Start) '-SecondBuildMinMinutes is an alias of -NextBuildMinMinutes'
# the run budget stays inside the scheduled task's ExecutionTimeLimit
$tb = Get-RunTimeBudget -Requested 360 -TaskLimitMinutes 420
Check ($tb.Minutes -eq 360) "7-h task limit: the full 360 min ($($tb.Reason))"
$tb = Get-RunTimeBudget -Requested 360 -TaskLimitMinutes 300
Check ($tb.Minutes -eq 270 -and $tb.Reason -match 'cut') "5-h task limit (not yet reinstalled): cut to 270 ($($tb.Reason))"
Check ((Get-RunTimeBudget -Requested 360 -TaskLimitMinutes 0).Minutes -eq 360) 'task limit unknown: the request stands'
Check ((Get-RunTimeBudget -Requested 360 -TaskLimitMinutes 60).Minutes -eq 60) 'never below 60 min'
$real = Join-Path $PSScriptRoot 'run-loop.ps1'
$rl = [IO.File]::ReadAllText($real)
# drain.json progress: Get-Variable -ValueOnly emits an array as ONE object, so run-loop must unroll it before counting
$gvT = { param([string]$N) Get-Variable -Name $N -ValueOnly -ErrorAction SilentlyContinue }
$builtT = @((D 1 'deployed'), (D 2 'deployed'), (D 3 'skipped'))
& { $built = $builtT; Check (@(@(& $gvT 'built' | ForEach-Object { $_ } | Where-Object { $_ }) | Where-Object { $_.Outcome -eq 'deployed' }).Count -eq 2) 'unrolled Get-Variable value counts each build' }
Check ($rl -match "& \`$gv 'built' \| ForEach-Object \{ \`$_ \}") 'run-loop.ps1 unrolls the builds before counting drain progress'
Check ($rl -match '\[ValidateRange\(1, 6\)\]\[int\]\$MaxBuilds = 4' -and $rl -match '\[int\]\$TimeoutMinutes = 360' -and $rl -match 'NextBuildMinMinutes = 100') 'run-loop.ps1 defaults: MaxBuilds 4, 360 min, 100 min for later builds'
$it = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install-task.ps1'))
Check ($it -match "-Daily -At \`$At\s*\n(?:\s*#.*\n)?\s*\`$settings = New-ScheduledTaskSettingsSet @settingsCommon -ExecutionTimeLimit \(New-TimeSpan -Hours 7\)") 'install-task.ps1 gives the daily task 7 h (360-min run + reporting)'

# ---- the build model (2026-11-23: Sonnet by default, Opus only when needed) ---------------------------------------
$bm = Get-BuildModelChoice -Labels @('loop:proposal', 'approved') -Config $cfg
Check ($bm.Model -eq 'claude-sonnet-5-5' -and -not $bm.Opus) "plain approved issue -> Sonnet ($($bm.Why))"
$bm = Get-BuildModelChoice -Labels @('loop:proposal', 'approved', 'model:opus') -Config $cfg
Check ($bm.Model -eq 'claude-opus-5-5' -and $bm.Opus -and $bm.Why -match 'model:opus') "model:opus label -> Opus ($($bm.Why))"
$bm = Get-BuildModelChoice -Labels @('loop:proposal', 'approved') -Config $cfg -ServerDeploy $true
Check ($bm.Model -eq 'claude-opus-5-5' -and $bm.Why -match 'server') "proposal deploys the server -> Opus ($($bm.Why))"
$bm = Get-BuildModelChoice -Labels @('loop:proposal', 'approved', 'loop:failed') -Config $cfg -OpusRetry $true
Check ($bm.Model -eq 'claude-opus-5-5' -and $bm.Why -match 'retry') "retry of a failed Sonnet build -> Opus ($($bm.Why))"
foreach ($sl in 'size:small', 'test-only') {
    $bm = Get-BuildModelChoice -Labels @('approved', $sl) -Config $cfg
    Check ($bm.Model -eq 'claude-sonnet-5-5' -and $bm.Why -match [regex]::Escape($sl)) "$sl stays on Sonnet"
}
Check ((Get-BuildModelChoice -Labels @('approved', 'size:small', 'model:opus') -Config $cfg).Opus) 'model:opus beats size:small (Ve chose Opus)'
Check ((Get-BuildModelChoice -Labels @('approved', 'model:opus') -Config $cfg -Override 'x-model').Model -eq 'x-model') '-Model override beats model:opus'
Check ((Get-SessionModel -Kind 'build' -Labels @('approved') -Config $cfg -ServerDeploy $true) -eq 'claude-opus-5-5') 'Get-SessionModel passes the server flag through'
$cfgO = Get-SessionConfig ('{"build":{"opusModel":"claude-opus-9","opusLabels":["needs-opus"]}}' | ConvertFrom-Json)
Check ((Get-BuildModelChoice -Labels @('needs-opus') -Config $cfgO).Model -eq 'claude-opus-9' -and -not (Get-BuildModelChoice -Labels @('model:opus') -Config $cfgO).Opus) 'sessions.json opusModel / opusLabels are honoured'
# server deploy known up front (portfolio: the API jar on server-pc)
Check (Test-ProposalNeedsServer -Labels @('loop:proposal', 'approved', 'area:backend')) 'area:backend -> server deploy known up front'
Check (Test-ProposalNeedsServer -Labels @('area:both')) 'area:both -> server deploy'
Check (-not (Test-ProposalNeedsServer -Labels @('area:frontend') -Body "## What deploys`nfront end (GitHub Pages)`n## Scope`nIn scope.")) 'area:frontend, front end only -> no'
Check (Test-ProposalNeedsServer -Labels @('area:frontend') -Body "## What deploys`nAPI (server-pc jar; files: ContactController.java)`n## Scope`nx") 'What deploys names the API -> yes'
Check (Test-ProposalNeedsServer -Body "## What deploys`nboth: API first, then front end`n## Scope`nx") 'What deploys: both -> yes'
Check (-not (Test-ProposalNeedsServer -Body "## Why`nThe API is slow.`n## Scope`nx")) 'no What deploys section and no area -> no (a mention elsewhere does not count)'
$bm = Get-BuildModelChoice -Labels @('approved', 'area:backend') -Config $cfg -ServerDeploy (Test-ProposalNeedsServer -Labels @('approved', 'area:backend'))
Check ($bm.Opus -and $bm.Why -match 'API') "an area:backend build -> Opus ($($bm.Why))"
# ---- the Opus retry of a failed Sonnet build ----------------------------------------------------------------------
function Frm { param([string]$Class, [string]$Model, [string]$Outcome = 'failed') [pscustomobject]@{ Class = $Class; Outcome = $Outcome; Model = $Model } }
$Lf = @('loop:proposal', 'approved', 'loop:failed')
foreach ($c in 'tests', 'other', 'max-turns', 'max-budget') {
    $d = Get-RetryDecision -Labels $Lf -Failures @(Frm $c 'claude-sonnet-5-5')
    Check ($d.Retry -and $d.Opus -and $d.Reason -match 'on Opus') "$c on Sonnet -> one retry on Opus ($($d.Reason))"
    $d = Get-RetryDecision -Labels $Lf -Failures @(Frm $c 'claude-opus-5-5')
    Check (-not $d.Opus) "$c on Opus -> no escalation"
}
Check (-not (Get-RetryDecision -Labels $Lf -Failures @(Frm 'tests' 'claude-opus-5-5')).Retry) 'tests on Opus -> waits for Ve, as before'
Check (-not (Get-RetryDecision -Labels $Lf -Failures @(Frm 'tests' '')).Retry) 'tests with no model in the marker (old markers) -> waits for Ve'
foreach ($c in 'ci-infra', 'ci-timeout', 'gap-refused', 'deploy-unavailable', 'out-of-time', 'timeout') {
    $d = Get-RetryDecision -Labels $Lf -Failures @(Frm $c 'claude-sonnet-5-5')
    Check ($d.Retry -and -not $d.Opus) "$c (infrastructure) on Sonnet -> retried on the same model"
}
foreach ($c in 'guard-refused', 'scope', 'session-ended') {
    Check (-not (Get-RetryDecision -Labels $Lf -Failures @(Frm $c 'claude-sonnet-5-5')).Retry) "$c on Sonnet -> never retried"
}
Check (-not (Get-RetryDecision -Labels $Lf -Failures @(Frm 'tests' 'claude-sonnet-5-5' 'rolled-back')).Retry) 'rolled back on Sonnet -> no retry (something went live)'
Check (-not (Get-RetryDecision -Labels ($Lf + 'loop:retried') -Failures @(Frm 'tests' 'claude-sonnet-5-5')).Retry) 'already retried -> no second retry'
Check (-not (Get-RetryDecision -Labels $Lf -Failures @((Frm 'tests' 'claude-sonnet-5-5'), (Frm 'tests' 'claude-opus-5-5'))).Retry) 'failed again on Opus -> waits for Ve'
# the marker round trip
$mkr = Format-FailureMarker -Class 'tests' -Outcome 'failed' -Model 'claude-sonnet-5-5'
Check ($mkr -eq '<!-- innovation-loop:failure class=tests outcome=failed model=claude-sonnet-5-5 -->') "marker names the model ($mkr)"
Check ((Format-FailureMarker -Class 'tests' -Model 'bad model;x') -eq '<!-- innovation-loop:failure class=tests outcome=failed -->') 'an unsafe model string is left out'
$frs = @(Get-FailureRecords -Comments @([pscustomobject]@{ id = 9; created_at = '2026-11-23T10:00:00Z'; user = [pscustomobject]@{ login = 'vekbui96' }; body = "$mk`n$mkr`n## Synopsis" }) -Owner 'vekbui96' -Marker $mk)
Check ($frs.Count -eq 1 -and $frs[0].Model -eq 'claude-sonnet-5-5' -and $frs[0].Class -eq 'tests') 'Get-FailureRecords reads the model'
$frs = @(Get-FailureRecords -Comments @([pscustomobject]@{ id = 9; created_at = '2026-11-23T10:00:00Z'; user = [pscustomobject]@{ login = 'vekbui96' }; body = "$mk`n<!-- innovation-loop:failure class=tests outcome=failed -->" }) -Owner 'vekbui96' -Marker $mk)
Check ($frs.Count -eq 1 -and $frs[0].Model -eq '') 'an old marker without a model still parses'

# ---- the queue drain (approval watcher) ---------------------------------------------------------------------------
$now = [datetime]'2026-11-23T20:00:00'
function Dr { param([int[]]$B = @(181, 192), [int[]]$Op = @(), [int]$Ago = 30, [object[]]$H = $null, [bool]$Rb = $false, [bool]$Ve = $false, [string]$Cap = '', [string]$Run = '20261123-150000', [int]$Prog = 1)
    $end = $now.AddMinutes(-$Ago).ToString('o')
    if ($null -eq $H) { $H = @([pscustomobject]@{ runId = $Run; endedAt = $end; head = $(if ($B.Count) { $B[0] } else { 0 }); progress = $Prog; result = 'OK'; rolledBack = $Rb }) }
    ([ordered]@{ schema = 1; runId = $Run; endedAt = $end; result = 'OK'; buildable = @($B); head = $(if ($B.Count) { $B[0] } else { 0 }); needsOpus = @($Op); progress = $Prog; rolledBack = $Rb; needsVe = $Ve; buildCapped = $Cap; history = @($H) } | ConvertTo-Json -Depth 5 | ConvertFrom-Json) }
$dd = Get-DrainDecision -Drain (Dr) -Now $now -Repo 'vekbui96/cardlens'
Check ($dd.Start -and $dd.Key -eq 'drain:vekbui96/cardlens:20261123-150000') "buildable + idle -> start ($($dd.Reason))"
Check (-not (Get-DrainDecision -Drain (Dr) -Now $now -Running $true).Start) 'a run holds the lock / task running -> no'
Check (-not (Get-DrainDecision -Drain (Dr) -Now $now -Verdict 'hold').Start) 'plan budget hold -> no'
Check (-not (Get-DrainDecision -Drain (Dr -Op @(181, 192)) -Now $now -Verdict 'no-opus').Start) 'no-opus and every buildable issue needs Opus -> no'
Check ((Get-DrainDecision -Drain (Dr -Op @(181)) -Now $now -Verdict 'no-opus').Start) 'no-opus but a Sonnet build is buildable -> start'
Check ((Get-DrainDecision -Drain (Dr -Op @(181, 192)) -Now $now -Verdict 'normal').Start) 'normal: Opus builds drain too'
Check (-not (Get-DrainDecision -Drain (Dr -B @()) -Now $now).Start) 'nothing buildable -> no'
Check (-not (Get-DrainDecision -Drain (Dr -Ago 5) -Now $now -IdleMinutes 15).Start) 'the last run ended 5 min ago -> not yet'
Check ((Get-DrainDecision -Drain (Dr -Ago 16) -Now $now -IdleMinutes 15).Start) '16 min idle -> start'
Check (-not (Get-DrainDecision -Drain (Dr) -Now $now -Repo 'r' -Done @('drain:r:20261123-150000')).Start) 'one drain run per finished run'
Check (-not (Get-DrainDecision -Drain $null -Now $now).Start -and -not (Get-DrainDecision -Drain ([pscustomobject]@{ schema = 2; runId = 'x' }) -Now $now).Start) 'no / unknown drain state -> no'
Check (-not (Get-DrainDecision -Drain (Dr -Ve $true) -Now $now).Start) 'uncertain deploy (needs Ve) -> never'
Check (-not (Get-DrainDecision -Drain (Dr -Cap 'daily cap reached') -Now $now).Start) 'daily build cap reached today -> no'
Check ((Get-DrainDecision -Drain (Dr -Cap 'daily cap reached' -Ago 1500) -Now $now).Start) 'capped yesterday -> start today'
# repeated failure on the same queue head -> back off 2 h
$stuckH = @([pscustomobject]@{ runId = 'a'; endedAt = $now.AddMinutes(-200).ToString('o'); head = 181; progress = 0; result = 'FAILED' },
    [pscustomobject]@{ runId = '20261123-150000'; endedAt = $now.AddMinutes(-30).ToString('o'); head = 181; progress = 0; result = 'FAILED' })
$dd = Get-DrainDecision -Drain (Dr -H $stuckH -Prog 0) -Now $now
Check (-not $dd.Start -and $dd.Reason -match 'backing off') "2 runs, same head #181, nothing deployed -> back off ($($dd.Reason))"
Check ((Get-DrainDecision -Drain (Dr -H $stuckH -Prog 0 -Ago 121) -Now $now).Start) 'after the 2-h back-off: one more try'
$okH = @([pscustomobject]@{ runId = 'a'; endedAt = $now.AddMinutes(-200).ToString('o'); head = 181; progress = 0; result = 'FAILED' },
    [pscustomobject]@{ runId = '20261123-150000'; endedAt = $now.AddMinutes(-30).ToString('o'); head = 181; progress = 2; result = 'OK' })
Check ((Get-DrainDecision -Drain (Dr -H $okH) -Now $now).Start) 'the last run made progress -> no back-off'
$movedH = @([pscustomobject]@{ runId = 'a'; endedAt = $now.AddMinutes(-200).ToString('o'); head = 175; progress = 0; result = 'FAILED' },
    [pscustomobject]@{ runId = '20261123-150000'; endedAt = $now.AddMinutes(-30).ToString('o'); head = 181; progress = 0; result = 'FAILED' })
Check ((Get-DrainDecision -Drain (Dr -H $movedH -Prog 0) -Now $now).Start) 'the head moved on (the failed one waits for Ve) -> no back-off'
Check (-not (Get-DrainDecision -Drain (Dr -Rb $true) -Now $now).Start) 'the last run rolled a build back -> back off'
Check ((Get-DrainDecision -Drain (Dr -Rb $true -Ago 130) -Now $now).Start) 'rollback, 2 h later -> one more try'
# the record the runner writes
$s1 = New-DrainState -RunId 'r1' -EndedAt $now.AddMinutes(-60) -Result 'OK' -Buildable @(181, 192, 193) -NeedsOpus @(193) -Progress 4
Check ($s1.schema -eq 1 -and $s1.head -eq 181 -and (@($s1.buildable) -join ',') -eq '181,192,193' -and (@($s1.needsOpus) -join ',') -eq '193' -and @($s1.history).Count -eq 1) 'New-DrainState: the record'
$prev = $s1 | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$s2 = New-DrainState -RunId 'r2' -EndedAt $now.AddMinutes(-30) -Result 'FAILED' -Buildable @(181) -Progress 0 -Previous $prev
Check (@($s2.history).Count -eq 2 -and $s2.history[1].runId -eq 'r2' -and $s2.history[0].runId -eq 'r1') 'history keeps the earlier runs, newest last'
$p = $s2 | ConvertTo-Json -Depth 5 | ConvertFrom-Json
foreach ($k in 3..9) { $p = (New-DrainState -RunId "r$k" -Buildable @(1) -Previous $p) | ConvertTo-Json -Depth 5 | ConvertFrom-Json }
Check (@($p.history).Count -eq 6) 'at most 6 runs of history'
$rt = (New-DrainState -RunId 'x1' -EndedAt $now.AddMinutes(-20) -Buildable @(5) -Progress 1) | ConvertTo-Json -Depth 5 | ConvertFrom-Json
Check ((Get-DrainDecision -Drain $rt -Now $now -Repo 'r').Start) 'a JSON round trip of New-DrainState drains'

# the approval watcher keeps a literal copy of Get-DrainDecision: the two must stay identical (the cardlens loop checks the same copy)
$watchRef = 'C:\Users\Ve Bui\.claude\skills\loop-install\assets\watch-approvals.reference.ps1'
if (Test-Path -LiteralPath $watchRef) {
    $fnD = { param([string]$File) $ast = [Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $fn = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Get-DrainDecision' }, $true) | Select-Object -First 1
        if ($fn) { ($fn.Extent.Text -replace '\s+', ' ').Trim() } else { '' } }
    $mineD = & $fnD "$PSScriptRoot\gate-rules.ps1"; $theirsD = & $fnD $watchRef
    Check ($theirsD -and $mineD -eq $theirsD) 'the approval watcher''s copy of Get-DrainDecision matches gate-rules.ps1 (change both together)'
    Check ([IO.File]::ReadAllText($watchRef) -match 'Drain = ''C:\\Users\\Ve Bui\\\.innovation-loop-portfolio\\state\\drain\.json''') 'the watcher''s solid-website entry names the drain file run-loop.ps1 writes'
}
# ---- a scope refusal that merged nothing does not end Phase A --------------------------------------------------------
Check ((Get-BuildOutcome -Labels @('loop:proposal', 'approved', 'loop:failed') -MarkerOutcome 'skipped') -eq 'skipped') 'scope refusal (loop:failed + skipped), nothing merged -> skipped'
Check ((Get-BuildOutcome -Labels @('loop:proposal', 'approved', 'loop:failed') -MarkerOutcome 'skipped' -Merged $true) -eq 'failed') 'loop:failed + skipped but something was merged -> failed (ends Phase A)'
Check ((Get-BuildOutcome -Labels @('loop:proposal', 'approved', 'loop:failed') -MarkerOutcome 'failed') -eq 'failed') 'a real failure stays failed'
Check ((Get-BuildOutcome -Labels @('loop:proposal', 'approved', 'loop:failed') -MarkerOutcome 'rolled-back') -eq 'rolled-back') 'a rollback stays rolled-back'
$nb = Get-NextBuildDecision -Buildable @(12, 14) -Done @([pscustomobject]@{ Issue = 12; Outcome = 'skipped' }) -RemainingMinutes 240
Check ($nb.Start -and $nb.Issue -eq 14) "after a scope skip the next approved issue is built ($($nb.Reason))"
$nb = Get-NextBuildDecision -Buildable @(12, 14, 15) -Done @([pscustomobject]@{ Issue = 12; Outcome = 'skipped' }, [pscustomobject]@{ Issue = 14; Outcome = 'failed' }) -RemainingMinutes 240
Check (-not $nb.Start) 'a real failure after a skip still ends Phase A'

# ---- the needs-Ve flag ---------------------------------------------------------------------------------------------
Check (-not (Get-NeedsVeBlock -Exists $false).Blocked) 'no flag file -> not blocked'
$nvr = New-NeedsVeRecord -RunId '20261123-183500' -Loop 'x' -Reason "#39: solid-website: merged as abc1234 but the deploy was not verified (deploy: DEPLOY FAILED)" -Issues @(39) -ClearCommand 'clear-needs-ve.ps1 -Clear -Note x'
$nvt = $nvr | ConvertTo-Json -Depth 5
foreach ($k in 'approval', 'request', 'refill', 'drain', 'FULL run', 'PROPOSE_ONLY run') {
    $b = Get-NeedsVeBlock -Exists $true -Text $nvt -Kind $k
    Check ($b.Blocked -and $b.Key -eq 'needs-ve:20261123-183500' -and $b.Reason -like "$k skipped: NEEDS VE*#39*") "flag set -> $k blocked ($($b.Reason))"
}
Check ((Get-NeedsVeBlock -Exists $true -Text ([char]0xFEFF + $nvt)).Blocked) 'a flag file with a BOM still blocks'
$b = Get-NeedsVeBlock -Exists $true -Text 'not json {'
Check ($b.Blocked -and $b.Key -eq 'needs-ve:unreadable') "an unparsable flag file blocks (fail closed: $($b.Reason))"
Check ((Get-NeedsVeBlock -Exists $true -Text '').Blocked) 'an empty flag file blocks'
Check ((Get-NeedsVeBlock -Exists $true -Text '{"schema":1}').Blocked) 'a flag file without a runId blocks'
Check ((Get-NeedsVeBlock -Exists $true -ReadError 'access denied').Blocked) 'a flag file that cannot be read blocks'
Check ((New-NeedsVeRecord -RunId r -Reason ('x' * 600)).reason.Length -le 403) 'the reason is cut to one short line'
$nvDir = Join-Path $tmp 'nv-test'; $nvPath = Join-Path $nvDir 'state\needs-ve.json'
Check (-not (Get-NeedsVeState -Path $nvPath).Blocked) 'Get-NeedsVeState: no file -> not blocked'
Check ((Set-NeedsVeFlag -Path $nvPath -Record $nvr) -eq 'set') 'Set-NeedsVeFlag writes the flag'
Check ((Set-NeedsVeFlag -Path $nvPath -Record (New-NeedsVeRecord -RunId 'later-run' -Reason 'later')) -eq 'kept') 'a second uncertain deploy keeps the first flag'
$st = Get-NeedsVeState -Path $nvPath -Kind 'refill'
Check ($st.Blocked -and $st.RunId -eq '20261123-183500') "the first flag survives (never overwritten): $($st.RunId)"
$cm = Format-NeedsVeComment -Issue 39 -RunId 'r1' -Reason 'merged as abc1234 but the deploy was not verified' -ClearCommand 'clear-needs-ve.ps1 -Clear -Note x' -Marker '<!-- innovation-loop -->' -Who 'Ve'
Check ($cm.StartsWith('<!-- innovation-loop -->') -and $cm -match 'Needs Ve' -and $cm -match 'clear-needs-ve\.ps1') 'the issue comment carries the loop marker and the clear command'

# the clear path: clear-needs-ve.ps1 against this test's LOOP_HOME (the env override set at the top)
$homeNv = Join-Path $tmp "state\needs-ve.json"
$clearPs = Join-Path $PSScriptRoot 'clear-needs-ve.ps1'
$runClear = { param([string[]]$A) $o = & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $clearPs @A 2>&1 | ForEach-Object { "$_" }; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
$c = & $runClear @()
Check ($c.Code -eq 0 -and $c.Out -match 'NOT SET') "clear-needs-ve.ps1 with no flag: not set, exit 0 ($($c.Code))"
[void](Set-NeedsVeFlag -Path $homeNv -Record $nvr)
$c = & $runClear @()
Check ($c.Code -eq 1 -and $c.Out -match 'NEEDS-VE SET' -and (Test-Path -LiteralPath $homeNv)) "show only: exit 1, flag kept ($($c.Code))"
$c = & $runClear @('-Clear')
Check ($c.Code -eq 2 -and (Test-Path -LiteralPath $homeNv)) "-Clear without -Note is refused, flag kept ($($c.Code))"
$envMode = "$($script:EnvPrefix)_MODE"
[Environment]::SetEnvironmentVariable($envMode, 'BUILD', 'Process')
$c = & $runClear @('-Clear', '-Note', 'from a session')
[Environment]::SetEnvironmentVariable($envMode, $null, 'Process')
Check ($c.Code -eq 2 -and $c.Out -match 'REFUSED' -and (Test-Path -LiteralPath $homeNv)) "inside a loop run (_MODE set) clearing is refused ($($c.Code))"
$c = & $runClear @('-Clear', '-Note', 'checked the live site; deploy verified by hand')
$cleared = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'state') -Filter 'needs-ve-cleared-*.json')
Check ($c.Code -eq 0 -and -not (Test-Path -LiteralPath $homeNv) -and $cleared.Count -eq 1) "-Clear -Note clears it and keeps the record ($($c.Code): $($c.Out -split "`n" | Select-Object -Last 1))"
if ($cleared.Count -eq 1) { $cr = [IO.File]::ReadAllText($cleared[0].FullName) | ConvertFrom-Json; Check ($cr.runId -eq '20261123-183500' -and $cr.note -match 'checked' -and $cr.clearedAt) 'the cleared record keeps the flag, the note and the time' }
Check ((Test-Path -LiteralPath (Join-Path $tmp 'logs\needs-ve.log')) -and ([IO.File]::ReadAllText((Join-Path $tmp 'logs\needs-ve.log')) -match 'cleared needs-ve:20261123-183500')) 'the clear is logged in logs\needs-ve.log'
Check (-not (Get-NeedsVeState -Path $homeNv).Blocked) 'after the clear nothing is blocked'

# run-loop.ps1 itself refuses while the flag is set: no session, no queue, no drain.json, lock released (FULL and PROPOSE_ONLY)
foreach ($ra in @(@(), @('-ProposeOnly'))) {
    [void](Set-NeedsVeFlag -Path $homeNv -Record $nvr)
    Get-ChildItem -LiteralPath (Join-Path $tmp 'logs') -Filter 'run-*' -ErrorAction SilentlyContinue | Remove-Item -Force
    $o = & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-loop.ps1') @ra -ClaudeExe 'C:\nonexistent\claude.exe' 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $sumF = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'logs') -Filter 'run-*.summary.txt' -ErrorAction SilentlyContinue)
    $rdF = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'logs') -Filter 'run-*.rundata.json' -ErrorAction SilentlyContinue)
    $sumT = ''; if ($sumF.Count -eq 1) { $sumT = [IO.File]::ReadAllText($sumF[0].FullName) }
    $rdJ = $null; if ($rdF.Count -eq 1) { $rdJ = [IO.File]::ReadAllText($rdF[0].FullName) | ConvertFrom-Json }
    $what = "run-loop $($ra -join ' ')".Trim()
    Check ($code -eq 1 -and $sumT -match 'LOOP-RESULT: FAILED NEEDS VE' -and $sumT -match 'clear-needs-ve\.ps1') "$what with the flag set: exit 1, LOOP-RESULT FAILED NEEDS VE with the clear command (exit $code)"
    Check ($rdJ -and -not $rdJ.claudeStarted -and $rdJ.needsVe.set -and $rdJ.totals.Cost -eq 0) "${what}: run data says no claude session, `$0, needsVe set"
    Check (-not (Test-Path -LiteralPath (Join-Path $tmp 'state\drain.json'))) "${what}: drain.json is not written"
    Check (-not (Test-Path -LiteralPath (Join-Path $tmp 'lock\run.lock'))) "${what}: the lock is released"
    Check (Test-Path -LiteralPath $homeNv) "${what}: the flag is still set afterwards (only Ve clears it)"
    Remove-Item -LiteralPath $homeNv -Force
}

# the approval watcher keeps a literal copy of Get-NeedsVeBlock and reads this loop's flag file
if (Test-Path -LiteralPath $watchRef) {
    $fnN = { param([string]$File) $ast = [Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $fn = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Get-NeedsVeBlock' }, $true) | Select-Object -First 1
        if ($fn) { ($fn.Extent.Text -replace '\s+', ' ').Trim() } else { '' } }
    $mineN = & $fnN "$PSScriptRoot\gate-rules.ps1"; $theirsN = & $fnN $watchRef
    Check ($theirsN -and $mineN -eq $theirsN) 'the approval watcher''s copy of Get-NeedsVeBlock matches gate-rules.ps1 (change both together)'
    Check ([IO.File]::ReadAllText($watchRef) -match ('NeedsVe = ''' + [regex]::Escape((Join-Path "C:\Users\Ve Bui\.innovation-loop-$(([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'loop.config.json')) | ConvertFrom-Json).project)" 'state\needs-ve.json')) + '''')) 'the watcher''s entry for this loop names the needs-Ve flag run-loop.ps1 writes'
}

# Script-scope name clashes (2026-11-24): PowerShell variable names are case-insensitive, so a plain `$marker = ...`
# at script level (outside any function) IS `$script:Marker`. run-loop.ps1 did exactly that with a build outcome,
# and every runner comment after a build began with "deployed"/"failed" instead of the loop marker (hub #48;
# here the spec-progress comments were re-posted as duplicates that read as Ve's adjustments). A script-level assignment whose name differs only in case from a `$script:` name is that bug. Script blocks
# count as script level (run-loop.ps1 dot-sources $phaseA); only function bodies have a scope of their own.
foreach ($sf in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1 | Where-Object { $_.Name -notlike 'test-*' })) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($sf.FullName, [ref]$null, [ref]$null)
    $scriptNames = @{}
    foreach ($v in $ast.FindAll({ param($a) $a -is [Management.Automation.Language.VariableExpressionAst] -and "$($a.VariablePath.UserPath)" -like 'script:*' }, $true)) {
        $nm = "$($v.VariablePath.UserPath)".Substring(7); if (-not $scriptNames.ContainsKey($nm.ToLowerInvariant())) { $scriptNames[$nm.ToLowerInvariant()] = @{} }; $scriptNames[$nm.ToLowerInvariant()][$nm] = 1
    }
    $clash = @()
    foreach ($as in $ast.FindAll({ param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $inFn = $false; $p = $as.Parent; while ($p) { if ($p -is [Management.Automation.Language.FunctionDefinitionAst]) { $inFn = $true; break }; $p = $p.Parent }
        if ($inFn -or -not ($as.Left -is [Management.Automation.Language.VariableExpressionAst])) { continue }
        $nm = "$($as.Left.VariablePath.UserPath)"; if ($nm -match ':') { continue }
        $k = $nm.ToLowerInvariant()
        if ($scriptNames.ContainsKey($k) -and -not (@($scriptNames[$k].Keys) -ccontains $nm)) { $clash += "`$$nm (line $($as.Extent.StartLineNumber)) vs `$script:$(@($scriptNames[$k].Keys)[0])" }
    }
    Check ($clash.Count -eq 0) "$($sf.Name): no script-level variable that overwrites a `$script: variable of another case ($($clash -join '; '))"
}

if ($script:fail -gt 0) { Write-Host "TEST-QUEUE-RULES FAIL ($script:fail failed, $script:pass passed)"; exit 1 }
Write-Host "TEST-QUEUE-RULES PASS ($script:pass checks)"
exit 0
