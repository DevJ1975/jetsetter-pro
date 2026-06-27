// Renders the all-in-one contact sheet to pitch-deck/screens/_contact-sheet.png at 2x.
// Run from the repo root:  node pitch-deck/scripts/render-contact-sheet.mjs
// (Run render-screens.mjs first — the sheet embeds those PNGs.)
import { chromium } from 'playwright';
import { existsSync } from 'node:fs';
import path from 'node:path';

function findChrome() {
  for (const c of [
    process.env.PW_CHROME,
    '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  ]) if (c && existsSync(c)) return c;
  return undefined;
}

const HTML = 'file://' + path.resolve('pitch-deck/assets/contact-sheet.html');
const exe = findChrome();
const browser = await chromium.launch(exe ? { executablePath: exe } : {});
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(HTML, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);
await page.locator('#sheet').screenshot({ path: 'pitch-deck/screens/_contact-sheet.png' });
await browser.close();
console.log('done → pitch-deck/screens/_contact-sheet.png');
