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

`install-task.ps1` (run once from an **elevated** PowerShell; asks for your password once) registers two
tasks, both **disabled**:

| Task | Runs | Privileges |
| --- | --- | --- |
| `InnovationLoop` | daily 13:17: `run-loop.ps1` -> `claude -p` | **not elevated** (Limited) |
| `innovation-loop-api` | no trigger; started by the loop to deploy or roll back the API | elevated (Highest) |

The loop session itself never runs elevated. When it needs to deploy or roll back the API it calls
`api-request.ps1`, which writes a small request file (mode, issue, sha, time, nonce: data only) to
`C:\Users\Ve Bui\.innovation-loop\api-queue\` and starts `innovation-loop-api`. That task runs
`api-runner.ps1` from `C:\ProgramData\innovation-loop-api\bin\`, which is a copy the loop cannot write. The
runner treats the request as untrusted. It rejects unknown fields, stale or replayed requests, and any deploy
sha that is not the current tip of the API's `origin/main`. It then runs `deploy-api.ps1` or
`rollback-api.ps1` with arguments it builds itself, and writes the result to
`C:\ProgramData\innovation-loop-api\results\`. Reverting main is done back on the non-elevated side.

```powershell
Enable-ScheduledTask  -TaskName InnovationLoop; Enable-ScheduledTask -TaskName innovation-loop-api
Disable-ScheduledTask -TaskName InnovationLoop       # stops the daily run (the API task has no trigger)
Start-ScheduledTask   -TaskName InnovationLoop       # run once now

# by hand, from a normal (non-elevated) PowerShell:
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -ProposeOnly   # first supervised run
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -DryRun        # everything except the claude call
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\api-request.ps1 -Mode noop  # checks the elevated task answers
```

The daily task runs `run-loop.ps1` and `LOOP.md` from **this checkout** (`D:\projects\solid-website\innovation`),
so keep it on `main` and `git pull` to update the loop. The elevated task runs the **copies** in
`C:\ProgramData\innovation-loop-api\bin\`. After pulling changes to `api-runner.ps1`, `lib.ps1`,
`deploy-api.ps1` or `rollback-api.ps1`, re-run `install-task.ps1` to refresh them. The loop itself cannot
edit either location.

## Where things are

Loop state lives outside the repos, in `C:\Users\Ve Bui\.innovation-loop\`:

| Path | What |
| --- | --- |
| `logs\run-<time>.log` | runner log (start here) |
| `logs\run-<time>.summary.txt` | the session's final summary, ending in `LOOP-RESULT: ...` |
| `logs\run-<time>.jsonl` | full transcript (every tool call) |
| `logs\deploy-frontend-*.log`, `logs\api-request-*.log`, `logs\test-*.log` | script logs |
| `clones\` | the loop's own clones of both repos (never your `D:\projects` checkouts) |
| `artifacts\<issue>\` | before/after screenshots |
| `api-queue\request.json` | the last request to the elevated API task |
| `state\` | front-end deploy records (used by rollback-frontend) |

The elevated API side lives in `C:\ProgramData\innovation-loop-api\`. It is readable by you and writable
only from an elevated shell:

| Path | What |
| --- | --- |
| `results\<nonce>.json` | outcome of each request |
| `logs\api-runner-*.log`, `logs\deploy-api-*.log`, `logs\rollback-api-*.log` | elevated logs |
| `api-backups\` | the last 5 live API jars |
| `state\api-last-deploy.json`, `state\nonces.log` | last API deploy record, used request nonces |
| `clones\solid-website-api` | the elevated side's own clone (fetched over SSH with `ssh_config` there) |

## Rolling back by hand

```powershell
# front end (normal PowerShell, in D:\projects\solid-website\innovation):
.\rollback-frontend.ps1                                   # gh-pages back to before the last loop deploy
.\rollback-frontend.ps1 -PrevSha <gh-pages sha> -RevertSha <merge sha on main>

# API, the easy way (normal PowerShell; goes through the elevated task, then reverts main):
.\api-request.ps1 -Mode rollback -RevertSha <api merge sha>

# API, directly (ELEVATED PowerShell; restores the jar recorded by the last loop deploy, verifies):
$env:INNOVATION_LOOP_HOME = 'C:\ProgramData\innovation-loop-api'
& C:\ProgramData\innovation-loop-api\bin\rollback-api.ps1
#   then revert the merge on main yourself (Render follows main): .\api-request.ps1 -Mode revert-only -Sha <sha>
```

Exit codes for all deploy/rollback scripts: `0` ok, `1` precondition failed (nothing changed),
`2` deploy failed and was rolled back, `3` rollback failed (look now), `4` build failed (nothing live
changed). `api-request.ps1` adds `5`: no result in time (the API task is disabled, missing or still running).

## Safety, in short

- The loop session is **not elevated**. Only the fixed, argument-less `innovation-loop-api` task is, and it
  only acts on a validated request (see above).
- It runs with `--permission-mode dontAsk` and an explicit allowlist: anything not listed is denied, since
  nobody is there to approve a prompt.
- A `guard.mjs` hook checks every tool call:
  - only the two site repos
  - no secrets or `.env`
  - nothing in the never-touch list (cardlens, recognition, target-stock-checker, Palworld,
    Tailscale/Funnel, OpenClaw/WSL, SSH keys, NSSM, `.server-setup`)
  - no force pushes
  - no service or scheduled-task commands (`schtasks` included: only `api-request.ps1` starts the API task)
  - no edits to `innovation/` itself
- Secret-looking environment variables (including `RESEND_API_KEY`) are removed before the session starts.
- The deploy scripts verify the served bytes / live endpoints and roll back on their own.
- **Accepted risk: the gh token.** The loop uses your normal `gh` login, whose token has `repo` scope on
  all of your repositories. You chose not to switch to a fine-grained token limited to the two site repos.
  The guard is the protection here: it blocks any `gh`/git command naming another repository and requires
  every `gh` call to name one of the two site repos explicitly. A bug or bypass in the guard would not be
  stopped by the token.
- **Residual risk: the API runs as LocalSystem.** Once deployed, code merged to the API's `main` runs as
  SYSTEM (that is how the NSSM service is set up). The elevation split guarantees such code is a public,
  reviewable commit on `origin/main` before it is deployed; it cannot stop malicious code that gets merged.
- The guard is a guardrail, not a sandbox.