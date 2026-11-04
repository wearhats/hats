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

# Test mode has no real Claude.app, Keychain or claude:// handler, so it reads these stand-ins.
app="$root/Applications/Claude.app"
mkdir -p "$app/Contents"
cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.anthropic.claudefordesktop</string>
<key>CFBundleShortVersionString</key><string>0.0.0-demo</string>
</dict></plist>
PLIST
printf '%s\n' "$app" >"$root/.test/claude-url-handler"

# Service names follow KeychainCredentialProbe: the first 8 hex of the config dir's SHA-256.
service() { printf 'Claude Code-credentials-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"; }
printf '["Claude Code-credentials","%s","%s"]\n' \
  "$(service "$home/.claude-work")" "$(service "$root/hats/profiles/personal/code")" >"$root/.test/keychain.json"

cat <<EXPORTS
export HATS_TEST_SANDBOX='$root'
export HOME='$home'
export HATS_HOME='$root/hats'
export HATS_LAUNCHER_DIR='$root/launchers'
export HATS_DEFAULT_CONFIG_DIR='$home/.claude'
export HATS_CLAUDE_APP='$app'
export TMPDIR='$root/tmp'
export NO_COLOR=1
EXPORTS
