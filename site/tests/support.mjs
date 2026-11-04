import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, extname, relative } from 'node:path';
import { gzipSync } from 'node:zlib';

export const SITE_ROOT = new URL('..', import.meta.url).pathname;
export const DIST = join(SITE_ROOT, 'dist');

export function filesIn(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? filesIn(path) : [path];
  });
}

export const htmlFiles = (dir = DIST) => filesIn(dir).filter((file) => extname(file) === '.html');
export const rel = (file, dir = DIST) => relative(dir, file);
export const read = (file) => readFileSync(file, 'utf8');
export const gzipSize = (file) => gzipSync(readFileSync(file)).length;

export function visibleText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/g, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ');
}

export function buildInto(outDir, env = {}) {
  execFileSync('pnpm', ['exec', 'astro', 'build', '--outDir', outDir], {
    cwd: SITE_ROOT,
    env: { ...process.env, ...env },
    stdio: 'pipe',
  });
  if (!existsSync(join(SITE_ROOT, outDir, 'index.html'))) throw new Error(`no build in ${outDir}`);
}

const answers = (origin) => fetch(origin, { redirect: 'manual' }).then(() => true, () => false);

export async function startWrangler(port = 8788) {
  const origin = `http://127.0.0.1:${port}`;
  // Another server on the port would answer for ours, and the tests would check whatever build it serves.
  if (await answers(origin)) throw new Error(`something already serves ${origin}; stop it so the tests check this build`);
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
    const status = await fetch(origin, { redirect: 'manual' }).then((response) => response.status, () => 0);
    if (status === 200) return { origin, stop: () => process.kill(-child.pid) };
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
