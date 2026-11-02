import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { startWrangler } from '../tests/support.mjs';

// Usage: pnpm run screenshots <output-dir> [path...]
const [outDir = 'test-results/screenshots', ...requested] = process.argv.slice(2);
const paths = requested.length ? requested : ['/', '/privacy', '/this-page-does-not-exist'];
const WIDTHS = [360, 768, 1280];

mkdirSync(outDir, { recursive: true });
const server = await startWrangler(8790);
const browser = await chromium.launch();

try {
  for (const path of paths) {
    const slug = path === '/' ? 'home' : path.replace(/\W+/g, '-').replace(/^-|-$/g, '');
    for (const width of WIDTHS) {
      for (const colorScheme of ['light', 'dark']) {
        for (const reducedMotion of ['no-preference', 'reduce']) {
          const context = await browser.newContext({ viewport: { width, height: 900 }, colorScheme, reducedMotion });
          const page = await context.newPage();
          await page.goto(server.origin + path, { waitUntil: 'networkidle' });
          await page.waitForTimeout(reducedMotion === 'reduce' ? 100 : 2000);
          const suffix = reducedMotion === 'reduce' ? '-reduced' : '';
          await page.screenshot({ path: join(outDir, `${slug}-${width}-${colorScheme}${suffix}.png`), fullPage: true });
          await context.close();
        }
      }
    }
  }
} finally {
  await browser.close();
  server.stop();
}
