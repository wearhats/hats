# Architecture

## 1. Overview

```
┌──────────────┐                       ┌──────────────────────────┐
│  hats (CLI)  │                       │ Launcher bundles         │
│ArgumentParser│                       │ Claude (Work).app        │
└──────┬───────┘                       │   MacOS/launch (sh) ─────┼──► hats open work
       │                               └──────────────────────────┘
       ▼
┌────────────────────────────────────────────────────────────────┐
│                         HatsCore                               │
│  ProfileStore · Layout · ClaudeApp · DesktopLauncher           │
│  InstanceScanner ─┬─ ProcessTable (sysctl)                     │
│                   └─ SessionRegistry (<config>/sessions/*.json)│
│  LauncherBuilder · IconRenderer (CoreGraphics → ICNS)          │
│  CredentialProbe (Security.framework, attributes only)         │
│  AccountProbe (identifiers only) · DockEditor (CFPreferences)  │
│  Housekeeping (duplicates, reset, adoption) · Doctor           │
└────────────────────────────────────────────────────────────────┘
```

`HatsCore` holds all logic. The CLI and the launchers are thin front ends.
Every OS touchpoint sits behind a protocol or injected value (`ProcessTable`,
`AppControl`, `CredentialProbe`, `DockPreferences`, `Discarder`, `AppRegistrar`,
`FolderOpener`, Doctor's URL-scheme lookup, `ClaudeAppSearch`, `ReleaseFeed`, `applicationsDir`,
`accountID`, and filesystem roots via `Layout`), gathered in `Touchpoints`, so tests inject fakes. The rules every change keeps, and the terms used here, are in
[design.md](design.md). Everything hats reads and writes is in
[privacy.md](privacy.md).

hats supports macOS only. CI also builds and tests `HatsCore` on Linux, which
keeps the core portable: the macOS implementations of those touchpoints are
compiled only where their frameworks exist, and the package has no `hats`
executable there.

## 2. Module map

