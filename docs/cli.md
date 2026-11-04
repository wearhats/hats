# CLI reference

`hats <command> [options]`. Every command is scriptable. Commands that list
things take `--json`. Exit codes: 0 ok, 1 failure, 64 usage error.

A `--json` object always has every key, with `null` for no value. Keys may be
added, so scripts should ignore ones they don't know. Renaming or removing a key
is a breaking change.

| Command | Summary |
|---|---|
| `hats setup` | Guided first run: adopt hand-made `~/.claude-*` dirs, add a profile for the other account, optionally pin it, link the launchers into Finder's Applications folder, copy it to the Desktop and open it to sign in. Prints the equivalent command for each step. |
| `hats add <name> [--label L] [--color NAME\|#RRGGBB] [--icon letter\|briefcase\|person] [--code-dir DIR] [--shortcut S\|--no-shortcut] [--desktop] [--pin] [--open]` | Create a profile and its launcher, and print how to open it (Spotlight, `dock pin` or `launcher reveal`). Idempotent: re-running rebuilds the launcher and keeps data. Labels are unique across profiles, ignoring case. `--color` takes blue, green, red, purple, orange, teal, pink, brown or a hex value. `--code-dir` adopts an existing `CLAUDE_CONFIG_DIR` (such as `~/.claude-work`), which hats never deletes. `--shortcut` sets a short name for the profile (see below). While another profile's `profile.json` cannot be read, this refuses and names that profile, since the label, adopted-dir and shortcut checks can't finish; `setup` does the same. |
| `hats ls [--json] [--size] [--paths]` | List profiles (`default` included), with any shortcut beside the name: running instances, Desktop sign-in, CLI login, the CLI account (email and organization), launcher state. `--size` adds disk usage. `--paths` shows the full paths of the Desktop data dir and the Claude Code config dir instead of the status columns, and `--size` still adds disk usage next to them. `--json` always includes both dirs as `desktopDir` and `codeDir`, and keeps the status fields when combined with `--paths`. Control characters in a path print as `?` in the table; `--json` keeps the exact path. Profiles whose `profile.json` cannot be read are left out, with a warning for each on stderr; `hats doctor` names them. |
| `hats open <name…> \| --all` | Focus each profile's Desktop instance, or launch it. `default` opens stock Claude.app; `--all` opens every other profile. If a running instance can't be brought forward, `open` fails with a hint instead of starting a second instance on the same data dir. |
| `hats run <name> [-- claude-args…]` | `exec claude` with `CLAUDE_CONFIG_DIR` set. |
| `hats exec <name> -- <cmd…>` | Run any command with the profile's env. |
| `hats env <name> [--shell zsh\|bash\|sh\|fish]` | Print an `export` line for `eval` or `.envrc`. |
| `hats ps [--json] [--profile P]` | List running Desktop instances and Claude Code sessions across profiles. |
| `hats focus <pid\|session-name>` | Bring the host app of a session or instance forward. |
| `hats reset <name> [--code] [--open] [--yes] [--dry-run]` | Start a profile fresh when it opened on the wrong account: move its Desktop data (and with `--code`, its own Claude Code dir) to the Trash and rebuild the launcher. Refuses while running. |
| `hats dedupe [--yes] [--dry-run]` | Quit extra Desktop instances that share a data dir, keeping the oldest. Graceful, like Cmd-Q. |
| `hats rm <name…> \| --all [--purge] [--yes] [--force] [--dry-run]` | Remove launchers and the copies hats placed. `--all` also removes the `/Applications/Hats` link when it points at this user's launcher dir. `--purge` also moves the profile's data to the Trash after typed confirmation (`--yes` for scripts); an adopted code dir is kept. Refuses a running profile; `--force` removes only the launcher and never allows `--purge`. A profile whose `profile.json` cannot be read is refused by `--purge` until that file is repaired. |
| `hats doctor [--json]` | Read-only health checks, including how hats was installed and the command that upgrades it, launchers that call another `hats`, a `/Applications/Hats` link of this user's that dangles or points at an old launcher dir, sign-in state, accounts shared between profiles, conflicting shortcuts, duplicates and the `claude://` handler. An unreadable profile is reported as its own `[fail]` on the `profile:<name>` check. Non-zero exit only on `[fail]`. |
| `hats launcher rebuild [<name>…]` | Regenerate launchers (all by default) and the copies hats recorded. Naming `default` is an error, because Claude.app launches itself. |
| `hats launcher copy <name…> [--to DIR]` | Copy launchers to a folder (default `~/Desktop`) and record the copy, so rebuilds and `rm` keep it in step. Other folders are never scanned. Naming `default` is an error. |
| `hats launcher reveal` | Show the launchers folder in Finder. |
| `hats launcher link` | Show the launchers in Finder's Applications folder, through a link at `/Applications/Hats` to the launcher dir. Does nothing when the link is already there, or when the launcher dir is already inside `/Applications`. Refuses, and changes nothing, when `/Applications/Hats` is anything else, such as another user's link or a real folder. Writing to `/Applications` needs an admin account; for a standard account it fails and prints the `ln -s` command an admin can run. |
| `hats launcher unlink` | Remove the `/Applications/Hats` link, only when it points at this user's launcher dir. |
| `hats dock pin [<name>…] [--dedupe-claude]` | Pin launchers to the Dock (all by default), next to Claude.app. Restarts the Dock. `--dedupe-claude` keeps one Claude.app tile. |
| `hats dock unpin [<name>…]` | Remove launchers from the Dock. |

