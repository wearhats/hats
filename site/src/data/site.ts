export const REPO_URL = 'https://github.com/wearhats/hats';
export const DISCUSSIONS_URL = `${REPO_URL}/discussions`;
export const LICENSE_URL = `${REPO_URL}/blob/main/LICENSE`;
export const PRIVACY_SOURCE_URL = `${REPO_URL}/blob/main/docs/privacy.md`;
export const MAINTAINER_URL = 'https://github.com/maximn';
export const MAINTAINER_SITE = 'https://maxondev.com';

export const TITLE = 'hats: run several Claude accounts side by side on macOS';
export const DESCRIPTION =
  'Open-source macOS tool that runs work, personal and client Claude accounts side by side in Claude Desktop and Claude Code, and lists every session.';

export const SUBHEAD =
  'Run your work, personal and client Claude accounts side by side on one Mac, in Claude Desktop and in the terminal, and see every running Claude in one place.';

export const INSTALL_OPTIONS = [
  { id: 'homebrew', label: 'Homebrew', command: 'brew install wearhats/tap/hats' },
  { id: 'script', label: 'Script', command: 'curl -fsSL https://wearhats.dev/install.sh | sh' },
] as const;

/** Only in the Install section: the quick installs above stay to two choices. */
export const READ_FIRST_INSTALL = {
  id: 'read',
  label: 'Read it first',
  command: 'curl -fsSLO https://wearhats.dev/install.sh && less install.sh && sh install.sh',
} as const;

export const SOURCE_INSTALL = {
  id: 'source',
  label: 'From source',
  command:
    'git clone https://github.com/wearhats/hats && cd hats && swift build -c release --product hats && mkdir -p ~/.local/bin && install -m 0755 .build/release/hats ~/.local/bin/',
} as const;

export const NOTICE = 'Unofficial community tool. Not affiliated with or endorsed by Anthropic.';

export const NAV = [
  { label: 'How it works', href: '/#how-it-works' },
  { label: 'Privacy', href: '/#privacy' },
  { label: 'Docs', href: '/docs' },
  { label: 'GitHub', href: REPO_URL },
];
