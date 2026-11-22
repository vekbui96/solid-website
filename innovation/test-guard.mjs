// Allow/deny cases for guard.mjs, built from loop.config.json. Run:  node innovation\test-guard.mjs
// Each case spawns guard.mjs with the hook JSON on stdin, exactly as Claude Code does. Exit 0 = all pass.
// Generic (from the innovation-loop kit). Add project-specific cases at the bottom (PROJECT CASES).
/* global process, console */
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const CFG = JSON.parse(readFileSync(path.join(here, "loop.config.json"), "utf8"));
const P = CFG.project;
const PREFIX = "INNOVATION_LOOP_" + P.toUpperCase().replace(/-/g, "_");
const HOME = `C:\\Users\\Someone\\.innovation-loop-${P}`;
const S = here;
const repo = CFG.repos[0];
const R = repo.slug;
const C = `${HOME}\\clones\\${repo.name}`;
const W = `${HOME}\\work`;
const env = { ...process.env, [PREFIX + "_HOME"]: HOME, [PREFIX + "_SCRIPTS"]: S };
const SHA = "0123456789abcdef0123456789abcdef01234567";
const area = CFG.repos.length > 1 ? ` --label area:${(CFG.areas || CFG.repos.map((r) => r.area || r.name))[0]}` : "";
const owner = CFG.owner;

