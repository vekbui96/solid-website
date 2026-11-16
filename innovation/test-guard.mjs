// Allow/deny cases for guard.mjs. Run:  node innovation\test-guard.mjs
// Each case spawns guard.mjs with the hook JSON on stdin, exactly as Claude Code does.
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const HOME = 'C:\\Users\\Ve Bui\\.innovation-loop';
const S = 'D:\\projects\\solid-website\\innovation';
const F = `${HOME}\\clones\\solid-website`;
const W = `${HOME}\\work`;
const env = { ...process.env, INNOVATION_LOOP_HOME: HOME, INNOVATION_LOOP_SCRIPTS: S };
const ps = (command) => ({ tool_name: 'PowerShell', tool_input: { command } });

const allow = [
  ps(`${S}\\check-approval.ps1 -List`),
  ps(`${S}\\test-frontend.ps1 -Issue 4 -Label after`),
  ps(`${S}\\deploy-frontend.ps1 -MergeSha 0123456789abcdef0123456789abcdef01234567 -ExpectString "aria-pressed"`),
  ps(`${S}\\api-request.ps1 -Mode noop -TimeoutMinutes 3`),
  // progress.ps1: the one way the session updates its live progress comment
  ps(`${S}\\progress.ps1 -Issue 4 -Stage approval -Status ok -Detail "check-approval exit 0"`),
  ps(`${S}\\progress.ps1 -Issue 4 -Stage test -Detail "yarn build:all + preview check running"`),
  ps(`${S}\\progress.ps1 -Issue 4 -Stage done -Outcome rolled-back -Detail "served bytes check failed; rolled back"`),
  ps(`gh issue comment 4 -R vekbui96/solid-website --body-file "${W}\\c.md"`),
  ps(`gh issue edit 4 -R vekbui96/solid-website --add-label loop:in-progress`),
  ps(`gh api repos/vekbui96/solid-website/issues/4/comments`),
  ps(`git -C "${F}" push -u origin loop/4-filter-aria`),
];
const deny = [
  // editing comments directly (only progress.ps1 edits, and only its own marker-checked comment)
  ps(`gh api repos/vekbui96/solid-website/issues/comments/123 -X PATCH -f body=x`),
  ps(`gh api -X PATCH repos/vekbui96/solid-website/issues/comments/123 --input "${W}\\b.json"`),
  ps(`gh api --method PATCH repos/vekbui96/solid-website/issues/comments/123 -f body=x`),
  ps(`gh api repos/vekbui96/solid-website/issues/comments/123 -f body=x`),
  ps(`gh issue comment 4 -R vekbui96/solid-website --edit-last --body-file "${W}\\c.md"`),
  ps(`gh pr comment 12 -R vekbui96/solid-website --delete-last`),
  // the runner-only scripts
  ps(`${S}\\reporting.ps1`),
  ps(`${S}\\test-reporting.ps1`),
  ps(`${S}\\run-loop.ps1 -ProposeOnly`),
  ps(`${S}\\lib.ps1`),
  // progress.ps1 from anywhere but the pinned dir
  ps(`${F}\\innovation\\progress.ps1 -Issue 4 -Stage plan`),
  ps(`& "${S}\\progress.ps1" -Issue 4 -Stage plan; powershell -c x`),
  // unchanged rules
  ps(`gh api repos/vekbui96/solid-website/issues/4 -X DELETE`),
  ps(`gh issue edit 4 -R vekbui96/solid-website --add-label approved`),
  ps(`gh issue edit 4 -R vekbui96/solid-website --body "x"`),
  ps(`git -C "${F}" push origin main`),
];

let failed = 0;
const run = (c) => spawnSync(process.execPath, [path.join(here, 'guard.mjs')], { input: JSON.stringify(c), env, encoding: 'utf8' });
for (const c of allow) {
  const r = run(c);
  if (r.status !== 0) { failed++; console.log(`SHOULD ALLOW (exit ${r.status}): ${c.tool_input.command}\n  ${r.stderr.trim()}`); }
}
for (const c of deny) {
  const r = run(c);
  if (r.status !== 2) { failed++; console.log(`SHOULD BLOCK (exit ${r.status}): ${c.tool_input.command}`); }
}
const total = allow.length + deny.length;
if (failed) { console.log(`test-guard: ${failed} of ${total} cases FAILED`); process.exit(1); }
console.log(`test-guard: all ${total} cases pass (${allow.length} allow, ${deny.length} block)`);
