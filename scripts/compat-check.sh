#!/bin/sh
# Checks the Claude Desktop behaviour hats relies on (the "Platform notes" in
# docs/architecture.md) against the installed Claude Desktop. Some checks need
# a person to sign in; the script pauses for them. Claude's data and hats' profile
# live in a temporary directory, and nothing in the default install is touched.
# Outside it, hats registers its launcher with Launch Services, which this undoes,
# and doctor reads the default profile.
#
# The first part drives hats itself against the real Claude Desktop. It uses
# `hats` from PATH, or HATS_BIN to test another build. It never quits anything:
# dedupe only runs with --dry-run, and you close the windows yourself.
#
# Exits 1 if any check isn't confirmed. The rest of the output is for a person to read.
set -eu

app="${HATS_CLAUDE_APP:-/Applications/Claude.app}"
hats_bin="${HATS_BIN:-hats}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! command -v "$hats_bin" >/dev/null 2>&1; then
  echo "cannot find hats ('$hats_bin'): put it on PATH or set HATS_BIN" >&2
  exit 64
fi

# Physical and without the `//` a trailing slash in TMPDIR would leave: hats
# normalizes the paths it's given, and the process list has to match them.
work_dir="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hats-compat.XXXXXX")" && pwd -P)"
desktop="$work_dir/desktop"
code="$work_dir/code"
mkdir -p "$desktop" "$code"

failures=0

main_pids() {
  pgrep -f "Contents/MacOS/Claude --user-data-dir=$1\$" || true
}

count_main_pids() {
  main_pids "$1" | wc -l | tr -d ' '
}

# Claude takes a moment to start, and nothing signals when it's up.
wait_for_main_pids() {
  attempts=0
  while [ "$(count_main_pids "$1")" -ne "$2" ] && [ "$attempts" -lt "${3:-15}" ]; do
    sleep 1
    attempts=$((attempts + 1))
  done
}

pause() {
  printf '\n%s\nPress Return to continue. ' "$1"
  read -r _
}

report() {
  if [ "$1" = ok ]; then
    echo "  confirmed: $2"
  else
    echo "  NOT confirmed: $2"
    failures=$((failures + 1))
  fi
}

run_hats() {
  HATS_HOME="$work_dir/hats" HATS_LAUNCHER_DIR="$work_dir/launchers" HATS_CLAUDE_APP="$app" HATS_NO_UPDATE_CHECK=1 \
    "$hats_bin" "$@"
}

# Leaves the combined output in `output`. A hats failure is a result to report, not
# a reason to skip every check after it.
capture_hats() {
  if output="$(run_hats "$@" 2>&1)"; then return 0; else return 1; fi
}

json_value() {
  printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null || true
}

frontmost_pid() {
  # Printed as `"pid"=123` or `pid = 123`, depending on how much it may say.
  lsappinfo info -only pid "$(lsappinfo front)" | sed -n 's/.*pid"\{0,1\} *= *\([0-9][0-9]*\).*/\1/p' | head -n 1
}

