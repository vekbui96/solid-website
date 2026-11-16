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
   `loop:failed`, details in a comment, issue left open. Up to **2 issues per run** (`run-loop.ps1
   -MaxBuilds <n>`, 1-5), strictly one after the other, each with its own full cycle. A second one is
   started only if the first ended `loop:deployed` (never after a failure or rollback), the run is still
   inside the first half of its time budget (`-NextBuildCutoffPercent`, default 50% of the 180-minute
   claude timeout, which leaves room for a worst-case build with rollback plus Phase B), and, for
   API work, the elevated API task still answers.
2. **Phase B (propose).** If fewer than 5 proposals are open, it looks over both repos and the live
   site and opens up to 3 new `loop:proposal` issues (never more than 5 open), weighted toward
   [`FOCUS.md`](FOCUS.md).

## Steering it: FOCUS.md

**Edit [`FOCUS.md`](FOCUS.md) to steer the loop.** It lists your priorities (highest first) and things to
avoid. Phase B reads it first, prefers ideas in those priorities, treats the avoid list as off-limits,
and names the priority each proposal serves. It only steers proposals: it never overrides `LOOP.md`'s
hard rules, never builds anything by itself, and is not approval or content sign-off.

- The run reads it from this checkout (`D:\projects\solid-website\innovation\FOCUS.md`), so an edit takes
  effect on the next run. Commit it so the laptop copy agrees.
- The loop cannot change it: the guard blocks every write under `innovation/`, and `LOOP.md` forbids
  proposing changes to it.
- Missing, or nothing left but headings and `<!-- comments -->`: the loop proposes from its own judgment,
  as before. The run log says which (`focus file: present|none`).

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

`install-task.ps1` (run once from an **elevated** PowerShell) registers two tasks, both **disabled**:

| Task | Runs | Privileges |
| --- | --- | --- |
| `InnovationLoop` | daily 13:17: `run-loop.ps1` -> `claude -p` | starts elevated; **run-loop drops its own rights** before anything else |
| `innovation-loop-api` | no trigger; started by the loop to deploy or roll back the API | elevated (Highest) |

Both default to an S4U logon (no stored password). `-LoopLogonType Password` / `-ApiLogonType Password`
switch to a stored password, which is then asked for in the console.

### Where the loop's non-elevation comes from

Not from the task's RunLevel. `InnovationLoop` is registered RunLevel Limited, but Windows creates no UAC
split token for a non-interactive logon (S4U or Password) of an admin account, so the task starts
`run-loop.ps1` with a full admin token whatever the RunLevel says (measured: TokenElevation=1,
TokenElevationType=1).

So `run-loop.ps1` drops its rights itself. The outer invocation does one privileged thing, making the
loop's clones owned by you (git rejects an Administrators-owned repo once Administrators is deny-only).
It then re-runs itself under a reduced token and waits. That token comes from `reduced-token.ps1`: a
UAC-style filtered copy of its own token, with Administrators and the local-admin SID deny-only, every
privilege except SeChangeNotify removed, and Medium integrity. These are the rights of
`runas /trustlevel:0x20000`, but with TokenElevation=0 (SAFER's own token keeps the elevation flag set).
The lock, the clone refresh, the preflight, `claude` and everything `claude` starts run under that token.
It is the same user, so `~\.claude`, `gh`'s `hosts.yml`, `~\.ssh` and git all still work.

It **fails closed**. If the token cannot be reduced, or the reduced process still reports elevation or an
enabled Administrators group, the run aborts and nothing runs elevated. Children are created suspended
and checked before they start. There is no override switch.

**How to verify:** every run log (`logs\run-<time>.log`) has these lines near the top:

```
runner token: TokenElevation=1 TokenElevationType=1 integrity=High Administrators=enabled. Elevated, as expected ...
reduced inner runner pid 1234; its token: TokenElevation=0 TokenElevationType=1 integrity=Medium Administrators=deny-only
inner runner pid 1234 token: TokenElevation=0 ...
claude pid 5678 token: TokenElevation=0 TokenElevationType=1 integrity=Medium Administrators=deny-only; timeout 180 min
```

TokenElevationType stays 1 in the scheduled task (2 when you start it from an elevated interactive shell).
That is the logon's type, not the token's rights. What matters is `TokenElevation=0` and
`Administrators=deny-only`. If you see `could not run the loop with dropped rights`, the run did not happen.

### Installing over SSH

`install-task.ps1` opens no GUI dialogs, so it works from an SSH session. The SSH session must be elevated:
an admin account's OpenSSH session is.

```powershell
cd D:\projects\solid-website
powershell -NoProfile -ExecutionPolicy Bypass -File .\innovation\install-task.ps1                          # S4U, no password
powershell -NoProfile -ExecutionPolicy Bypass -File .\innovation\install-task.ps1 -LoopLogonType Password  # asks in the console
```

With `Password`, it prompts with `Read-Host -AsSecureString` and refuses an empty password. Task Scheduler
cannot store an empty password, so an account without one has to use S4U. The loop needs no Windows
network credentials: GitHub goes over SSH keys and the `gh` token in `hosts.yml`. S4U is therefore enough.
One caveat applies: an S4U logon cannot decrypt DPAPI-protected secrets such as Credential Manager entries.
If a tool ever moves its credentials there (for example `gh auth login` without `--insecure-storage`),
switch to `-LoopLogonType Password`.

### The API task

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

# by hand, from a normal or an elevated PowerShell (either way run-loop drops to the reduced token;
# only an elevated one can hand Administrators-owned clones to you, which a non-elevated run then needs):
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -ProposeOnly   # first supervised run
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -DryRun        # everything except the claude call
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -MaxBuilds 1   # one build this run
# (the daily task passes no arguments, so it uses the param defaults in run-loop.ps1: MaxBuilds 2, cutoff 50%)
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

- The loop session is **not elevated**: `run-loop.ps1` drops rights before starting it and fails closed
  (see "Where the loop's non-elevation comes from"). Only the fixed, argument-less `innovation-loop-api`
  task is elevated, and it only acts on a validated request (see above).
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