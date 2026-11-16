<#
.SYNOPSIS
  Decide whether an issue may be built by Phase A. Prints one JSON line; exit 0 = buildable, 1 = not.

.DESCRIPTION
  An issue is buildable only if ALL hold:
   - it is in vekbui96/solid-website, open, and not a pull request
   - it carries loop:proposal AND approved, and none of loop:in-progress / loop:deployed / loop:failed
   - it was opened by vekbui96 (the loop opens proposals as vekbui96; nobody else can label anyway)
   - per the issue events API, the most recent `labeled approved` event was performed by vekbui96,
     and no `unlabeled approved` event came after it
   - the issue body was not edited after the approval (checked via GraphQL lastEditedAt), so the approved
     text is the text that gets built

  Also prints `adjustments`: the ids of comments by vekbui96 that are NOT the loop's own (no
  `<!-- innovation-loop -->` marker). Only those comments may adjust an approved proposal.

  With -List it checks every open approved proposal and prints the buildable ones, oldest first.
#>
[CmdletBinding()]
param(
    [int]$Issue = 0,
    [switch]$List
)
. "$PSScriptRoot\lib.ps1"
Add-GhToPath
$Owner = 'vekbui96'
$Repo = $script:FrontRepo
$Marker = '<!-- innovation-loop -->'

function Get-GhJson {
    param([string[]]$GhArgs)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $script:GhExe @GhArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "gh $($GhArgs -join ' ') failed: $($out -join ' ')" }
    return (($out -join "`n") | ConvertFrom-Json)
}

function Test-Issue {
    param([int]$Number)
    $res = [ordered]@{ issue = $Number; buildable = $false; reasons = @(); approvedBy = $null; approvedAt = $null; adjustments = @() }
    $i = Get-GhJson @('api', "repos/$Repo/issues/$Number")
    $labels = @($i.labels | ForEach-Object { $_.name })
    if ($i.PSObject.Properties.Name -contains 'pull_request' -and $i.pull_request) { $res.reasons += 'is a pull request' }
    if ($i.state -ne 'open') { $res.reasons += "state is $($i.state)" }
    if ($i.user.login -ne $Owner) { $res.reasons += "opened by $($i.user.login), not $Owner" }
    foreach ($need in 'loop:proposal', 'approved') { if ($labels -notcontains $need) { $res.reasons += "missing label $need" } }
    foreach ($bad in 'loop:in-progress', 'loop:deployed', 'loop:failed') { if ($labels -contains $bad) { $res.reasons += "has label $bad" } }

    $events = @()
    $page = 1
    do {
        $batch = @(Get-GhJson @('api', "repos/$Repo/issues/$Number/events?per_page=100&page=$page"))
        $events += $batch; $page++
    } while ($batch.Count -eq 100 -and $page -lt 10)
    $approvalEvents = @($events | Where-Object { ($_.event -eq 'labeled' -or $_.event -eq 'unlabeled') -and $_.label -and $_.label.name -eq 'approved' })
    $lastLabeled = $approvalEvents | Where-Object { $_.event -eq 'labeled' } | Select-Object -Last 1
    if (-not $lastLabeled) { $res.reasons += 'no labeled-approved event found' }
    else {
        $res.approvedBy = $lastLabeled.actor.login
        $res.approvedAt = $lastLabeled.created_at
        if ($lastLabeled.actor.login -ne $Owner) { $res.reasons += "approved label added by $($lastLabeled.actor.login), not $Owner" }
        $later = @($approvalEvents | Where-Object { $_.event -eq 'unlabeled' -and [datetime]$_.created_at -gt [datetime]$lastLabeled.created_at })
        if ($later.Count -gt 0) { $res.reasons += 'approved label was removed after it was added' }
        $q = 'query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){lastEditedAt}}}'
        $g = Get-GhJson @('api', 'graphql', '-f', "query=$q", '-F', "o=$Owner", '-F', 'r=solid-website', '-F', "n=$Number")
        $edited = $g.data.repository.issue.lastEditedAt
        if ($edited -and ([datetime]$edited -gt [datetime]$lastLabeled.created_at)) { $res.reasons += "issue body edited at $edited, after approval; re-approve (remove and re-add approved) to build it" }
    }

    $comments = @(Get-GhJson @('api', "repos/$Repo/issues/$Number/comments?per_page=100"))
    $res.adjustments = @($comments | Where-Object { $_.user.login -eq $Owner -and -not ($_.body -and $_.body.Contains($Marker)) } | ForEach-Object { $_.id })
    $res.buildable = ($res.reasons.Count -eq 0)
    return $res
}

try {
    if ($List) {
        $open = @(Get-GhJson @('issue', 'list', '-R', $Repo, '--state', 'open', '--label', 'loop:proposal', '--label', 'approved', '--json', 'number,createdAt', '--limit', '50'))
        $results = @()
        foreach ($o in ($open | Sort-Object { [datetime]$_.createdAt })) { $results += (Test-Issue -Number $o.number) }
        $ok = @($results | Where-Object { $_.buildable })
        Write-Output (@{ buildable = @($ok | ForEach-Object { $_.issue }); checked = $results } | ConvertTo-Json -Depth 5 -Compress)
        if ($ok.Count -gt 0) { exit 0 } else { exit 1 }
    }
    if ($Issue -le 0) { throw 'pass -Issue <n> or -List' }
    $r = Test-Issue -Number $Issue
    Write-Output ($r | ConvertTo-Json -Depth 5 -Compress)
    if ($r.buildable) { exit 0 } else { exit 1 }
} catch {
    Write-Output (@{ error = "$_" } | ConvertTo-Json -Compress)
    exit 2
}
