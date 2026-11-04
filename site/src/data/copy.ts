import { TESTED_WITH } from './release';
import { DISCUSSIONS_URL } from './site';
import { expected, shipped, type Status } from './status';

export const PROBLEMS = [
  {
    title: 'Sign out. Sign in. Wait for the code.',
    body: 'Claude Desktop holds one account at a time. Changing it means signing out, signing back in, often waiting for an email code, and stopping whatever the other account was running.',
  },
  {
    title: 'Right work, wrong account.',
    body: 'Client work on your personal plan, side projects on the company seat. You find out afterwards.',
  },
  {
    title: 'Six windows, one icon.',
    body: 'Every Claude window shares the same Dock icon. Which one is waiting for you, and which account is it on?',
  },
];

export type Feature = { title: string; body: string; command: string; statuses: Status[] };

export const FEATURES: Feature[] = [
  {
    title: 'Side by side, not switching',
    body: 'Each account runs in its own Claude Desktop. Nothing pauses when you open another.',
    command: 'hats open --all',
    statuses: [shipped()],
  },
  {
    title: 'Desktop and terminal, one profile',
    body: 'A profile covers Claude Desktop, its Code tab and the `claude` CLI. Cowork is expected to follow it.',
    command: 'hats run work',
    statuses: [shipped(), expected('Cowork')],
  },
  {
    title: 'Every Claude in one list',
    body: 'Desktop instances and Claude Code sessions from terminals, IDEs and Desktop, on every account. Sessions show status, name and folder.',
    command: 'hats ps',
    statuses: [shipped()],
  },
  {
    title: 'Know which account is which',
    body: 'Sign-in state per profile, plus the email and organization of its CLI login. Doctor warns when two profiles share an account.',
    command: 'hats ls',
    statuses: [shipped()],
  },
  {
    title: 'Click again to focus',
    body: 'Launchers bring the running window forward instead of starting a duplicate. Clean up strays gracefully, like Cmd-Q.',
    command: 'hats dedupe',
    statuses: [shipped()],
  },
  {
    title: 'Icons you can tell apart',
    body: "Briefcase, person or letter, in each profile's colour. In the Dock only when you ask. *Running windows still share Claude's own icon.*",
    command: 'hats dock pin',
    statuses: [shipped()],
  },
  {
    title: 'Bring your own config dirs',
    body: 'Already juggling `CLAUDE_CONFIG_DIR`? hats adopts the folder with its login and history, and never deletes it.',
    command: 'hats add work --code-dir ~/.claude-work',
    statuses: [shipped()],
  },
  {
    title: 'Start fresh',
    body: "A sign-in landed in the wrong window? Move that profile's Desktop data to the Trash and sign in again. `--code` adds its Claude Code folder.",
    command: 'hats reset personal --open',
    statuses: [shipped()],
  },
  {
    title: 'After a Claude update',
    body: 'Updates are reported to reopen profile windows on your default account. If stock Claude is also open, doctor flags the duplicate, and two commands should put things back.',
    command: 'hats dedupe && hats open --all',
    statuses: [shipped('Doctor check'), expected('Update behaviour')],
  },
  {
    title: 'Scriptable',
    body: '`--json` on every listing command, `hats env` for direnv, `hats exec` for any tool that honours `CLAUDE_CONFIG_DIR`.',
    command: 'eval "$(hats env personal)"',
    statuses: [shipped()],
  },
];

export const COMPARISON_HEADERS = ['Approach', 'Both live at once', 'Desktop', 'CLI', 'Leaves your install alone', 'The catch'];

export const COMPARISON = [
  ['Sign out and back in', 'No', 'Yes', 'Yes', 'Yes', 'Stops what\'s running; email codes'],
  ['Separate macOS users', 'Partly', 'Yes', 'Yes', 'Yes', "Notifications, background jobs and permissions don't cross users"],
  ['Browser for the second account', 'Yes', 'No', 'No', 'Yes', 'No local files, local MCP, Cowork or Code tab'],
  ['Shell alias with `CLAUDE_CONFIG_DIR`', 'Yes', 'No', 'Yes', 'Yes', "Desktop isn't covered"],
  ['Script around `open -n --user-data-dir`', 'Yes', 'Yes', 'Varies', 'Yes', 'You handle duplicates, the Code tab and updates yourself'],
  ['Copied or re-signed Claude.app', 'Yes', 'Yes', 'Varies', 'Adds a copy', 'Can break updates and passkeys'],
  ['Swapping the live data folder', 'No', 'Yes', 'Varies', '**No** (renames or symlinks it)', 'Risks data on an interrupted swap; fights the updater'],
];

export const HATS_ROW = ['hats', 'Yes', 'Yes', 'Yes', 'Yes', '[See below](#not-yet)'];

export const NOT_YET = [
  "Running windows share Claude's Dock icon. Only launchers are coloured. Different themes per profile help.",
  'No guided sign-in. If a sign-in lands in the wrong window, you quit the others yourself.',
  'No automatic recovery after a Claude update. Doctor can flag a duplicate, and two commands should fix it.',
  "No menu-bar app. It's a command-line tool.",
  'Chrome extension pairing only works in the default profile.',
  'macOS only.',
];