check_hats() {
  echo
  echo "hats against the real Claude Desktop ($("$hats_bin" --version))"
  if ! capture_hats add compat; then
    report no "add failed: $output"
    return
  fi
  # `default` is always the first row.
  if ! capture_hats ls --json; then
    report no "ls failed: $output"
    return
  fi
  hats_desktop="$(json_value "$output" 1.desktopDir)"
  hats_code="$(json_value "$output" 1.codeDir)"
  hats_launcher="$(json_value "$output" 1.launcher)"

  if ! capture_hats open compat; then
    report no "open failed: $output"
    return
  fi
  wait_for_main_pids "$hats_desktop" 1
  compat_pid="$(main_pids "$hats_desktop" | head -n 1)"
  case "$output" in
    "Launched Claude (Compat), pid $compat_pid."*)
      if [ -n "$compat_pid" ]; then
        report ok "open launched pid $compat_pid"
      else
        report no "open printed '$output', but no process runs on the data dir"
        return
      fi
      ;;
    *)
      report no "open printed '$output', and pid '$compat_pid' runs on the data dir"
      if [ -z "$compat_pid" ]; then return; fi
      ;;
  esac
  # A process exists before its app can be activated, as the fixed waits below allow for.
  sleep 5

  if capture_hats ps --json --profile compat && [ "$(json_value "$output" 0.pid)" = "$compat_pid" ]; then
    report ok "ps --json --profile lists pid $compat_pid"
    if [ "$(json_value "$output" 0.configDir)" = "$hats_code" ]; then
      report ok "CLAUDE_CONFIG_DIR read back from the live process"
    else
      report no "the live process has CLAUDE_CONFIG_DIR '$(json_value "$output" 0.configDir)', not '$hats_code'"
    fi
  else
    report no "ps --json --profile doesn't list pid $compat_pid: $output"
  fi

  if capture_hats doctor; then
    report ok "doctor finds nothing to fail on"
  else
    report no "doctor failed: $(printf '%s\n' "$output" | grep -F '[fail]' || printf '%s' "$output")"
  fi

  # With another app in front, so this can't pass with focus doing nothing.
  open -a Finder
  sleep 2
  if capture_hats open compat; then
    case "$output" in
      "Focused Claude (Compat), pid $compat_pid."*) report ok "a second open says it focused the same pid" ;;
      *) report no "a second open printed '$output'" ;;
    esac
  else
    report no "a second open failed: $output"
  fi
  sleep 2
  if [ "$(frontmost_pid)" = "$compat_pid" ]; then
    report ok "pid $compat_pid really is frontmost"
  else
    report no "pid $(frontmost_pid) is frontmost, not $compat_pid"
  fi
  running="$(count_main_pids "$hats_desktop")"
  if [ "$running" -eq 1 ]; then
    report ok "one process still runs on the data dir"
  else
    report no "$running processes run on the data dir after a second open"
  fi

  open -n -a "$app" --env CLAUDE_CONFIG_DIR="$hats_code" --args --user-data-dir="$hats_desktop"
  wait_for_main_pids "$hats_desktop" 2
  # Other real duplicates, which this temporary HATS_HOME doesn't know, may print too.
  if capture_hats dedupe --dry-run && printf '%s\n' "$output" | grep -qF "'compat': keep pid $compat_pid, quit "; then
    report ok "dedupe --dry-run keeps the older instance"
  else
    report no "dedupe --dry-run printed '$output' for a forced duplicate"
  fi

  pause "Quit the 'compat' windows, pids $(main_pids "$hats_desktop" | tr '\n' ' '), with Cmd-Q. hats sends them nothing, so Claude can save its state as it normally would."
  wait_for_main_pids "$hats_desktop" 0 60
  if [ "$(count_main_pids "$hats_desktop")" -ne 0 ]; then
    report no "pids $(main_pids "$hats_desktop" | tr '\n' ' ') still run on the data dir, so the profile stays in $work_dir"
    return
  fi
  if [ -n "$hats_launcher" ]; then "$lsregister" -u "$hats_launcher" || true; fi
  if capture_hats rm compat; then
    report ok "rm removes the launcher once nothing runs"
  else
    report no "rm failed: $output"
  fi
}

echo "Claude Desktop $(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString)"
echo "Work dir: $work_dir"

check_hats

echo
echo "1. CLAUDE_CONFIG_DIR reaches the Desktop main process"
open -n -a "$app" --env CLAUDE_CONFIG_DIR="$code" --args --user-data-dir="$desktop"
wait_for_main_pids "$desktop" 1
pid="$(main_pids "$desktop" | head -n 1)"
if [ -n "$pid" ] && ps eww -o command= -p "$pid" | tr ' ' '\n' | grep -qx "CLAUDE_CONFIG_DIR=$code"; then
  report ok "pid $pid has it"
else
  report no "pid '$pid' doesn't have it"
fi

echo
echo "2. A second launch with the same data dir"
open -n -a "$app" --env CLAUDE_CONFIG_DIR="$code" --args --user-data-dir="$desktop"
wait_for_main_pids "$desktop" 2
echo "  main processes on the work dir: $(count_main_pids "$desktop") (2 means duplicate)"

pause "3. Sign-in: sign in with the new window while your default Claude stays open. Note where the login lands, then try pasting the code from the browser."
pause "4. Code tab: open the Code tab in the new window and send one message."
echo "  $code/projects: $(find "$code/projects" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ') entries"
echo "  $code/sessions: $(find "$code/sessions" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ') entries"
echo "  (entries mean the Code tab used this profile's CLAUDE_CONFIG_DIR)"
pause "5. Cowork: use Cowork once in the new window."
du -sh "$desktop" "$desktop"/vm_bundles 2>/dev/null || true

echo
pause "Quit each test window with Cmd-Q. The script sends no signals, so Claude can save its state as it normally would."
echo "  main processes still on the work dir: $(count_main_pids "$desktop") (0 means all quit)"
echo "Done. Delete $work_dir when you no longer need it."
if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) NOT confirmed."
  exit 1
fi
