#!/bin/sh
# Runs brew style and brew audit on a rendered formula before any release
# ships it. Both need the formula inside a tap, so it goes into a throwaway
# local tap that is removed afterwards.
# Usage: scripts/check-formula.sh <path-to-formula.rb>
set -eu

formula=$1
tap=wearhats/formula-check
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1

brew tap-new --no-git "$tap" >/dev/null
trap 'brew untrust --formula "$tap/hats" >/dev/null; brew untap "$tap" >/dev/null' EXIT
cp "$formula" "$(brew --repository "$tap")/Formula/hats.rb"
brew style "$(brew --repository "$tap")/Formula/hats.rb"
# Homebrew loads formulae from third-party taps only once they are trusted.
brew trust --formula "$tap/hats" >/dev/null
# Not --online: the URL points at a release that doesn't exist yet.
brew audit --strict --formula "$tap/hats"
