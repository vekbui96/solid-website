# Innovation loop

A daily, unattended job on server-pc that suggests small improvements to the portfolio site and, once
you approve one, builds, tests, deploys and verifies it on its own.

## This is only for the loop's own ideas

The issue/label/approval flow below exists **only for ideas the loop comes up with itself**. Your
direct requests ("change X on my site") do not go through it. Ask for them as usual: the site agents
(`site-frontend`, `site-backend`) handle them end to end and deploy without asking, as they always have.
No issue or label is needed, and nobody should route manual work through the loop.

## How it works

Once a day the `InnovationLoop` scheduled task runs `run-loop.ps1`, which starts a headless
`claude -p` session that follows [`LOOP.md`](LOOP.md). Each run:

1. **Phase A (build).** Picks the oldest open issue in `vekbui96/solid-website` labelled
   `loop:proposal` + `approved` whose approval really came from you (checked against the issue's
   event history by `check-approval.ps1`). It posts a plan as a comment, builds on a
   `loop/<issue>-<slug>` branch, tests, opens and merges a PR, deploys with the scripts here, and
   verifies the live result. Success: `loop:deployed`, issue closed. Failure: automatic rollback,
   `loop:failed`, details in a comment, issue left open. At most one issue per run.
2. **Phase B (propose).** If fewer than 5 proposals are open, it looks over both repos and the live
   site and opens up to 3 new `loop:proposal` issues (never more than 5 open).

GitHub issues in **solid-website** are the single source of truth, even for API work.

## Approving

- Read the proposal. Add the **`approved`** label to green-light it. Only you can: it needs write access,
  and the loop checks the label event was yours.
- To adjust scope, comment on the issue before or after approving. Your comments (not the loop's,
  which carry a hidden `<!-- innovation-loop -->` marker) are treated as adjustments. Comments from
  anyone else are ignored as instructions.
- If you **edit the issue body after approving**, the loop will not build it until you remove and re-add
  `approved`, so what gets built is what you approved.
- A proposal marked **FLAGGED: content claims** (Fit Analyzer gap terms/strengths, profile copy,
  projects.json content): approving it is your sign-off on that content.
- A proposal marked **Manual step required** is never deployed by the loop.
- To reject: close the issue. The loop will not propose it again.

## Labels

| Label | Meaning |
| --- | --- |
| `loop:proposal` | an idea from the loop |
| `area:frontend` / `area:backend` / `area:both` | which repo(s) it touches |
| `approved` | you said go (you set this) |
| `loop:in-progress` | being built right now |
| `loop:deployed` | shipped, verified live, closed |
| `loop:failed` | failed or rolled back; read the comments |

## Enable, disable, run

The task is installed **disabled** (`install-task.ps1`, elevated PowerShell, asks for your password once).

```powershell
Enable-ScheduledTask  -TaskName InnovationLoop
Disable-ScheduledTask -TaskName InnovationLoop
Start-ScheduledTask   -TaskName InnovationLoop      # run once now

# by hand (elevated, so API deploys work):
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -ProposeOnly   # first supervised run
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -DryRun        # everything except the claude call
```

The task runs the scripts and `LOOP.md` from **this checkout** (`D:\projects\solid-website\innovation`),
so keep it on `main` and `git pull` to update the loop. The loop itself cannot edit them.

## Where things are

Everything lives outside the repos, in `C:\Users\Ve Bui\.innovation-loop\`:

| Path | What |
| --- | --- |
| `logs\run-<time>.log` | runner log (start here) |
| `logs\run-<time>.summary.txt` | the session's final summary, ending in `LOOP-RESULT: ...` |
| `logs\run-<time>.jsonl` | full transcript (every tool call) |
| `logs\deploy-*.log`, `logs\rollback-*.log`, `logs\test-frontend-*.log` | script logs |
| `clones\` | the loop's own clones of both repos (never your `D:\projects` checkouts) |
| `artifacts\<issue>\` | before/after screenshots |
| `api-backups\` | the last 5 live API jars |
| `state\` | last deploy records (used by the rollback scripts) |

## Rolling back by hand

From an elevated PowerShell in `D:\projects\solid-website\innovation`:

```powershell
# front end: gh-pages back to the commit before the last loop deploy (from state\frontend-last-deploy.json)
.\rollback-frontend.ps1
# ...or to a specific gh-pages commit, also reverting the loop's merge on main
.\rollback-frontend.ps1 -PrevSha <gh-pages sha> -RevertSha <merge sha on main>

# API: restore the jar backed up by the last loop deploy, verify, optionally revert main (Render follows main)
.\rollback-api.ps1
.\rollback-api.ps1 -BackupJar "C:\Users\Ve Bui\.innovation-loop\api-backups\personal-site-api-<time>.jar" -RevertSha <merge sha>
```

Exit codes for all deploy/rollback scripts: `0` ok, `1` precondition failed (nothing changed),
`2` deploy failed and was rolled back, `3` rollback failed (look now), `4` build failed (nothing live changed).

## Safety, in short

- Runs with `--permission-mode dontAsk` and an explicit allowlist: anything not listed is denied, since
  nobody is there to approve a prompt. A `guard.mjs` hook checks every tool call: only the two site repos,
  no secrets or `.env`, nothing in the never-touch list (cardlens, recognition, target-stock-checker,
  Palworld, Tailscale/Funnel, OpenClaw/WSL, SSH keys, NSSM, `.server-setup`), no force pushes, no service
  or scheduled-task changes outside the deploy scripts, no edits to `innovation/` itself.
- Secret-looking environment variables (including `RESEND_API_KEY`) are removed before the session starts.
- The deploy scripts verify the served bytes / live endpoints and roll back on their own.
- The guard is a guardrail, not a sandbox; see the PR that added this directory for the residual risk.
