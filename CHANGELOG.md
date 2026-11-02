# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/).

## 0.1.0 (2026-11-02)


### Features

* initial public release of hats ([10c6b91](https://github.com/wearhats/hats/commit/10c6b9187ee6703b1d5a25687a5abdaae4261ff0))
* show how to upgrade in hats doctor ([#8](https://github.com/wearhats/hats/issues/8)) ([557c53a](https://github.com/wearhats/hats/commit/557c53a793454007c93b500901ad95ee328964c4))
* warn when a newer release is available ([#9](https://github.com/wearhats/hats/issues/9)) ([d9bc6c3](https://github.com/wearhats/hats/commit/d9bc6c31c7bda40fb27c968ce7463d04f1579c23))


### Bug Fixes

* harden release packaging and correct the provenance claim ([#10](https://github.com/wearhats/hats/issues/10)) ([59c274d](https://github.com/wearhats/hats/commit/59c274d5b3920884fdd6d711185f6f3e407f814c))

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
