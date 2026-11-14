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
  ['editor-blocks-flyout', '?open=1&mode=blocks&panel=0', 1440, 900, 'Movement'],
  ['home', '', 1440, 900],
  ['update-banner-home', '?update=1.0.7', 1440, 900],
  ['update-banner-editor', '?open=1&mode=blocks&panel=0&update=1.0.7', 1440, 900],
];

const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--lang=en-US'], env: { ...process.env, LANG: 'en_US.UTF-8' } });
for (const [name, query, width, height, category] of shots) {
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, locale: 'en-US', timezoneId: 'Africa/Johannesburg' });
  await ctx.addInitScript((s) => localStorage.setItem('flutter.robocore-ide-v1', JSON.stringify(s)), JSON.stringify(store));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log(`[${name}] page error: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error') console.log(`[${name}] console: ${m.text().slice(0, 300)}`); });
  await page.goto(base + query, { waitUntil: 'load', timeout: 60000 });
  await page.waitForTimeout(20000); // the launch animation, then Blockly and Monaco loading in their frames
  if (category) {
    // Open a block category, so the block list (the flyout) shows, as when someone picks blocks.
    for (const f of page.frames()) {
      const opened = await f
        .evaluate((name) => {
          const B = window.Blockly;
          const ws = B && B.getMainWorkspace && B.getMainWorkspace();
          const tb = ws && ws.getToolbox && ws.getToolbox();
          if (!tb) return false;
          const item = tb.getToolboxItems().find((i) => i.getName && i.getName() === name);
          if (!item) return false;
          tb.setSelectedItem(item);
          return true;
        }, category)
        .catch(() => false);
      if (opened) break;
    }
    await page.waitForTimeout(1500);
  }
  await page.screenshot({ path: `${out}/${name}.png` });
  console.log(`saved ${name}.png`);
  await ctx.close();
}
await browser.close();
