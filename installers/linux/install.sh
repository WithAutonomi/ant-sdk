#!/bin/sh
# antd generic Linux installer — published as the release asset
# `antd-linux-install.sh`. Catch-all for distros without a .deb/.rpm and for
# headless systems. Downloads the antd binary from the GitHub release, installs
# a per-user systemd unit running `antd --cors`, enables it for login autostart,
# and (best-effort) starts it now.
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
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

is_root() { [ "$(id -u)" = "0" ]; }

# Resolve install locations based on privilege.
if is_root; then
    BIN_DIR="/usr/local/bin"
    UNIT_DIR="/etc/systemd/user"          # global user-unit search path
else
    BIN_DIR="${HOME}/.local/bin"
    UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
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

if [ -n "$TAG" ]; then
    URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
else
    # /releases/latest/download resolves to the most recent (non-pre) release.
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
fi

echo "Downloading $ASSET from $URL"
mkdir -p "$BIN_DIR"
# shellcheck disable=SC2086
$DL "$BIN_PATH" "$URL"
chmod 0755 "$BIN_PATH"

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