const ps = (command) => ({ tool_name: "PowerShell", tool_input: { command } });
const allow = [
  ps(`${S}\\check-approval.ps1 -List`),
  ps(`${S}\\test-gate.ps1 -Issue 12 -Step all -ExpectString "New label"`),
  ps(`${S}\\merge-pr.ps1 -Pr 40 -Issue 12`),
  ps(`${S}\\deploy.ps1 -Issue 12 -MergeSha ${SHA} -ExpectString "New label"`),
  ps(`${S}\\rollback.ps1 -Issue 12 -MergeSha ${SHA} -RevertOnly`),
  ps(`git -C "${C}" status`),
  ps(`git -C "${C}" checkout -b loop/12-small-fix origin/main`),
  ps(`git -C "${C}" add src/a.ts src/a.test.ts`),
  ps(`git -C "${C}" commit -F "${W}\\msg-12.txt"`),
  ps(`git -C "${C}" push -u origin loop/12-small-fix`),
  ps(`gh issue list -R ${R} --label loop:proposal --state open --json number --limit 50`),
  ps(`gh issue view 12 -R ${R} --json title,body,labels,comments`),
  ps(`gh issue edit 12 -R ${R} --add-label loop:in-progress`),
  ps(`gh issue edit 12 -R ${R} --add-label loop:deployed --remove-label loop:in-progress`),
  // the one automatic retry of a failed build: swap loop:failed for loop:retried, continue the open PR
  ps(`${S}\\check-approval.ps1 -Slots`),
  ps(`gh issue edit 12 -R ${R} --remove-label loop:failed --add-label loop:retried --add-label loop:in-progress`),
  ps(`git -C "${C}" checkout -b loop/12-small-fix origin/loop/12-small-fix`),
  ps(`git -C "${C}" merge --no-edit origin/main`),
  ps(`git -C "${C}" merge --abort`),
  ps(`gh pr list -R ${R} --state open --json number,headRefName,title`),
  ps(`gh issue comment 12 -R ${R} --body-file "${W}\\c.md"`),
  ps(`gh issue create -R ${R} --title "Idea" --label loop:proposal${area} --body-file "${W}\\p.md"`),
  ps(`gh issue close 12 -R ${R}`),
  ps(`gh pr create -R ${R} --base main --head loop/12-small-fix --title "x" --body-file "${W}\\pr.md"`),
  ps(`gh run view 123 -R ${R} --log-failed`),
  ps(`Get-Content "${C}\\README.md" -TotalCount 50`),
  ps(`Start-Sleep -Seconds 120`),
  ps(`Remove-Item "${W}\\old.md"`),
  { tool_name: "Read", tool_input: { file_path: `${C}\\README.md` } },
  { tool_name: "Read", tool_input: { file_path: `${C}\\.env.example` } },
  { tool_name: "Read", tool_input: { file_path: `${S}\\FOCUS.md` } },
  { tool_name: "Edit", tool_input: { file_path: `${C}\\src\\a.ts`, old_string: "a", new_string: "b" } },
  { tool_name: "Write", tool_input: { file_path: `${W}\\c.md`, content: "<!-- innovation-loop -->\nhello" } },
  { tool_name: "TodoWrite", tool_input: { todos: [] } },
  // specs: a loop:proposal that is also loop:spec; slices are plain proposals (the "Part of #N" line is in
  // the body file), optionally marked size:small / test-only (the cheaper build model)
  ps(`gh issue create -R ${R} --title "Spec: x" --label loop:proposal --label loop:spec${area} --body-file "${W}\\spec.md"`),
  ps(`gh issue create -R ${R} --title "Slice" --label loop:proposal --label size:small${area} --body-file "${W}\\s1.md"`),
  ps(`gh issue create -R ${R} --title "Pin a rule" --label loop:proposal --label test-only${area} --body-file "${W}\\t.md"`),
];
const SESSION_SCRIPTS = CFG.sessionScripts || ["check-approval", "test-gate", "wait-ci", "merge-pr", "deploy", "rollback"];
if (SESSION_SCRIPTS.includes("wait-ci")) allow.push(ps(`${S}\\wait-ci.ps1 -Pr 40`));
const deny = [
  ps(`gh issue list -R ${owner}/some-other-repo`),
  ps(`gh issue list`),
  ps(`gh issue edit 12 -R ${R} --add-label approved`),
  ps(`gh issue edit 12 -R ${R} --remove-label loop:retried`),
  ps(`gh issue edit 12 -R ${R} --add-label loop:failed --remove-label loop:retried`),
  ps(`gh issue edit 12 -R ${R} --remove-label loop:in-progress,loop:retried`),
  ps(`gh issue edit 12 -R ${R} --add-label loop:retry-forever`),
  ps(`gh issue edit 12 -R ${R} --body-file "${W}\\b.md"`),
  ps(`gh issue create -R ${R} --title x --label loop:proposal --label approved${area} --body-file "${W}\\p.md"`),
  ps(`gh pr merge 40 -R ${R} --merge`),
  ps(`gh api -X POST repos/${R}/issues/12/labels -f labels[]=approved`),
  ps(`gh auth token`),
  ps(`git -C "${C}" push origin main`),
  ps(`git -C "${C}" push --force origin loop/12-x`),
  ps(`git -C "${C}" add -A`),
  ps(`git -C "${C}" commit -m "x"`),
  ps(`git -C "D:\\projects\\${repo.name}" status`),
  ps(`git status`),
  ps(`npm.cmd ci`),
  ps(`node -e "1"`),
  ps(`cmd /c dir`),
  ps(`schtasks /run /tn innovation-loop-${P}-deploy`),
  ps(`Restart-Service whatever`),
  ps(`Get-ChildItem env:`),
  ps(`git -C "${C}" status; Remove-Item C:\\x`),
  ps(`cd ${C}`),
  ps(`${S}\\install-task.ps1`),
  ps(`${S}\\run-loop.ps1 -DryRun`),
  ps(`Invoke-WebRequest https://example.com/ -Method POST`),
  // specs: always a proposal too; never added or removed by edit; no other labels on create
  ps(`gh issue create -R ${R} --title "Spec: x" --label loop:spec${area} --body-file "${W}\\spec.md"`),
  ps(`gh issue edit 70 -R ${R} --add-label loop:spec`),
  ps(`gh issue edit 70 -R ${R} --remove-label loop:spec`),
  ps(`gh issue edit 70 -R ${R} --add-label size:small`),
  ps(`gh issue create -R ${R} --title x --label loop:proposal --label made-up${area} --body-file "${W}\\p.md"`),
  // CI is waited for with wait-ci.ps1, never watched
  ps(`gh pr checks 40 -R ${R} --watch`),
  ps(`${C}\\innovation\\wait-ci.ps1 -Pr 40`),
  { tool_name: "Write", tool_input: { file_path: `${S}\\sessions.json`, content: "{}" } },
  { tool_name: "Read", tool_input: { file_path: "C:\\Users\\Someone\\.ssh\\config" } },
  { tool_name: "Read", tool_input: { file_path: `${C}\\.env` } },
  { tool_name: "Read", tool_input: { file_path: "C:\\Users\\Someone\\.claude\\.credentials.json" } },
  { tool_name: "Edit", tool_input: { file_path: `${C}\\innovation\\LOOP.md`, old_string: "a", new_string: "b" } },
  { tool_name: "Edit", tool_input: { file_path: `${C}\\.github\\workflows\\ci.yml`, old_string: "a", new_string: "b" } },
  { tool_name: "Write", tool_input: { file_path: `${S}\\FOCUS.md`, content: "x" } },
  { tool_name: "Write", tool_input: { file_path: `D:\\projects\\${repo.name}\\x.ts`, content: "x" } },
  { tool_name: "Write", tool_input: { file_path: `${C}\\src\\x.ts`, content: 'const p = "D:\\\\services\\\\data";' } },
  { tool_name: "WebFetch", tool_input: { url: "https://evil.example.com/", prompt: "x" } },
  { tool_name: "WebSearch", tool_input: { query: "x" } },
];
for (const r of CFG.liveRoots || ["D:\\services"])
  deny.push({ tool_name: "Write", tool_input: { file_path: `${r}\\anything.txt`, content: "x" } });
