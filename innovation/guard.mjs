// PreToolUse hook for the innovation loop's headless Claude session.
// Reads the hook JSON on stdin; exit 0 = allow, exit 2 = block (stderr is shown to the model).
// It FAILS CLOSED: any parse error blocks the call.
//
// This is a guardrail, not a sandbox: an allowed interpreter (node, yarn scripts, mvnw) can still do
// anything the Windows user can. It exists to stop the obvious and the accidental, and to make the
// LOOP.md rules mechanical where a string check can express them.
//
// Env: INNOVATION_LOOP_HOME (state dir), INNOVATION_LOOP_SCRIPTS (the pinned innovation/ dir).
import { readFileSync } from 'node:fs';
import path from 'node:path';

const HOME = (process.env.INNOVATION_LOOP_HOME || path.join(process.env.USERPROFILE || '', '.innovation-loop')).toLowerCase();
const SCRIPTS = (process.env.INNOVATION_LOOP_SCRIPTS || '').toLowerCase();

function block(msg) {
  process.stderr.write(`innovation-loop guard blocked this: ${msg}\n`);
  process.exit(2);
}

let input;
try {
  input = JSON.parse(readFileSync(0, 'utf8'));
} catch (e) {
  block('could not parse hook input (failing closed)');
}
const tool = input.tool_name || '';
const ti = input.tool_input || {};

