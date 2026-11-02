#!/bin/sh
# Prints the Homebrew formula for a release.
# Usage: scripts/render-formula.sh <owner/repo> <release-tag> <sha256>
set -eu

repo=$1
tag=$2
sha256=$3

cat <<FORMULA
class Hats < Formula
  desc "Run several Claude accounts side by side and see every running Claude"
  homepage "https://github.com/$repo"
  url "https://github.com/$repo/releases/download/$tag/hats-macos-universal.tar.gz"
  sha256 "$sha256"
  license "MIT"
  head "https://github.com/$repo.git", branch: "main"

  depends_on macos: :sonoma

  def install
    if build.head?
      system "swift", "build", "--disable-sandbox", "-c", "release"
      bin.install ".build/release/hats"
    else
      bin.install "hats"
    end
  end

  def caveats
    <<~EOS
      Get started with:
        hats setup
      Launchers call #{HOMEBREW_PREFIX}/bin/hats, so they keep working across upgrades.
    EOS
  end

  test do
    assert_match "Run several Claude accounts", shell_output("#{bin}/hats --help")
  end
end
FORMULA
