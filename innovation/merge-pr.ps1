<#
.SYNOPSIS
  The ONLY way the loop merges to main. Checks everything in code, waits for CI on the PR's EXACT head
  commit, then merges with --match-head-commit.
  Last output line: MERGE-PR OK <mergeSha> | MERGE-PR REFUSED <why> | MERGE-PR CI-FAILED <why> | MERGE-PR CI-TIMEOUT <why>

.DESCRIPTION
  1. check-approval.ps1 -Issue <n> -InProgress must pass (approved by the owner, not edited since, not manual)
  2. the PR is open, base main, not a draft, from a branch of the same repo named loop/<issue>-<slug>,
     opened by the owner
  3. no changed file matches a protected path, and no added line fails hooks.ps1 Test-MergeLine
  4. if this repo is the server repo: the server side must be deployable, decided BEFORE merging because
     merging may deploy: in the commits already on main that the live server lacks, no protected path that
     changes what the server runs (inert ones such as innovation/**, .github/** are listed as MERGE-PR GAP;
     the owner's non-protected server changes go live with this deploy and are listed as MERGE-PR
     GAP-SERVER); the elevated task answers a selftest
  5. the repo's required CI checks (loop.config.json repos[].requiredChecks, regexes on check-run names)
     all completed with success on the head sha; a push that moves the head while waiting is refused.
     A repo WITHOUT CI instead names repos[].localGate (hooks.ps1 test steps): this script itself, not the
     session, runs those steps on the EXACT head sha in a fresh detached worktree (work\merge-gate-<repo>),
     and any failure is CI-FAILED. Neither configured: every merge is refused.
  6. gh pr merge --merge --match-head-commit <sha> --delete-branch; records the merge for deploy/rollback

.EXIT CODES
  0 merged | 1 refused (nothing merged) | 3 CI failed on the head sha | 4 CI did not finish in time
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Pr,
    [Parameter(Mandatory)][int]$Issue,
    [string]$Repo = '',
    [int]$TimeoutMinutes = 50
)
. "$PSScriptRoot\lib.ps1"
. "$PSScriptRoot\gate-rules.ps1"
. "$PSScriptRoot\hooks.ps1"
Start-ScriptLog "merge-pr-$Issue-$Pr"
Add-GhToPath
$repoCfg = Get-RepoCfg $Repo
$Slug = $repoCfg.slug
$clone = Get-ClonePath $repoCfg.name
$RequiredChecks = @($repoCfg.requiredChecks | Where-Object { $_ })
$LocalGate = @($repoCfg.localGate | Where-Object { $_ })

function Refuse([string]$why) { Write-Log "refused: $why" 'ERROR'; Write-Output "MERGE-PR REFUSED $why"; exit 1 }

try {
    if ($RequiredChecks.Count -eq 0 -and $LocalGate.Count -eq 0) { Refuse "no requiredChecks and no localGate configured for ${Slug}: the loop never merges untested" }
    foreach ($s in $LocalGate) { if ($script:TestStepsValid -notcontains "$s") { Refuse "localGate step '$s' is not a hooks.ps1 test step ($($script:TestStepsValid -join ', '))" } }

    # ---- 1. approval ---------------------------------------------------------------
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $ap = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\check-approval.ps1" -Issue $Issue -InProgress 2>&1 | ForEach-Object { "$_" }
    $apCode = $LASTEXITCODE; $ErrorActionPreference = $prevEap
    Write-Log "check-approval: exit $apCode $($ap -join ' ')"
    if ($apCode -ne 0) { Refuse "issue #$Issue is not buildable: $($ap -join ' ')" }

    # ---- 2. the PR itself ------------------------------------------------------------
    $p = Get-GhJson @('api', "repos/$Slug/pulls/$Pr")
    if ($p.state -ne 'open') { Refuse "PR #$Pr is $($p.state)" }
    if ($p.draft) { Refuse "PR #$Pr is a draft" }
    if ($p.base.ref -ne 'main') { Refuse "PR base is $($p.base.ref), not main" }
    if ($p.head.repo.full_name -ne $Slug) { Refuse "PR head is from $($p.head.repo.full_name), not $Slug" }
    if ($p.head.ref -notmatch "^loop/$Issue-[a-z0-9][a-z0-9-]*$") { Refuse "PR branch '$($p.head.ref)' is not loop/$Issue-<slug>" }
    if ($p.user.login -ne $script:Owner) { Refuse "PR opened by $($p.user.login)" }
    $headSha = $p.head.sha
    Write-Log "PR #$Pr head $headSha branch $($p.head.ref)"

    # ---- 3. what it changes ----------------------------------------------------------
    $files = @()
    for ($page = 1; $page -le 10; $page++) {
        $batch = @(Get-GhJson @('api', "repos/$Slug/pulls/$Pr/files?per_page=100&page=$page"))
        $files += $batch
        if ($batch.Count -lt 100) { break }
    }
    if ($files.Count -eq 0) { Refuse 'PR changes no files' }
    foreach ($f in $files) {
        foreach ($name in @($f.filename, $f.previous_filename) | Where-Object { $_ }) {
            $hit = Test-ProtectedPath $name
            if ($hit) { Refuse "PR touches protected path $name ($hit): manual / needs Ve" }
        }
        foreach ($line in @("$($f.patch)" -split "`n" | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })) {
            $why = Test-MergeLine -File $f.filename -Line $line
            if ($why) { Refuse $why }
        }
    }
    Write-Log "files ok: $(@($files | ForEach-Object { $_.filename }) -join ', ')"

    # ---- 4. server deployability (decided BEFORE merging) ------------------------------
    Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', '--prune') -Quiet | Out-Null
    Invoke-Git -Repo $clone -Arguments @('fetch', 'origin', "refs/heads/$($p.head.ref)") -Quiet | Out-Null
    if ($script:ServerEnabled -and "$(Get-Cfg 'server.repo')" -eq $repoCfg.name) {
        $base = Get-GitValue -Repo $clone -Arguments @('merge-base', 'origin/main', $headSha)
        $plan = Get-ServerPlan -Repo $clone -Target $headSha -OwnCommitsFrom $base
        Write-Log "server plan: liveHead=$($plan.LiveHead) needed=$($plan.ServerNeeded) files=$($plan.ServerFiles -join ',') foreign=$($plan.Foreign -join ',')"
        # The PR's own files were checked in step 3 (strict). In the gap (commits already on main the live server
        # lacks) only protected paths that change what the server RUNS refuse; inert ones are listed
        # (gate-rules.ps1 Get-GapDecision). Non-protected server changes in the gap ride along with this deploy.
        $ownNames = @($files | ForEach-Object { $_.filename; $_.previous_filename } | Where-Object { $_ })
        $gap = Get-GapDecision -Protected $plan.Protected -OwnFiles $ownNames
        $gapServerCommits = @(); $gapBlockCommits = @()
        if ($plan.LiveHead -and $base -and $plan.LiveHead -ne $base) {
            $range = "$($plan.LiveHead)..$base"
            foreach ($c in @((Invoke-Git -Repo $clone -Arguments @('log', '--format=%h %s', $range) -AllowFail -Quiet).Output | Where-Object { $_ })) { Write-Log "gap commit (on main, not yet on the live server): $c"; Write-Output "MERGE-PR GAP $c" }
            $gapLive = @((Get-ChangedFiles -Repo $clone -From $plan.LiveHead -To $base) | Where-Object { Test-LiveAffectingPath $_ })
            if ($gapLive.Count -gt 0) { $gapServerCommits = @((Invoke-Git -Repo $clone -Arguments (@('log', '--format=%h %s', $range, '--') + $gapLive) -AllowFail -Quiet).Output | Where-Object { $_ }) }
            if ($gap.Block.Count -gt 0) { $gapBlockCommits = @((Invoke-Git -Repo $clone -Arguments (@('log', '--format=%h %s', $range, '--') + $gap.Block) -AllowFail -Quiet).Output | Where-Object { $_ }) }
        }
        foreach ($c in $gapServerCommits) { Write-Log "gap commit that changes what the server runs (goes live with this deploy): $c"; Write-Output "MERGE-PR GAP-SERVER $c" }
        if ($gap.Ignored.Count -gt 0) { Write-Log "gap: protected but inert on the server, ignored: $($gap.Ignored -join ', ')" }
        if ($gap.Refuse.Count -gt 0) {
            $why = "protected paths between the live server and this PR: $($gap.Refuse -join ', ')"
            if ($gapBlockCommits.Count -gt 0) { $why += ". Already on main in: $($gapBlockCommits -join '; '); the owner must deploy those by hand first" }
            Refuse $why
        }
        if ($plan.ServerNeeded) {
            $self = Invoke-ElevatedRequest -Mode selftest -TimeoutMinutes 5
            if ($self.status -ne 'ok') { Refuse "this merge needs a server deploy ($($plan.ServerFiles -join ', ')) but the elevated deploy task is not usable: $($self.status) $($self.message)" }
            Write-Log "elevated task selftest ok: $($self.message)"
        }
    }

    # ---- 5. CI on the exact head sha (or, for a repo without CI, the local gate run HERE) ----
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $ciOk = $false
    if ($RequiredChecks.Count -eq 0) {
        $wt = Join-Path $script:LoopHome "work\merge-gate-$($repoCfg.name)"
        $gateFail = ''
        Invoke-Git -Repo $clone -Arguments @('worktree', 'prune') -AllowFail -Quiet | Out-Null
        if (Test-Path -LiteralPath $wt) { Invoke-Git -Repo $clone -Arguments @('worktree', 'remove', '--force', $wt) -AllowFail -Quiet | Out-Null; if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force } }
        Invoke-Git -Repo $clone -Arguments @('worktree', 'add', '--detach', $wt, $headSha) -Quiet | Out-Null
        try {
            foreach ($s in $LocalGate) {
                Write-Log "local gate ($($repoCfg.name) @ $($headSha.Substring(0,7))): $s"
                $why = Invoke-TestStep -Step "$s" -RepoName $repoCfg.name -RepoPath $wt -Issue "$Issue" -ExpectString '' -UnitFilter ''
                if ($why) { $gateFail = "${s}: $why"; break }
            }
        } catch { $gateFail = "error: $_" }
        finally {
            Invoke-Git -Repo $clone -Arguments @('worktree', 'remove', '--force', $wt) -AllowFail -Quiet | Out-Null
            if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force -ErrorAction SilentlyContinue }
        }
        if ($gateFail) { Write-Log "local gate failed: $gateFail" 'ERROR'; Write-Output "MERGE-PR CI-FAILED local gate on $($headSha.Substring(0,7)): $gateFail"; exit 3 }
        $now = Get-GhJson @('api', "repos/$Slug/pulls/$Pr")
        if ($now.head.sha -ne $headSha) { Refuse "the PR head moved to $($now.head.sha) while the local gate ran" }
        Write-Log "local gate passed on $headSha ($($LocalGate -join ', '))"
        $ciOk = $true
    }
    while (-not $ciOk -and (Get-Date) -lt $deadline) {
        $cr = Get-GhJson @('api', "repos/$Slug/commits/$headSha/check-runs?per_page=100")
        $runs = @($cr.check_runs)
        $state = @(); $failed = @(); $pending = $false
        foreach ($re in $RequiredChecks) {
            $job = @($runs | Where-Object { $_.name -match $re } | Sort-Object { [datetime]$_.started_at } -Descending | Select-Object -First 1)
            if ($job.Count -eq 0) { $pending = $true; $state += "$re=missing"; continue }
            $j = $job[0]
            $state += "$($j.name)=$($j.status)/$($j.conclusion)"
            if ($j.status -ne 'completed') { $pending = $true }
            elseif ($j.conclusion -ne 'success') { $failed += "$($j.name): $($j.conclusion)" }
        }
        Write-Log "CI $($headSha.Substring(0,7)): $($state -join '; ')"
        if ($failed.Count -gt 0) { Write-Output "MERGE-PR CI-FAILED $($failed -join '; ') (see gh run list -R $Slug --commit $headSha)"; exit 3 }
        if (-not $pending) { $ciOk = $true; break }
        $now = Get-GhJson @('api', "repos/$Slug/pulls/$Pr")
        if ($now.head.sha -ne $headSha) { Refuse "the PR head moved to $($now.head.sha) while waiting for CI" }
        Start-Sleep -Seconds 30
    }
    if (-not $ciOk) { Write-Output "MERGE-PR CI-TIMEOUT CI did not finish within $TimeoutMinutes minutes"; exit 4 }

    # ---- 6. merge --------------------------------------------------------------------------
    Invoke-Gh -Arguments @('pr', 'merge', "$Pr", '-R', $Slug, '--merge', '--match-head-commit', $headSha, '--delete-branch') | Out-Null
    $mergeSha = $null
    for ($i = 0; $i -lt 10 -and -not $mergeSha; $i++) {
        $m = Get-GhJson @('api', "repos/$Slug/pulls/$Pr")
        if ($m.merged -and $m.merge_commit_sha) { $mergeSha = $m.merge_commit_sha } else { Start-Sleep -Seconds 3 }
    }
    if (-not $mergeSha) { throw 'merge reported success but no merge commit sha was found' }
    Save-State "merge-$Issue-$($repoCfg.name)" @{ issue = $Issue; repo = $repoCfg.name; pr = $Pr; headSha = $headSha; mergeSha = $mergeSha; mergedUtc = [DateTime]::UtcNow.ToString('o') }
    Write-Log "merged PR #$Pr as $mergeSha"
    Write-Output "MERGE-PR OK $mergeSha"
    exit 0
} catch {
    Write-Log "error: $_" 'ERROR'
    Write-Output "MERGE-PR REFUSED error: $_"
    exit 1
}
