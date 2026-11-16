// Smoke check: load a URL in headless Edge/Chrome (via playwright-core, no bundled browser download),
// confirm the <main-page> custom element rendered a non-empty shadow root, and save a screenshot.
//
// usage: node smoke.mjs <repoPath> <url> <screenshot.png>
// exit 0 = rendered, 1 = did not render, 2 = could not run (no playwright-core / no browser)
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import path from 'node:path';

const [repoPath, url, shot] = process.argv.slice(2);
if (!repoPath || !url || !shot) {
  console.error('usage: node smoke.mjs <repoPath> <url> <screenshot.png>');
  process.exit(2);
}

let chromium;
try {
  // resolve from the repo under test so this script needs no node_modules of its own
  ({ chromium } = createRequire(path.join(repoPath, 'package.json'))('playwright-core'));
} catch (e) {
  console.error('playwright-core not installed in', repoPath);
  process.exit(2);
}

const candidates = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
];
const executablePath = candidates.find((p) => existsSync(p));
if (!executablePath) {
  console.error('no Edge/Chrome found');
  process.exit(2);
}

const browser = await chromium.launch({ executablePath, headless: true });
const errors = [];
try {
  // reduced motion: the site's reveal directive then shows every section at once, so the full-page
  // screenshot is complete instead of showing un-revealed blank bands below the fold
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1500);
  const info = await page.evaluate(() => {
    const el = document.querySelector('main-page');
    const root = el && el.shadowRoot;
    if (!root) return { found: !!el, shadow: false, children: 0, textLength: 0, sections: [] };
    const ids = Array.from(root.querySelectorAll('section[id]')).map((s) => s.id);
    return { found: true, shadow: true, children: root.childElementCount, textLength: (root.textContent || '').trim().length, sections: ids };
  });
  await page.screenshot({ path: shot, fullPage: true });
  const ok = info.found && info.shadow && info.children > 0 && info.textLength > 200;
  console.log(JSON.stringify({ ok, ...info, screenshot: shot, pageErrors: errors.slice(0, 10) }));
  process.exitCode = ok ? 0 : 1;
} catch (e) {
  console.error('smoke failed:', e && e.message ? e.message : e);
  process.exitCode = 1;
} finally {
  await browser.close();
}
