import { spawn, execFile } from 'node:child_process';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { promisify } from 'node:util';
import { join, extname, relative } from 'node:path';
import { gzipSync } from 'node:zlib';

export const SITE_ROOT = new URL('..', import.meta.url).pathname;
export const DIST = join(SITE_ROOT, 'dist');

export const PAGES = ['/', '/privacy'];
export const MISSING_PAGE = '/this-page-does-not-exist';
export const VIEWPORTS = [{ width: 360, height: 800 }, { width: 768, height: 1024 }, { width: 1280, height: 800 }];

export const filesIn = (dir) =>
  readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => join(entry.parentPath, entry.name));

export const htmlFiles = (dir = DIST) => filesIn(dir).filter((file) => extname(file) === '.html');
export const rel = (file, dir = DIST) => relative(dir, file);
export const read = (file) => readFileSync(file, 'utf8');
export const gzipSize = (file) => gzipSync(readFileSync(file)).length;

export const decodeEntities = (html) =>
  html.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'").replace(/&amp;/g, '&');

export const visibleText = (html) =>
  decodeEntities(html.replace(/<script[\s\S]*?<\/script>/g, ' ').replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ');

const RESOURCE_ATTRIBUTES = /<(script|img|source|video|audio|track|iframe|embed|object)\b[^>]*?\s(?:src|srcset|poster|data)=["']([^"']+)["']/g;
const isLocal = (url) => url.startsWith('/') && !url.startsWith('//');

/** Everything in a page that would load from another origin. The canonical link only names the page, so it doesn't count. */
export function foreignReferences(html, allowedOrigins = []) {
  const resources = [...html.matchAll(RESOURCE_ATTRIBUTES)].filter(([, , url]) => !isLocal(url)).map(([, tag, url]) => `<${tag}> loads ${url}`);
  const links = [...html.matchAll(/<link\b[^>]*>/g)]
    .map(([tag]) => tag)
    .filter((tag) => !/rel=["']canonical["']/.test(tag) && !isLocal(tag.match(/href=["']([^"']+)["']/)?.[1] ?? ''));
  const hosts = [...html.matchAll(/data-host-url=["']([^"']+)["']/g)]
    .map(([, origin]) => origin)
    .filter((origin) => !allowedOrigins.includes(origin))
    .map((origin) => `analytics sends to ${origin}`);
  return [...resources, ...links, ...hosts];
}

export async function buildInto(outDir, env = {}) {
  await promisify(execFile)('pnpm', ['exec', 'astro', 'build', '--outDir', outDir], {
    cwd: SITE_ROOT,
    env: { ...process.env, ...env },
  });
  if (!existsSync(join(SITE_ROOT, outDir, 'index.html'))) throw new Error(`no build in ${outDir}`);
}

const statusOf = (origin) => fetch(origin, { redirect: 'manual' }).then((response) => response.status, () => 0);

export async function startWrangler(port = 8788) {
  const origin = `http://127.0.0.1:${port}`;
  // Another server on the port would answer for ours, and the tests would check whatever build it serves.
  if ((await statusOf(origin)) !== 0) throw new Error(`something already serves ${origin}; stop it so the tests check this build`);
  const child = spawn('pnpm', ['exec', 'wrangler', 'dev', '--port', String(port), '--ip', '127.0.0.1'], {
    cwd: SITE_ROOT,
    env: { ...process.env, WRANGLER_SEND_METRICS: 'false', CI: 'true' },
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: true,
  });
  let output = '';
  let exited = false;
  child.stdout.on('data', (chunk) => (output += chunk));
  child.stderr.on('data', (chunk) => (output += chunk));
  child.on('exit', () => (exited = true));
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (exited) throw new Error(`wrangler dev exited before serving:\n${output}`);
    if ((await statusOf(origin)) === 200) return { origin, stop: () => process.kill(-child.pid) };
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  process.kill(-child.pid);
  throw new Error(`wrangler dev did not start:\n${output}`);
}

/** The CSP as the deployed site sends it, from the committed _headers file. */
export function cspFromHeaders() {
  const match = read(join(SITE_ROOT, 'public/_headers')).match(/Content-Security-Policy: (.+)/);
  if (!match) throw new Error('_headers has no CSP');
  return match[1];
}
