import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { join, extname } from 'node:path';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { chromium } from 'playwright';
import { AxeBuilder } from '@axe-core/playwright';
import { SITE_ROOT, buildInto, cspFromHeaders, startWrangler } from './support.mjs';

const PAGES = ['/', '/privacy', '/this-page-does-not-exist'];
const VIEWPORTS = [{ width: 360, height: 800 }, { width: 768, height: 1024 }, { width: 1280, height: 800 }];
const ANALYTICS_DIST = 'dist-analytics';

let server;
let browser;

before(async () => {
  server = await startWrangler();
  browser = await chromium.launch();
});

after(async () => {
  await browser?.close();
  server?.stop();
  rmSync(join(SITE_ROOT, ANALYTICS_DIST), { recursive: true, force: true });
});

function watchPage(page) {
  const problems = [];
  const requests = [];
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(message.text());
  });
  page.on('pageerror', (error) => problems.push(error.message));
  page.on('request', (request) => requests.push(request));
  return { problems, requests };
}

test('built pages load cleanly under the real CSP, from their own origin only', async () => {
  for (const path of PAGES) {
    const page = await browser.newPage();
    const { problems, requests } = watchPage(page);
    const response = await page.goto(server.origin + path, { waitUntil: 'networkidle' });
    assert.match(response.headers()['content-security-policy'], /script-src 'self'/, path);
    const expected = path === '/this-page-does-not-exist' ? 404 : 200;
    assert.equal(response.status(), expected, path);
    const real = problems.filter((text) => !(expected === 404 && /404/.test(text)));
    assert.deepEqual(real, [], path);
    for (const request of requests) {
      assert.equal(new URL(request.url()).origin, server.origin, `${path} requested ${request.url()}`);
    }
    await page.close();
  }
});

test('the CSP really is enforced by this harness', async () => {
  const page = await browser.newPage();
  await page.goto(server.origin);
  const ran = await page.evaluate(() => {
    const script = document.createElement('script');
    script.textContent = 'window.__inlineRan = true';
    document.head.append(script);
    return window.__inlineRan === true;
  });
  assert.equal(ran, false);
  await page.close();
});

test('JetBrains Mono loads from the site', async () => {
  const page = await browser.newPage();
  await page.goto(server.origin, { waitUntil: 'networkidle' });
  const loaded = await page.evaluate(async () => {
    await document.fonts.ready;
    return document.fonts.check("700 16px 'JetBrains Mono'");
  });
  assert.equal(loaded, true);
  await page.close();
});

test('redirects and plumbing behave as deployed', async () => {
  const redirects = {
    '/docs': 'https://github.com/wearhats/hats/blob/main/docs/cli.md',
    '/changelog': 'https://github.com/wearhats/hats/releases',
    '/security': 'https://github.com/wearhats/hats/blob/main/SECURITY.md',
  };
  for (const [path, location] of Object.entries(redirects)) {
    const response = await fetch(server.origin + path, { redirect: 'manual' });
    assert.equal(response.status, 302, path);
    assert.equal(response.headers.get('location'), location);
  }
  for (const path of ['/robots.txt', '/sitemap.xml', '/.well-known/security.txt', '/favicon.svg']) {
    assert.equal((await fetch(server.origin + path)).status, 200, path);
  }
  const installScript = await fetch(`${server.origin}/install.sh`, { redirect: 'manual' });
  assert.equal(installScript.status, 404, 'the site must not answer /install.sh; the zone rule does');
  const missing = await fetch(`${server.origin}/nope`);
  assert.equal(missing.status, 404);
  assert.match(await missing.text(), /This hat doesn&#x27;t exist|This hat doesn't exist/);
  const home = await fetch(server.origin);
  assert.equal(home.headers.get('x-content-type-options'), 'nosniff');
  assert.match(home.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  const font = await fetch(`${server.origin}/fonts/jetbrains-mono.var.woff2`);
  assert.match(font.headers.get('cache-control'), /immutable/);
});

test('axe finds no violations in either colour scheme at any width', async () => {
  for (const colorScheme of ['light', 'dark']) {
    for (const viewport of VIEWPORTS) {
      const context = await browser.newContext({ colorScheme, viewport, reducedMotion: 'reduce' });
      for (const path of PAGES) {
        const page = await context.newPage();
        await page.goto(server.origin + path, { waitUntil: 'networkidle' });
        const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa', 'best-practice']).analyze();
        const summary = violations.map(({ id, nodes }) => `${id}: ${nodes.map((node) => node.target).join(', ')}`);
        assert.deepEqual(summary, [], `${path} ${colorScheme} ${viewport.width}px`);
        await page.close();
      }
      await context.close();
    }
  }
});

test('no page scrolls sideways at any width', async () => {
  for (const viewport of VIEWPORTS) {
    const page = await browser.newPage({ viewport });
    for (const path of PAGES) {
      await page.goto(server.origin + path, { waitUntil: 'networkidle' });
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      assert.ok(overflow <= 0, `${path} overflows by ${overflow}px at ${viewport.width}`);
    }
    await page.close();
  }
});

const CONTENT_TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.png': 'image/png' };

/** Serves a build as https://wearhats.dev so data-domains matches. No request leaves this process. */
async function openAsProduction(dist) {
  const context = await browser.newContext();
  const pageviews = [];
  const elsewhere = [];
  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.origin === 'https://umami.maxondev.com') {
      pageviews.push(`${route.request().method()} ${url.href}`);
      return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: '{}' });
    }
    if (url.origin !== 'https://wearhats.dev') {
      elsewhere.push(url.href);
      return route.abort();
    }
    const file = join(SITE_ROOT, dist, url.pathname === '/' ? 'index.html' : url.pathname);
    if (!existsSync(file)) return route.fulfill({ status: 404, body: '' });
    return route.fulfill({
      status: 200,
      contentType: CONTENT_TYPES[extname(file)] ?? 'application/octet-stream',
      headers: { 'content-security-policy': cspFromHeaders() },
      body: readFileSync(file),
    });
  });
  const page = await context.newPage();
  const { problems } = watchPage(page);
  await page.goto('https://wearhats.dev/', { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  await context.close();
  return { pageviews, elsewhere, problems };
}

test('with a website ID, the tag sends one pageview through the CSP, and the script stays first-party', async () => {
  buildInto(ANALYTICS_DIST, { PUBLIC_UMAMI_WEBSITE_ID: '00000000-0000-4000-8000-000000000000' });
  const tag = readFileSync(join(SITE_ROOT, ANALYTICS_DIST, 'index.html'), 'utf8').match(/<script[^>]*stats\.js[^>]*>/)?.[0];
  assert.ok(tag, 'no analytics tag');
  assert.match(tag, /src="\/stats\.js"/);
  assert.match(tag, /data-host-url="https:\/\/umami\.maxondev\.com"/);
  assert.match(tag, /data-domains="wearhats\.dev"/);
  assert.match(tag, /data-do-not-track="true"/);
  const { pageviews, elsewhere, problems } = await openAsProduction(ANALYTICS_DIST);
  assert.deepEqual(pageviews, ['POST https://umami.maxondev.com/api/send']);
  assert.deepEqual(elsewhere, []);
  assert.deepEqual(problems, []);
});

test('without a website ID, nothing is sent', async () => {
  const { pageviews, elsewhere, problems } = await openAsProduction('dist');
  assert.deepEqual(pageviews, []);
  assert.deepEqual(elsewhere, []);
  assert.deepEqual(problems, []);
});
