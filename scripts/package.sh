#!/bin/sh
# Packages a built hats binary as a release asset plus SHA256SUMS.
# Usage: scripts/package.sh <path-to-hats-binary> <output-dir>
#
# The tarball is byte-for-byte reproducible for a given binary: fixed mtimes
# (SOURCE_DATE_EPOCH, else the HEAD commit time), a fixed entry order, owner and
# group 0, fixed modes, no extended attributes or AppleDouble files, ustar
# headers, and a gzip header without a name or timestamp.
set -eu

binary=$1
out=$2
asset=hats-macos-universal.tar.gz

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 2>/dev/null) ||
    { echo "package.sh: set SOURCE_DATE_EPOCH or run inside a git checkout with a commit" >&2; exit 1; }
fi
stamp=$(date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage=$work/stage
mkdir "$stage"
mkdir -p "$out"
cp "$binary" "$stage/hats"
cp LICENSE README.md "$stage/"
chmod 0755 "$stage/hats"
chmod 0644 "$stage/LICENSE" "$stage/README.md"
TZ=UTC touch -h -t "$stamp" "$stage/hats" "$stage/LICENSE" "$stage/README.md"

# Entries are listed explicitly, so their order is fixed. ustar has no fields
# for atime, ctime or xattrs, unlike bsdtar's default pax format.
# A fixed, version-free asset name lets "releases/latest/download/<asset>" work.
# No pipe into gzip: sh has no pipefail, so a failed tar would still leave a
# tarball, and a checksum for it.
COPYFILE_DISABLE=1 tar -c -f "$work/hats.tar" --format ustar --no-xattrs --no-mac-metadata --no-acls --no-fflags \
  --uid 0 --gid 0 --uname '' --gname '' \
  -C "$stage" LICENSE README.md hats
gzip -n -9 -c "$work/hats.tar" >"$out/$asset"
(cd "$out" && shasum -a 256 "$asset" >SHA256SUMS)
cat "$out/SHA256SUMS"
