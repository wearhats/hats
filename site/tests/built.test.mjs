import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { DIST, SITE_ROOT, filesIn, gzipSize, htmlFiles, read, rel, visibleText } from './support.mjs';

const DESCRIPTION_LENGTH = (html) => html.match(/<meta name="description" content="([^"]*)"/)[1].length;
const pages = htmlFiles().map((file) => ({ name: rel(file), html: read(file), text: visibleText(read(file)) }));
const home = pages.find((page) => page.name === 'index.html');
const privacy = pages.find((page) => page.name === 'privacy.html');

// False statements about the tool. docs/privacy.md and design rule 9 are why each one is wrong.
const BANNED_CLAIMS = [
  'no network',
  'nothing leaves your mac',
  'uninstalls cleanly',
  'just delete the folders',
  'generated from the docs',
  '--json everywhere',
  "never reads claude's files",
  'loads nothing from',
  'unlimited',
  'seamless',
  '100% private',
  'stack your plans',
];

test('no page makes a banned claim', () => {
  for (const { name, text } of pages) {
    for (const phrase of BANNED_CLAIMS) {
      assert.ok(!text.toLowerCase().includes(phrase), `${name} says "${phrase}"`);
    }
  }
});

test('fixture output is captioned as a sample until it is captured from a release', () => {
  assert.match(home.text, /Sample output of hats ps\./);
  assert.doesNotMatch(home.text, /\breal\b[^.]{0,40}\boutput\b/i);
});

test('the demo section renders only when its media exists', () => {
  const hasMedia = existsSync(join(SITE_ROOT, 'public/media/demo.mp4'));
  assert.equal(/<video\b/.test(home.html), hasMedia);
  assert.equal(home.html.includes('See it run.'), hasMedia);
});

test('status labels are defined in one file', () => {
  const others = filesIn(join(SITE_ROOT, 'src')).filter((file) => !file.endsWith('data/status.ts') && !/\.(svg|css)$/.test(file));
  for (const file of others) {
    assert.doesNotMatch(read(file), /Expected, being verified|['"`]Shipped['"`]/, rel(file, SITE_ROOT));
  }
  assert.match(home.text, /Cowork: expected, being verified/);
});

test('the page metadata follows the content plan', () => {
  assert.ok(DESCRIPTION_LENGTH(home.html) <= 155);
  const structured = JSON.parse(home.html.match(/<script type="application\/ld\+json">(.+?)<\/script>/s)[1]);
  assert.equal(structured['@type'], 'SoftwareApplication');
  assert.equal(structured.softwareVersion, JSON.parse(read(join(SITE_ROOT, '../.release-please-manifest.json')))['.']);
});

test('no page mentions internal planning terms', () => {
  for (const { name, html } of pages) {
    assert.doesNotMatch(html, /\bspike\b|\bM[23]\b/i, name);
  }
});

const RESOURCE_ATTRIBUTES = /<(script|img|source|video|audio|track|iframe|embed|object)\b[^>]*?\s(?:src|srcset|poster|data)="([^"]+)"/g;

