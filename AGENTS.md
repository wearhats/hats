# Agent guide

hats is a Swift 6 macOS tool: `Sources/HatsCore` (all logic), `Sources/hats`
(thin ArgumentParser CLI), `Tests/HatsCoreTests` (swift-testing).

## Commands

Run them through [just](justfile) (`just` lists them):

- Build: `just build`
- Test: `just test` (all suites; extra arguments go to `swift test`, e.g.
  `just test --filter ProfileColorTests`). `just e2e` runs only the
  end-to-end suite.
- Lint: `just lint`. `just format` fixes Swift formatting.
- Before finishing a change: `just check`.

## Rules

Read `docs/design.md` before changing behaviour. Its terms and rules are
binding, and changing a rule needs the maintainer's agreement first. Code
conventions on top of it:

- Every OS touchpoint goes through a protocol or injected value (`ProcessTable`,
  `AppControl`, `CredentialProbe`, `DockPreferences`, `Discarder`, `AppRegistrar`,
  `FolderOpener`, Doctor's `urlSchemeHandler`, `ClaudeAppSearch`, `ReleaseFeed`,
  `applicationsDir`) with a fake in `Tests/HatsCoreTests/Support.swift`. All of
  them live in `Touchpoints`, and a new one also gets a stand-in in
  `TestSandbox`. Add any new touchpoint to `docs/privacy.md` in the same change.
- Quitting a Claude process only goes through `AppControl.terminate`.
- Paths handed to other programs use `URL.plainPath`. Path comparisons use
  `canonicalPath`, except `TestSandbox`, which needs `realpath` results because
  `canonicalPath` strips the `/private` that `proc_pidpath` reports.
- Tests use `Sandbox` and never touch the real HOME, Keychain secrets, Dock,
  Trash or Launch Services (`sandbox.doctor()`, `sandbox.discarder`,
  `sandbox.launchers`). End-to-end tests use `E2ESandbox`, which runs the binary
  under `HATS_TEST_SANDBOX` and a Seatbelt profile.
  The one exception is `DisposableHostTests`, which refuses to run anywhere but a
  GitHub-hosted runner.

## Docs to keep in sync

`docs/cli.md` (commands), `README.md` (features, examples and scope),
`docs/design.md` (terms and rules), `docs/privacy.md` (every read, write and
process action), `docs/architecture.md` (modules, flows and platform notes),
`docs/releasing.md` (channels and the release flow). release-please writes
`CHANGELOG.md` from Conventional Commits, so describe a change in the PR title
(the squash commit subject) and commit messages instead of editing the
changelog.
