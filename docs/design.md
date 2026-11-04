# Design rules

The terms the code and docs use, and the rules every change keeps. The rules
are binding. A change that breaks one starts as an issue, and the pull request
that changes a rule edits this file and says why.

## Terms

- **Profile**: one Claude identity. It owns a Desktop data dir (`desktop/`,
  Electron's `--user-data-dir`) and a Claude Code config dir (`code/`,
  `CLAUDE_CONFIG_DIR`), or adopts an existing config dir.
- **`default`**: the stock install (`~/Library/Application Support/Claude` and
  `~/.claude`), shown as a read-only profile.
- **Adopted config dir**: an existing `CLAUDE_CONFIG_DIR` registered with
  `hats add --code-dir`. It stays where it is, with its login and history.
- **Profile shortcut**: an optional short name for a profile (`w` for `work`),
  set with `hats add --shortcut`. It stands in for the name, but the directories,
  launcher and `HATS_PROFILE` always use the full name.
- **Unmanaged config dir**: a `CLAUDE_CONFIG_DIR` that a running process uses
  but no profile owns or adopts. `hats ps` shows it in parentheses.
- **Instance**: a running Desktop main process or Claude Code session. Kinds:
  `desktop`, `desktop-code`, `cli`, `ide`, `sdk`, `other`.
- **Session registry**: Claude Code's internal `<config>/sessions/<pid>.json`
  files, the source of a session's status, name and working directory.
- **Launcher**: a generated `Claude (<Label>).app` in `~/Applications/Hats`
  whose executable is a shell script that runs `hats open <name>`. A
  `Contents/Resources/hats-launcher.json` marker identifies it.
- **Focus**: bring an existing instance forward, or the terminal or IDE that
  hosts a CLI session.

## Rules

### 1. Profiles are additive; the stock install is never touched

hats never writes Claude.app, `~/Library/Application Support/Claude`,
`~/.claude` or `~/.claude.json`. It never renames, symlinks, re-signs or
force-quits anything to switch accounts. Each profile is another instance next
to the stock one, and all profile data lives under one root (`HATS_HOME`).

