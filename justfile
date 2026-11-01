# Run `just` to list the recipes.

set positional-arguments

# Keep in step with the linux job in .github/workflows/ci.yml.
linux_image := "swift:6.4-noble"

[private]
default:
    @just --list --unsorted

# Debug build of everything.
build:
    swift build

# All tests: unit, integration and end-to-end. Extra arguments go to `swift test`.
test *args:
    #!/bin/sh
    set -eu
    # SwiftPM doesn't find swift-testing's macro plugin when only the Command
    # Line Tools are selected ("plugin for module 'TestingMacros' not found").
    plugins=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
    if [ "$(xcode-select -p 2>/dev/null)" = /Library/Developer/CommandLineTools ] && [ -d "$plugins" ]; then
      set -- -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
    fi
    swift test "$@"

# End-to-end tests only, failing if the Seatbelt guard can't be applied.
e2e *args:
    HATS_E2E_REQUIRE_GUARD=1 just test --filter HatsE2ETests "$@"

# swift-format, shellcheck and actionlint.
lint:
    swift format lint --strict --recursive Sources Tests Package.swift
    shellcheck scripts/*.sh
    actionlint

# Rewrite Swift sources with swift-format.
format:
    swift format --in-place --recursive Sources Tests Package.swift

# Release build, package, install through install.sh and check the formula, as CI does. Extra arguments go to `swift build`.
package *build_args:
    #!/bin/sh
    set -eu
    rm -rf dist
    swift build -c release "$@"
    bin="$(swift build -c release "$@" --show-bin-path)/hats"
    # Before the first commit package.sh has no commit time to fall back on.
    SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)} \
      scripts/package.sh "$bin" dist/release
    HATS_BASE_URL="file://$PWD/dist/release" HATS_INSTALL_DIR="$PWD/dist/bin" sh scripts/install.sh
    dist/bin/hats --version
    scripts/render-formula.sh wearhats/hats 0.0.0 "$(cut -d' ' -f1 dist/release/SHA256SUMS)" > dist/hats.rb
    ruby -c dist/hats.rb

# Build and test HatsCore on Linux in Docker, as the linux CI job does.
linux:
    docker run --rm -v "$PWD:/src:ro" {{linux_image}} sh -euc '\
      mkdir /work && cd /src && \
      tar --exclude=./.build -cf - Package.swift Package.resolved Sources Tests | tar -xf - -C /work && \
      cd /work && swift build --target HatsCore && swift test --parallel'

# Everything to run before pushing: lint, tests and packaging.
check: lint test package
