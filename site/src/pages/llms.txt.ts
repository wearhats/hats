import type { APIRoute } from 'astro';
import { VERSION } from '../data/release';
import { INSTALL_OPTIONS, NOTICE, PRIVACY_SOURCE_URL, REPO_URL, SUBHEAD } from '../data/site';

const doc = (name: string) => `${REPO_URL}/blob/main/docs/${name}.md`;

export const GET: APIRoute = ({ site }) => {
  const body = `# hats

> ${SUBHEAD}

hats is a free, MIT-licensed command-line tool for macOS 14 and later. The current release is ${VERSION}. ${NOTICE}

It starts the installed Claude.app as an extra instance for each profile, with its own data folders, and never modifies Claude.app or the default install. It keeps no tokens and has no telemetry. It is not for getting around usage limits: it doesn't pool, rotate or switch accounts when one runs out.

## Install

${INSTALL_OPTIONS.map(({ label, command }) => `- ${label}: \`${command}\``).join('\n')}
- Then run \`hats setup\`.

## Pages

- [Home](${new URL('/', site).href}): what hats does, how it compares with other ways to run two Claude accounts, and common questions
- [What hats reads and writes](${new URL('/privacy', site).href}): every file, Keychain query, process action and network request

## Documentation

- [CLI reference](${doc('cli')})
- [Design rules](${doc('design')})
- [Architecture and platform notes](${doc('architecture')})
- [Privacy inventory, source](${PRIVACY_SOURCE_URL})
- [Source code](${REPO_URL})
- [Releases](${REPO_URL}/releases)
`;
  return new Response(body, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
