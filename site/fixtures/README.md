# Fixtures

Output shown on the site. **These are samples, not captures.** They follow the README's shape and the real column
headers and strings in `Sources/hats/`, and they were not produced by running hats. Captions say "Sample output" until
each file is replaced with a capture from a released version.

| File | Capture with | Status |
|---|---|---|
| `hats-ps.txt` | `hats ps` | Sample |
| `hats-ls.txt` | `hats ls` | Sample, not on the page yet |
| `hats-doctor.txt` | `hats doctor` | Sample, not on the page yet |

The `hats ps --profile <name>` views on the page are derived from `hats-ps.txt` with the same column-width rule as
`Output.printTable`, so they stay correct when `hats-ps.txt` is replaced.

After replacing a file, run `pnpm run render:brand`, because the Open Graph card and GitHub preview use `hats-ps.txt`.
When all of them are captures, change `FIXTURE_CAPTION` in `src/components/HeroTerminal.astro` and the note in
`scripts/render-brand.mjs`.