test('nothing on a page loads from another origin', () => {
  for (const { name, html } of pages) {
    for (const [, tag, url] of html.matchAll(RESOURCE_ATTRIBUTES)) {
      assert.ok(url.startsWith('/') && !url.startsWith('//'), `${name}: <${tag}> loads ${url}`);
    }
    for (const [link] of html.matchAll(/<link\b[^>]*>/g)) {
      if (/rel="canonical"/.test(link)) continue;
      const href = link.match(/href="([^"]+)"/)?.[1] ?? '';
      assert.ok(href.startsWith('/') && !href.startsWith('//'), `${name}: ${link}`);
    }
  }
  for (const file of filesIn(DIST).filter((path) => /\.(css|js)$/.test(path) && !path.endsWith('stats.js'))) {
    assert.doesNotMatch(read(file), /(url\(|@import\s+|from\s*["']|import\(["'])\s*["']?(https?:)?\/\//, rel(file));
  }
});

test('pages hold nothing the CSP would block', () => {
  for (const { name, html } of pages) {
    assert.doesNotMatch(html, /<style\b/, `${name} has a <style> block`);
    assert.doesNotMatch(html, /\sstyle="/, `${name} has a style attribute`);
    assert.doesNotMatch(html, /\son[a-z]+="/, `${name} has an inline event handler`);
    for (const [tag] of html.matchAll(/<script\b[^>]*>/g)) {
      assert.match(tag, /\ssrc="|type="application\/ld\+json"/, `${name} has an inline script: ${tag}`);
    }
  }
});

test('the CSP allows no inline code and the Umami origin only for connections', () => {
  const headers = read(join(SITE_ROOT, 'public/_headers'));
  assert.doesNotMatch(headers, /unsafe-inline|unsafe-eval/);
  assert.match(headers, /script-src 'self';/);
  assert.match(headers, /connect-src 'self' https:\/\/umami\.maxondev\.com;/);
  assert.equal(headers.match(/umami\.maxondev\.com/g).length, 1);
});

test('without a website ID there is no analytics tag', () => {
  for (const { name, html } of pages) {
    assert.doesNotMatch(html, /stats\.js|data-website-id|umami\.maxondev\.com"/, name);
  }
});

test('/install.sh is never part of the site', () => {
  assert.doesNotMatch(read(join(DIST, '_redirects')), /install\.sh/);
  assert.ok(!filesIn(DIST).some((file) => file.endsWith('install.sh')));
});

test('the home page carries the install commands and the separate notices', () => {
  assert.match(home.text, /Wear every hat at once\./);
  assert.ok(home.text.includes('brew install wearhats/tap/hats'));
  assert.ok(home.text.includes('curl -fsSL https://wearhats.dev/install.sh | sh'));
  assert.ok(home.text.includes('curl -fsSLO https://wearhats.dev/install.sh && less install.sh && sh install.sh'));
  assert.match(home.text, /No telemetry\. One update check, which you can turn off\./);
  assert.match(home.text, /Not affiliated with or endorsed by Anthropic\./);
  assert.match(home.text, /not affiliated with, endorsed by or sponsored by Anthropic, PBC\./);
  assert.match(home.text, /It counts visits with self-hosted Umami\./);
});

test('words never run into an inline tag', () => {
  for (const { name, html } of pages) {
    const body = html.slice(html.indexOf('<body'));
    assert.doesNotMatch(body, /[a-z:,]<(code|a|strong|em)\b/, name);
    assert.doesNotMatch(body, /<\/(code|a|strong|em)>[a-z]/, name);
  }
});

test('every page has one h1 and a language', () => {
  for (const { name, html } of pages) {
    assert.equal(html.match(/<h1\b/g)?.length, 1, name);
    assert.match(html, /<html lang="en">/, name);
  }
});

test('/privacy is rendered from docs/privacy.md, with its links on GitHub', () => {
  const source = read(join(SITE_ROOT, '../docs/privacy.md'));
  for (const [, heading] of source.matchAll(/^## (.+)$/gm)) {
    assert.match(privacy.html, new RegExp(`<h2[^>]*>${heading}</h2>`), heading);
  }
  assert.ok(privacy.text.includes('hats collects no telemetry.'));
  assert.ok(privacy.text.includes('KERN_PROCARGS2'));
  assert.match(privacy.html, /href="https:\/\/github\.com\/wearhats\/hats\/blob\/main\/docs\/design\.md/);
  assert.doesNotMatch(privacy.html, /href="[^"#:]*\.md/);
  assert.match(privacy.html, /id="this-website"/);
});

test('the "Tested with" line matches the README', () => {
  const readme = read(join(SITE_ROOT, '../README.md'));
  const [line] = readme.match(/^Tested with .+$/m);
  assert.ok(home.text.includes(line), line);
});

test('security.txt expires more than 30 days from now', () => {
  const [, expires] = read(join(DIST, '.well-known/security.txt')).match(/^Expires: (.+)$/m);
  assert.ok(new Date(expires) - Date.now() > 30 * 86_400_000, expires);
});

test('the Open Graph card stays small enough to unfurl', () => {
  assert.ok(gzipSize(join(DIST, 'og/home.png')) <= 100 * 1024);
  assert.match(home.html, /property="og:image" content="https:\/\/wearhats\.dev\/og\/home\.png"/);
});

const KB = 1024;
const budgets = (ext) => filesIn(DIST).filter((file) => file.endsWith(ext) && file.includes('_astro'));
const total = (files) => files.reduce((sum, file) => sum + gzipSize(file), 0);

test('pages stay inside the performance budgets', () => {
  for (const file of htmlFiles().filter((path) => path.endsWith('index.html'))) {
    assert.ok(gzipSize(file) <= 30 * KB, `${rel(file)} is ${gzipSize(file)} bytes`);
  }
  assert.ok(total(budgets('.css')) <= 20 * KB, `CSS is ${total(budgets('.css'))} bytes`);
  assert.ok(total(budgets('.js')) <= 10 * KB, `JS is ${total(budgets('.js'))} bytes`);
  const fonts = filesIn(join(DIST, 'fonts')).filter((file) => file.endsWith('.woff2'));
  assert.equal(fonts.length, 1);
  assert.ok(gzipSize(fonts[0]) <= 40 * KB);
});
