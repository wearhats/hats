export const REPO_URL = 'https://github.com/wearhats/hats';
export const DISCUSSIONS_URL = `${REPO_URL}/discussions`;
export const LICENSE_URL = `${REPO_URL}/blob/main/LICENSE`;
export const PRIVACY_SOURCE_URL = `${REPO_URL}/blob/main/docs/privacy.md`;
export const MAINTAINER_URL = 'https://github.com/maximn';

export const TITLE = 'hats: run several Claude accounts side by side on macOS';
export const DESCRIPTION =
  'Open-source macOS tool that runs work, personal and client Claude accounts side by side in Claude Desktop and Claude Code, and lists every session.';

export const SUBHEAD =
  'Run your work, personal and client Claude accounts side by side on one Mac, in Claude Desktop and in the terminal, and see every running Claude in one place.';

export const INSTALL_OPTIONS = [
  { id: 'homebrew', label: 'Homebrew', command: 'brew install wearhats/tap/hats' },
  { id: 'script', label: 'Script', command: 'curl -fsSL https://wearhats.dev/install.sh | sh' },
  {
    id: 'read',
    label: 'Read it first',
    command: 'curl -fsSLO https://wearhats.dev/install.sh && less install.sh && sh install.sh',
  },
] as const;
