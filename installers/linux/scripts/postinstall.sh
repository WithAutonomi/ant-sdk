#!/bin/sh
# antd .deb/.rpm post-install scriptlet (runs as root).
#
# Goal (approach B): register a PER-USER login autostart for antd --cors and,
# best-effort, start it now so the browser extension connects without a
# re-login. We must NOT run antd as root / a system unit, or its per-user
# daemon.port/config would land in root's profile and the extension couldn't
# find it.
set -e

UNIT="antd.service"

# 1) Enable the user unit for every user's FUTURE login session. --global
#    writes the enablement symlink under /etc/systemd/user/...default.target.wants
#    so antd starts in each user's `systemd --user` manager at login.
if command -v systemctl >/dev/null 2>&1; then
    systemctl --global enable "$UNIT" >/dev/null 2>&1 || true
fi

# 2) Best-effort start NOW in the active (non-root) user's session. postinst
#    runs as root, so we hop into the logged-in user's --user manager via their
#    XDG_RUNTIME_DIR. If we can't (headless / no active session), antd will
#    start automatically on their next login thanks to step 1.
start_for_user() {
    _user="$1"
    [ -n "$_user" ] && [ "$_user" != "root" ] || return 1
    _uid=$(id -u "$_user" 2>/dev/null) || return 1
    [ -n "$_uid" ] || return 1
    if [ -d "/run/user/$_uid" ]; then
        sudo -u "$_user" \
            XDG_RUNTIME_DIR="/run/user/$_uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$_uid/bus" \
            systemctl --user start "$UNIT" >/dev/null 2>&1 && return 0
    fi
    return 1
}

started=0
if command -v loginctl >/dev/null 2>&1; then
    # Iterate active users reported by logind; start in the first that works.
    for u in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $2}'); do
        if start_for_user "$u"; then
            started=1
            break
        fi
    done
fi

if [ "$started" -ne 1 ]; then
    echo "antd: enabled for autostart. It will launch on next login;"
    echo "      to start it now run:  systemctl --user start antd.service"
fi

exit 0