Why: switching the live data dir (rename or symlink it, then restart Desktop)
risks data loss on a force-quit or an interrupted rename, and fights Desktop's
updater. Adding needs no migration and leaves nothing to roll back. The cost:
the stock Desktop keeps the `claude://` handler, so a sign-in for an added
profile can land in another window. The workaround is in the
[platform notes](architecture.md#8-platform-notes).

### 2. No tokens, no sign-in routing, no limit stretching

- hats never keeps, stores, copies or relays Claude credentials or session
  tokens. Keychain queries ask for attributes, never the secret. Account files
  are parsed whole in memory (JSON can't be read selectively, and Desktop's
  `config.json` holds its token cache), and only the identifiers listed in
  [privacy.md](privacy.md) are kept.
- hats never changes, registers or intercepts the `claude://` handler, and
  never proxies or rewrites sign-in. Sign-in happens inside Claude. A sign-in
  helper may quit and reopen Claude windows around it, nothing more.
- hats ships nothing meant to stretch usage limits: no rotating sessions across
  accounts when one runs out, no pooling, no switching accounts on rate limits.
- hats never edits or overrides employer-managed Claude settings or
  MDM-delivered preferences.

Why: hats organizes accounts a person legitimately holds, such as a work seat
and a personal plan, or one account per client. Each of the features above
would put hats between a user and their Claude account, or help spread one
person's usage across accounts. Anthropic's
[Consumer Terms](https://www.anthropic.com/legal/consumer-terms) and
[Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
govern how accounts may be used. The cost: there is no live usage view per
account, because it needs the token. Local tools that estimate usage from a
config dir still work per profile through `hats exec`.

### 3. Read Claude's files, never write them

Claude's internal files (`sessions/*.json`, Desktop's `config.json`, Claude
Code's `.claude.json`) are undocumented and change between versions, so hats
decodes them tolerantly. In the session registry every field except `pid` is
optional, and files that fail to decode are skipped and reported by doctor. An
unreadable account file means "unknown", not an error. The only writes inside a
profile's Claude dirs create them empty. hats installs no hooks into Claude's
settings and reads no transcripts.

### 4. Of other processes, keep only what identifies the profile

To tell which profile a process belongs to, hats reads its argv and environment
block from the kernel (`KERN_PROCARGS2`). It keeps argv and
`CLAUDE_CONFIG_DIR`. Every other variable, which may hold an API key, is
skipped as raw bytes without being decoded. Discovery is passive: session
registry entries count only when their PID and start time match a live Claude
Code process.

### 5. Writes outside hats' own dirs happen only on request

hats' own dirs are `HATS_HOME` and the launcher dir. Anything else is written
only for a command or flag that names it: launcher copies (`add --desktop`,
`launcher copy`), the Dock (`add --pin`, `dock pin`, `dock unpin`) and the Trash
(`reset`, `rm --purge`, after confirmation).

- Profile data is never deleted outright: `reset` and `rm --purge` move it to
  the Trash, and both refuse a running profile.
- hats never lists a folder such as `~/Desktop` on its own. It revisits only the
  launcher copies it recorded.
- The Dock is written through CFPreferences. Only tiles that point at hats
  launchers change (`--dedupe-claude` also drops repeated Claude.app tiles).
  Nothing is written, and the Dock isn't restarted, when nothing changes.
- Claude processes are only ever asked to quit, as Cmd-Q does. hats never kills
  them.
- Commands that remove or quit things (`rm`, `reset`, `dedupe`) have no
  one-letter shortcut, so running one always means typing its name.
- `rm` and `reset` take a profile's full name, never its shortcut, so removing a
  profile always means typing its name.
- Profile names match `[a-z0-9][a-z0-9-]{0,31}`, and every recursive delete
  checks that its target is strictly inside the profile's own directory.

### 6. Every OS touchpoint is injectable and listed

Process, Keychain, Dock, Trash, Launch Services, network and filesystem access goes
through a protocol or an injected value, with a fake in tests, so no test
touches the real targets on a machine anyone cares about: the only tests that do
refuse to run anywhere but a throwaway CI runner, because a fake can't show that
the Dock really rereads a tile. [privacy.md](privacy.md) lists every read, write and
process action. A change that adds one updates that file in the same pull
request, and review treats it as a design change.

Commands get all of these from one `Touchpoints` value, built in the CLI's
`Context`, and nothing below it defaults to a real implementation.
`HATS_TEST_SANDBOX=<dir>` swaps them for stand-ins that stay inside `<dir>`, so the
end-to-end tests can run the shipped binary on a contributor's Mac. It only
narrows what hats does: other processes are invisible unless their executable is
inside `<dir>`, and hats refuses to start unless everything it would touch is
inside too, and `<dir>` holds a marker file, so it can't be pointed at real data.

Why ship a test switch: a separate test build wouldn't test the binary people
run, and without one `swift test` couldn't safely cover the commands that scan
processes, or that touch the Dock or the Trash, on a Mac with real Claude windows
open. The cost is a small amount of test support in the release binary.

### 7. One core, thin front ends, native APIs

`HatsCore` holds all logic and has no UI and no global state. The CLI parses
input, calls the core and renders the result. A launcher is a short shell
script that runs `hats open <name>`, so fixes ship without rebuilding
launchers. hats calls native APIs rather than subprocesses or AppleScript, so
focusing a window needs no Automation prompt. The only programs it `exec`s are
`claude` and the user's own commands. The launcher script, not hats, holds the
one AppleScript: when the `hats` binary is gone it runs `osascript` to show an
alert, because nothing else is left to tell the user. That alert controls no
other app, so it needs no Automation prompt either.

Why a script launcher: AppleScript applets trigger Automation prompts and can
fail silently, and a compiled stub would need signing per bundle.

### 8. Adopted config dirs belong to the user

hats never moves or deletes an adopted config dir: `rm --purge` keeps it, and
`reset --code` refuses it. Adoption refuses the default dir, dirs inside
`HATS_HOME`, and a dir another profile already uses.

### 9. One network request, and it only warns

The only network request is the update check: a GET of GitHub's latest-release
API, at most once a day, sending the User-Agent and the HTTP client's standard
headers, and nothing about the user, their profiles or their Mac. It runs only
when stderr is a terminal, to reach a person who will see the notice: never for
launchers, `run`, `exec` or CI, nor when stderr is redirected. A script or
pipeline started from a terminal still makes it, because its stderr is
usually that terminal. `HATS_NO_UPDATE_CHECK=1` turns it off. A newer release produces a notice with
the upgrade command. hats never downloads, installs or replaces itself.

Why: users of the install script have no package manager to tell them about
fixes, so without a check they stay on old versions. A self-updater would put
code that rewrites the binary in every install; Homebrew and the install
script already verify and replace it.
