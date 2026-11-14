// Screenshots of the web build for a pull request (build.yml, Web job): the editor in Blocks and in Code, and Home,
// so a layout change can be looked at without installing it. Usage: node tools/ci_screens.mjs <base url> <out dir>
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const [base, out] = process.argv.slice(2);
mkdirSync(out, { recursive: true });

// A returning user with the starter projects (the app adds them to an empty list), on the preview board.
const store = { v: 1, profile: true, user: 'Fredo', board: 'v2', port: 'sim', baud: 115200, connected: true, settings: {}, libs: {}, projects: [] };

const shots = [
  ['editor-blocks', '?open=1&mode=blocks&panel=0', 1440, 900],
  ['editor-code-serial', '?open=1&mode=code&panel=1', 1440, 900],
  ['editor-blocks-serial', '?open=1&mode=blocks&panel=1', 1440, 900],
  ['editor-blocks-small', '?open=1&mode=blocks&panel=0', 1100, 700],
  ['home', '', 1440, 900],
];

const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
for (const [name, query, width, height] of shots) {
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  await ctx.addInitScript((s) => localStorage.setItem('flutter.robocore-ide-v1', JSON.stringify(s)), JSON.stringify(store));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log(`[${name}] page error: ${e.message}`));
  await page.goto(base + query, { waitUntil: 'load', timeout: 60000 });
  await page.waitForTimeout(14000); // the launch animation, then Blockly and Monaco loading in their frames
  await page.screenshot({ path: `${out}/${name}.png` });
  console.log(`saved ${name}.png`);
  await ctx.close();
}
await browser.close();
