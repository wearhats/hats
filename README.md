# hats

**Wear every hat at once.** Run work, personal and client Claude accounts side
by side on one Mac (Claude Desktop with Cowork, and the `claude` CLI), and see
every running Claude in one place.

```console
$ hats add personal
Created profile 'personal'.
  launcher  ~/Applications/Hats/Claude (Personal).app

$ hats ps
PROFILE   KIND     PID    STATUS   AGE  NAME          CWD
default   desktop  16717  -        14h  -             -
default   cli      22045  waiting  17h  acme-4b       ~/dev/acme
personal  desktop  81792  -        2m   -             -
personal  cli      83110  busy     1m   blog-1c       ~/oss/blog
```

> Unofficial community tool. Not affiliated with or endorsed by Anthropic.

## Why

Claude Desktop holds one account per install, and the CLI one per config
directory. hats gives each identity its own **profile**, and leaves your
existing install alone:

| | Stock install (`default`) | `hats add personal` |
|---|---|---|
| Desktop chats, login, connectors, MCP | `~/Library/Application Support/Claude` | `…/hats/profiles/personal/desktop` |
| `claude` CLI and Desktop's Code tab (Cowork: expected, being verified) | `~/.claude` | `…/hats/profiles/personal/code` |
| How you open it | Claude.app | `Claude (Personal).app`, or `hats open personal` |

- **Never touches Claude.app or your default install.** No renaming, symlinking,
  re-signing or force-quitting.
- **Know which account is which.** `hats ls` shows each profile's sign-in state
  and account; `hats doctor` warns when two profiles ended up on the same account
  and `hats reset` starts one fresh.
- **Click again to focus.** A launcher brings its window forward instead of
  starting a duplicate, and `hats dedupe` cleans up duplicates from elsewhere.
- **Dock-ready.** Briefcase, person or letter icons in profile colours;
  `hats dock pin` (opt-in) or `--desktop` copies.
- **One view of everything.** `hats ps` lists Desktop instances and Claude Code
  sessions across all accounts, with live status (busy, idle, waiting).
- **Already juggling `CLAUDE_CONFIG_DIR`?** `hats add work --code-dir ~/.claude-work`
  adopts the existing directory with its login and history intact.
- **Native and auditable.** Swift, one dependency, no telemetry. The one
  network request is a daily update check (`HATS_NO_UPDATE_CHECK=1` turns it
  off).
  Keychain queries ask for *attributes* only, never the secret. Of other
  processes' environments it keeps only `CLAUDE_CONFIG_DIR`. Claude's account
  files are parsed in memory and only the account ID, email, organization and
  sign-in state are kept. It never reads, stores or relays tokens
  ([everything it reads and writes](docs/privacy.md)).

## Install

> **Not released yet.** Until the first release is out, the Homebrew and
> script installs below don't work; build from source instead.

Requires macOS 14+, Claude Desktop, and (for `run`) Claude Code.

```sh
brew install wearhats/tap/hats
```

Homebrew 6 and later only load third-party taps you trust. Installing by the
full name, as above, trusts just the `hats` formula. If you `brew tap
wearhats/tap` first, run `brew trust --formula wearhats/tap/hats` before
`brew install hats`.

Without Homebrew, the install script checks the download's SHA-256 (and its
GitHub build provenance when the `gh` CLI is signed in) and installs to
`~/.local/bin`, without sudo:

```sh
curl -fsSL https://wearhats.dev/install.sh | sh
# or read it first:
curl -fsSLO https://wearhats.dev/install.sh && less install.sh && sh install.sh
```

From source: `swift build -c release && install -m 0755 .build/release/hats ~/.local/bin/`.

Manual download: get `hats-macos-universal.tar.gz` from the Releases page and
check its build provenance with
`gh attestation verify hats-macos-universal.tar.gz --repo wearhats/hats`.
Until releases are notarized, a binary downloaded with a browser is
quarantined; clear that with `xattr -d com.apple.quarantine hats`.

Then run `hats setup`. Upgrade with `brew upgrade hats` or by re-running the
script; `hats doctor` shows the command for your install. More in
[`docs/releasing.md`](docs/releasing.md).

## Use

```sh
hats setup                         # guided: adopt existing dirs, add your other account
hats add personal --pin            # profile + launcher in ~/Applications/Hats, pinned to the Dock
hats open personal                 # or click the launcher; hats open --all opens every profile
hats run personal                  # claude CLI on the personal account (then /login once)
hats ps                            # every running Claude, across accounts
hats focus acme-4b                 # jump to the terminal or window running a session
hats ls                            # profiles, sign-in state, accounts (--size for disk use, --paths for dirs instead)
hats reset personal --open         # it opened on the wrong account: start it fresh
hats doctor                        # explain what's set up and what's wrong
```

Per-directory accounts with direnv: `echo 'eval "$(hats env personal)"' > ~/oss/.envrc`.

Other tools that honour `CLAUDE_CONFIG_DIR`, such as usage reporters, work per
account through `hats exec personal -- <command>`.

Full reference: [`docs/cli.md`](docs/cli.md).

### Signing in to a second account

Sign-in links (`claude://…`) can open in a Claude window that is already
running instead of the new one. If that happens, quit the other Claude windows
(Cmd-Q), sign in to the new profile, then bring the rest back with
`hats open --all`. If a profile still ends up on the wrong account,
`hats reset <name> --open` starts it fresh.

### Tips

- Give each profile its own theme in Claude's settings (for example, work dark and
  personal light). Every instance shares Claude's Dock icon, and this tells the
  windows apart at a glance.
- Cowork downloads its VM (about 12 GB) separately for each profile that uses it
  (`hats ls --size` shows it).
- After a Claude update, a profile's window is expected to come back on the
  default account (reported by users, being verified). `hats doctor`
  spots the resulting duplicate; `hats dedupe && hats open --all` fixes it.
- Desktop's Chrome extension pairing only works in the default profile.

## Uninstall

```sh
hats dock unpin && hats rm --all --purge   # launchers, their copies, Dock tiles; data to the Trash
brew uninstall hats                        # or: rm ~/.local/bin/hats
rm -rf ~/Applications/Hats "$HOME/Library/Application Support/hats"
```

`rm` also removes the launcher copies hats placed (for example on the
Desktop); delete any you moved elsewhere by hand. Claude Code's own logins for
profile config dirs stay in your Keychain as `Claude Code-credentials-<hash>`
items; delete them in Keychain Access if you no longer need them (`hats rm
--purge` prints the exact name). Your default Claude install was never
modified, so there's nothing to restore.

## Scope

hats runs on macOS only and organizes accounts you hold. It won't:

- modify, re-sign or clone Claude.app;
- move chats or sessions between accounts;
- show usage, billing or quota (that needs your account token);
- change or intercept the `claude://` sign-in handler;
- change your Dock unless you ask;
- orchestrate agents;
- help stretch usage limits across accounts.

The reasons are in the [design rules](docs/design.md). Planned work is tracked
in [issues](https://github.com/wearhats/hats/issues).

## Docs

[CLI reference](docs/cli.md) · [Design rules](docs/design.md) ·
[What hats reads and writes](docs/privacy.md) · [Architecture](docs/architecture.md) ·
[Releasing](docs/releasing.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)

Tested with Claude Desktop 4.29.0, Claude Code 2.1.312 and macOS 27.0.1.

## Thanks

hats builds on workarounds and reports shared by the community in
[anthropics/claude-code#18435](https://github.com/anthropics/claude-code/issues/18435).

## License

[MIT](LICENSE)