export const PRIVACY = [
  {
    title: 'Writes',
    items: [
      'Its own profile folders (`~/Library/Application Support/hats`)',
      'Launchers in `~/Applications/Hats`, registered with macOS',
      'Only when you ask: Dock tiles, launcher copies, moving data to the Trash',
    ],
  },
  {
    title: 'Reads',
    items: [
      "Claude Code's session list, and Claude.app's `Info.plist`",
      "Account files, parsed whole in memory because JSON can't be read selectively. Only the account ID, email, organization and sign-in state are kept.",
      'Keychain item *attributes*, never the secret',
      'From other processes: their arguments and `CLAUDE_CONFIG_DIR`. Other variables are skipped without being decoded.',
      'With `--size`: file names and sizes, never contents',
    ],
  },
  {
    title: 'Runs',
    items: [
      'Launches Claude.app as a new instance; brings windows forward',
      'Asks Claude to quit, as Cmd-Q does, after you confirm `hats dedupe`',
      'Restarts the Dock after a Dock change you asked for',
      'Runs `claude` or your command for `hats run` and `hats exec`',
    ],
  },
  {
    title: 'Network',
    items: [
      'One update check: at most once a day, a request to GitHub\'s latest-release API, when you run a command at a terminal. It sends its version, and GitHub sees your IP address, as with any request. It never downloads or installs anything. `HATS_NO_UPDATE_CHECK=1` turns it off.',
    ],
  },
  {
    title: 'Never writes',
    items: [
      'Claude.app, or your default install (`~/Library/Application Support/Claude`, `~/.claude`)',
      "An adopted config dir, Claude's settings or the `claude://` handler",
    ],
  },
  {
    title: 'Never',
    items: ['Keeps or sends tokens or passwords', 'Sends telemetry', 'Force-kills Claude'],
  },
];

export const FAQ = [
  ['Is this an official Anthropic product?', 'No. It is an independent open-source project, not affiliated with, endorsed by or sponsored by Anthropic.'],
  ['Does it modify Claude.app or my existing setup?', 'No. It starts your installed Claude.app as an extra instance with its own data folders. Your stock install becomes the read-only `default` profile.'],
  ['Does it read my tokens or passwords?', "It doesn't keep or send them. Keychain queries ask for attributes, never the secret. Account files are parsed whole in memory, because JSON can't be read selectively, and only the account ID, email, organization and sign-in state are kept. Sign-in always happens inside Claude."],
  ['Does it phone home?', "Only to check for updates. At most once a day, when you run a command at a terminal, hats asks GitHub for the latest version. It sends its version and nothing about your profiles or accounts; GitHub sees your IP address, as with any request. `HATS_NO_UPDATE_CHECK=1` turns it off. There's no telemetry, and it never downloads or installs anything by itself."],
  ['Can I use it to get more usage across accounts?', "No, and it won't add features for that. hats keeps accounts you legitimately hold apart; it doesn't pool or rotate them."],
  ['Can I use my personal account on my work Mac?', "That's your employer's call. hats never edits or overrides employer-managed Claude settings or MDM-delivered preferences. If your company restricts personal accounts, follow that."],
  ["Does Desktop's Code tab use the right account?", `Yes: it runs Claude Code with the window's \`CLAUDE_CONFIG_DIR\`, checked on Claude Desktop ${TESTED_WITH.desktop}, and doctor flags a window that runs without it. Cowork is expected to do the same; we're still verifying that.`],
  ['What happens when Claude updates?', "Other tools report that the updater reopens profile windows on your default account. We're still verifying this. If stock Claude is also open, `hats doctor` flags the duplicate, and `hats dedupe && hats open --all` should fix it."],
  ['A sign-in landed in the wrong window. Now what?', 'Quit the other Claude windows (Cmd-Q), sign in to the new profile, then `hats open --all`, which skips `default`, so reopen Claude.app yourself. If a profile still ended up on the wrong account, `hats reset <name> --open` starts it fresh.'],
  ['Why not separate macOS users?', "Notifications, background jobs and permissions don't cross users. hats profiles run in your one login session."],
  ['Why not the browser for the second account?', "A browser can't reach local files or local MCP servers, and it has no Cowork or Desktop Code tab."],
  ['What if Claude ships multi-account support?', "Then use it. It only adds things, so removing it takes three lines and there's nothing to restore. `hats ps` may still be useful for listing sessions."],
  ['How much disk does a profile use?', 'Little, unless it uses Cowork: its VM is about 12 GB per profile. `hats ls --size` shows it.'],
  ['Known limitations?', 'See [What hats doesn\'t do yet](#not-yet). Also, the VS Code extension ignores `CLAUDE_CONFIG_DIR` ([an upstream issue](https://github.com/anthropics/claude-code/issues/30538)), though `hats ps` still lists its sessions.'],
  ['How do I check what I\'m installing?', 'The script verifies the SHA-256, and build provenance when `gh` is signed in. You can read it first, verify a download with `gh attestation verify`, or build from source. The code has one dependency and is MIT licensed.'],
  ['Windows or Linux?', 'Not in v1.'],
  ['What does it cost?', 'Nothing. MIT licence.'],
  ['Only Claude?', `For now. hats works with Claude Desktop and Claude Code. Tell us which other app you'd want in [Discussions](${DISCUSSIONS_URL}).`],
  ['Who makes this?', 'Max Novak, as a personal open-source project.'],
];
