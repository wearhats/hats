# Demo recording guide

**Nothing in this folder has been run.** The tapes, sandbox script, captions and transcript were written on Linux, where
hats, VHS and Claude Desktop don't run. Expect to fix small things on the first pass, and treat every timing as a guess.

The site's Demo section stays hidden until the media exists (`src/lib/demoMedia.ts`). Until then the page reads fine
without it, so nothing here blocks the holding page.

## Rules for every frame

- Every `hats` frame comes from a released version. Captions say "sample data" and name the version.
- Silent, with captions. No music on the site version. No AI-generated visuals or voices.
- No Claude logo or icon, and no Claude Code welcome banner: cut right after launch.
- Personal accounts only, never an employer's account or org, even blurred.
- Neutral names only: profiles `work`, `personal`, `acme`, folders `~/demo/api`, `~/demo/blog`.
- Review every frame for emails, org names, paths, session titles and other apps before publishing.

## 1. Prepare the Mac

```sh
brew install vhs ffmpeg
brew install wearhats/tap/hats
hats --version          # the version the captions will name
```

Use a clean shell: a short prompt, no user or host name, no history suggestions. Turn on Focus mode, hide desktop icons
and quit everything else, so `hats ps` shows only demo rows.

## 2. Record the terminal parts with VHS

`sandbox.sh` builds a throwaway `HATS_TEST_SANDBOX` with neutral profiles, so these frames can't touch real data.

```sh
cd site/demo
eval "$(sh sandbox.sh)"     # prints exports; every path is inside a new temp dir
vhs tapes/v2-readme.tape    # one tape at a time; output lands in out/
```

| Tape | Video | Length | Notes |
|---|---|---|---|
| `v2-readme.tape` | V2, README GIF | 25s | 800px wide, 3 MB at most |
| `v1-setup.tape` | V1, 0:04 to 0:25 | 21s | Interactive: answers are typed in the tape |
| `v1-ps.tape` | V1, 0:47 to 0:55 | 8s | Needs running sessions, see below |
| `v1-ls-doctor.tape` | V1, 1:02 to 1:09 | 7s | Doctor should be all `[ok]`; adjust `sandbox.sh` if a stand-in is missing |
| `v4c-adopt.tape` | V4c | 15s | |
| `v4d-same-account.tape` | V4d | 12s | Two profiles planted on one account |
| `v4e-start-fresh.tape` | V4e | 15s | |
| `v4f-folder-account.tape` | V4f | 15s | Needs `direnv` |
| `v4g-audit.tape` | V4g | 20s | Uses the real `install.sh` and `gh`, not the sandbox |
| `v4h-uninstall.tape` | V4h | 15s | Dry-run where possible |

**`hats ps` rows need a fake Claude.** Test mode only sees processes whose executable is inside the sandbox, so
`v1-ps.tape` and `v2-readme.tape` show no sessions until you start some. `swift build --product hats-e2e-fake` builds the
stand-in, and `Tests/HatsE2ETests/Support/FakeProcess.swift` shows how the tests name and start it, since hats tells
processes apart by kernel name and argv. `sandbox.sh` doesn't do this yet. Check the output looks believable before
planning around it. If it doesn't, record those frames on the Mac with real neutral sessions under the rules above.

## 3. Capture the fixtures for the site

The page shows sample output until these are real. On a released version, with the rows above:

```sh
hats ps                                > ../fixtures/hats-ps.txt
NO_COLOR=1 hats ls                     > ../fixtures/hats-ls.txt
NO_COLOR=1 hats doctor                 > ../fixtures/hats-doctor.txt
```

Then follow `../fixtures/README.md`: re-render the cards and change the captions.

## 4. Record the window parts on the Mac

Use a macOS screen recording, because VHS has no GUI, Dock or tabs. Create fresh neutral profiles and remove them afterwards
with `hats rm --purge`.

| V1 time | Shot | Treatment |
|---|---|---|
| 0:25 | Launchers appear in the Dock | Crop to the hats launchers; no Claude tile |
| 0:30 | Click "Claude (Personal)"; a second window opens beside the first | Blur window contents |
| 0:37 | Click it again; it comes forward, nothing new opens | Blur window contents |
| 0:42 | `hats run personal`, cut right on launch | No welcome banner |
| 0:55 | `hats focus <name>`; the right terminal jumps forward | |

Real windows appear only for these few seconds, small and blurred, as evidence that it works with the installed app. Never
use them as decoration.

## 5. Assemble V1

The cuts, in order, with their captions, are in `v1.vtt`. Type cards are plain text on the terminal background. Burn nothing
in for the site: captions come from the track.

```sh
ffmpeg -f concat -safe 0 -i cuts.txt -c:v libx264 -crf 28 -preset slow -pix_fmt yuv420p -movflags +faststart -an demo.mp4
ffmpeg -i demo.mp4 -c:v libvpx-vp9 -crf 38 -b:v 0 -an demo.webm
ffmpeg -ss 30 -i demo.mp4 -frames:v 1 -q:v 60 demo-poster.webp
```

Budgets: video 1.5 MB at most, poster 40 KB at most.

## 6. Put it on the site

```text
site/public/media/demo.mp4              required
site/public/media/demo-poster.webp      required
site/public/media/demo.vtt              required, from v1.vtt: fix the timings, delete the NOTE
site/public/media/demo-transcript.txt   required, from v1-transcript.txt: delete the draft line
site/public/media/demo-version.txt      required, the hats version it was recorded with, such as 0.2.0
site/public/media/demo.webm             optional
site/public/media/still-dock.avif/.webp     optional stills, shown only with both formats
site/public/media/still-ls.avif/.webp
site/public/media/still-doctor.avif/.webp
```

Run `just site-check`. The section appears once the five required files exist.

## 7. README

Add `out/v2-readme.gif` to the README, and upload the 1280×640 `../brand/github-social-preview.png` under the repository's
Settings, General, Social preview.
