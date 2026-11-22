// First-load bundle budget.
//
// Reads dist/index.html after `vite build`, gzips every JS and CSS asset the
// page loads up front (<script src>, <link rel="stylesheet|modulepreload">),
// and compares the totals with bundle-budget.json. Exits 1 when either total
// rises above its recorded baseline (plus toleranceBytes, which absorbs small
// zlib differences between Node versions), so `yarn build:all` and
// `yarn deploy` fail.
//
// After an intentional size change, lower or raise the baseline on purpose:
//   node scripts/check-bundle-size.mjs --update
// If bundle-budget.json is missing, the current sizes are recorded as the
// baseline (one-time bootstrap).
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const budgetFile = join(root, "bundle-budget.json");
const DEFAULT_TOLERANCE = 512;

const html = readFileSync(join(dist, "index.html"), "utf8");

const refs = new Set();
for (const tag of html.match(/<(script|link)\b[^>]*>/gi) ?? []) {
  const isScript = /^<script/i.test(tag);
  if (!isScript && !/\brel=["']?(stylesheet|modulepreload)\b/i.test(tag)) continue;
  const m = tag.match(isScript ? /\bsrc=["']([^"']+)["']/i : /\bhref=["']([^"']+)["']/i);
  if (!m || /^(https?:)?\/\//i.test(m[1])) continue;
  refs.add(m[1].replace(/^\.?\//, "").split(/[?#]/)[0]);
}

let js = 0;
let css = 0;
const rows = [];
for (const ref of refs) {
  const bytes = gzipSync(readFileSync(join(dist, ref)), { level: 9 }).length;
  if (ref.endsWith(".css")) css += bytes;
  else if (ref.endsWith(".js")) js += bytes;
  else continue;
  rows.push(`  ${ref}  ${bytes} B gzip`);
}
if (js === 0) {
  console.error("bundle budget: no first-load JS found in dist/index.html");
  process.exit(1);
}

console.log("bundle budget: first-load assets");
for (const r of rows) console.log(r);
console.log(`bundle budget: JS ${js} B gzip, CSS ${css} B gzip`);

const record = (tolerance) => {
  writeFileSync(
    budgetFile,
    JSON.stringify({ jsGzipBytes: js, cssGzipBytes: css, toleranceBytes: tolerance }, null, 2) + "\n",
  );
  console.log(`bundle budget: baseline recorded in bundle-budget.json (JS ${js} B, CSS ${css} B)`);
};

if (!existsSync(budgetFile)) {
  record(DEFAULT_TOLERANCE);
  process.exit(0);
}

const budget = JSON.parse(readFileSync(budgetFile, "utf8"));
const tolerance = budget.toleranceBytes ?? DEFAULT_TOLERANCE;

if (process.argv.includes("--update")) {
  record(tolerance);
  process.exit(0);
}

const over = [];
if (js > budget.jsGzipBytes + tolerance) over.push(`JS ${js} B > baseline ${budget.jsGzipBytes} B`);
if (css > budget.cssGzipBytes + tolerance) over.push(`CSS ${css} B > baseline ${budget.cssGzipBytes} B`);

if (over.length) {
  console.error(`bundle budget EXCEEDED (tolerance ${tolerance} B): ${over.join("; ")}`);
  console.error("If the growth is intended, run: node scripts/check-bundle-size.mjs --update");
  process.exit(1);
}
console.log(
  `bundle budget OK: JS ${js}/${budget.jsGzipBytes} B, CSS ${css}/${budget.cssGzipBytes} B (tolerance ${tolerance} B)`,
);