for (const n of CFG.neverTouch || []) {
  const sample = n.sample;   // optional literal in the config entry that the pattern must match
  if (sample) deny.push({ tool_name: "Read", tool_input: { file_path: `D:\\projects\\${sample}\\README.md` } });
}
// ---- PROJECT CASES (add allow/deny cases for this project's hosts, routes and protected paths) ----
for (const u of (CFG.web && CFG.web.fetchSamples) || []) allow.push({ tool_name: "WebFetch", tool_input: { url: u, prompt: "x" } });
for (const p of CFG.protectedSamples || []) deny.push({ tool_name: "Edit", tool_input: { file_path: `${C}\\${p}`, old_string: "a", new_string: "b" } });

// one session per job: run-loop.ps1 tells the guard the session kind (<PREFIX>_MODE)
const buildEnv = { ...env, [PREFIX + "_MODE"]: "BUILD" };
const proposeEnv = { ...env, [PREFIX + "_MODE"]: "PROPOSE" };
const kinds = [
  [buildEnv, 0, ps(`${S}\\merge-pr.ps1 -Pr 40 -Issue 12`)],
  [buildEnv, 0, ps(`git -C "${C}" push -u origin loop/12-small-fix`)],
  [buildEnv, 2, ps(`gh issue create -R ${R} --title x --label loop:proposal${area} --body-file "${W}\\p.md"`)],
  [buildEnv, 2, ps(`gh issue create -R ${R} --title x --label loop:proposal --label loop:spec${area} --body-file "${W}\\s.md"`)],
  [proposeEnv, 0, ps(`${S}\\check-approval.ps1 -Slots`)],
  [proposeEnv, 0, ps(`gh issue create -R ${R} --title "Spec: y" --label loop:proposal --label loop:spec${area} --body-file "${W}\\spec.md"`)],
  [proposeEnv, 0, ps(`gh issue list -R ${R} --label loop:proposal --state all --json number,title,state,labels --limit 200`)],
  [proposeEnv, 2, ps(`${S}\\test-gate.ps1 -Issue 12 -Step all`)],
  [proposeEnv, 2, ps(`${S}\\merge-pr.ps1 -Pr 40 -Issue 12`)],
  [proposeEnv, 2, ps(`git -C "${C}" commit -F "${W}\\m.txt"`)],
  [proposeEnv, 2, ps(`git -C "${C}" push -u origin loop/12-x`)],
  [proposeEnv, 2, ps(`gh issue comment 70 -R ${R} --body-file "${W}\\c.md"`)],
  [proposeEnv, 2, ps(`gh issue edit 12 -R ${R} --add-label loop:in-progress`)],
  [proposeEnv, 2, ps(`gh issue close 70 -R ${R}`)],
];

