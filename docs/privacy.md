# What hats reads and writes

hats sits next to software that holds people's accounts. Its safety claims are
only checkable if the whole surface is written down, so this page is the
complete list. A change that adds a row updates this page in the same pull
request ([design rule 6](design.md#6-every-os-touchpoint-is-injectable-and-listed)).

hats collects no telemetry. Its only network request is the daily update
check under [Network](#network), which can be turned off. **Opt-in** below
means it happens only for a command or flag that asks for it by name.

## Writes

| What | Where | When | Opt-in |
|---|---|---|---|
| Profile dirs and `profile.json` | `$HATS_HOME/profiles/<name>/` | `add`, `setup`, `reset` (recreates empty dirs) | no (hats' own data) |
| Launcher bundles and their marker | `$HATS_LAUNCHER_DIR` (`~/Applications/Hats`) | `add`, `setup`, `reset`, `launcher rebuild`; removed by `rm` | no (hats' own data) |
| Launcher copies | a folder the user names (default `~/Desktop`), recorded in the launcher's marker | `add --desktop`, `launcher copy`, `setup` after asking; refreshed by rebuilds, removed by `rm` | yes |
| Launch Services registration of launchers | the Launch Services database (`LSRegisterURL`) | whenever a launcher is built | no |
| Dock `persistent-apps` preference, then a Dock restart (SIGTERM to the Dock, as `killall Dock` does; launchd restarts it) | `com.apple.dock` through CFPreferences | `add --pin`, `dock pin`, `dock unpin`, `setup` after asking | yes |
| Update check state: when hats last asked and the latest version it heard of | `$HATS_HOME/update-check.json` | the update check below | no (hats' own data) |
| Moving data to the user's Trash | `~/.Trash` (`FileManager.trashItem`) | `reset`, `rm --purge`, after confirmation | yes |

Nothing else is written: never Claude.app, `~/Library/Application Support/Claude`,
`~/.claude`, `~/.claude.json`, an adopted code dir, Claude's settings, or the
`claude://` handler ([design rules](design.md)).

## Reads

| What | Why |
|---|---|
| `$HATS_HOME`, `$HATS_LAUNCHER_DIR`, and recorded launcher copies | hats' own state |
| A folder the user names in `launcher copy --to` (or `~/Desktop`, the default) | to replace an older copy there |
| `HOME` entries named `.claude-*`, `.claude.*`, `.claude_*` (and whether they contain `.claude.json`, `settings.json`, `projects`, `sessions`) | `setup` adoption candidates |
| `<config>/sessions/<pid>.json` for every known or in-use config dir | `ps`, `focus`, doctor; never written |
| Desktop's `config.json` per profile, parsed whole in memory; only token-cache key presence and `lastKnownAccountUuid` are kept | sign-in state |
| Claude Code's `.claude.json` per profile, parsed in memory; only `oauthAccount.accountUuid`, `emailAddress`, `organizationName` are kept | account view |
| Claude.app's `Info.plist`, and the `claude://` handler's bundle ID (Launch Services lookup) | locate Claude, doctor |
| Whether `~/.claude` is a symlink | doctor (another tool may manage it) |
| Process table (`KERN_PROC_ALL`: PID, parent, start time, kernel name) | instance discovery |
| Argv and environment block of candidate processes (`KERN_PROCARGS2`); only argv and `CLAUDE_CONFIG_DIR` are kept, other variables are skipped as raw bytes | profile attribution |
| Keychain attribute query for `Claude Code-credentials[-<hash>]` (`kSecReturnAttributes`, never data) | CLI login present or not |
| `$HATS_HOME/install.json`, a receipt `install.sh` writes with the path it installed to; hats never writes it | doctor names the upgrade command |
| The path of the running `hats` binary, and of the `hats` on `PATH` | doctor: install channel, launchers that call another `hats` |
| hats' own environment (`HOME`, `PATH`, `HATS_*`, `CLAUDE_CONFIG_DIR`, `NO_COLOR`, `CI`) | configuration |
| Names and allocated sizes of files under each profile's Claude dirs, the stock dirs, and adopted config dirs (file metadata only, contents never opened) | `ls --size` disk usage |

The account email and organization name appear in hats' terminal output (`ls`,
doctor). They are your own data on your own Mac, and hats never sends them
anywhere.

## Process actions

| Action | When |
|---|---|
| Launch Claude.app (`NSWorkspace.openApplication`, new instance, `--user-data-dir`, `CLAUDE_CONFIG_DIR`) | `open`, launcher click |
| Activate an app (`NSRunningApplication.activate`) | `open` on a running profile, `focus` |
| Ask an app to quit (`NSRunningApplication.terminate`, as Cmd-Q) | `dedupe` after confirmation |
| SIGTERM to the Dock process | the Dock restart above, only after the Dock preference changed |
| `execve` the `claude` CLI or a user command | `run`, `exec` |
| Open the launcher folder in Finder (`NSWorkspace.open`) | `launcher reveal` |

No other signal is ever sent, and never SIGKILL.

## Network

| Request | When | Sent | Kept |
|---|---|---|---|
| `GET https://api.github.com/repos/wearhats/hats/releases/latest` | At most once a day, alongside a command run in an interactive terminal by a release build. Never for `run` and `exec`, launchers, scripts, piped output, or when `CI` is set. | Your IP address (as with any request) and `User-Agent: hats/<version>`. No profile, account, path or machine data, and no cookies. | The `tag_name` of the reply, in `update-check.json` |

If the reply names a newer version, hats prints a notice on stderr with the
upgrade command for your install. It never downloads or installs anything.
Set `HATS_NO_UPDATE_CHECK=1` to turn the check off.
