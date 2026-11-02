// Read-only checks of the deployed site, run daily and after each release.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

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
  const release = await (await fetch(RELEASE_API, { headers: { 'User-Agent': 'hats-site-check' } })).json();
  const asset = release.assets?.find(({ name }) => name === 'install.sh');
  const digest = `sha256:${createHash('sha256').update(body).digest('hex')}`;
  expect(asset?.digest === digest, `${digest} against ${asset?.digest}`);
});

await check('the apex serves the site', async () => {
  const response = await fetch(APEX);
  expect(response.status === 200, `status ${response.status}`);
  expect(/Wear every hat at once\./.test(await response.text()), 'headline missing');
});

await check('www redirects to the apex', async () => {
  const response = await fetch('https://www.wearhats.dev/', { redirect: 'manual' });
  expect(response.status === 301, `status ${response.status}`);
  expect(response.headers.get('location')?.startsWith(`${APEX}/`), `location ${response.headers.get('location')}`);
});

await check('live HTML references no other origin, so the edge injected nothing', async () => {
  for (const path of ['/', '/privacy']) {
    const html = await (await fetch(APEX + path)).text();
    const resources = [...html.matchAll(/<(?:script|img|iframe|source|video|audio|embed)\b[^>]*?\ssrc="(https?:)?\/\/([^"]+)"/g)].map((match) => match[2]);
    const links = [...html.matchAll(/<link\b[^>]*>/g)]
      .map(([tag]) => tag)
      .filter((tag) => !/rel="canonical"/.test(tag) && /href="(https?:)?\/\//.test(tag));
    const hosts = [...html.matchAll(/data-host-url="([^"]+)"/g)].map((match) => match[1]).filter((origin) => origin !== ALLOWED_ORIGIN);
    expect(resources.length + links.length + hosts.length === 0, `${path}: ${[...resources, ...links, ...hosts].join(', ')}`);
    expect(!/email-decode|cdn-cgi\/(challenge|scripts)|beacon\.min\.js/.test(html), `${path}: Cloudflare injected a script`);
  }
});

await check(`security.txt is good for more than ${MIN_SECURITY_TXT_DAYS} days`, async () => {
  const text = await (await fetch(`${APEX}/.well-known/security.txt`)).text();
  const expires = new Date(text.match(/^Expires: (.+)$/m)?.[1]);
  expect((expires - Date.now()) / 86_400_000 > MIN_SECURITY_TXT_DAYS, `expires ${expires}`);
});

process.exitCode = failures.length ? 1 : 0;
