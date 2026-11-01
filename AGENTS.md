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
  `FolderOpener`, Doctor's `urlSchemeHandler`) with a fake in
  `Tests/HatsCoreTests/Support.swift`.
  Add any new touchpoint to `docs/privacy.md` in the same change.
- Quitting a Claude process only goes through `AppControl.terminate`.
- Paths handed to other programs use `URL.plainPath`. Path comparisons use
  `canonicalPath`.
- Tests use `Sandbox` and never touch the real HOME, Keychain secrets, Dock,
  Trash or Launch Services (`sandbox.doctor()`, `sandbox.discarder`,
  `sandbox.launchers`).

## Docs to keep in sync

`docs/cli.md` (commands), `README.md` (features, examples and scope),
`docs/design.md` (terms and rules), `docs/privacy.md` (every read, write and
process action), `docs/architecture.md` (modules, flows and platform notes),
`docs/releasing.md` (channels and the release flow), `CHANGELOG.md` (the
Unreleased section until the first release; from then on release-please owns
`CHANGELOG.md`, and changes are described in conventional commit messages
instead).
