#!/bin/sh
# NOT RUN YET: written on Linux, where hats doesn't run.
#
# Builds a throwaway hats test sandbox with neutral profiles and prints the exports
# for it, so the tapes can't touch real data:
#
#   eval "$(sh sandbox.sh)"
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/hats-demo.XXXXXX")
root=$(cd "$root" && pwd -P)
home="$root/home"

mkdir -p "$home/.claude" "$home/demo/api" "$home/demo/blog" "$home/.claude-work" "$root/launchers" "$root/.test" "$root/tmp"
: >"$root/.hats-test-sandbox"

printf '{"oauthAccount":{"accountUuid":"00000000-0000-4000-8000-000000000001","emailAddress":"you@example.com"}}\n' \
  >"$home/.claude.json"
printf '{"oauthAccount":{"accountUuid":"00000000-0000-4000-8000-000000000002","emailAddress":"you@acme.example","organizationName":"Acme Inc."}}\n' \
  >"$home/.claude-work/.claude.json"

# Hook for the fake Claude from the running-instances test support, once it's merged.
: "${HATS_E2E_FAKE:=}"

cat <<EXPORTS
export HATS_TEST_SANDBOX='$root'
export HOME='$home'
export HATS_HOME='$root/hats'
export HATS_LAUNCHER_DIR='$root/launchers'
export HATS_DEFAULT_CONFIG_DIR='$home/.claude'
export TMPDIR='$root/tmp'
export NO_COLOR=1
cd '$home'
EXPORTS
