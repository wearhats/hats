# CLI reference

`hats <command> [options]`. Every command is scriptable. Commands that list
things take `--json`. Exit codes: 0 ok, 1 failure, 64 usage error.

| Command | Summary |
|---|---|
| `hats setup` | Guided first run: adopt hand-made `~/.claude-*` dirs, add a profile for the other account, optionally pin it, copy it to the Desktop and open it to sign in. Prints the equivalent command for each step. |
| `hats add <name> [--label L] [--color NAME|#RRGGBB] [--icon letter\|briefcase\|person] [--code-dir DIR] [--desktop] [--pin] [--open]` | Create a profile and its launcher. Idempotent: re-running rebuilds the launcher and keeps data. Labels are unique across profiles, ignoring case. `--color` takes blue, green, red, purple, orange, teal, pink, brown or a hex value. `--code-dir` adopts an existing `CLAUDE_CONFIG_DIR` (such as `~/.claude-work`), which hats never deletes. While another profile's `profile.json` cannot be read, this refuses and names that profile, since the label and adopted-dir checks can't finish; `setup` does the same. |
| `hats ls [--json] [--size] [--paths]` | List profiles (`default` included): running instances, Desktop sign-in, CLI login, the CLI account (email and organization), launcher state. `--size` adds disk usage. `--paths` adds the full paths of the Desktop data dir and the Claude Code config dir, which `--json` always includes as `desktopDir` and `codeDir`. Profiles whose `profile.json` cannot be read are left out, with a warning for each on stderr; `hats doctor` names them. |
| `hats open <name…> \| --all` | Focus each profile's Desktop instance, or launch it. `default` opens stock Claude.app; `--all` opens every other profile. If a running instance can't be brought forward, `open` fails with a hint instead of starting a second instance on the same data dir. |
| `hats run <name> [-- claude-args…]` | `exec claude` with `CLAUDE_CONFIG_DIR` set. |
| `hats exec <name> -- <cmd…>` | Run any command with the profile's env. |
| `hats env <name> [--shell zsh\|bash\|sh\|fish]` | Print an `export` line for `eval` or `.envrc`. |
| `hats ps [--json] [--profile P]` | List running Desktop instances and Claude Code sessions across profiles. |
| `hats focus <pid\|session-name>` | Bring the host app of a session or instance forward. |
| `hats reset <name> [--code] [--open] [--yes] [--dry-run]` | Start a profile fresh when it opened on the wrong account: move its Desktop data (and with `--code`, its own Claude Code dir) to the Trash and rebuild the launcher. Refuses while running. |
| `hats dedupe [--yes] [--dry-run]` | Quit extra Desktop instances that share a data dir, keeping the oldest. Graceful, like Cmd-Q. |
| `hats rm <name…> \| --all [--purge] [--yes] [--force] [--dry-run]` | Remove launchers and the copies hats placed. `--purge` also moves the profile's data to the Trash after typed confirmation (`--yes` for scripts); an adopted code dir is kept. Refuses a running profile; `--force` removes only the launcher and never allows `--purge`. A profile whose `profile.json` cannot be read is refused by `--purge` until that file is repaired. |
| `hats doctor [--json]` | Read-only health checks, including how hats was installed and the command that upgrades it, launchers that call another `hats`, sign-in state, accounts shared between profiles, duplicates and the `claude://` handler. An unreadable profile is reported as its own `[fail]` on the `profile:<name>` check. Non-zero exit only on `[fail]`. |
| `hats launcher rebuild [<name>…]` | Regenerate launchers (all by default) and the copies hats recorded. |
| `hats launcher copy <name…> [--to DIR]` | Copy launchers to a folder (default `~/Desktop`) and record the copy, so rebuilds and `rm` keep it in step. Other folders are never scanned. |
| `hats launcher reveal` | Show the launchers folder in Finder. |
| `hats dock pin [<name>…] [--dedupe-claude]` | Pin launchers to the Dock (all by default), next to Claude.app. Restarts the Dock. `--dedupe-claude` keeps one Claude.app tile. |
| `hats dock unpin [<name>…]` | Remove launchers from the Dock. |

## Environment

| Variable | Effect |
|---|---|
| `HATS_HOME` | Root for profile data (default `~/Library/Application Support/hats`). |
| `HATS_LAUNCHER_DIR` | Where launchers are written (default `~/Applications/Hats`). |
| `HATS_CLAUDE_APP` | Path to the Claude.app to launch. |
| `HATS_CLAUDE_BIN` | Path to the `claude` CLI for `run` (default: first on `PATH`). |
| `HATS_DEFAULT_CONFIG_DIR` | The `default` profile's Claude Code dir (default `~/.claude`). An inherited `CLAUDE_CONFIG_DIR` never changes it. |
| `HATS_PROFILE` | Set by hats, not read: `run` and `exec` export the profile name to the child, for prompts and scripts. |
| `HATS_NO_UPDATE_CHECK` | Set to `1` to turn off the daily update check. It also stays off when `CI` is set, output isn't a terminal, or hats is a dev build. |
| `NO_COLOR` | Disable colour output. |

## Examples

```sh
hats setup                              # guided first run
hats add personal --color green --pin --open
hats open --all                         # or click "Claude (Personal)" in ~/Applications/Hats
hats reset personal --open              # it opened on the wrong account
alias claude-p='hats run personal --'
echo 'eval "$(hats env personal)"' > ~/oss/.envrc
hats ps
hats exec personal -- printenv CLAUDE_CONFIG_DIR
```
