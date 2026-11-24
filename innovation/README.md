# Portfolio site innovation loop

An unattended job on server-pc that suggests small improvements to Portfolio site and, once you approve one,
builds, tests, merges, deploys and verifies it on its own. Same design as the other loops on this box
(see `D:\projects\CLAUDE.md`, "Innovation loops"); set up and operated with the `innovation-loop` agent.

## This is only for the loop's own ideas

The issue/label/approval flow below exists **only for ideas the loop comes up with itself**. Your direct
requests ("change X in Portfolio site") do not go through it: ask as usual and they are handled end to end
outside the loop. No issue or label is needed. The loop never touches issues without `loop:proposal`.

## How it works

The `InnovationLoop` task runs `run-loop.ps1` daily at 13:17; the shared watcher
(`innovation-loop-watch`, every 10 min) also starts it when you approve a proposal, and for a research run
when fewer than 5 proposals await your review (at most once an hour, never twice for the same open
set). The shared setup (lock, preflight, the elevated selftest, the queue precheck, the clones) runs once in
PowerShell; then it starts **one headless `claude -p` session per job** (`--permission-mode dontAsk`,
explicit allowlist, `guard.mjs` PreToolUse hook told the session kind) under a reduced token, each with a
prompt naming its one job and only the [`LOOP.md`](LOOP.md) sections it needs, and its own model, turn cap
and time limit from [`sessions.json`](sessions.json). A fresh, small session per job is much cheaper than
one long session re-reading its whole context. Each run:

