# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/).

## [Unreleased]

### Added
- Profiles that isolate Claude Desktop (chats, login, MCP, Cowork) and the
  `claude` CLI, and hand their config dir to Desktop's Code tab (`add`, `ls`,
  `open`, `rm`).
- Adopting existing Claude Code config dirs (`add --code-dir`).
- Generated launcher apps with per-profile icons that focus the running
  instance instead of starting a duplicate. Labels are unique ignoring case,
  and a build never replaces another profile's launcher.
- `ps` and `focus`, covering Desktop instances and Claude Code sessions across
  all profiles and unmanaged config dirs. Session registry entries count only
  when their start time matches a live Claude Code process.
- `run`, `exec` and `env` for terminal use.
- Read-only `doctor`.
- `setup`, a guided first run that adopts hand-made `~/.claude-*` dirs and adds
  a profile for the other account.
- `open --all` and `add --open`.
- `reset` to start a profile fresh when it opened on the wrong account, and
  `rm --purge` to remove one. Both move data to the Trash and refuse a running
  profile.
- `dedupe` to quit duplicate Desktop instances on one data dir.
- Briefcase and person launcher icons (`add --icon`), picked automatically for
  `work` and `personal`.
- Named icon colours (`add --color green`): blue, green, red, purple, orange,
  teal, pink and brown, besides `#RRGGBB`.
- Desktop copies of launchers (`add --desktop`, `launcher copy`) and
  `launcher reveal`. Copies are recorded in the launcher, so hats never lists
  `~/Desktop` unasked.
- Opt-in Dock pinning (`add --pin`, `dock pin`, `dock unpin`,
  `--dedupe-claude`).
- Account view: `ls` shows Desktop sign-in state and the CLI account; doctor
  warns when two profiles share an account or a profile's Desktop and CLI
  differ, and reports the `claude://` handler.
- `ls --size`, and `--dry-run` for `rm`, `reset` and `dedupe`.
- Distribution: Homebrew tap formula, a checksum- and provenance-verifying
  `install.sh`, reproducibly packaged release tarballs, and a release-please
  driven release workflow that publishes a draft and makes it public only after
  every asset is uploaded.
- Privacy: of other processes' environments only `CLAUDE_CONFIG_DIR` is kept;
  Claude's account files are parsed in memory and only identifiers are kept;
  Keychain queries ask for attributes only. `docs/privacy.md` lists everything
  hats reads and writes, and `docs/design.md` rules out reading tokens, routing
  sign-ins and stretching usage limits.
