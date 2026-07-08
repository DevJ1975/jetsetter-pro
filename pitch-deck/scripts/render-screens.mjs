// Renders the 9 phone-screen mockups to pitch-deck/screens/*.png at 3x.
// Run from the repo root:  node pitch-deck/scripts/render-screens.mjs
// Requires: Node 18+, `playwright` installed, and a Chromium build available
// (this repo's environment ships one under /opt/pw-browsers).
import { chromium } from 'playwright';
import { existsSync } from 'node:fs';
import path from 'node:path';

function findChrome() {
  for (const c of [
    process.env.PW_CHROME,
    '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  ]) if (c && existsSync(c)) return c;
  return undefined; // fall back to Playwright's own download
}

const HTML = 'file://' + path.resolve('pitch-deck/assets/mockups.html');
const OUT = 'pitch-deck/screens';
const IDS = ['cover', 'home', 'disruption', 'iris', 'wallet', 'expenses', 'inflight', 'paywall', 'emailimport'];

const exe = findChrome();
const browser = await chromium.launch(exe ? { executablePath: exe } : {});
const page = await browser.newPage({ deviceScaleFactor: 3 });
await page.goto(HTML, { waitUntil: 'networkidle' });
await page.waitForTimeout(300);

for (const id of IDS) {
  await page.locator('#' + id).screenshot({ path: `${OUT}/${id}.png`, omitBackground: true });
  console.log('shot', id);
}
await browser.close();
console.log('done →', OUT);
