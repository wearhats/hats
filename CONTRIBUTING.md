# Contributing

Thanks for helping. Start with [`docs/design.md`](docs/design.md): its rules
keep hats safe (never touch the default install, read Claude's files but never
write them, no tokens), and every change keeps them.
[`docs/architecture.md`](docs/architecture.md) maps the code, and
[`AGENTS.md`](AGENTS.md) has the commands and code conventions in one place.

## Setup

You need Xcode 16+ or the Command Line Tools with Swift 6, and
[just](https://github.com/casey/just) to run the project's commands:

```sh
brew install just shellcheck actionlint
just                # list the recipes
just test           # all tests; never touches your real profiles
just lint           # swift-format, shellcheck, actionlint
just check          # lint, tests and packaging: run this before pushing
just linux          # HatsCore on Linux, in Docker
```

Each recipe is a few plain commands in the [`justfile`](justfile), so you can
also run them by hand. CI runs the same recipes.

### Linux

hats is macOS only, but HatsCore builds and its tests run on Linux in Docker.
Install [just](https://github.com/casey/just) (your package manager or its
install script) and Docker, then:

```sh
just linux          # builds and tests HatsCore in the swift:6.4-noble image
```

`just lint`, `just test` and `just check` need the macOS toolchain, so they
don't run on Linux.

## Tests

| Layer | What | How |
|---|---|---|
| Unit | Name validation, layout paths, metadata coding, `KERN_PROCARGS2` parsing, registry decoding, the instance join, icons and ICNS, account probing, duplicates, reset, Dock tile editing, adoption candidates, launcher bundles, doctor checks | swift-testing with the fakes in `Tests/HatsCoreTests/Support.swift` |
| Fixture | Real `sessions/*.json` samples per Claude Code version | `Tests/HatsCoreTests/Fixtures/claude-code/<version>/` |
| Integration (tag `.integration`) | Real sysctl against the test process itself (its own argv, and that only `CLAUDE_CONFIG_DIR` is kept of its env), a Keychain attribute query for a service that can't exist, `sh -n` on the generated launcher script | swift-testing |
| End-to-end (tag `.e2e`) | The built binary as a user runs it: exit codes, stderr, `execve` semantics, the profile lifecycle (`add`, `ls`, `open`, `reset`, `rm`, `doctor`, `launcher`, `dock`), running instances (`ps`, `focus`, `dedupe`, and the refusals for a running profile) against real processes started from a fake Claude binary, prompts and `setup` on a real pseudo-terminal, the launcher script, the `--json` key sets, refusals that change nothing, and that it imports no secret-reading or handler-changing API | `Tests/HatsE2ETests` spawns the binary with `HATS_TEST_SANDBOX`, which keeps every OS touchpoint in a temp root ([privacy.md](docs/privacy.md#test-mode)), under a Seatbelt profile that denies writes outside that root, reads of real Claude data, preference writes and signals. `HATS_E2E_BINARY` tests another build; `HATS_E2E_REQUIRE_GUARD=1` fails instead of running without the guard. CI runs them again against the packaged binary, then checks the runner's real Dock, Trash and Launch Services state didn't change |
| Manual, before each minor release | The Claude Desktop behaviour hats relies on; `dock pin` and `dock unpin` on a real Dock | `scripts/compat-check.sh` and the checklist in [`docs/releasing.md`](docs/releasing.md) |

CI runs every layer except the manual one on each pull request. hats supports
macOS only, but CI also builds and tests `HatsCore` on Linux so the core can't
quietly grow macOS-only dependencies: put macOS implementations behind
`#if canImport(...)` or `#if os(macOS)`.

- Every test runs in a `Sandbox`: a temporary `HOME`, `HATS_HOME` and launcher
  dir. Tests never touch the real Claude data, the Dock, the Trash, Launch
  Services or Keychain secrets: use `sandbox.doctor()`, `sandbox.discarder` and
  `sandbox.launchers` rather than the real implementations.
- A safety test runs the full create, build, remove and purge cycle and asserts
  that nothing changed in `HOME`.

## Pull requests

- Conventional Commits (`feat:`, `fix:`, `docs:` …). release-please turns them
  into the release PR, the version bump and the changelog.
- Every behaviour change comes with a test. OS touchpoints go behind the
  existing protocols and injected values (listed in `AGENTS.md`) so they can be
  faked, and a new touchpoint is added to [`docs/privacy.md`](docs/privacy.md).
- Any change that writes to disk needs a test proving it stays inside the
  sandbox roots.
- A change to a rule in [`docs/design.md`](docs/design.md) starts as an issue.
  Before proposing a feature, check the README's [Scope](README.md#scope).

## Claude Code internals

hats reads `<config>/sessions/<pid>.json`, an internal Claude Code file. If a
new Claude Code version changes it, add a sanitized sample under
`Tests/HatsCoreTests/Fixtures/claude-code/<version>/` together with the fix.
