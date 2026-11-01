#!/bin/sh
# Installs the hats CLI from a GitHub release, verifying its checksum and, when
# the GitHub CLI is signed in, its build provenance.
#
#   curl -fsSL https://wearhats.dev/install.sh | sh
#   sh install.sh --version v0.2.0 --dir /usr/local/bin
#
# Installs to ~/.local/bin by default. Never uses sudo and never edits shell
# startup files.
set -eu

fail() {
  echo "hats install: $*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: install.sh [--version vX.Y.Z] [--dir DIR]

  --version  Release tag to install (default: latest)
  --dir      Install directory (default: ~/.local/bin)

Environment: HATS_VERSION, HATS_INSTALL_DIR, HATS_REPO, HATS_BASE_URL
USAGE
}

# Everything runs from main, called on the last line, so a download cut short
# by "curl | sh" defines functions and exits without doing anything.
main() {
  repo=${HATS_REPO:-wearhats/hats}
  version=${HATS_VERSION:-latest}
  dir=${HATS_INSTALL_DIR:-$HOME/.local/bin}
  base_url=${HATS_BASE_URL:-}
  asset=hats-macos-universal.tar.gz

  while [ $# -gt 0 ]; do
    case $1 in
      --version) [ $# -ge 2 ] || fail "--version needs a value"; version=$2; shift 2 ;;
      --dir) [ $# -ge 2 ] || fail "--dir needs a value"; dir=$2; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 64 ;;
    esac
  done

  [ "$(uname -s)" = Darwin ] || fail "hats runs on macOS only"
  macos_major=$(sw_vers -productVersion | cut -d. -f1)
  [ "$macos_major" -ge 14 ] || fail "hats needs macOS 14 or later (found $(sw_vers -productVersion))"

  if [ -z "$base_url" ]; then
    if [ "$version" = latest ]; then
      base_url="https://github.com/$repo/releases/latest/download"
    else
      base_url="https://github.com/$repo/releases/download/$version"
    fi
  fi

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading $base_url/$asset"
  curl -fsSL "$base_url/$asset" -o "$tmp/$asset" || fail "download failed"
  curl -fsSL "$base_url/SHA256SUMS" -o "$tmp/SHA256SUMS" || fail "checksum download failed"
  (cd "$tmp" && grep " $asset\$" SHA256SUMS | shasum -a 256 -c - >/dev/null) || fail "checksum mismatch; not installing"
  echo "Checksum OK"

  case $base_url in
    https://github.com/*) from_github=true ;;
    *) from_github=false ;;
  esac
  if [ "$from_github" = false ]; then
    echo "Skipping the build provenance check (not downloaded from GitHub)"
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh attestation verify "$tmp/$asset" --repo "$repo" >/dev/null || fail "build provenance check failed; not installing"
    echo "Build provenance OK"
  else
    echo "Skipping the build provenance check (needs a signed-in GitHub CLI: gh auth login)"
  fi

  tar -xzf "$tmp/$asset" -C "$tmp" hats
  mkdir -p "$dir"
  install -m 0755 "$tmp/hats" "$dir/hats"
  echo "Installed $("$dir/hats" --version) to $dir/hats"

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) echo "Add it to your PATH, for example: echo 'export PATH=\"$dir:\$PATH\"' >> ~/.zshrc" ;;
  esac
  echo "Get started: hats setup"
  echo "Moved hats from another install? Point existing launchers at this one: hats launcher rebuild"
}

main "$@"
