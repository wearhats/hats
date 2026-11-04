import { chromium } from 'playwright';
import lighthouse from 'lighthouse';
import { PAGES, startWrangler } from './support.mjs';

const MIN_SCORE = 0.95;
// Desktop scoring is stricter and swings by 0.1 on a shared machine, on unchanged code. The budgets are set on mobile.
const MIN_DESKTOP_PERFORMANCE = 0.85;
const MAX_LCP_MS = 1500;
const MAX_CLS = 0.05;
const PORT = 9333;
const RUNS = 3;

const server = await startWrangler(8789);
const browser = await chromium.launch({ args: [`--remote-debugging-port=${PORT}`] });
let failed = false;

try {
  for (const formFactor of ['mobile', 'desktop']) {
    for (const path of PAGES) {
      const config = {
        extends: 'lighthouse:default',
        settings:
          formFactor === 'desktop'
            ? { preset: 'desktop', formFactor, screenEmulation: { mobile: false, width: 1350, height: 940, deviceScaleFactor: 1, disabled: false } }
            : { formFactor },
      };
      const runLighthouse = async (onlyCategories) =>
        (await lighthouse(server.origin + path, { port: PORT, output: 'json', logLevel: 'error', onlyCategories }, config)).lhr;
      // Performance swings widely on a busy machine, so judge its median, as Lighthouse's own docs advise.
      // The other categories come out the same every run, so they run once.
      const full = await runLighthouse();
      const runs = [full];
      for (let run = 1; run < RUNS; run += 1) runs.push(await runLighthouse(['performance']));
      const median = runs.sort((a, b) => a.categories.performance.score - b.categories.performance.score)[Math.floor(RUNS / 2)];
      const reportFor = (id) => (id === 'performance' ? median : full);
      const scores = Object.fromEntries(Object.keys(full.categories).map((id) => [id, reportFor(id).categories[id].score]));
      const lcp = median.audits['largest-contentful-paint'].numericValue;
      const cls = median.audits['cumulative-layout-shift'].numericValue;
      console.log(formFactor, path, JSON.stringify(scores), `LCP ${Math.round(lcp)}ms`, `CLS ${cls.toFixed(3)}`);
      for (const [id, score] of Object.entries(scores)) {
        const minimum = id === 'performance' && formFactor === 'desktop' ? MIN_DESKTOP_PERFORMANCE : MIN_SCORE;
        if (score < minimum) {
          failed = true;
          const report = reportFor(id);
          const lost = Object.values(report.categories[id].auditRefs)
            .map((ref) => report.audits[ref.id])
            .filter((audit) => audit.score !== null && audit.score < 1 && audit.scoreDisplayMode !== 'informative');
          console.error(`  ${id} below ${minimum}:`, lost.map((audit) => audit.id).join(', '));
        }
      }
      if (lcp > MAX_LCP_MS || cls > MAX_CLS) {
        failed = true;
        console.error(`  over budget: LCP ${lcp}, CLS ${cls}`);
      }
    }
  }
} finally {
  await browser.close();
  server.stop();
}

process.exit(failed ? 1 : 0);