| Module | Responsibility | Key types |
|---|---|---|
| `Layout` | Every path hats uses, derived from `HATS_HOME`, `HOME` and the launcher dir. Single source of truth. | `Layout` |
| `ProfileName` | Validation (`^[a-z0-9][a-z0-9-]{0,31}$`), reserved names, label derivation. | `ProfileName` |
| `ProfileStore` | CRUD on profile dirs and `profile.json`. Lists `default` + managed profiles. Resolves what a person typed, a name or a shortcut, to a profile. | `Profile`, `ProfileMetadata`, `ProfileStore` |
| `ClaudeApp` | Resolve Claude.app (bundle ID → known paths → override). Read its version. | `ClaudeApp` |
| `ProcessTable` | Enumerate processes and their start times (`KERN_PROC_ALL`). Read argv and `CLAUDE_CONFIG_DIR` through `sysctl(KERN_PROCARGS2)`; every other environment variable is skipped without being decoded. | `ProcessSummary`, `ProcessDetails`, `DarwinProcessTable` |
| `SessionRegistry` | Decode `<config>/sessions/<pid>.json` tolerantly. | `RegisteredSession` |
| `InstanceScanner` | Join processes, registry and profiles into `Instance` values. | `Instance`, `InstanceKind`, `InstanceStatus` |
| `DesktopLauncher` | Launch a new Desktop instance or activate the existing one. | `AppControl` (protocol), `WorkspaceAppControl`, `HostAppResolver` |
| `LauncherBuilder` | Write and refresh `.app` launcher bundles and their recorded copies; register them with Launch Services. | `LauncherBuilder`, `LauncherMarker`, `AppRegistrar` |
| `IconRenderer` | Render a rounded-square icon (letter, briefcase or person) at 16–1024 px and encode ICNS. | `IconRenderer`, `ICNSEncoder` |
| `CredentialProbe` | Does a Keychain item exist for a config dir? Never reads the secret. | `CredentialProbe` |
| `AccountProbe` | Desktop sign-in state and account IDs from `config.json` and `.claude.json`. | `AccountInfo`, `AccountProbe` |
| `Housekeeping` | Duplicate Desktop instances, `reset` (to the Trash), adoption candidates, disk usage. `rm --purge` uses the same `Discarder`. | `DuplicateInstances`, `Discarder`, `AdoptionCandidates`, `DiskUsage` |
| `ApplicationsLink` | The optional `/Applications/Hats` link to the launcher dir: whose link it is, by its target and its owner; create it, remove it. | `ApplicationsLink`, `ApplicationsLink.State` |
| `Dock` | Opt-in pinning of launchers. | `DockPreferences` (protocol), `SystemDockPreferences`, `DockEditor` |
| `Installation` | Tell how the running binary was installed (Homebrew `Cellar`, an `install.sh` receipt, or unknown) and which command upgrades it. hats never upgrades itself. | `InstallChannel`, `HatsInstall` |
| `UpdateCheck` | The daily release check: ask GitHub at most once a day, keep the latest version, build the notice. Warns only; never downloads. | `UpdateCheck`, `ReleaseFeed` (protocol), `GitHubReleaseFeed`, `SemanticVersion` |
| `Doctor` | Run checks and produce `Finding`s. | `Check`, `Finding`, `Doctor` |
| `Touchpoints` | The one value that holds every OS touchpoint. `.system` is the real set. Built once in the CLI's `Context`; nothing below it defaults to a real implementation, so forgetting one is a compile error. | `Touchpoints`, `ClaudeAppSearch` |
| `TestSandbox` | `HATS_TEST_SANDBOX`: stand-ins for every touchpoint, kept inside one directory, for the end-to-end tests. `HATS_TEST_APP_CONTROL=guarded` makes launch, activate and quit real for apps inside it. Refuses to start if anything would be outside it ([privacy.md](privacy.md#test-mode)). | `TestSandbox` |

## 3. Data model and on-disk layout

```
$HATS_HOME = ~/Library/Application Support/hats
  profiles/
    <name>/
      profile.json                # {schemaVersion, label, color, icon?, shortcut?, createdAt, externalCodeDir?}
      desktop/                    # Electron --user-data-dir (Claude-owned)
      code/                       # CLAUDE_CONFIG_DIR       (Claude-owned; absent when adopted)
~/Applications/Hats/
  Claude (<Label>).app/           # launcher, regenerable at any time
    Contents/Resources/hats-launcher.json   # marker: {name, launcherVersion, hatsPath, copies?}
~/Desktop/Claude (<Label>).app/   # optional copy (add --desktop, launcher copy)
/Applications/Hats -> ~/Applications/Hats   # optional link (launcher link, setup)
```

The launchers live in the home folder's Applications because a standard
account can't write to `/Applications`, and every account on the Mac shares
it, so two users' `Claude (Work).app` would collide. Finder's sidebar shows
`/Applications`, though, so `launcher link` and `setup` offer a link there.
`ApplicationsLink` treats a link as its own when it points at this user's
launcher dir or this account owns it, such as one left from before
`HATS_LAUNCHER_DIR` changed, and leaves another account's link or a real folder
in place. `launcher link` refuses to run as an account that doesn't own HOME,
such as under `sudo`: `sudo` keeps HOME, so hats as root would leave root-owned
dirs in this user's home.

A launcher's marker records the paths of the copies hats placed. Rebuilds and
`rm` revisit only those paths; hats never lists `~/Desktop` (or any other
folder) on its own, because that can raise a privacy prompt. The record lives
in the launcher rather than in `profile.json` because it has the launcher's
lifecycle: it goes away with the launcher, and `ProfileStore` stays unaware
of launchers. Labels are unique across profiles, ignoring case, so two
profiles never compete for one bundle name.

`default` is synthesized: `desktop = ~/Library/Application Support/Claude`,
`code = $HATS_DEFAULT_CONFIG_DIR ?? ~/.claude`. If `~/.claude` is a symlink
(another tool manages it), doctor warns that "default" is not the stock install.

A profile with `externalCodeDir` has adopted an existing Claude Code dir and
has no `code/` of its own. `Profile.codeDirIsExternal` marks it wherever a
delete or a Keychain cleanup hint happens, so the adopted dir is never removed.

`profile.json` is versioned. A reader refuses a newer `schemaVersion` than it
knows. `ProfileStore.inventory()` reports such a profile on its own, and
`list()` skips it, so one unreadable file does not hide the others. While a
profile is unreadable, creating a profile (`add`, with or without `--code-dir`,
and `setup`) refuses, because it cannot finish the label, adopted-dir and shortcut
checks without that profile's data. Looking up a name that exists still works,
but `profile(matching:)` refuses anything else, shortcuts included, because the
unreadable profile may own it. That covers every command that looks up a profile,
including `ps --profile`, `rm` and `reset`. `rm --purge` of a full name refuses
only when the profile being purged is itself unreadable. A schema bump needs a
migration function plus a test.

`add` refuses ambiguous shortcuts, but a hand edit or a profile put back from
the Trash can still create them. At lookup a name wins over a shortcut, and a
shortcut two profiles claim is refused. Doctor warns about both.

## 4. Key flows

### 4.1 `hats open work`
1. Load the profile and resolve Claude.app.
2. Scan processes for the Desktop main executable (`…/Contents/MacOS/Claude`)
   whose parsed `--user-data-dir` equals `profiles/work/desktop`, after
   standardizing the path.
3. If found, `NSRunningApplication(processIdentifier:).activate()`, which needs
   no Automation permission. If activation fails, the scan runs again: an
   instance still running is a conflict error with a hint, so nothing is
   launched next to it. An instance that has exited in the meantime lets the
   launch go ahead. The stock `default` profile skips the block, because it
   passes no data dir and cannot start a duplicate.
4. Otherwise, `NSWorkspace.openApplication(at:configuration:)` with
   `createsNewApplicationInstance = true`, `arguments = ["--user-data-dir=…"]`
   and `environment = ["CLAUDE_CONFIG_DIR": …]`. The environment merges with
   the inherited one, so only the variable is passed.

### 4.2 `hats ps`
1. Get the process snapshot (one `KERN_PROC_ALL` sysctl, plus argv and
   `CLAUDE_CONFIG_DIR` for candidates only: kernel name `Claude`, `claude`, or
   a version string, which is how the native installer's binary shows up).
2. For each config dir (default, all profiles, and unmanaged dirs in use),
   read `sessions/*.json`. Keep entries whose PID is a live Claude Code
   process and whose start time matches: `startedAt` (epoch ms) within a few
   seconds of the kernel start time, else `procStart` to the second. A
   reused PID fails both.
3. Attribute unregistered CLI processes by their `CLAUDE_CONFIG_DIR` env
   (absent means default). Attribute Desktop processes by `--user-data-dir`.
4. Sort by profile, then kind, then start time. Render a table or JSON.

### 4.3 Launcher click
`launch` is `#!/bin/sh`. It exports `HATS_HOME`, because Finder and the Dock
start apps with launchd's environment rather than the user's shell, and runs
`exec '<hats path>' open '<name>'` with both values single-quoted. The hats
path is recorded when the launcher is built: the first `hats` found on `PATH`
(a stable Homebrew symlink), else the resolved path of the running binary. If
it's gone, the script shows a one-line `osascript` dialog telling the user to
reinstall. Doctor flags launchers whose recorded path no longer exists, or
whose `launcherVersion` is older than the current one.

## 5. Concurrency and performance

- The CLI is synchronous. The process scan is a single sysctl plus per-PID
  argv reads for under 100 candidates (about 5 ms).
- Swift 6 strict concurrency is enabled across the package.

## 6. Error handling

- Core APIs throw typed errors (`HatsError`) with a user-facing message and a
  remediation hint. The CLI prints `hats: <message>` and `hint: <hint>`, and
  exits 1 (usage errors exit 64, following sysexits).
- Decoding Claude's files never throws upward. Bad entries are skipped and
  counted, and doctor reports the count.
- A command that lists profiles and leaves out an unreadable one prints a
  `hats: warning:` line for it on stderr, once per run, with a `hint:` to run
  `hats doctor`. Stdout is unchanged. Doctor reports the profile as a `[fail]`
  and does not add a warning.

## 7. Security and threat model

| Asset | Threat | Control |
|---|---|---|
| Stock install | hats corrupts or signs it out | Never write to default paths. Tests assert no writes outside the temp `HATS_HOME`. |
| Credentials | Leakage | Attribute-only Keychain queries. Of other processes' environments only `CLAUDE_CONFIG_DIR` is kept; the rest is skipped as raw bytes. hats never keeps, stores or relays tokens ([design rule 2](design.md#2-no-tokens-no-sign-in-routing-no-limit-stretching)). |
| Path injection | A crafted profile name escapes the root | Strict name regex, `URL.standardized` with a prefix check before any delete, no shell interpolation (launch script values are single-quoted and validated). |
| Wrong-process actions | Focus or quit hits the wrong PID | Exact argv match plus a start-time check. The only quit is `dedupe`: Desktop main processes that share a data dir, after confirmation, through `NSRunningApplication.terminate()` (graceful). No SIGKILL. |
| User's Dock | hats scrambles or loses pins | Opt-in only. Only tiles pointing at hats launchers change; `--dedupe-claude` keeps one Claude.app tile. Written through CFPreferences; no write when nothing changes. |
| Profile data on reset or purge | Accidental loss | `reset` and `rm --purge` move data to the Trash, never delete; both refuse running profiles (`--force` never overrides that for `--purge`), and neither touches an adopted code dir. |
| Launchers of other profiles | A label collision repoints another profile's launcher or Dock tile | Labels are unique ignoring case; a build refuses a bundle whose marker names another profile. |
| Account identifiers | Leakage of tokens while reading `config.json` | The file is parsed whole in memory (it holds Desktop's token cache), and only key presence and `lastKnownAccountUuid` are kept before the parsed object is dropped; token values are never kept or printed. |
| Other accounts on the Mac | `/Applications` is shared: the link shows this account's launcher labels (such as client names) to every account, and their launchers run with this account's `HATS_HOME` | Only on request (`launcher link`, or `setup` after a question that defaults to No and says other accounts will see the folder). hats removes only its own link and never replaces another account's. Another account's launch can't reach this account's data while `~/Library` keeps its default owner-only permissions. |
| Supply chain | A malicious release | One dependency, pinned by `Package.resolved`. Releases are Developer ID signed and notarized once the project has a Developer ID (ad-hoc signed until then), with SHA256SUMS and GitHub build provenance attestations. `install.sh` refuses a checksum mismatch, and a provenance mismatch when a signed-in `gh` can check it; the tap job's token can write only the tap ([releasing.md](releasing.md)). |

## 8. Platform notes

Behaviour hats relies on, last checked on Claude Desktop 4.4212.0, Claude Code
2.1.312 and macOS 27.0.1. `scripts/compat-check.sh` drives hats against Claude
Desktop, then re-runs the checks that need it directly.

- Electron's `--user-data-dir` isolates cookies, local storage, the login
  session, `claude_desktop_config.json` (MCP) and Cowork's VM.
- A new instance launched with `NSWorkspace` (or `open -n --env`) receives
  `CLAUDE_CONFIG_DIR` in its main process, merged with the inherited
  environment. hats reads it back from the live process (`KERN_PROCARGS2`),
  which is how doctor checks a profile window's isolation.
- A second launch with the same `--user-data-dir` starts a duplicate instead
  of focusing the first, so focus-if-running is mandatory.
  `NSRunningApplication.activate()` brings one specific instance forward
  without an Automation (TCC) prompt.
- Desktop's Code tab runs Claude Code with the window's `CLAUDE_CONFIG_DIR`:
  its `projects/` and `sessions/` land in the profile's config dir. Cowork
  follows the same profile. Desktop also keeps part of the Code tab's state
  under its own data dir, which `--user-data-dir` isolates either way.
- A launcher whose executable is a shell script, with an ICNS rendered
  in-process, launches through Launch Services like any other app.
- `<config>/sessions/<pid>.json` holds `pid`, `sessionId`, `cwd`, `startedAt`,
  `procStart`, `version`, `kind`, `entrypoint`, `name`, `status` and
  `updatedAt`. It is undocumented, so hats decodes it tolerantly.
- Natively installed Claude Code runs `~/.local/share/claude/versions/<version>`,
  so the kernel's process name is the version string, not `claude`.
- Desktop's `config.json` has `oauth:tokenCache*` keys only while signed in,
  plus `lastKnownAccountUuid`. Claude Code's `.claude.json` (in HOME for the
  stock install, else in the config dir) has `oauthAccount.accountUuid`,
  `emailAddress` and `organizationName`. Desktop and Claude Code account IDs
  share one namespace, so they can be compared.
- Cowork's VM takes about 12 GB in each Desktop data dir that uses it.
- Dock tiles live in the `com.apple.dock` preferences (`persistent-apps`).
  Editing the plist file directly races with cfprefsd's cache, so hats writes
  through CFPreferences and then restarts the Dock with SIGTERM (launchd
  relaunches it). The Dock silently ignores tiles whose `file-mod-date` is 0.

Not verified yet, and re-checked before each minor release:
- Where a sign-in lands with several instances running. Reports conflict:
  the `claude://` link may reach whichever Desktop instance runs (they share
  one bundle ID). Supported workaround today: quit the other Claude windows
  while signing in, then `hats open --all`. hats never changes the `claude://` handler; doctor reports which app owns
  it.
- Whether a Claude update relaunches a profile's window without its argv and
  env, so that it comes back on the default data dir. Doctor flags the
  resulting default duplicate, and `dedupe` plus `open --all` repairs it.

Known limitations:
- Every instance shares Claude.app's Dock icon. Per-instance icons need a
  cloned, re-signed app bundle, which hats declines. The launcher icon and a
  different Desktop theme per profile are the mitigation.
- Relocated data dirs disable Desktop's Chrome extension pairing ("userData
  relocated" in Claude's log). Only `default` keeps it.
