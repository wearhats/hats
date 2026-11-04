import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DIST, SITE_ROOT, decodeEntities, filesIn, foreignReferences, gzipSize, htmlFiles, read, rel, visibleText } from './support.mjs';

const DESCRIPTION_LENGTH = (html) => html.match(/<meta name="description" content="([^"]*)"/)[1].length;
const pages = htmlFiles().map((file) => {
  const html = read(file);
  return { name: rel(file), html, text: visibleText(html) };
});
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
  assert.match(home.text, /Sample output, not a recording\./);
  assert.doesNotMatch(home.text, /\breal\b[^.]{0,40}\boutput\b/i);
});

test('the example session ships every scene in full, for readers without JavaScript and for search engines', () => {
  for (const line of [
    '$ hats add work --code-dir',
    'Everyday commands:',
    'Launched Claude (Work), pid 81655.',
    "Claude Code starts here with work's own login, history and settings.",
    'you@acme.example (Acme Inc.)',
    'api-4b',
  ]) {
    assert.ok(home.text.includes(line), line);
  }
});

test("the example session's fixed sentences are the CLI's own", () => {
  const sources = ['SetupCommand.swift', 'Prompt.swift', 'ProfileCommands.swift']
    .map((file) => read(join(SITE_ROOT, '../Sources/hats', file)))
    .join('\n');
  for (const sentence of [
    "hats keeps your current Claude.app and ~/.claude as the 'default' profile and never changes them.",
    'Found a Claude Code config dir you made yourself: ',
    'Turn it into a profile? Its login and history stay as they are.',
    'Add a profile for another account?',
    'Name for your other account (for example personal, work, acme)',
    'Pin the new launcher(s) to the Dock? This restarts the Dock.',
    'Also put a copy on the Desktop?',
    'now to sign in?',
    'Sign in inside the new window. If the browser hands the login to another Claude window,',
    'Everyday commands:',
    'focus or launch a profile\'s Claude Desktop (--all for every profile)',
    'case .focused(let pid): print("Focused Claude (',
    'case .launched(let pid): print("Launched Claude (',
    'Pinned \\(url.deletingPathExtension().lastPathComponent) to the Dock.',
  ]) {
    assert.ok(sources.includes(sentence), sentence);
  }
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

test('nothing on a page loads from another origin', () => {
  for (const { name, html } of pages) {
    assert.deepEqual(foreignReferences(html), [], name);
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

const uninstallBlocks = () => [
  ['README.md', read(join(SITE_ROOT, '../README.md')).match(/^hats dock unpin[\s\S]*?^\s*brew uninstall hats.*$/m)[0]],
  ['index.html', decodeEntities(home.html.match(/<pre class="uninstall"[^>]*>([\s\S]*?)<\/pre>/)[1])],
];

// Pasted into a terminal: stock zsh has interactivecomments off, so an inline `#` would end the chain.
const SHELLS = [
  ['zsh', '-f', '-i'],
  ['bash', '--norc', '-i'],
  ['sh', '-i'],
];

function pasteIntoShell(shell, block) {
  const home = mkdtempSync(join(tmpdir(), 'hats-uninstall-'));
  const bin = join(home, 'bin');
  const log = join(home, 'calls.log');
  mkdirSync(bin);
  const stub = (name, body) => writeFileSync(join(bin, name), `#!/bin/sh\necho "${name} $*" >> "$CALLS"\n${body}\n`, { mode: 0o755 });
  stub('hats', '[ "$1" = rm ] && exit 1; exit 0');
  stub('rm', 'exit 0');
  stub('brew', 'exit 0');
  writeFileSync(log, '');
  try {
    spawnSync(shell[0], shell.slice(1), {
      input: `${block}\nexit\n`,
      env: { HOME: home, PATH: `${bin}:/usr/bin:/bin`, CALLS: log, TERM: 'dumb' },
      cwd: home,
      stdio: ['pipe', 'ignore', 'ignore'],
      timeout: 10_000,
    });
    return read(log).trim().split('\n');
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
}

test('pasted into any shell, the uninstall steps stop when the purge is refused', () => {
  for (const [source, block] of uninstallBlocks()) {
    assert.match(block, /hats rm --all --purge &&/, source);
    for (const shell of SHELLS) {
      const calls = pasteIntoShell(shell, block);
      assert.deepEqual(calls, ['hats dock unpin', 'hats rm --all --purge'], `${source} in ${shell.join(' ')}`);
    }
  }
});

test('the home page carries the install commands and the separate notices', () => {
  assert.match(home.text, /Wear every hat at once\./);
  assert.ok(home.text.includes('brew install wearhats/tap/hats'));
  assert.ok(home.text.includes('curl -fsSL https://wearhats.dev/install.sh | sh'));
  assert.ok(home.text.includes('curl -fsSLO https://wearhats.dev/install.sh && less install.sh && sh install.sh'));
  assert.ok(home.html.includes('id="install-tab-read"'), 'the Install section keeps the read-it-first option');
  assert.ok(!home.html.includes('id="hero-tab-read"') && !home.html.includes('id="cta-tab-read"'), 'the quick installs offer two choices');
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