1. **Phase A (build), up to `-MaxBuilds` (default 4) issues, one session each, strictly one after
   another.** Takes the oldest open `loop:proposal` + `approved` issue whose approval really came from you
   (`check-approval.ps1`, against the issue's event history). Posts a plan, builds on `loop/<issue>-<slug>`
   in its own clone, runs `test-gate.ps1`, opens a PR, waits for CI with ONE `wait-ci.ps1` call (one
   PASS / FAIL line with the failed checks and their log tails), merges with `merge-pr.ps1` only when CI is
   green on the PR's exact head commit, then `deploy.ps1` deploys and verifies, rolling everything back on
   failure. Success: `loop:deployed`, closed. Failure: `loop:failed`, comment, left open, and Phase A stops.
   The runner starts the next build session only after the previous one deployed and only if enough of the
   run's time remains. **If a build session merged something whose deploy was neither verified nor rolled
   back and verified, the runner stops the whole run** (no further build, no proposals, LOOP-RESULT FAILED).
2. **Phase B (propose), a separate session, only if a slot is free.** It reads [`FOCUS.md`](FOCUS.md)
   first, then the docs, the code and the live site, opens the next slices of any spec you approved, then
   new `loop:proposal` issues (or one spec), up to 3.

**Proposal slots (one rule everywhere).** A proposal holds one of the 5 slots while it awaits
your review: open, `loop:proposal`, and neither `approved` nor `loop:failed`. A spec awaiting review is one
proposal; its slices take slots as they are opened, ahead of new ideas; at most one unapproved spec at a
time. Approved work is your build queue and does not block new ideas. The loop (`check-approval.ps1 -Slots`,
`gate-rules.ps1 Get-ProposalSlots`) and the approval watcher's refill trigger (its `$Loops` entry carries
this loop's `Cap`) count the same way.

**Specs: big features in slices.** For a feature too big for one build the loop opens a `loop:spec` issue
(also `loop:proposal`): problem and evidence, the user flow per surface, a success metric with baseline and
target, risks and what is out of scope, and 3-5 independently shippable slices. Approve it like any
proposal; the loop never builds the spec itself. Its next proposal sessions open the slices, in order, as
normal proposals starting `Part of #<spec> (slice <k> of <m>)`. **Approving the spec approves its slices:**
each slice the loop opens for it is built without its own `approved` (the runner posts one "Auto-approved via
spec #N" comment on it), in order, unless it is marked Manual / needs Ve, failed, was edited, or you
hold it. **To stop:** comment `/hold` on a slice (that slice) or on the spec (all its slices), or close it; add
`approved` by hand to build a held slice anyway. An auto-approved slice that fails is not retried
automatically: remove `loop:failed` to rebuild it. Auto-approved slices take no proposal slot. The runner keeps
a "## Spec progress" checklist comment on the spec and closes it when every slice is deployed or closed.

**Models and caps** ([`sessions.json`](sessions.json), yours; kept out of `loop.config.json` so changing a
model never makes the elevated copy stale). Build sessions run on `claude-sonnet-5-5` (your decision of
2026-11-23) and on `claude-opus-5-5` (`build.opusModel`) only when: the issue carries `model:opus` (add it before
approving to choose Opus), the change deploys the API server (`area:backend` / `area:both`, or "What deploys" names
the API), or it is the one automatic retry of a Sonnet build that failed on the change (class `tests`, `other` or
`max-turns`; the failure marker records the model). `size:small` / `test-only` stay on Sonnet. The log says which
and why (`Phase A: #n model ... (...)`, `gate-rules.ps1 Get-BuildModelChoice`). Proposal sessions run on
`claude-sonnet-5-5`. Turn caps 150 per build and 80 for proposals; time limits 150 / 45 minutes, each cut to what is
left of the run's 360. Every build after the first needs 100 minutes left (`-NextBuildMinMinutes`): four builds
of up to ~85 min fit. The run budget is cut to end 30 minutes inside the task's ExecutionTimeLimit (7 h from
install-task.ps1; the log's `time: run budget ...` line).
`-Model` / `-MaxTurns` on run-loop.ps1 override every session for one run.

**Plan budget.** Before every session the runner (never claude) reads the ops hub's verdict in
`D:\hub\state\plan-budget.json` (written every 15 min from the plan's 5-hour and weekly use, which the loop
shares with your interactive sessions): `normal` = as always; `no-opus` = no session on an Opus model (only the Opus builds above: an Opus
build is deferred, still approved and untouched, to the first run whose verdict allows it; Sonnet builds and
proposal sessions still run); `hold` = no session at all (the run ends `LOOP-RESULT: NOTHING-TO-DO plan budget
hold`, $0). It fails open: a missing, unreadable, unknown or stale (older than its `staleAfterMinutes`, default
30) file counts as `normal` and is logged as a WARN. `run-loop.ps1 -IgnoreBudget` skips it for a supervised
run. The run log has a `budget:` line per check, and the summary lists deferred issues.

**Queue drain (the approval watcher).** At the end of every FULL run the runner writes
`<LOOP_HOME>\state\drain.json` (what `check-approval.ps1 -List` still calls buildable, which of those need Opus,
the last runs' queue head and progress; log line `drain state: ...`). The watcher reads it as data and starts the
task again when approved work is left, no run holds the lock and the last run ended 15+ minutes ago; never under
`hold`, nor `no-opus` when every buildable issue needs Opus, nor after an uncertain deploy (nor while the needs-Ve flag is set, see "Needs Ve: an uncertain deploy"); after a rollback, or
when the last 2 runs had the same queue head and deployed nothing, it backs off 2 hours. At most one drain run per
finished run. Rule: `Get-DrainDecision` in `gate-rules.ps1` (literal copy in the watcher, checked by
`test-queue-rules.ps1`).

**No-op runs cost nothing.** Before it starts claude, `run-loop.ps1` asks `check-approval.ps1 -List` for
the queue; with nothing buildable (FULL mode) and no free slot it logs `precheck: launch=False (...)`,
writes a summary ending `LOOP-RESULT: NOTHING-TO-DO` and `run-<id>.rundata.json` (cost 0) and exits 0
without a session. If that check fails, claude starts as before.

**Failed builds: one automatic retry, never silent.** Every failure comment carries a hidden failure
marker with a class (LOOP.md section 3, "Failure classes"). A failure outside the change (CI
infrastructure, CI timeout, the live-server gap refusal, the elevated task or its lock unavailable, out of
time, the run's time or turn limit) is built ONCE more by a later run (`loop:failed` -> `loop:retried`,
continuing the open PR); a second failure waits for you. Failures caused by the change, rolled-back ones
and unclassified ones are never retried automatically. If the session is killed mid-build, the runner
marks the issue `loop:failed` itself (`timeout` / `max-turns`; anything already merged is
`session-ended` and waits for you). Failed issues take no proposal slot and are listed in every run
summary as `Failed, waiting on Ve: #n (reason)`.

## Steering: FOCUS.md

[`FOCUS.md`](FOCUS.md) is yours: a short list of **Priorities** (what you want more of, in order) and
**Avoid** (what you do not want proposed). The loop reads it at the start of Phase B and weights its
proposals toward it; it can never write it. It only steers proposals: it never makes the loop build
anything or relaxes a rule. Missing or empty (only headings/comments) = the loop uses its own judgment.
Edit it in `D:\projects\solid-website\innovation`, commit, push; the next run picks it up.

## Approving

- Read the proposal. Add **`approved`** to green-light it. Only you can: the loop checks that the last
  `labeled approved` event was by `vekbui96`, and it can never add the label itself.
- To adjust scope, comment (before or after approving). Your comments (not the loop's, which carry a
  hidden `<!-- innovation-loop -->` marker) are adjustments. Comments from anyone else are ignored.
- If you **edit the issue body after approving**, the loop will not build it until you remove and re-add
  `approved`, so what gets built is what you approved.
- A proposal marked **Manual / needs Ve** is never built or deployed by the loop:
  API config / `.env` / `render.yaml` / `Dockerfile`, CORS, the pom artifactId/version, the contact
  contract (except an `area:both` change of both sides), `vite.config.ts`, `fit-backend/`, `openspec/`, `.github/`.
- A proposal marked **FLAGGED: content claims** (Fit Analyzer gap terms / strengths, profile and hero copy,
  `projects.json` content, experience text): approving it is your sign-off on that content.
- A visible change arrives with **before/after screenshots** in its PR and success comment (phone width, plus
  desktop when the desktop layout changed); "No visible change." otherwise.
- To reject: close the issue. The loop will not propose it again.

## Labels

| Label              | Meaning                                  |
| ------------------ | ---------------------------------------- |
| `loop:proposal`    | an idea from the loop                    |
| `loop:spec`        | a spec (also a proposal); never built    |
| `size:small`       | small: built with the cheaper model      |
| `test-only`        | tests only: built with the cheaper model |
| `approved`         | you said go (you set this)               |
| `loop:in-progress` | being built right now                    |
| `loop:deployed`    | shipped, verified live, closed           |
| `loop:failed`      | failed or rolled back; read the comments |
| `loop:retried`     | its one automatic retry was used         |
| `area:frontend` | which repo(s) it touches | the loop, when opening the issue |
| `area:backend` | which repo(s) it touches | the loop, when opening the issue |
| `area:both` | which repo(s) it touches | the loop, when opening the issue |

## Install, enable, run

```powershell
# once, from an ELEVATED PowerShell (SSH to server-pc is elevated). S4U by default: no password stored.
D:\projects\solid-website\innovation\install-task.ps1                      # -ExtraArgs '-ProposeOnly' for the supervised start
#   -LogonType Password asks for your password in the console (Read-Host); an empty one is refused

# then from a NORMAL PowerShell: prove the non-elevated loop can start the elevated task (touches nothing)
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -SelfTest

Enable-ScheduledTask  -TaskName InnovationLoop
Disable-ScheduledTask -TaskName InnovationLoop
Start-ScheduledTask   -TaskName InnovationLoop       # run once now

# by hand, from a NORMAL PowerShell:
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -ProposeOnly   # supervised run
powershell -ExecutionPolicy Bypass -File D:\projects\solid-website\innovation\run-loop.ps1 -DryRun        # everything except the claude call
```

| Task                                  | Runs as                          | Trigger                       | Does                                                                |
| ------------------------------------- | -------------------------------- | ----------------------------- | ------------------------------------------------------------------- |
| `InnovationLoop`         | SERVER-PC\VeBui, reduced token  | daily 13:17 (disabled at install) | `run-loop.ps1` from this checkout                        |
| `innovation-loop-api`  | SERVER-PC\VeBui, **highest**    | none (started on demand)      | `C:\ProgramData\innovation-loop-portfolio\bin\elevated-task.ps1`  |
| `innovation-loop-watch` (shared)      | SERVER-PC\VeBui, S4U            | every 10 min                  | starts this loop's task when you approve a proposal, to refill proposals (fewer than 5 awaiting review; at most hourly), or to drain approved work left after a run (state\drain.json) |

The loop task reads the scripts, `LOOP.md` and `FOCUS.md` from **this checkout**: keep it on `main` and
`git pull` to update the loop. The elevated task runs an **admin-only copy** of `lib.ps1`,
`loop.config.json`, `hooks-server.ps1`, `elevated-task.ps1`, `deploy-server.ps1`, `rollback-server.ps1`:
after pulling changes to any of those, re-run `install-task.ps1 -ElevatedOnly` (elevated). Until you do,
`run-loop.ps1` sees the copy differs and builds only changes that need no server deploy.

## Rights

The task's RunLevel does not make the session unprivileged: Windows gives an admin account's
non-interactive logons (scheduled tasks, S4U or Password) a full token whatever the RunLevel says. So
`run-loop.ps1` starts `claude` through `LowRights.cs`: a UAC-filtered copy of its own token
(CreateRestrictedToken LUA_TOKEN: Administrators deny-only, privileges reduced to SeChangeNotify,
TokenElevation=0) at Medium integrity, created suspended and resumed only after its real token passes the
check. The run log line `reduced child pid ... token: elevated=0 ... adminState=deny-only` proves it.
Privileged steps go through the deploy task: `deploy.ps1` / `rollback.ps1` write
`~\.innovation-loop-portfolio\elevated\request.json` `{ mode, issue, sha, requestedAt, nonce }`, run
`schtasks /run`, and poll `C:\ProgramData\innovation-loop-portfolio\results\<nonce>.json`. The elevated
wrapper validates the request as untrusted (fixed keys, mode allowlist, sha on a freshly fetched
origin/main, 15-minute age limit, nonce replay log, lock, scrubbed environment).

## What a deploy does

**Front end (solid-website, GitHub Pages).** No workflow publishes it: `hooks.ps1 Invoke-FrontendDeploy` runs
`yarn install --frozen-lockfile` and `yarn deploy --repo git@github-solid-website:vekbui96/solid-website.git`
(build:all + `gh-pages -d dist`) in the loop's clone at origin/main, after recording the current gh-pages sha
(`~\.innovation-loop-portfolio\state\ghpages-last.json`), then waits for the Pages build of the new gh-pages
commit. `Test-FrontendLive` proves the new build is served: the cache-busted page is a new build (its
`./assets/` set or its own bytes changed, so an `index.html`-only change counts), every chunk reachable from it
at any depth loads (`live-check.ps1`), `-ExpectString` is in `index.html` or one of them, the
Storybook sub-site and the resume PDF answer 200 (`frontend.extraLive`), and headless Edge renders
`<main-page>`'s shadow root. Rollback: gh-pages is force-with-lease reset to the recorded sha (instant; only
if gh-pages is still at that deploy), its Pages build awaited, then the merge is reverted on main, and the
string must be gone. A change that ships nothing new (gh-pages pushes nothing for an identical dist) is not
a failure. `src/ui/` (Storybook only) needs no `-ExpectString`.

**`-NoVisibleString "<why>"`** (test-gate.ps1 and deploy.ps1, instead of `-ExpectString`, never both) is for a
front-end change that ships no new bytes, like #36 (a bundle-budget script: `package.json` `"scripts"` plus files
outside the bundle), which was merged clean and then rolled back for want of a string. It is accepted only when
git proves the served output cannot change (`live-check.ps1` `Get-NoVisibleStringDecision`): every changed
front-end file is NEW under `src/` (Vite bundles only what is imported) or `package.json` with only `"scripts"`
changed; a modified, deleted or renamed `src/` file, anything in `public/`, `index.html`, `vite.config.ts` or
`yarn.lock` refuses it, as does a shipped `import.meta.glob`. The build output proves it: the test gate requires
the built `dist\index.html` (content-hashed asset names + its own bytes) to match the live site's signature, and
deploy.ps1 re-applies the git rule at the merge, then requires the served signature to be unchanged after the
deploy, plus the usual chunk walk, extra URLs and headless render. Every other front-end merge still needs
`-ExpectString`.

The gh-pages publish clone lives in `clones\solid-website\node_modules\.cache\gh-pages\`. The old loop's copy
was left owned by Administrators by an elevated run, and under the reduced token git refused it ("dubious
ownership"), which gh-pages reports as "Failed to get remote.origin.url" (runs 20261116-140147 and
20261121-194352, both exit 4, nothing went live). This loop has fresh clones made by the reduced runner,
`loop.config.json gitSafeExtra` gives every git child a `safe.directory` entry for that cache, gh-pages gets
`--repo` explicitly, and an unusable cache is deleted before publishing (gh-pages clones it again).

**Server (solid-website-api, the `solid-website-api` NSSM service, a jar).** Triggered when the merge changes
`src/main/`, `pom.xml`, `.mvn/` or `mvnw*`. The repo is private, so the elevated side deploys from its OWN
clone, `C:\ProgramData\innovation-loop-portfolio\clones\solid-website-api` (made by `install-task.ps1` over SSH
with an admin-only `config\ssh_config` + pinned GitHub host key; `server.elevatedClone`); that clone's HEAD is
the sha the live jar was built from. `hooks-server.ps1`: refuse a pom artifactId/version change; `git archive`
the target into `<ElevHome>\staging`, `mvnw -B -DskipTests package` with Maven settings / repository / wrapper
inside ElevHome (never the user's `~\.m2`); back up the live jar to `<ElevHome>\backups` (newest 5); stop /
copy / start; move the clone's HEAD; mirror the source into `D:\services\solid-website-api` (informational,
never `.env` or `target\`). Checks: local `/api/health` UP and the java pid stable for 4 x 10 s,
`/actuator/health`, the Funnel `/api/health`, an empty contact POST = 400 "Validation failed", a
honeypot-only POST = 200 "received" (dropped by the API: no email), and the CORS preflight from
`https://vekbui96.github.io` echoing exactly that origin. Rollback restores the backup jar and the HEAD. There
is no data to snapshot (the API keeps none).

**No CI.** Neither repo has GitHub Actions, so `merge-pr.ps1` itself (not the session) runs the local gate
on the PR's exact head in a fresh worktree before merging (`repos[].localGate`: front end install +
typecheck + build, API `mvnw -B verify`), and `wait-ci.ps1` answers PASS at once. Adding real CI is your call;
then list its check names in `requiredChecks` and the loop waits for them instead.

