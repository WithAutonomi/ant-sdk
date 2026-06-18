#!/usr/bin/env bash
# Build the antd Linux .deb and .rpm packages with nfpm.
#
# Usage:
#   build-deb-rpm.sh --bin <path/to/antd> [--version X.Y.Z] [--out <dir>] [--deb] [--rpm]
#
# Defaults: version is read from antd/Cargo.toml; both packages are built;
# output goes to ./dist. Produces the fixed asset filenames from metadata.env
# (antd-linux-x64.deb / antd-linux-x64.rpm) so the release CI can upload them
# directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../common/metadata.env
. "$SCRIPT_DIR/../common/metadata.env"

BIN_SRC=""
VERSION=""
OUT_DIR="$SCRIPT_DIR/dist"
BUILD_DEB=0
BUILD_RPM=0

while [ $# -gt 0 ]; do
    case "$1" in
        --bin)     BIN_SRC="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --out)     OUT_DIR="$2"; shift 2 ;;
        --deb)     BUILD_DEB=1; shift ;;
        --rpm)     BUILD_RPM=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Default: build both if neither flag was given.
if [ "$BUILD_DEB" -eq 0 ] && [ "$BUILD_RPM" -eq 0 ]; then
    BUILD_DEB=1; BUILD_RPM=1
fi

# Resolve the version from antd/Cargo.toml if not supplied.
if [ -z "$VERSION" ]; then
    VERSION="$(grep -m1 '^version' "$REPO_ROOT/antd/Cargo.toml" | sed -E 's/.*"([^"]+)".*/\1/')"
fi
[ -n "$VERSION" ] || { echo "could not determine version" >&2; exit 1; }

# Locate the binary if not supplied.
if [ -z "$BIN_SRC" ]; then
    BIN_SRC="$REPO_ROOT/antd/target/release/$ANTD_BINARY_NAME"
fi
[ -f "$BIN_SRC" ] || { echo "antd binary not found: $BIN_SRC (pass --bin)" >&2; exit 1; }

command -v nfpm >/dev/null 2>&1 || {
    echo "nfpm not found. Install with:" >&2
    echo "  go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest" >&2
    exit 1
}

mkdir -p "$OUT_DIR"

cd "$SCRIPT_DIR"

# Render nfpm.yaml explicitly. This nfpm build does not expand env vars inside
# contents[].src globs, so we substitute our known placeholders ourselves with
# envsubst (restricted to our variables so any literal nfpm `$` syntax is kept).
export ANTD_VERSION="$VERSION"
export ANTD_BIN_SRC="$BIN_SRC"
export ANTD_MAINTAINER ANTD_DESCRIPTION ANTD_VENDOR ANTD_HOMEPAGE ANTD_LICENSE
RENDERED="$(mktemp "${TMPDIR:-/tmp}/antd-nfpm.XXXXXX.yaml")"
trap 'rm -f "$RENDERED"' EXIT
envsubst '$ANTD_VERSION $ANTD_BIN_SRC $ANTD_MAINTAINER $ANTD_DESCRIPTION $ANTD_VENDOR $ANTD_HOMEPAGE $ANTD_LICENSE' \
    < nfpm.yaml > "$RENDERED"

if [ "$BUILD_DEB" -eq 1 ]; then
    echo "Building $ANTD_ASSET_DEB (version $VERSION)"
    nfpm package --config "$RENDERED" --packager deb --target "$OUT_DIR/$ANTD_ASSET_DEB"
fi

if [ "$BUILD_RPM" -eq 1 ]; then
    echo "Building $ANTD_ASSET_RPM (version $VERSION)"
    nfpm package --config "$RENDERED" --packager rpm --target "$OUT_DIR/$ANTD_ASSET_RPM"
fi

echo "Done. Artifacts in: $OUT_DIR"
ls -lh "$OUT_DIR"
