#!/bin/sh
# antd generic Linux installer — published as the release asset
# `antd-linux-install.sh`. Catch-all for distros without a .deb/.rpm and for
# headless systems. Downloads the antd binary from the GitHub release, installs
# a per-user systemd unit running `antd --cors`, enables it for login autostart,
# and (best-effort) starts it now. antd's licence files and the third-party
# notices for the downloaded binary go into share/doc/antd beside the install.
#
# Usage:
#   ./antd-linux-install.sh [--tag vX.Y.Z] [--uninstall]
#   ANTD_TAG=v0.10.0 ./antd-linux-install.sh
#
# Run as root to install for all users (binary in /usr/local/bin, unit enabled
# --global). Run as a normal user for a rootless install into ~/.local/bin +
# ~/.config/systemd/user.
set -eu

REPO="WithAutonomi/ant-sdk"
UNIT="antd.service"
TAG="${ANTD_TAG:-}"
ACTION="install"

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        --uninstall) ACTION="uninstall"; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

is_root() { [ "$(id -u)" = "0" ]; }

# Resolve install locations based on privilege.
if is_root; then
    BIN_DIR="/usr/local/bin"
    UNIT_DIR="/etc/systemd/user"          # global user-unit search path
    DOC_DIR="/usr/local/share/doc/antd"
else
    BIN_DIR="${HOME}/.local/bin"
    UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    DOC_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/doc/antd"
fi
BIN_PATH="$BIN_DIR/antd"
UNIT_PATH="$UNIT_DIR/$UNIT"

# ---- uninstall ----------------------------------------------------------
if [ "$ACTION" = "uninstall" ]; then
    if is_root; then
        systemctl --global disable "$UNIT" >/dev/null 2>&1 || true
    else
        systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true
    fi
    rm -f "$BIN_PATH" "$UNIT_PATH"
    rm -rf "$DOC_DIR"
    echo "antd uninstalled."
    exit 0
fi

# ---- detect arch --------------------------------------------------------
case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
ASSET="antd-linux-${ARCH}"

# ---- pick a downloader --------------------------------------------------
if command -v curl >/dev/null 2>&1; then
    DL="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
    DL="wget -qO"
else
    echo "need curl or wget to download antd" >&2
    exit 1
fi

# Read the release's metadata once: it pins "latest" to one tag, so the binary
# and its notices always come from the same release, and its asset list says
# whether that release publishes the licence files and notices.
if [ -n "$TAG" ]; then
    API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
else
    API="https://api.github.com/repos/$REPO/releases/latest"
fi
# shellcheck disable=SC2086
RELEASE="$($DL - "$API")" || { echo "could not read release metadata from $API" >&2; exit 1; }
if [ -z "$TAG" ]; then
    TAG="$(printf '%s\n' "$RELEASE" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$TAG" ] || { echo "could not resolve the latest antd release; pass --tag vX.Y.Z" >&2; exit 1; }
fi
BASE_URL="https://github.com/$REPO/releases/download/$TAG"
URL="$BASE_URL/$ASSET"
if printf '%s\n' "$RELEASE" | grep -q "\"name\": *\"$ASSET.THIRD-PARTY-NOTICES.txt\""; then
    WITH_NOTICES=1
else
    WITH_NOTICES=0
fi

# ---- download into a staging directory first ---------------------------
# The binary and, when the release publishes them, its licence files and
# third-party notices are fetched before anything is installed; every download
# must succeed.
if [ -d "$BIN_PATH" ]; then
    echo "$BIN_PATH is a directory; remove it and run the installer again" >&2
    exit 1
fi
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/antd-install.XXXXXX")"
NEW_BIN="$BIN_PATH.new.$$"
NEW_DOC="$DOC_DIR.new.$$"
OLD_DOC="$DOC_DIR.old.$$"
DOC_PLACED=0
COMMITTED=0
# On any exit before the binary is in place, put the previous documents back
# and remove everything this run created next to the destinations.
cleanup() {
    status=$?
    set +e
    if [ "$COMMITTED" -eq 0 ]; then
        if [ "$DOC_PLACED" -eq 1 ]; then
            rm -rf "$DOC_DIR"
        fi
        if [ -d "$OLD_DOC" ] && [ ! -e "$DOC_DIR" ]; then
            mv "$OLD_DOC" "$DOC_DIR"
        fi
        rm -f "$NEW_BIN"
        rm -rf "$NEW_DOC"
    fi
    rm -rf "$STAGE"
    exit "$status"
}
trap cleanup EXIT

echo "Downloading $ASSET ($TAG) from $URL"
# shellcheck disable=SC2086
$DL "$STAGE/antd" "$URL"
chmod 0755 "$STAGE/antd"

mkdir -p "$STAGE/doc"
if [ "$WITH_NOTICES" -eq 1 ]; then
    for doc in LICENSE-MIT LICENSE-APACHE \
        "$ASSET.THIRD-PARTY-NOTICES.txt:THIRD-PARTY-NOTICES.txt" \
        "$ASSET.RUST-STD-COPYRIGHT.html:RUST-STD-COPYRIGHT.html"; do
        remote="${doc%%:*}"
        local_name="${doc#*:}"
        # shellcheck disable=SC2086
        $DL "$STAGE/doc/$local_name" "$BASE_URL/$remote" \
            || { echo "could not download $remote from $BASE_URL; not installing" >&2; exit 1; }
    done
else
    echo "note: $TAG predates the published licence files and notices; see https://github.com/$REPO for licence information." >&2
fi

# ---- install ------------------------------------------------------------
# Copy everything next to its destination first, then swap it in by rename;
# the binary goes last. If anything fails, the cleanup trap restores the
# previous documents, so the notices are always those of the installed binary.
mkdir -p "$BIN_DIR" "$(dirname "$DOC_DIR")"
cp "$STAGE/antd" "$NEW_BIN"
chmod 0755 "$NEW_BIN"
cp -R "$STAGE/doc" "$NEW_DOC"
chmod 0755 "$NEW_DOC"
if [ "$WITH_NOTICES" -eq 1 ]; then
    chmod 0644 "$NEW_DOC"/*
fi
if [ -d "$DOC_DIR" ]; then
    mv "$DOC_DIR" "$OLD_DOC"
fi
mv "$NEW_DOC" "$DOC_DIR"
DOC_PLACED=1
mv "$NEW_BIN" "$BIN_PATH"
COMMITTED=1
rm -rf "$OLD_DOC"
if [ "$WITH_NOTICES" -eq 1 ]; then
    echo "Installed antd's licence files and third-party notices to $DOC_DIR"
fi

# ---- install the per-user systemd unit ----------------------------------
# NOTE: keep this in sync with installers/linux/systemd/antd.service.
mkdir -p "$UNIT_DIR"
cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Autonomi antd daemon
Documentation=https://github.com/WithAutonomi/ant-sdk
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_PATH --cors
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
chmod 0644 "$UNIT_PATH"

# ---- enable + start -----------------------------------------------------
if is_root; then
    systemctl --global enable "$UNIT" >/dev/null 2>&1 || true
    echo "antd installed to $BIN_PATH and enabled for all users at login."
    echo "It will start on each user's next login (run 'systemctl --user start antd.service' to start now)."
else
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if systemctl --user enable --now "$UNIT" >/dev/null 2>&1; then
        echo "antd installed to $BIN_PATH and started (systemd --user)."
    else
        echo "antd installed to $BIN_PATH and enabled. Start it with:"
        echo "  systemctl --user enable --now antd.service"
    fi
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) echo "note: $BIN_DIR is not on your PATH." ;;
    esac
fi
