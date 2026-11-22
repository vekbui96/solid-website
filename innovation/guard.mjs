// PreToolUse hook for this project's innovation loop headless Claude session.
// Reads the hook JSON on stdin; exit 0 = allow, exit 2 = block (stderr is shown to the model).
// It FAILS CLOSED: any parse error blocks the call.
//
// Generic (from the innovation-loop kit): every project value comes from loop.config.json next to this
// file (repos, never-touch names, protected paths, allowed hosts, readable logs, session scripts). Edit the
// config, not this file. `node test-guard.mjs` runs its allow/deny cases.
//
// This is a guardrail, not a sandbox: the session runs as the owner's (reduced) Windows user, and an allowed
// script can do anything that user can. It stops the obvious and the accidental, and turns the LOOP.md rules
// that a string check can express into code. The permission allowlist in run-loop.ps1 is the other half:
// anything not listed there is denied before this hook runs.
/* global process */
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

function block(msg) {
  process.stderr.write(`innovation-loop guard blocked this: ${msg}\n`);
  process.exit(2);
}

// fileURLToPath, not URL.pathname: pathname keeps %20 for paths with spaces.
const HERE = path.dirname(fileURLToPath(import.meta.url));
let CFG;
try {
  CFG = JSON.parse(readFileSync(path.join(HERE, "loop.config.json"), "utf8"));
} catch {
  block("could not read loop.config.json next to guard.mjs (failing closed)");
}
const PROJECT = String(CFG.project || "");
if (!/^[a-z0-9][a-z0-9-]{1,40}$/.test(PROJECT)) block("loop.config.json has no valid project (failing closed)");
const PREFIX = "INNOVATION_LOOP_" + PROJECT.toUpperCase().replace(/-/g, "_");
const esc = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const norm = (p) => path.win32.normalize(String(p || "").replace(/\//g, "\\")).toLowerCase();
const HOME = norm(
  process.env[PREFIX + "_HOME"] ||
    path.join(process.env.USERPROFILE || "c:\\users\\unknown", ".innovation-loop-" + PROJECT),
).replace(/\\$/, "");
const SCRIPTS = norm(process.env[PREFIX + "_SCRIPTS"] || HERE).replace(/\\$/, "");
const REPOS = (CFG.repos || []).map((r) => ({ name: r.name, slug: String(r.slug).toLowerCase() }));
if (REPOS.length === 0) block("loop.config.json has no repos (failing closed)");
const OWNER = String(CFG.owner || "").toLowerCase();
const CLONES = REPOS.map((r) => HOME + "\\clones\\" + r.name.toLowerCase());
const inClone = (n) => CLONES.find((c) => n === c || n.startsWith(c + "\\"));
const SLUG_RE = REPOS.map((r) => esc(r.slug)).join("|");
const LIVE_ROOTS = (CFG.liveRoots || ["D:\\services"]).map(norm);
const READABLE = (CFG.readableLogs || []).map(norm); // prefixes the session may READ under a live root
const SESSION_SCRIPTS = (
  CFG.sessionScripts || ["check-approval", "test-gate", "wait-ci", "merge-pr", "deploy", "rollback"]
).map((s) => s.toLowerCase());
// The session kind, set by run-loop.ps1 before each session (one session per job): BUILD (one approved
// issue) or PROPOSE (Phase B proposals). FULL (unset: tests, older runners) allows both. A proposal session
// is read-only research plus opening issues; a build session opens no issues.
const MODE = String(process.env[PREFIX + "_MODE"] || "FULL").toUpperCase();
const READ_ONLY = ["PROPOSE", "PROPOSE_ONLY", "PRODUCT_REVIEW"].includes(MODE);
const AREAS = REPOS.length > 1 ? (CFG.areas || REPOS.map((r) => r.area || r.name)) : [];

const tool = (() => {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    block("could not parse hook input (failing closed)");
  }
  return null;
})();
const toolName = tool.tool_name || "";
const ti = tool.tool_input || {};

// ---- never-touch items, by name (anywhere: paths, patterns, commands) ------------------------
const NEVER = [
  [/\\\.ssh\b|\/\.ssh\b|~[\\/]\.ssh|id_(rsa|ed25519|ecdsa)/i, "SSH keys"],
  [/\bnssm\b/i, "NSSM"],
  [/\.server-setup|0\d-[\w-]*secret/i, "server setup / secret scripts"],
  [/currentcontrolset[\\/]+services|hklm:|hkey_local_machine/i, "service registry keys (service env holds secrets)"],
  [new RegExp(`\\.innovation-loop(?!-${esc(PROJECT)}\\b)`, "i"), "another innovation loop's state"],
  [/programdata[\\/]+innovation-loop/i, "the elevated side's directory (only the scripts talk to it)"],
  ...(CFG.neverTouch || []).map((n) => [new RegExp(n.pattern, n.flags || "i"), n.name]),
];
// secrets: .env files (not .env.example), credential stores, env dumps, gh token
const SECRET = [
  [/(^|[\\/\s"'=:])\.env(?!\.example)(\.[\w-]+)?($|[\s"'\\/;|),])/i, ".env files"],
  [/\$env:[\w]*(key|token|secret|password|pass|origins|credential)\b/i, "secret environment variables"],
  [/\b(Get-ChildItem|gci|dir|ls|Get-Item|gi)\s+env:/i, "environment dumps"],
  [/\benv:\\?\s*$|\[(System\.)?Environment\]::GetEnvironmentVariable|\b(printenv|set)\s*$/i, "environment dumps"],
  [/gh(\.exe)?["']?\s+auth\b/i, "gh auth"],
  [/hosts\.yml|github cli[\\/]/i, "gh's token store"],
  [/\.credentials|git\s+credential|cmdkey|Get-StoredCredential|vault/i, "credential stores"],
  [/\\users\\[^\\]+\\\.claude(\\|$)|~[\\/]\.claude([\\/]|$)/i, "Claude's own config and credentials"],
  ...(CFG.secretEnvNames || []).map((n) => [new RegExp(`\\b${esc(n)}\\b`), `secret ${n}`]),
];
function checkNames(s, what) {
  for (const [re, name] of NEVER) if (re.test(s)) block(`${what} references a never-touch item: ${name}`);
  for (const [re, name] of SECRET) if (re.test(s)) block(`${what} looks like it reads or prints a secret: ${name}`);
}
// Live roots (D:\services ...): only the configured log prefixes may be READ, nothing written, ever.
function checkLive(s, what, readOk) {
  const n = norm(s);
  for (const root of LIVE_ROOTS) {
    // esc() doubles each backslash of the root; turn every one into "one or more backslashes"
    const re = new RegExp(esc(root).replace(/\\\\/g, "\\\\+") + "[^\\s\"';|]*", "g");
    for (const h of n.match(re) || []) {
      if (readOk && READABLE.some((r) => h === r || h.startsWith(r))) continue;
      block(`${what} touches ${root} (${h}); only the fixed deploy scripts may. Readable: ${READABLE.join(", ") || "nothing"}`);
    }
  }
}
const PROTECTED = ["^\\.github/", "^\\.claude/", "^innovation/", "(^|/)\\.env", ...(CFG.protectedPaths || [])].map(
  (p) => new RegExp(p, "i"),
);
const isProtected = (rel) => PROTECTED.find((re) => re.test(rel));

// ---- file tools --------------------------------------------------------------------------------
if (["Read", "Edit", "Write", "MultiEdit", "NotebookEdit", "Glob", "Grep"].includes(toolName)) {
  const p = ti.file_path || ti.path || ti.notebook_path || "";
  checkNames(p, `${toolName} ${p}`);
  if (ti.glob) checkNames(ti.glob, `${toolName} glob`);
  checkLive(p, `${toolName} ${p}`, ["Read", "Grep", "Glob"].includes(toolName));
  if (["Edit", "Write", "MultiEdit", "NotebookEdit"].includes(toolName)) {
    const n = norm(p);
    const clone = inClone(n);
    const inWork = n.startsWith(HOME + "\\work\\") || n.startsWith(HOME + "\\artifacts\\");
    if (!clone && !inWork) block(`writes are only allowed in the loop clones (${CLONES.join(", ")}) and ${HOME}\\work / artifacts`);
    if (clone) {
      const rel = n.slice(clone.length + 1).replace(/\\/g, "/");
      if (rel === ".git" || rel.startsWith(".git/")) block("do not edit .git directly");
      if (isProtected(rel)) block(`${rel} is a protected path (out of scope for the loop: manual / needs the owner)`);
    }
    const content = [ti.content, ti.new_string, ...(Array.isArray(ti.edits) ? ti.edits.map((e) => e && e.new_string) : [])]
      .filter(Boolean)
      .join("\n");
    for (const root of LIVE_ROOTS)
      if (new RegExp(esc(root).replace(/\\\\/g, "[\\\\/]+"), "i").test(content))
        block(`new content references ${root} (tests and code must never point at live data)`);
    if (/VITE_[A-Z_]*(TOKEN|SECRET|PASSWORD|API_KEY)/.test(content))
      block("a secret-looking name in a VITE_ variable ships in the public bundle");
  }
  process.exit(0);
}

// ---- web ---------------------------------------------------------------------------------------
if (toolName === "WebFetch") {
  const u = String(ti.url || "");
  if (!(CFG.web && (CFG.web.fetchAllow || []).some((re) => new RegExp(re, "i").test(u))))
    block(`WebFetch is limited to: ${((CFG.web && CFG.web.fetchAllow) || []).join(" | ") || "nothing"}`);
  process.exit(0);
}
if (toolName === "WebSearch") block("WebSearch is not used by the loop");

// ---- shell -------------------------------------------------------------------------------------
if (toolName === "Bash" || toolName === "PowerShell") {
  const c = String(ti.command || "");
  checkNames(c, "command");
  checkLive(c, "command", /^\s*(Get-Content|Select-String|gc|cat|type)\b/i.test(c));

  // single-quoted strings are literal in PowerShell (e.g. a --jq filter), so separators inside them are fine;
  // double-quoted strings can run $(...) and are checked as they are.
  const unquoted = c.replace(/'[^']*'/g, "''").replace(/"[^"]*"/g, '""');
  const isGhOrGit = /^\s*["']?(gh|git)(\.exe)?["']?\s/i.test(c);
  if (
    /`|\$\(|\r|\n/.test(c) ||
    /[{}]/.test(unquoted) ||
    /[;&|]/.test(
      unquoted.replace(
        /\|\s*(Select-Object|Where-Object|ForEach-Object|Sort-Object|Measure-Object|Format-List|Format-Table|Out-String|ConvertFrom-Json|ConvertTo-Json|Select-String)\b/gi,
        "",
      ),
    )
  )
    block("one command per call: no ; & && || backticks, $(...), { } script blocks or newlines (pipes only into read-only formatting cmdlets)");
  if (/^\s*(cd|Set-Location|sl|Push-Location|pushd|chdir)\b/i.test(c)) block('do not change directory; use git -C "<clone>" and absolute paths');

  // only this loop's repos
  const ownerRe = new RegExp(`\\b${esc(OWNER)}\\/[A-Za-z0-9_.-]+`, "gi");
  for (const r of c.match(ownerRe) || [])
    if (!new RegExp(`^(${SLUG_RE})(\\.git)?$`, "i").test(r)) block(`only ${REPOS.map((x) => x.slug).join(", ")} may be touched (saw ${r})`);
  if (new RegExp(`github\\.com[:/](?!(${SLUG_RE})(\\.git)?\\b)`, "i").test(c)) block("git/gh against a repo outside this loop");

  // gh
  if (/(^|[\s"'\\])gh(\.exe)?["']?\s/i.test(c)) {
    const [g1, g2] = (c.match(/gh(?:\.exe)?["']?\s+([a-z-]+)(?:\s+([a-z-]+))?/i) || []).slice(1).map((x) => (x || "").toLowerCase());
    const named = new RegExp(`(-R|--repo)\\s+["']?(${SLUG_RE})\\b`, "i").test(c) || new RegExp(`repos/(${SLUG_RE})\\b`, "i").test(c);
    if (!named) block(`every gh command must name the repo: -R <owner/repo> (or a repos/<owner/repo>/... API path) of this loop`);
    const restricted = ["repo", "secret", "variable", "ssh-key", "gpg-key", "auth", "extension", "codespace", "gist", "org", "ruleset", "cache", "alias", "config", "release", "label", "workflow", "attestation", "project"];
    if (restricted.includes(g1)) {
      const ok =
        (g1 === "repo" && g2 === "view") ||
        (g1 === "workflow" && (g2 === "list" || g2 === "view")) ||
        (g1 === "release" && (g2 === "list" || g2 === "view")) ||
        (g1 === "label" && g2 === "list");
      if (!ok) block(`gh ${g1} ${g2 || ""} is not allowed for the loop`);
    }
    if (g1 === "api") {
      if (/\bgraphql\b/i.test(c)) block("gh api graphql is not used by the session (check-approval.ps1 does that)");
      if (/(-X|--method)\s*["']?(?!GET\b)\w+/i.test(c) || /\s(-f|-F|--field|--raw-field|--input)\s/i.test(c))
        block("gh api is read-only for the session (GET); use gh issue / gh pr subcommands to write");
    }
    if (g1 === "run" && !["list", "view", "watch", "download"].includes(g2)) block(`gh run ${g2} is not allowed (deploy.ps1 handles workflow runs)`);
    if (g1 === "pr") {
      if (g2 === "merge") block("merging is done only by merge-pr.ps1 (approval, protected paths, CI on the exact head sha)");
      if (["edit", "review", "ready", "reopen", "lock", "unlock", "update-branch", "revert"].includes(g2)) block(`gh pr ${g2} is not allowed`);
      if (g2 === "create" && !/--head\s+["']?loop\/\d+-[a-z0-9-]+\b/i.test(c)) block("gh pr create needs --head loop/<issue#>-<slug>");
      if ((g2 === "create" || g2 === "comment") && /\s(-b|--body)\s/i.test(c)) block("use --body-file <file in WORK>, not an inline body");
      if (g2 === "checks" && /\s--watch\b|\s-w\b/i.test(c))
        block("wait for CI with wait-ci.ps1 -Pr <n> (one call, one result line), not gh pr checks --watch");
    }
    if (g1 === "issue") {
      if (["delete", "transfer", "lock", "unlock", "pin", "unpin", "reopen", "develop"].includes(g2)) block(`gh issue ${g2} is not allowed`);
      if (g2 === "edit") {
        if (/\s(--body|--body-file|-b|--title|-t|--milestone|--assignee|--add-assignee|--remove-assignee|--add-project)\b/i.test(c))
          block("the loop never edits issue bodies/titles/assignees; post a comment instead");
        const labels = [...c.matchAll(/--(?:add|remove)-label\s+["']?([^"'\s]+)/gi)].flatMap((m) => m[1].split(","));
        if (labels.length === 0) block("gh issue edit is only for the loop:* state labels");
        for (const l of labels)
          if (!/^loop:(in-progress|deployed|failed|retried)$/i.test(l))
            block(`the loop may only add/remove loop:in-progress, loop:deployed, loop:failed (and add loop:retried) (saw ${l}); never 'approved'`);
        // loop:retried caps the automatic retry of a failed build at one; only the owner may take it off
        if (/--remove-label\s+["']?[^"'\s]*loop:retried\b/i.test(c))
          block("the loop never removes loop:retried (it limits a failed build to one automatic retry)");
      }
      if (g2 === "create") {
        // a build session builds its one issue and opens nothing (proposals and specs: the proposal session)
        if (MODE === "BUILD") block("a build session does not open issues (proposals and specs come from the proposal session)");
        if (!/--body-file\s/i.test(c)) block("gh issue create needs --body-file <file in WORK>");
        const labels = [...c.matchAll(/--label[\s=]+["']?([^"'\s]+)/gi)].flatMap((m) => m[1].toLowerCase().split(","));
        // a spec is a proposal too (it takes one slot) that check-approval.ps1 never builds: loop:proposal + loop:spec
        if (!labels.includes("loop:proposal")) block("gh issue create needs --label loop:proposal (a spec: --label loop:proposal --label loop:spec)");
        const SIZE = ["loop:proposal", "loop:spec", "size:small", "test-only"];
        for (const l of labels)
          if (!(SIZE.includes(l) || (AREAS.length && AREAS.some((a) => l === `area:${a}`))))
            block(
              `gh issue create may only set ${SIZE.join(", ")}${AREAS.length ? " and area:<" + AREAS.join("|") + ">" : ""} (saw ${l})`,
            );
        if (AREAS.length && !labels.some((l) => l.startsWith("area:"))) block(`multi-repo hub: add --label area:<${AREAS.join("|")}>`);
      }
      if (g2 === "comment" && (/\s(-b|--body)\s/i.test(c) || /--edit-last|--delete-last/i.test(c)))
        block("comment with --body-file <file in WORK>; never edit/delete comments");
    }
    if (/\bapproved\b/i.test(c) && /(--add-label|--remove-label|--label|labels)/i.test(c) && !/^\s*\S*gh(\.exe)?["']?\s+(issue|pr)\s+(list|view|status)\b/i.test(c))
      block("only the owner adds or removes 'approved'");
  }

  // proposal sessions are read-only research: no commits, pushes, PRs, comments or label changes
  if (READ_ONLY) {
    if (/\bgit(\.exe)?\b[^|;&]*\b(push|commit|merge|rebase|reset|checkout\s+-b|switch\s+-c|branch\s+\S)/i.test(c))
      block("a proposal session is read-only: no commits, branches or pushes");
    if (/\bgh(\.exe)?["']?\s+(pr\s+(create|merge|comment|close)|issue\s+(edit|close|comment))\b/i.test(c))
      block("a proposal session only reads and opens issues (proposals, specs); no PRs, edits or comments");
  }

  // git
  if (/\bgit(\.exe)?\b/i.test(c)) {
    if (/\bpush\b/i.test(c)) {
      if (/(\s--force\b|\s-f\b|--force-with-lease|--mirror|--delete|\s-d\s|\s\+[\w/]|:refs\/|\s:[\w/]|\bmain\b|--all|--tags|\s[\w./-]+:[\w./-]+)/i.test(c))
        block("no force/delete/main/refspec pushes (main changes only via merge-pr.ps1; reverts via deploy.ps1/rollback.ps1)");
      if (!/\bpush\s+(-u\s+|--set-upstream\s+)?origin\s+loop\/\d+-[a-z0-9-]+\s*$/i.test(c)) block("the loop may only `git push [-u] origin loop/<issue#>-<slug>`");
    }
    if (/\b(filter-branch|filter-repo|replace|update-ref|reflog\s+expire|gc\s+--prune|worktree|clone|submodule)\b/i.test(c))
      block("history rewriting, worktrees, clones and submodules are not allowed");
    if (/\badd\s+(-A\b|--all\b|-u\b|\.(\s|$)|\*)/i.test(c)) block("stage explicit paths only (no git add -A / . / -u / *)");
    if (/\bconfig\b/i.test(c) && !/\bconfig\s+(--get|-l|--list)\b/i.test(c)) block("no git config changes");
    if (/\bremote\s+(add|set-url|remove|rm|rename|set-head)/i.test(c)) block("no remote changes");
    if (/--no-verify|\bcommit\b[^]*\s-m\s/i.test(c)) block("commit with -F <message file in WORK> (and never --no-verify)");
    const dirs = [...c.matchAll(/\s-C\s+("([^"]+)"|'([^']+)'|(\S+))/gi)].map((m) => norm(m[2] || m[3] || m[4]));
    for (const d of dirs) if (!inClone(d)) block(`git -C must point at a loop clone (${CLONES.join(", ")}); saw ${d}`);
    if (dirs.length === 0 && !/^\s*git(\.exe)?\s+(--version|version|help)\b/i.test(c)) block('always run git as git -C "<clone>" ...');
  }

  // HTTP: GET only, allowed URLs only, never a token, never the write routes
  if (/\b(Invoke-WebRequest|Invoke-RestMethod|iwr|irm|curl|wget)\b/i.test(c)) {
    if (/-Method\s+["']?(?!GET\b|HEAD\b)\w+|\s-(Body|InFile|Form)\b|\s(-X|--request|-d|--data[\w-]*|-F|--form|-T|--upload-file)\s/i.test(c))
      block("HTTP from the session is GET-only (never POST to production)");
    if (/authorization|bearer|-Headers|\s-H\s|-Credential|-UseDefaultCredentials/i.test(c)) block("no auth headers / credentials in HTTP calls");
    const urls = c.match(/https?:\/\/[^\s"']+/gi) || [];
    if (urls.length === 0) block("HTTP calls must spell out a full URL");
    const allowList = ((CFG.web && CFG.web.httpAllow) || []).map((re) => new RegExp(re, "i"));
    const forbidden = CFG.web && CFG.web.forbiddenRoutes ? new RegExp(CFG.web.forbiddenRoutes, "i") : null;
    for (const u of urls) {
      if (!allowList.some((re) => re.test(u))) block(`HTTP URL not allowed: ${u}`);
      if (forbidden && forbidden.test(u)) block(`route not allowed from the session (it writes): ${u}`);
    }
  }

  // machine safety (gh/git commands are exempt: their text is titles, messages and refs)
  if (!isGhOrGit && /\b(Stop|Start|Restart|Set|New|Remove|Suspend|Resume)-Service\b|\bsc(\.exe)?\s+(stop|start|config|delete|create)\b|\bnet\s+(stop|start|user|localgroup)\b/i.test(c))
    block("services are only restarted by the elevated deploy task");
  if (
    !isGhOrGit &&
    /schtasks|ScheduledTask|Set-ExecutionPolicy|\breg(\.exe)?\s|New-ItemProperty|Set-ItemProperty|Remove-ItemProperty|NetFirewall|netsh|Restart-Computer|Stop-Computer|shutdown(\.exe)?\b|bcdedit|diskpart|format\s+[a-z]:|takeown|icacls|Set-Acl|Add-MpPreference|Set-MpPreference|Stop-Process|\bkill\b|taskkill|runas|Start-Process|docker/i.test(c)
  )
    block("system administration commands are out of scope (deploys go through deploy.ps1, which triggers only the one elevated task)");
  if (!isGhOrGit && /\b(Invoke-Expression|iex|Invoke-Command|icm)\b|DownloadString|DownloadFile|-EncodedCommand|\s-enc\s|FromBase64String|Add-Type|\[scriptblock\]/i.test(c))
    block("no dynamic/encoded code execution");
  // Only the first token runs (separators, $(...) and script blocks are blocked), so judge that token.
  const first = (unquoted.trim().split(/\s+/)[0] || "").replace(/^["']|["']$/g, "");
  const exe = path.win32.basename(first).toLowerCase().replace(/\.(exe|cmd|bat|ps1)$/, "");
  const interpreters = ["npm", "npx", "pnpm", "yarn", "node", "tsx", "vite", "vitest", "playwright", "python", "python3", "py", "cmd", "bash", "sh", "wsl", "pwsh", "powershell", "powershell_ise", "cscript", "wscript", "mshta", "rundll32", "regsvr32", "java", "mvn", "mvnw", "gradle", "gradlew", "dotnet", "cargo", "go", "ruby", "perl", "deno", "bun", "start"];
  if (!/\.ps1$/i.test(first) && interpreters.includes(exe))
    block("no interpreters, build tools or package managers directly: they go through test-gate.ps1");
  // scripts: only the pinned innovation scripts the session may run
  if (/\.ps1\b/i.test(c)) {
    const ps1 = [...c.matchAll(/"([^"]*\.ps1)"|'([^']*\.ps1)'|([^\s"';|&]+\.ps1)\b/gi)].map((m) => m[1] || m[2] || m[3]);
    for (const s of ps1) {
      const f = norm(s);
      if (!f.startsWith(SCRIPTS + "\\")) block(`scripts must be called by bare full path from ${SCRIPTS}\\<name>.ps1 (saw ${s})`);
      const base = path.win32.basename(f).replace(/\.ps1$/, "");
      if (!SESSION_SCRIPTS.includes(base)) block(`${s} is not a script the session may run (allowed: ${SESSION_SCRIPTS.join(", ")})`);
      if (READ_ONLY && base !== "check-approval")
        block(`a proposal session is read-only: ${s} builds, merges or deploys and is not allowed in it`);
    }
  }

  // shell writes: confine to the loop home's work/artifacts and the clones
  if (
    !isGhOrGit &&
    /\b(Remove-Item|rm|rmdir|del|erase|rd|ri|Move-Item|mv|move|Rename-Item|ren|Copy-Item|cp|copy|cpi|New-Item|ni|mkdir|md|Set-Content|sc|Add-Content|ac|Out-File|Clear-Content|Expand-Archive|Compress-Archive)\b|\s>>?\s?/i.test(c)
  ) {
    const re = /"([A-Za-z]:[\\/][^"]*)"|'([A-Za-z]:[\\/][^']*)'|([A-Za-z]:[\\/][^\s;|"']*)/g;
    const paths = [...c.matchAll(re)].map((m) => norm(m[1] || m[2] || m[3]));
    if (paths.length === 0) block("file-changing commands must use absolute paths (inside a loop clone or WORK)");
    for (const p of paths) {
      const clone = inClone(p);
      const ok = clone || p.startsWith(HOME + "\\work\\") || p.startsWith(HOME + "\\artifacts\\") || p === HOME + "\\work";
      if (!ok) block(`file changes outside the loop clones / WORK: ${p}`);
      if (clone && p !== clone) {
        const rel = p.slice(clone.length + 1).replace(/\\/g, "/");
        if (isProtected(rel)) block(`${rel} is a protected path`);
      }
    }
  }
  process.exit(0);
}

// Agent, Task, NotebookEdit, etc. are denied by the allowlist; TodoWrite/ToolSearch are harmless.
process.exit(0);
