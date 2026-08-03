#!/usr/bin/env bash
# Fetch a BYOND release into byond-standalones/<version>/ so run.sh finds it.
# The Linux counterpart of fetch-byond.ps1.
#
# The binaries are Byond Software's and are not redistributed with this
# repository. This downloads a published release archive, extracts it, and
# verifies that what came out reports the version the folder claims.
#
# The archive is downloaded to a temporary file and deleted afterwards, on
# success or failure, so no duplicate copy is kept.
#
# Usage:
#   tools/fetch-byond.sh 516.1685
#   tools/fetch-byond.sh 516.1685 --force
#   tools/fetch-byond.sh 516.1685 --url https://.../516.1685_byond_linux.zip
#
# Installs into $DMBENCH_BYOND, else <repo>/byond-standalones, else
# ~/byond-standalones, matching the order run.sh searches.

set -eu

VERSION=${1:-}
shift || true
URL=""
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --url)   URL="$2"; shift ;;
        --force) FORCE=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$VERSION" in
    [0-9][0-9][0-9].[0-9]*) ;;
    *) echo "usage: tools/fetch-byond.sh <version like 516.1685> [--force] [--url URL]" >&2; exit 2 ;;
esac
MAJOR=${VERSION%%.*}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ -n "${DMBENCH_BYOND:-}" ]; then STANDALONE="$DMBENCH_BYOND"
elif [ -d "$ROOT/byond-standalones" ]; then STANDALONE="$ROOT/byond-standalones"
else STANDALONE="$HOME/byond-standalones"; fi
mkdir -p "$STANDALONE"

DEST="$STANDALONE/$VERSION"
if [ -d "$DEST" ] && [ "$FORCE" != "1" ]; then
    echo "already present: $DEST (pass --force to replace)"
    exit 0
fi

[ -n "$URL" ] || URL="https://www.byond.com/download/build/$MAJOR/${VERSION}_byond_linux.zip"

TMPZIP=$(mktemp -t byond-XXXXXX.zip)
STAGE=$(mktemp -d -t byond-stage-XXXXXX)
# Clean up the archive and the staging tree whatever happens, so a failed
# fetch does not leave a 23 MB duplicate behind.
trap 'rm -rf "$TMPZIP" "$STAGE"' EXIT

echo "fetching $URL"
if command -v curl >/dev/null 2>&1; then
    curl -fSL --retry 2 -o "$TMPZIP" "$URL"
else
    wget -q -O "$TMPZIP" "$URL"
fi

unzip -q "$TMPZIP" -d "$STAGE"

# The archive carries a top-level byond/ directory holding bin/. Find the
# directory that actually contains the binaries rather than assuming a depth,
# so a change in packaging fails loudly here instead of producing an install
# that run.sh silently skips.
DM=$(find "$STAGE" -type f -name DreamMaker | head -1)
[ -n "$DM" ] || { echo "no DreamMaker inside $URL; the package layout has changed" >&2; exit 1; }
SRC=$(dirname "$(dirname "$DM")")

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/
chmod +x "$DEST"/bin/* 2>/dev/null || true

# The same check run.sh makes, applied at fetch time. Linux binaries carry no
# version metadata, but DreamMaker prints its version with no arguments.
BIN="$DEST/bin"
[ -x "$BIN/DreamMaker" ] || BIN="$DEST/byond/bin"
REPORTED=$(LD_LIBRARY_PATH="$BIN" "$BIN/DreamMaker" 2>&1 | sed -n 's/^DM compiler version \([0-9.]*\).*/\1/p' | head -1)
if [ "$REPORTED" != "$VERSION" ]; then
    rm -rf "$DEST"
    echo "extracted binaries report '$REPORTED' but the folder is $VERSION; removed" >&2
    exit 1
fi

echo "installed $VERSION -> $DEST (binaries report $REPORTED)"
echo "tools/run.sh --list to confirm"
