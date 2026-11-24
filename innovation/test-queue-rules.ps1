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
Check ($cfgS.build.model -eq 'claude-opus-5-5' -and $cfgS.propose.model -eq 'claude-sonnet-5-5' -and $cfgS.build.maxTurns -eq 150 -and $cfgS.propose.maxTurns -eq 80) 'session defaults'
$sj = Join-Path $PSScriptRoot 'sessions.json'
if (Test-Path $sj) { $c3 = Get-SessionConfig ([IO.File]::ReadAllText($sj) | ConvertFrom-Json); Check ($c3.build.maxTurns -gt 0 -and $c3.propose.model) 'sessions.json parses' }
Check ((Get-SessionModel -Kind 'build' -Labels @('size:small') -Config $cfgS) -eq 'claude-sonnet-5-5' -and (Get-SessionModel -Kind 'build' -Labels @('approved') -Config $cfgS) -eq 'claude-opus-5-5') 'build model by size label'
Check ((Get-SessionModel -Kind 'build' -Config $cfgS -Override 'x') -eq 'x') '-Model overrides'
function D { param([int]$I, [string]$O) [pscustomobject]@{ Issue = $I; Outcome = $O } }
Check ((Get-NextBuildDecision -Buildable @(12, 14) -Done @() -RemainingMinutes 240).Issue -eq 12) 'first build: the oldest buildable'
Check ((Get-NextBuildDecision -Buildable @(12, 14) -Done @(D 12 'deployed') -MaxBuilds 2 -RemainingMinutes 150).Issue -eq 14) 'after a deploy: the next'
Check (-not (Get-NextBuildDecision -Buildable @(14) -Done @(D 12 'deployed') -MaxBuilds 2 -RemainingMinutes 100 -NextBuildMinMinutes 120).Start) 'next build needs NextBuildMinMinutes'
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
$lo = @{ 12 = @('loop:proposal', 'approved'); 13 = @('loop:proposal', 'approved', 'size:small'); 14 = @('approved', 'test-only') }
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
if ($script:fail -gt 0) { Write-Host "TEST-QUEUE-RULES FAIL ($script:fail failed, $script:pass passed)"; exit 1 }
Write-Host "TEST-QUEUE-RULES PASS ($script:pass checks)"
exit 0
