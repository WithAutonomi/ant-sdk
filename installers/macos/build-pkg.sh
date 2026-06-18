#!/usr/bin/env bash
# Build (and, when signing env is present, sign + notarize) the antd macOS .pkg.
# Runs on macOS. Adapted from maidsafe/autonomi build-macos-pkg.yml, reduced to a
# single daemon binary plus a LaunchAgent + postinstall autostart.
#
# Usage:
#   build-pkg.sh --bin <path/to/antd> [--version X.Y.Z] [--arch arm64] [--out <dir>]
#
# Signing/notarization (all optional — skipped with a warning if unset):
#   Binary codesign : APP_SIGNING_IDENTITY  (Developer ID Application) + KEYCHAIN_PATH
#   Package sign    : INSTALLER_SIGNING_IDENTITY (Developer ID Installer) + KEYCHAIN_PATH
#   Notarization    : APPLE_ID, APPLE_NOTARIZATION_PASSWORD, APPLE_TEAM_ID
# The CI job is responsible for creating the keychain and importing the certs
# (same as autonomi) and exporting the *_SIGNING_IDENTITY / KEYCHAIN_PATH vars.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../common/metadata.env
. "$SCRIPT_DIR/../common/metadata.env"

BIN_SRC=""
VERSION=""
ARCH="arm64"                 # matches the release matrix (aarch64-apple-darwin)
OUT_DIR="$SCRIPT_DIR/dist"
IDENTIFIER="com.autonomi.antd"

while [ $# -gt 0 ]; do
    case "$1" in
        --bin)     BIN_SRC="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --arch)    ARCH="$2"; shift 2 ;;
        --out)     OUT_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(grep -m1 '^version' "$REPO_ROOT/antd/Cargo.toml" | sed -E 's/.*"([^"]+)".*/\1/')"
fi
[ -n "$BIN_SRC" ] && [ -f "$BIN_SRC" ] || { echo "antd binary not found (pass --bin)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT_DIR"

# 1) Assemble the payload root.
mkdir -p "$WORK/pkg-root/usr/local/bin"
mkdir -p "$WORK/pkg-root/Library/LaunchAgents"
install -m 0755 "$BIN_SRC" "$WORK/pkg-root$ANTD_MACOS_BIN"
install -m 0644 "$SCRIPT_DIR/com.autonomi.antd.plist" "$WORK/pkg-root/Library/LaunchAgents/com.autonomi.antd.plist"

# Scripts dir for pkgbuild (postinstall must be named exactly "postinstall").
mkdir -p "$WORK/scripts"
install -m 0755 "$SCRIPT_DIR/scripts/postinstall" "$WORK/scripts/postinstall"

# 2) Codesign the binary (Developer ID Application), if configured.
if [ -n "${APP_SIGNING_IDENTITY:-}" ] && [ -n "${KEYCHAIN_PATH:-}" ]; then
    echo "Codesigning antd with: $APP_SIGNING_IDENTITY"
    codesign --sign "$APP_SIGNING_IDENTITY" --keychain "$KEYCHAIN_PATH" \
        --options runtime --timestamp --force "$WORK/pkg-root$ANTD_MACOS_BIN"
    codesign --verify --verbose "$WORK/pkg-root$ANTD_MACOS_BIN"
else
    echo "WARNING: APP_SIGNING_IDENTITY/KEYCHAIN_PATH unset — binary NOT codesigned." >&2
fi

# 3) Component package.
pkgbuild \
    --root "$WORK/pkg-root" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --scripts "$WORK/scripts" \
    --install-location / \
    "$WORK/antd-component.pkg"

# 4) Product package via distribution XML (arm64-only host arch).
cat > "$WORK/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Autonomi antd daemon</title>
    <organization>com.autonomi</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" hostArchitectures="$ARCH"/>
    <choices-outline>
        <line choice="default"><line choice="$IDENTIFIER"/></line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$IDENTIFIER" visible="false"><pkg-ref id="$IDENTIFIER"/></choice>
    <pkg-ref id="$IDENTIFIER" version="$VERSION" onConclusion="none">antd-component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild \
    --distribution "$WORK/distribution.xml" \
    --package-path "$WORK" \
    "$WORK/antd-unsigned.pkg"

FINAL="$OUT_DIR/$ANTD_ASSET_PKG"

# 5) Sign the package (Developer ID Installer), if configured.
if [ -n "${INSTALLER_SIGNING_IDENTITY:-}" ] && [ -n "${KEYCHAIN_PATH:-}" ]; then
    echo "Signing package with: $INSTALLER_SIGNING_IDENTITY"
    productsign --sign "$INSTALLER_SIGNING_IDENTITY" --keychain "$KEYCHAIN_PATH" \
        "$WORK/antd-unsigned.pkg" "$FINAL"
    pkgutil --check-signature "$FINAL"
else
    echo "WARNING: INSTALLER_SIGNING_IDENTITY/KEYCHAIN_PATH unset — package NOT signed." >&2
    cp "$WORK/antd-unsigned.pkg" "$FINAL"
fi

# 6) Notarize + staple, if configured.
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_NOTARIZATION_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "Submitting $FINAL for notarization..."
    xcrun notarytool submit "$FINAL" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_NOTARIZATION_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait --timeout 45m
    # Staple with a few retries (ticket propagation can lag).
    n=0
    until xcrun stapler staple "$FINAL"; do
        n=$((n + 1)); [ "$n" -ge 5 ] && { echo "stapling failed" >&2; exit 1; }
        echo "staple retry $n..."; sleep 30
    done
    xcrun stapler validate "$FINAL"
    spctl -a -vv -t install "$FINAL" || true
else
    echo "WARNING: APPLE_ID/APPLE_NOTARIZATION_PASSWORD/APPLE_TEAM_ID unset — NOT notarized." >&2
fi

echo "Done: $FINAL"
ls -lh "$FINAL"
