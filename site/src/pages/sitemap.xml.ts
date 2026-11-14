import type { APIRoute } from 'astro';

// Every page in this folder is listed unless it is named here, so a new page can't be left out.
const UNLISTED = new Set(['/404']);

const paths = Object.keys(import.meta.glob('./**/*.astro'))
  .map((file) => file.replace(/^\./, '').replace(/\.astro$/, '').replace(/\/index$/, '') || '/')
  .filter((path) => !UNLISTED.has(path))
  .sort();

export const GET: APIRoute = ({ site }) => {
  const urls = paths.map((path) => `  <url><loc>${new URL(path, site).href}</loc></url>`).join('\n');
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
  return new Response(body, { headers: { 'Content-Type': 'application/xml' } });
};