// normalize resolves ".." so a path cannot climb out of an allowed directory
const norm = (p) => path.win32.normalize(String(p || '').replace(/\//g, '\\')).toLowerCase();

// ---- things nobody in the loop may touch, by name ---------------------------------
const NEVER = [
  /cardlens/i, /\brecognition\b/i, /target-stock-checker/i, /palworld/i, /tailscale/i,
  /openclaw/i, /\bwsl(\.exe)?\b/i, /\\\.ssh\b|\/\.ssh\b|~\/\.ssh/i, /\bnssm\b/i, /\.server-setup/i,
  /04-install-services/i, /07-.*secret/i, /id_(rsa|ed25519|ecdsa)/i,
];
// secrets: .env files, the Resend key, credential stores
const SECRET = [
  /(^|[\\/\s"'=])\.env(\.[\w-]+)?($|[\s"'\\/;|)])/i, /RESEND_API_KEY/i, /\$env:[\w]*(key|token|secret|password|pass)\b/i,
  /\benv:\\?\s*$/i, /Get-ChildItem\s+env:/i, /\bgci\s+env:/i, /\bls\s+env:/i, /\b(printenv|set)\s*$/i,
  /gh(\.exe)?["']?\s+auth\s+(token|status\s+-t|refresh|login|logout)/i, /hosts\.yml/i, /\.credentials/i,
  /git\s+credential/i, /cmdkey/i, /Get-StoredCredential/i,
];

function checkPathLike(s, what) {
  for (const re of NEVER) if (re.test(s)) block(`${what} references a never-touch item (${re})`);
  for (const re of SECRET) if (re.test(s)) block(`${what} looks like it reads or prints a secret (${re})`);
  const n = norm(s);
  if (n.includes('d:\\services') && !/d:\\services\\logs\\solid-website-api\.(out|err)\.log/.test(n)) {
    block(`${what} touches D:\\services directly; only deploy-api.ps1/rollback-api.ps1 may (logs: D:\\services\\logs\\solid-website-api.{out,err}.log are readable)`);
  }
}

// ---- file tools -------------------------------------------------------------------
if (['Read', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Glob', 'Grep'].includes(tool)) {
  const p = ti.file_path || ti.path || ti.notebook_path || '';
  checkPathLike(p, `${tool} ${p}`);
  if (ti.pattern) checkPathLike(ti.pattern, `${tool} pattern`);
  if (ti.glob) checkPathLike(ti.glob, `${tool} glob`);
  if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(tool)) {
    const n = norm(p);
    if (!n.startsWith(HOME + '\\')) block(`writes are only allowed under ${HOME} (the loop clones, work and artifacts dirs)`);
    if (/\\innovation\\/.test(n)) block('the loop may not modify innovation/ (its own instructions and scripts)');
    if (/\\\.claude\\|\\\.github\\/.test(n)) block('the loop may not modify .claude/ or .github/');
    if (n.startsWith(HOME + '\\state\\') || n.startsWith(HOME + '\\lock\\') || n.startsWith(HOME + '\\api-backups\\') || n.startsWith(HOME + '\\logs\\')) {
      block('state, lock, backups and logs are managed by the scripts, not by hand');
    }
  }
  process.exit(0);
}

// ---- web --------------------------------------------------------------------------
if (tool === 'WebFetch') {
  const u = String(ti.url || '');
  if (!/^https:\/\/(vekbui96\.github\.io\/solid-website|server-pc\.tail0e4194\.ts\.net|solid-website-api\.onrender\.com)(\/|$)/i.test(u)) {
    block('WebFetch is limited to the live site and the API');
  }
  process.exit(0);
}
if (tool === 'WebSearch') process.exit(0);

// ---- shell ------------------------------------------------------------------------
if (tool === 'Bash' || tool === 'PowerShell') {
  const c = String(ti.command || '');
  checkPathLike(c, 'command');

  // only the two repos
  const repoRefs = c.match(/vekbui96\/[A-Za-z0-9_.-]+/gi) || [];
  for (const r of repoRefs) {
    if (!/^vekbui96\/(solid-website|solid-website-api)(\.git)?$/i.test(r)) block(`only vekbui96/solid-website and vekbui96/solid-website-api may be touched (saw ${r})`);
  }
  if (/github\.com[:/](?!vekbui96\/solid-website(-api)?(\.git)?\b)/i.test(c)) block('git/gh against a repo other than the two site repos');
  if (/\bgh(\.exe)?["']?\s/i.test(c) && /\bgh(\.exe)?["']?\s+(api|issue|pr|label|run|workflow|release|browse)\b/i.test(c)) {
    // gh calls that can target a repo must name one explicitly (-R/--repo or a repos/ path), or run inside a clone
    const named = /(-R|--repo)\s+["']?vekbui96\/solid-website(-api)?\b/i.test(c) || /repos\/vekbui96\/solid-website(-api)?\b/i.test(c) || /\bgraphql\b/.test(c);
    const inClone = /clones[\\/]solid-website/i.test(c);
    if (!named && !inClone) block('gh commands must name the repo explicitly with -R vekbui96/solid-website or -R vekbui96/solid-website-api');
  }
  if (/\bgh(\.exe)?["']?\s+(repo\s+(delete|archive|rename|edit|create|fork)|secret|variable|ssh-key|gpg-key|auth|extension|codespace|gist|org|ruleset|cache\s+delete|alias)/i.test(c)) {
    block('gh repo admin / secrets / auth / gist commands are not allowed');
  }
  if (/(-X|--method)\s*["']?(DELETE|PUT)\b/i.test(c)) block('gh api DELETE/PUT is not allowed');
  if (/--add-label[^|;&]*\bapproved\b/i.test(c) || /labels[^|;&]*\bapproved\b/i.test(c) && /\b(-X|--method|-f|-F|--field|--raw-field)\b/i.test(c)) {
    block('only Ve adds the approved label');
  }
  if (/\bgh(\.exe)?["']?\s+issue\s+(edit\s+\S+\s+(--body|-b|--title|-t)|delete|transfer|lock|pin)/i.test(c) || /\bgh(\.exe)?["']?\s+issue\s+edit\b[^|;&]*(--body|--title)/i.test(c)) {
    block('the loop never edits issue bodies/titles or deletes/transfers issues; post a comment instead');
  }
  if (/\bgh(\.exe)?["']?\s+pr\s+merge\b/i.test(c) && /--admin\b/i.test(c)) block('no admin merges');

  // git safety
  if (/\bgit\b[^|;&]*\bpush\b/i.test(c)) {
    if (/(\s--force\b|\s-f\b|--force-with-lease|--mirror|--delete|\s-d\s|\s\+[\w/]|:refs\/|\s:[\w/])/i.test(c)) block('force/delete pushes are only done by the rollback scripts');
    if (!/\bloop\/\d+[\w./-]*/i.test(c)) block('the loop may only push loop/<issue#>-<slug> branches (main changes go through a merged PR; reverts through the rollback scripts)');
  }
  if (/\bgit\b[^|;&]*\b(filter-branch|filter-repo|replace|update-ref|reflog\s+expire|gc\s+--prune)/i.test(c)) block('history-rewriting git commands are not allowed');
  if (/\bgit\b[^|;&]*\badd\s+(-A\b|--all\b|\.(\s|$))/i.test(c)) block('stage explicit paths only (no git add -A / git add .)');
  if (/\bgit\b[^|;&]*\bconfig\s+(--global|--system)/i.test(c)) block('no global git config changes');
  if (/\bgit\b[^|;&]*\bremote\s+(add|set-url|remove|rename)/i.test(c)) block('no remote changes');

  // machine safety
  if (/\b(Stop|Start|Restart|Set|New|Remove|Suspend)-Service\b|\bsc(\.exe)?\s+(stop|start|config|delete|create)\b|\bnet\s+(stop|start)\b/i.test(c)) block('services are only stopped/started by deploy-api.ps1 / rollback-api.ps1');
  if (/schtasks|ScheduledTask|Set-ExecutionPolicy|\breg(\.exe)?\s+(add|delete|import)|New-ItemProperty|Set-ItemProperty|NetFirewall|netsh|Restart-Computer|Stop-Computer|shutdown(\.exe)?\b|bcdedit|diskpart|format\s+[a-z]:|takeown|icacls|Add-MpPreference|Set-MpPreference|Stop-Process|taskkill/i.test(c)) {
    block('system administration commands are out of scope');
  }
  if (/\b(Invoke-Expression|iex)\b|DownloadString|-EncodedCommand|\s-enc\s|FromBase64String/i.test(c)) block('no dynamic/encoded code execution');
  if (/\b(npm|pnpm)\s+(i|install|ci|add)\b/i.test(c)) block('yarn is the package manager (never npm install)');
  if (/package-lock\.json/i.test(c) && /(New-Item|Set-Content|Out-File|>)/i.test(c)) block('never create package-lock.json');
  if (/\bnpx\b(?!\s+(--no-install\s+)?(tsc|vite)\b)(?!\s+--yes\s+lighthouse@12\b)/i.test(c)) block('npx is limited to tsc, vite and lighthouse@12');
  if (/\byarn\s+(add|remove|upgrade|global|link|publish|config)\b/i.test(c)) block('dependency changes need an approved proposal and are made by editing package.json, then yarn install');

  // scripts: only the pinned innovation scripts, and never the entry point / installer
  // Every .ps1 mentioned must be a full path inside the pinned scripts dir.
  if (/\.ps1\b/i.test(c)) {
    const ps1 = [...c.matchAll(/"([^"]*\.ps1)"|'([^']*\.ps1)'|([^\s"';|&]+\.ps1)\b/gi)].map((m) => m[1] || m[2] || m[3]);
    for (const s of ps1) {
      const f = norm(s);
      if (!SCRIPTS || !f.startsWith(SCRIPTS + '\\')) block(`scripts must be called by bare full path from the pinned scripts dir: ${SCRIPTS}\\<name>.ps1 (saw ${s})`);
      if (/(run-loop|install-task|lib)\.ps1$/.test(f)) block('the loop may not start itself, install tasks, or run lib.ps1');
    }
  }
  if (/\b(powershell|pwsh)(\.exe)?\b/i.test(c)) block('no nested PowerShell; call scripts by bare full path: <scripts dir>\\<name>.ps1 <args>');

  // writes from the shell: confine to the loop home (best effort)
  if (/\b(Remove-Item|rm|rmdir|del|rd|Move-Item|mv)\b/i.test(c)) {
    const re = /"([A-Za-z]:[\\/][^"]*)"|'([A-Za-z]:[\\/][^']*)'|([A-Za-z]:[\\/][^\s;|"']*)/g;
    for (const m of c.matchAll(re)) {
      const p = m[1] || m[2] || m[3];
      if (!norm(p).startsWith(HOME + '\\')) block(`delete/move outside ${HOME}: ${p}`);
    }
  }
  if (/innovation[\\/]/i.test(c) && /(Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item|New-Item|\s>>?\s|sed\s+-i)/i.test(c)) {
    block('the loop may not modify innovation/');
  }
  process.exit(0);
}

// Everything else (TodoWrite, ToolSearch, ...) is decided by the permission allowlist.
process.exit(0);
