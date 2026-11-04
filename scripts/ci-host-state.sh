#!/bin/sh
# Prints what the end-to-end tests must leave alone on a CI runner, so a job can
# diff it before and after them. This catches a call the Seatbelt guard can't see
# failing, such as one that goes through a system daemon. It reads the account's
# real Dock, Trash and Launch Services state, so it only runs on a throwaway host.
set -u

if [ "${GITHUB_ACTIONS:-}" != true ] || [ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]; then
  echo "ci-host-state.sh reads real state and only runs on a GitHub-hosted runner" >&2
  exit 64
fi

# A read that fails must fail the job: failing the same way before and after would
# look like nothing changed.
set -e

for path in "$HOME/Library/Application Support/hats" "$HOME/Applications/Hats"; do
  if [ -e "$path" ]; then
    echo "exists: $path"
    find "$path" -print
  fi
done
# A link's own state, not its target's: test (-e) follows a link and misses a dangling one.
if [ -L /Applications/Hats ] || [ -e /Applications/Hats ]; then
  echo "exists: /Applications/Hats -> $(readlink /Applications/Hats || true)"
fi
echo "trash:"
ls -A "$HOME/.Trash"
dock="$(defaults read com.apple.dock persistent-apps)"
echo "dock: $(printf '%s' "$dock" | shasum)"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
dump="$("$lsregister" -dump)"
echo "launch services: $(printf '%s\n' "$dump" | grep -c 'dev\.wearhats' || true)"
