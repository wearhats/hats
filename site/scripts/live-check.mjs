// Read-only checks of the deployed site, run daily and after each release.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PAGES, foreignReferences } from '../tests/support.mjs';

const APEX = 'https://wearhats.dev';
const INSTALL_TARGET = 'https://github.com/wearhats/hats/releases/latest/download/install.sh';
const RELEASE_API = 'https://api.github.com/repos/wearhats/hats/releases/latest';
const ALLOWED_ORIGIN = 'https://umami.maxondev.com';
const MIN_SECURITY_TXT_DAYS = 30;

const failures = [];

async function check(name, run) {
  try {
    await run();
    console.log(`ok    ${name}`);
  } catch (error) {
    failures.push(name);
    console.log(`FAIL  ${name}: ${error.message}`);
  }
}

function expect(condition, message) {
  if (!condition) throw new Error(message);
}

const fetched = new Map();
/** Fetches each page once; the checks below share the response. */
function page(path) {
  if (!fetched.has(path)) {
    fetched.set(path, fetch(APEX + path).then(async (response) => ({ status: response.status, headers: response.headers, html: await response.text() })));
  }
  return fetched.get(path);
}

await check('/install.sh redirects to the latest release asset', async () => {
  const response = await fetch(`${APEX}/install.sh`, { redirect: 'manual' });
  expect(response.status === 302, `status ${response.status}`);
  expect(response.headers.get('location') === INSTALL_TARGET, `location ${response.headers.get('location')}`);
});

await check('the install script parses and matches the release asset', async () => {
  const body = Buffer.from(await (await fetch(`${APEX}/install.sh`)).arrayBuffer());
  const path = join(mkdtempSync(join(tmpdir(), 'hats-live-')), 'install.sh');
  writeFileSync(path, body);
  execFileSync('sh', ['-n', path]);
  // Runners share an IP, so an anonymous request can hit the rate limit and read as a false alarm.
  const token = process.env.GITHUB_TOKEN;
  const headers = { 'User-Agent': 'hats-site-check', ...(token && { Authorization: `Bearer ${token}` }) };
  const reply = await fetch(RELEASE_API, { headers });
  expect(reply.ok, `the release API answered ${reply.status}`);
  const release = await reply.json();
  const asset = release.assets?.find(({ name }) => name === 'install.sh');
  const digest = `sha256:${createHash('sha256').update(body).digest('hex')}`;
  expect(asset?.digest === digest, `${digest} against ${asset?.digest}`);
});

await check('the apex serves the site', async () => {
  const { status, html } = await page('/');
  expect(status === 200, `status ${status}`);
  expect(/Wear every hat at once\./.test(html), 'headline missing');
});

await check('pages keep their promises: no cookies, the real CSP, nosniff', async () => {
  for (const path of PAGES) {
    const { headers } = await page(path);
    expect(headers.getSetCookie().length === 0, `${path} sets ${headers.getSetCookie().join('; ')}`);
    expect(/script-src 'self';/.test(headers.get('content-security-policy') ?? ''), `${path} has no CSP`);
    expect(!/unsafe-inline/.test(headers.get('content-security-policy') ?? ''), `${path} allows inline code`);
    expect(headers.get('x-content-type-options') === 'nosniff', `${path} has no nosniff`);
  }
});

await check('www redirects to the apex', async () => {
  const response = await fetch('https://www.wearhats.dev/', { redirect: 'manual' });
  expect(response.status === 301, `status ${response.status}`);
  expect(response.headers.get('location')?.startsWith(`${APEX}/`), `location ${response.headers.get('location')}`);
});

await check('live HTML references no other origin, so the edge injected nothing', async () => {
  for (const path of PAGES) {
    const { html } = await page(path);
    const foreign = foreignReferences(html, [ALLOWED_ORIGIN]);
    expect(foreign.length === 0, `${path}: ${foreign.join(', ')}`);
    expect(!/email-decode|cdn-cgi\/|beacon\.min\.js/.test(html), `${path}: Cloudflare injected a script`);
  }
});

await check(`security.txt is good for more than ${MIN_SECURITY_TXT_DAYS} days`, async () => {
  const text = await (await fetch(`${APEX}/.well-known/security.txt`)).text();
  const expires = new Date(text.match(/^Expires: (.+)$/m)?.[1]);
  expect((expires - Date.now()) / 86_400_000 > MIN_SECURITY_TXT_DAYS, `expires ${expires}`);
});

process.exitCode = failures.length ? 1 : 0;
