#!/bin/sh
# Checks the Claude Desktop behaviour hats relies on (the "Platform notes" in
# docs/architecture.md) against the installed Claude Desktop. Some checks need
# a person to sign in; the script pauses for them. Everything lives in a
# temporary directory, and nothing in the default install is touched.
set -eu

app="${HATS_CLAUDE_APP:-/Applications/Claude.app}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/hats-compat.XXXXXX")"
desktop="$work_dir/desktop"
code="$work_dir/code"
mkdir -p "$desktop" "$code"

main_pids() {
  pgrep -f "Contents/MacOS/Claude --user-data-dir=$desktop\$" || true
}

pause() {
  printf '\n%s\nPress Return to continue. ' "$1"
  read -r _
}

echo "Claude Desktop $(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString)"
echo "Work dir: $work_dir"

echo
echo "1. CLAUDE_CONFIG_DIR reaches the Desktop main process"
open -n -a "$app" --env CLAUDE_CONFIG_DIR="$code" --args --user-data-dir="$desktop"
sleep 5
pid="$(main_pids | head -n 1)"
if ps eww -o command= -p "$pid" | tr ' ' '\n' | grep -qx "CLAUDE_CONFIG_DIR=$code"; then
  echo "  confirmed (pid $pid)"
else
  echo "  NOT confirmed"
fi

echo
echo "2. A second launch with the same data dir"
open -n -a "$app" --env CLAUDE_CONFIG_DIR="$code" --args --user-data-dir="$desktop"
sleep 5
echo "  main processes on the work dir: $(main_pids | wc -l | tr -d ' ') (2 means duplicate)"

pause "3. Sign-in: sign in with the new window while your default Claude stays open. Note where the login lands, then try pasting the code from the browser."
pause "4. Code tab: open the Code tab in the new window and send one message."
echo "  $code/projects: $(find "$code/projects" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ') entries"
echo "  $code/sessions: $(find "$code/sessions" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ') entries"
echo "  (entries mean the Code tab used this profile's CLAUDE_CONFIG_DIR)"
pause "5. Cowork: use Cowork once in the new window."
du -sh "$desktop" "$desktop"/vm_bundles 2>/dev/null || true

echo
pause "Quit each test window with Cmd-Q. The script sends no signals, so Claude can save its state as it normally would."
echo "  main processes still on the work dir: $(main_pids | wc -l | tr -d ' ') (0 means all quit)"
echo "Done. Delete $work_dir when you no longer need it."
