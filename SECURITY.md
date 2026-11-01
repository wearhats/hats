# Security policy

## Reporting

Report vulnerabilities privately through GitHub's "Report a vulnerability" (Security
Advisories) on this repository. Don't open a public issue. We aim to acknowledge
within 3 business days.

## Model

- hats never reads, stores or relays Claude credentials or session tokens, and
  never touches the `claude://` handler ([design rules](docs/design.md)).
  Keychain queries request attributes only, never the secret.
- To tell which profile a running process belongs to, hats reads its argument
  and environment block from the kernel and keeps only argv and
  `CLAUDE_CONFIG_DIR`. Other variables, which often hold API keys, are skipped
  without being decoded or stored.
- To show sign-in state, hats parses Desktop's `config.json` (which contains
  Desktop's token cache) and Claude Code's `.claude.json` in memory, and keeps
  only key presence, account ID, email and organization name.
- hats makes no network connections and collects no telemetry.
- hats writes only inside its data root (`HATS_HOME`), its launcher directory
  and launcher copies the user asked for. Opt-in exceptions: the Dock
  preference (`dock pin`) and the Trash (`reset`, `rm --purge`). It never
  modifies Claude.app or the default Claude data directories. The full
  inventory is [`docs/privacy.md`](docs/privacy.md).
- Profile names are restricted to `[a-z0-9-]`. Every recursive delete is guarded
  by a strict "inside the data root" check.
- Releases carry `SHA256SUMS` and GitHub build provenance.
  [`docs/releasing.md`](docs/releasing.md) explains how they're built and
  checked.

See the threat model in [`docs/architecture.md`](docs/architecture.md#7-security-and-threat-model).