## Migration from the pre-kit loop (2026-11-21)

The loop was rebuilt on the shared kit that the cardlens loop runs. Kept: the task name `InnovationLoop` (the
approval watcher's entry is unchanged), the elevated task's name `innovation-loop-api` (its action changes on
the next install), the schedule 13:17, your `FOCUS.md`, the labels and every open issue (no migration:
`loop:proposal` / `area:*` / `approved` / `loop:failed` mean what they meant). New: one session per job
(`sessions.json`, yours, seeded from the cardlens defaults), wait-ci, failure markers with one automatic retry,
the plan-budget gate, specs with slices approved through their spec, the proposal cap 5, before/after
screenshots, the deep live check. State moved to `~\.innovation-loop-portfolio` (the old `~\.innovation-loop`
keeps its logs) and the elevated home to `C:\ProgramData\innovation-loop-portfolio` (the old
`C:\ProgramData\innovation-loop-api` keeps its jar backups and logs; delete both by hand when no longer wanted).
Until you run `install-task.ps1` once from an elevated PowerShell, API deploys are unavailable
(SERVER_DEPLOY=unavailable: such issues wait, still approved); front-end builds work without it.
Screenshots are published to the `loop-screenshots` branch of this repo (images only; nothing serves it).

## Where things are

| Path                                                                       | What                                                     |
| -------------------------------------------------------------------------- | -------------------------------------------------------- |
| `~\.innovation-loop-portfolio\logs\run-<time>.log`                       | runner log (start here)                                  |
| `...\logs\run-<time>.summary.txt`                                          | the run summary (every session's), ending in the run's `LOOP-RESULT: ...` |
| `...\logs\run-<time>.<build-n or propose>.jsonl`, `.prompt.md`             | each session's transcript and the prompt it got          |
| `...\logs\{test-gate,wait-ci,merge-pr,deploy,rollback}-*.log`              | non-elevated script logs                                 |
| `...\clones\<repo>`                                                        | the loop's own clones (never `D:\projects`, never live dirs) |
| `...\artifacts\<issue>\`                                                   | live / rolled-back screenshots                           |
| `...\state\`                                                               | merge, deploy and rollback records; `spec\` checklist ids |
| `C:\ProgramData\innovation-loop-portfolio\logs\`                         | elevated logs                                            |
| `C:\ProgramData\innovation-loop-portfolio\state\server-last-deploy.json` | PREV / target of the last server deploy                  |

## Rolling back by hand

```powershell
# front end and (if the loop deployed it) server, from a NORMAL PowerShell:
D:\projects\solid-website\innovation\rollback.ps1 -Issue <n> -MergeSha <merge sha> -AbsentString "<new UI string>"
# only revert main:
D:\projects\solid-website\innovation\rollback.ps1 -Issue <n> -MergeSha <merge sha> -RevertOnly
# only the server, from an ELEVATED PowerShell (uses the recorded PREV):
C:\ProgramData\innovation-loop-portfolio\bin\rollback-server.ps1
```

Exit codes for deploy/rollback scripts: `0` ok, `1` precondition failed (nothing changed), `2` failed and
rolled back, `3` rollback failed (look now), `4` install/build failed (server rolled back).

## Needs Ve: an uncertain deploy

When a build merges a change but the deploy is neither verified nor rolled back and verified (a deploy killed half
way, a failed rollback, a session that ended between merge and deploy), the runner stops the run with
`DEPLOY STATE UNCERTAIN, NEEDS VE` and writes the **needs-Ve flag**, `C:\Users\Ve Bui\.innovation-loop-portfolio\state\needs-ve.json` (run id, issue,
reason, time). It is a file of its own: no later run, `drain.json` or label can overwrite or lift it. While it
exists:

- every run of the loop (the daily task, `Start-ScheduledTask`, `-ProposeOnly`) stops before any claude session:
  summary `Needs-Ve stop`, `LOOP-RESULT: FAILED NEEDS VE: ...`, cost 0, exit 1. Nothing is built, merged, deployed or
  proposed, and `drain.json` is not rewritten;
- the approval watcher starts the loop for nothing (approvals, requests, refill, queue drain) and logs each skipped
  trigger once: `... approval skipped: NEEDS VE since ...`. Approvals made in the meantime are not used up: they start
  the loop once the flag is cleared;
- the run that set it says so in its summary (`NEEDS VE: the needs-Ve flag is set ...`), its run data
  (`needsVe`) and a `## Needs Ve: the loop is stopped` comment on the issue.

What to check, then clear it (normal PowerShell):

```powershell
# 1. what happened: the flag, the run's summary and log, and the deploy / rollback records
D:\projects\solid-website\innovation\clear-needs-ve.ps1                 # shows the flag, changes nothing
Get-Content C:\Users\Ve Bui\.innovation-loop-portfolio\logs\run-<runId>.summary.txt
Get-Content C:\Users\Ve Bui\.innovation-loop-portfolio\state\deploy-<n>*.json, C:\Users\Ve Bui\.innovation-loop-portfolio\state\rollback-<n>*.json
# 2. production: load the live site and the health check; fix by hand (deploy, roll back, revert) as needed
# 3. clear it, saying what you checked (kept with the record in state\needs-ve-cleared-<time>.json and logs\needs-ve.log)
D:\projects\solid-website\innovation\clear-needs-ve.ps1 -Clear -Note "live site OK; #39 reverted by hand"
```

The next daily run or watcher poll (within about 10 minutes) starts the loop again. Only you can clear it: the loop's
sessions cannot run `clear-needs-ve.ps1` or write `state\` (guard.mjs), and the script refuses to run inside a
loop run. A flag file that cannot be read still blocks (fail closed). Rules: `Get-NeedsVeBlock` in `gate-rules.ps1`
(literal copy in the watcher, checked by `test-queue-rules.ps1`).

## Safety, in short

- `dontAsk` + explicit allowlist: no npm/node/cmd/mvn/docker/schtasks/services for the session; installs,
  builds and tests go through `test-gate.ps1`, CI waits through `wait-ci.ps1`, merges through `merge-pr.ps1`,
  deploys through `deploy.ps1`. A proposal session gets `check-approval.ps1` only, and the guard refuses
  commits, pushes, PRs, comments and label edits in it; a build session cannot open issues.
- `guard.mjs` checks every tool call against `loop.config.json`: only this loop's repos; no secrets,
  `.env`, env dumps, SSH keys, gh token; nothing under live dirs (except the readable logs); GET-only HTTP to
  known URLs; one command per call; edits only in the loop's clones and never to protected paths; pushes
  only to `loop/<n>-<slug>`; never `approved`. `node innovation\test-guard.mjs` runs its allow/deny cases.

**One test browser at a time (Ve, 2026-11-24).** Every loop on server-pc (cardlens, portfolio, ops-hub) shares one test-browser slot: `browser-lock.mjs`, lock file `%USERPROFILE%\.innovation-loop-shared\browser.lock` (owner pid + hold-until; stale locks are taken over). `smoke.mjs` takes it (waits up to 5 min), runs at BelowNormal (the browser inherits it), never longer than 5 minutes, and is skipped under 2 GB free RAM; busy or low memory = exit 2 ("could not run"), i.e. unverified (busy), fail-open as before. `test-gate.ps1` runs at BelowNormal. Tests: `node innovation\test-browser-lock.mjs`.
- The guard is a guardrail, not a sandbox, and UAC is not a security boundary. The design keeps the claude
  session away from admin rights and makes the one elevated action narrow, validated and logged.
- **Accepted risk: the gh token.** The loop uses the normal `gh` login, which can reach all repos; the guard
  is what limits it to this loop's repos.
