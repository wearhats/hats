import { defineConfig } from 'astro/config';
import { githubDocLinks, stripTitle, accessibleTables } from './src/lib/markdown.mjs';

const devOnlyPages = {
  name: 'dev-only-pages',
  hooks: {
    'astro:config:setup': ({ command, injectRoute }) => {
      if (command === 'dev') injectRoute({ pattern: '/brand', entrypoint: './src/dev/brand.astro' });
    },
  },
};

export default defineConfig({
  integrations: [devOnlyPages],
  site: 'https://wearhats.dev',
  output: 'static',
  trailingSlash: 'never',
  build: {
    format: 'file',
    // The CSP has no 'unsafe-inline', so styles and scripts must be files.
    inlineStylesheets: 'never',
  },
  devToolbar: { enabled: false },
  markdown: {
    // Shiki writes inline style attributes, which the CSP blocks.
    syntaxHighlight: false,
    remarkPlugins: [stripTitle, githubDocLinks],
    rehypePlugins: [accessibleTables],
  },
  vite: {
    // Same reason: stops Vite inlining small assets and processed scripts.
    build: { assetsInlineLimit: 0 },
  },
});