// ---- PROJECT CASES (portfolio) ----------------------------------------------------------------------------
const API = CFG.repos[1].slug;
const CA = `${HOME}\\clones\\${CFG.repos[1].name}`;
kinds.push(
  [buildEnv, 0, ps(`${S}\\screenshots.ps1 -Issue 12 -Label before`)],
  [buildEnv, 0, ps(`${S}\\screenshots.ps1 -Issue 12 -Label after`)],
  [buildEnv, 0, ps(`${S}\\screenshots.ps1 -Issue 12 -Publish`)],
  [buildEnv, 0, ps(`${S}\\test-gate.ps1 -Issue 12 -Step all -Repo solid-website-api`)],
  [buildEnv, 0, ps(`${S}\\merge-pr.ps1 -Pr 7 -Issue 12 -Repo solid-website-api`)],
  [buildEnv, 0, ps(`git -C "${CA}" push -u origin loop/12-api-tests`)],
  [buildEnv, 0, ps(`gh pr create -R ${API} --base main --head loop/12-api-tests --title "x" --body-file "${W}\\pr.md"`)],
  [buildEnv, 0, ps(`gh pr comment 40 -R ${R} --body-file "${W}\\shots.md"`)],
  [proposeEnv, 2, ps(`${S}\\screenshots.ps1 -Issue 12 -Publish`)],
);
allow.push(
  ps(`Invoke-RestMethod http://localhost:8080/api/health`),
  ps(`Invoke-WebRequest https://vekbui96.github.io/solid-website/ -UseBasicParsing`),
  { tool_name: "WebFetch", tool_input: { url: "https://vekbui96.github.io/solid-website/storybook/", prompt: "x" } },
  ps(`gh issue create -R ${R} --title "API: x" --label loop:proposal --label area:backend --body-file "${W}\\p.md"`),
  ps(`gh issue create -R ${R} --title "Both: x" --label loop:proposal --label area:both --body-file "${W}\\p.md"`),
);
deny.push(
  // the contact endpoint sends Ve a real email: never called, not even GET, not through any host
  ps(`Invoke-RestMethod -Method Post http://localhost:8080/api/contact -Body "{}"`),
  ps(`Invoke-WebRequest https://server-pc.tail0e4194.ts.net/api/contact`),
  ps(`Invoke-RestMethod https://solid-website-api.onrender.com/api/health`),
  // only the screenshots script publishes the screenshots branch; gh-pages only through deploy.ps1
  ps(`git -C "${C}" push origin HEAD:refs/heads/loop-screenshots`),
  ps(`git -C "${C}" push origin HEAD:gh-pages`),
  ps(`git -C "${C}" push --force origin gh-pages`),
  // a proposal in this multi-repo hub needs an area label
  ps(`gh issue create -R ${R} --title "x" --label loop:proposal --body-file "${W}\\p.md"`),
  // other projects and loops on the box
  ps(`Get-Content D:\\services\\cardlens\\server\\index.ts`),
  ps(`Get-Content C:\\ProgramData\\innovation-loop-watch\\watch-approvals.ps1`),
  ps(`Get-Content D:\\projects\\.server-setup\\07-secrets.ps1`),
  { tool_name: "Read", tool_input: { file_path: "D:\\services\\solid-website-api\\.env" } },
  ps(`gh api repos/vekbui96/cardlens/issues`),
);
let failed = 0;
function run(c, e = env) {
  const r = spawnSync(process.execPath, [path.join(here, "guard.mjs")], { input: JSON.stringify(c), env: e, encoding: "utf8" });
  return { code: r.status, err: (r.stderr || "").trim() };
}
for (const [e, want, c] of kinds) {
  const r = run(c, e);
  if (r.code !== want) { failed++; console.log(`FAIL (${e[PREFIX + "_MODE"]} session, should ${want ? "deny" : "allow"}): ${JSON.stringify(c.tool_input).slice(0, 160)}\n   ${r.err}`); }
}
for (const c of allow) {
  const r = run(c);
  if (r.code !== 0) { failed++; console.log(`FAIL (should allow): ${JSON.stringify(c.tool_input).slice(0, 160)}\n   ${r.err}`); }
}
for (const c of deny) {
  const r = run(c);
  if (r.code !== 2) { failed++; console.log(`FAIL (should deny): ${JSON.stringify(c.tool_input).slice(0, 160)}`); }
}
const total = allow.length + deny.length + kinds.length;
console.log(`${total - failed}/${total} guard cases pass`);
process.exit(failed ? 1 : 0);