## Shortcuts

| Shortcut | Command |
|---|---|
| `hats r` | `hats run` |
| `hats o` | `hats open` |
| `hats x` | `hats exec` |
| `hats f` | `hats focus` |

`rm`, `reset` and `dedupe` remove or quit things, so they have no one-letter
shortcut.

## Profile shortcuts

`hats add work --shortcut w` lets `w` stand in for `work` when a command looks up
a profile: `hats run w`, `hats r w`, `hats open w`, `hats ps --profile w`. Run it again with
another value to change the shortcut, or with `--no-shortcut` to remove it.

A shortcut uses the same characters as a profile name, and means one profile
only: `add` refuses a shortcut that is the profile's own name or another
profile's name or shortcut, and a new profile named after an existing shortcut.
Re-running `add` on an existing profile checks a shortcut only if you pass one.
`default` has no shortcut.

`add` takes the full name, because `hats add w` names a new profile. `rm` and
`reset` take the full name, so removing a profile always means typing its name.

A hand edit, or a profile put back from the Trash, can get past those checks, and
`hats doctor` warns when one has. A profile's name wins over a shortcut. A shortcut
two profiles claim is refused rather than guessed.

While any `profile.json` cannot be read, full names keep working, but a shortcut
or an unknown name is refused, because that profile may own it. `hats ps --profile`
refuses the same way, and otherwise lists nothing for a name no profile has.

## Environment

| Variable | Effect |
|---|---|
| `HATS_HOME` | Root for profile data (default `~/Library/Application Support/hats`). |
| `HATS_LAUNCHER_DIR` | Where launchers are written (default `~/Applications/Hats`). |
| `HATS_CLAUDE_APP` | Path to the Claude.app to launch. |
| `HATS_CLAUDE_BIN` | Path to the `claude` CLI for `run` (default: first on `PATH`). |
| `HATS_DEFAULT_CONFIG_DIR` | The `default` profile's Claude Code dir (default `~/.claude`). An inherited `CLAUDE_CONFIG_DIR` never changes it. |
| `HATS_PROFILE` | Set by hats, not read: `run` and `exec` export the profile name to the child, for prompts and scripts. |
| `HATS_TEST_SANDBOX` | For hats' own end-to-end tests only: keeps every OS touchpoint inside a directory ([privacy.md](privacy.md#test-mode)). hats refuses to start if anything it would touch is outside it. |
| `HATS_TEST_APP_CONTROL` | With `HATS_TEST_SANDBOX`, `guarded` makes launch, activate and quit real for apps inside that directory only. |
| `HATS_NO_UPDATE_CHECK` | Set to `1` to turn off the daily update check. It also stays off when `CI` is set, output isn't a terminal, or hats is a dev build. |
| `NO_COLOR` | Disable colour output. |

## Examples

```sh
hats setup                              # guided first run
hats add personal --color green --pin --open
hats open --all                         # or click "Claude (Personal)" in ~/Applications/Hats
hats launcher link                      # show the launchers in Finder's Applications folder too
hats reset personal --open              # it opened on the wrong account
alias claude-p='hats run personal --'
echo 'eval "$(hats env personal)"' > ~/oss/.envrc
hats ps
hats exec personal -- printenv CLAUDE_CONFIG_DIR
```
