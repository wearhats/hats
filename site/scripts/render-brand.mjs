// Renders the raster brand assets from their sources. Run after changing a tile, the mark or the fixture:
//   pnpm run render:brand
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { layoutRows, parseTable } from '../src/lib/table.ts';

const ROOT = new URL('..', import.meta.url).pathname;
const read = (path) => readFileSync(join(ROOT, path), 'utf8');
const font = readFileSync(join(ROOT, 'public/fonts/jetbrains-mono.var.woff2')).toString('base64');
const mark = read('public/favicon.svg');
const tiles = ['tile-claude-app', 'tile-work', 'tile-personal', 'tile-acme'].map((name) => read(`src/assets/brand/${name}.svg`));

// The card has room for these columns, and for every row but the stock install's.
const CARD_COLUMNS = ['PROFILE', 'KIND', 'STATUS', 'AGE'];
const ps = parseTable(read('fixtures/hats-ps.txt'), 'hats ps');
const columns = CARD_COLUMNS.map((header) => ps.headers.indexOf(header));
const pick = (cells) => columns.map((column) => cells[column]);
const shown = { headers: pick(ps.headers), rows: ps.rows.filter(([profile]) => profile !== 'default').map(pick) };
const terminal = layoutRows(shown).map((cells) => cells.join('')).join('\n');

const card = (width, height) => `<!doctype html><meta charset="utf-8"><style>
@font-face { font-family: JBM; src: url(data:font/woff2;base64,${font}) format('woff2'); font-weight: 100 800; }
* { box-sizing: border-box; margin: 0; }
body { width: ${width}px; height: ${height}px; background: #0f1115; color: #e6e8eb; font-family: JBM, monospace; padding: 64px 72px; display: flex; flex-direction: column; justify-content: space-between; overflow: hidden; }
.top { display: flex; align-items: center; justify-content: space-between; }
.logo { display: flex; align-items: center; gap: 14px; font-size: 36px; font-weight: 700; letter-spacing: -0.02em; }
.logo svg { width: 52px; height: 52px; }
.site { font-size: 28px; color: #a9afba; }
h1 { font-size: 86px; font-weight: 800; letter-spacing: -0.035em; line-height: 1.05; }
.bottom { display: flex; align-items: flex-end; justify-content: space-between; gap: 40px; }
pre { font: 500 25px/1.5 JBM, monospace; color: #e6e8eb; }
pre b { font-weight: 700; color: #a9afba; }
.note { font-size: 18px; color: #a9afba; margin-top: 10px; }
.tiles { display: flex; align-items: center; gap: 12px; }
.tiles svg { width: 68px; height: 68px; display: block; }
.divider { width: 2px; height: 56px; background: #3a414b; margin-inline: 6px; }
</style>
<div class="top"><div class="logo">${mark}<span>hats</span></div><div class="site">wearhats.dev</div></div>
<h1>Wear every hat<br>at once.</h1>
<div class="bottom">
  <div><pre>${terminal.replace(/^(.*)$/m, '<b>$1</b>')}</pre><div class="note">Sample output of hats ps</div></div>
  <div class="tiles">${tiles[0]}<span class="divider"></span>${tiles.slice(1).join('')}</div>
</div>`;

const browser = await chromium.launch();

async function shoot(html, width, height, out, omitBackground = false, scale = 1) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: scale });
  await page.setContent(html, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(ROOT, out), omitBackground, type: 'png' });
  await page.close();
}

await shoot(card(1200, 630), 1200, 630, 'public/og/home.png');
await shoot(card(1280, 640), 1280, 640, 'brand/github-social-preview.png');
await shoot(`<!doctype html><style>*{margin:0}body{background:transparent}svg{display:block;width:32px;height:32px}</style>${mark}`, 32, 32, 'public/favicon-32.png', true);
await browser.close();
