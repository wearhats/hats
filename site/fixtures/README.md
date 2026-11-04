# Fixtures

Output shown on the site. **These are samples, not captures.** They follow the README's shape and the real column
headers and strings in `Sources/hats/`, and they were not produced by running hats. Captions say "Sample output" until
each file is replaced with a capture from a released version.

| File | Capture with | Status |
|---|---|---|
| `hats-setup.txt` | `hats setup`, adopting `~/.claude-work` and adding `personal`, answers included | Sample |
| `hats-ps.txt` | `hats ps` | Sample |
| `hats-ls.txt` | `hats ls` | Sample |
| `hats-doctor.txt` | `hats doctor` | Sample, not on the page yet |

The hero's example session shows these files, laid out with the same column-width rule as `Output.printTable`. The
three samples tell one story, so replace them together: setup adopts `work` and adds `personal`, opens both, and `ls`
and `ps` then show both running. A question line is anything ending in `[default] ` followed by the typed answer.

After replacing a file, run `pnpm run render:brand`, because the Open Graph card and GitHub preview use `hats-ps.txt`.
When all of them are captures, change the caption in `src/components/HeroSession.astro` and the note in
`scripts/render-brand.mjs`.
