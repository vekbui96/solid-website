// Render check for the live (or a local) page: a blank SPA returns HTTP 200, so status codes prove nothing.
// Loads the URL in headless Edge/Chrome via the clone's playwright-core (no browser download), waits for the
// root element to have real content, and fails on an empty root or an uncaught page error.
// Generic (from the innovation-loop kit).
//
// usage: node smoke.mjs <repoPath> <url> [screenshot.png|""] [rootSelector=body] [width=390] [full]
// A root element that renders into a shadow root (a custom element) is measured through that shadow root.
// width: viewport width (height 844 below 800px, else 900); full: full-page screenshot.
// exit 0 = rendered, 1 = did not render / page error, 2 = could not run (no playwright-core / no browser)
/* global process, console, document */
import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import path from "node:path";

const [repoPath, url, shotArg, selectorArg, widthArg, fullArg] = process.argv.slice(2);
const shot = shotArg && shotArg !== "-" ? shotArg : ""; // "-" = no screenshot (PowerShell 5.1 drops empty arguments)
const selector = selectorArg || "body";
const width = Number(widthArg) > 0 ? Number(widthArg) : 390;
const fullPage = fullArg === "full";
if (!repoPath || !url) {
  console.error("usage: node smoke.mjs <repoPath> <url> [screenshot.png] [rootSelector]");
  process.exit(2);
}

let chromium;
try {
  const req = createRequire(path.join(repoPath, "package.json"));
  try {
    ({ chromium } = req("playwright-core"));
  } catch {
    ({ chromium } = req("@playwright/test"));
  }
} catch {
  console.error("playwright-core not installed in", repoPath);
  process.exit(2);
}

const candidates = [
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
];
const executablePath = candidates.find((p) => existsSync(p));
if (!executablePath) {
  console.error("no Edge/Chrome found");
  process.exit(2);
}

const browser = await chromium.launch({ executablePath, headless: true });
const pageErrors = [];
try {
  const page = await browser.newPage({ viewport: { width, height: width < 800 ? 844 : 900 }, reducedMotion: "reduce" });
  page.on("pageerror", (e) => pageErrors.push(String(e)));
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page
    .waitForFunction(
      (sel) => {
        const el = document.querySelector(sel);
        const r = el && el.shadowRoot ? el.shadowRoot : el;
        return !!r && r.childElementCount > 0 && (r.textContent || "").trim().length > 10;
      },
      selector,
      { timeout: 30000 },
    )
    .catch(() => {});
  await page.waitForTimeout(1500);
  const info = await page.evaluate((sel) => {
    const el = document.querySelector(sel);
    const r = el && el.shadowRoot ? el.shadowRoot : el;
    return { rootChildren: r ? r.childElementCount : -1, textLength: r ? (r.textContent || "").trim().length : 0, shadow: !!(el && el.shadowRoot), title: document.title };
  }, selector);
  if (shot) await page.screenshot({ path: shot, fullPage });
  const ok = info.rootChildren > 0 && info.textLength > 10 && pageErrors.length === 0;
  console.log(JSON.stringify({ ok, selector, width, ...info, screenshot: shot || null, pageErrors: pageErrors.slice(0, 5) }));
  process.exitCode = ok ? 0 : 1;
} catch (e) {
  console.error("smoke failed:", e && e.message ? e.message : e);
  process.exitCode = 1;
} finally {
  await browser.close();
}
