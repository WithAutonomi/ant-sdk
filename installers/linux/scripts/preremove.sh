#!/bin/sh
# antd .deb/.rpm pre-remove scriptlet (runs as root).
# Stop the running per-user instance(s) and undo the global enablement.
set -e

UNIT="antd.service"

stop_for_user() {
    _user="$1"
    [ -n "$_user" ] && [ "$_user" != "root" ] || return 0
    _uid=$(id -u "$_user" 2>/dev/null) || return 0
    [ -n "$_uid" ] || return 0
    if [ -d "/run/user/$_uid" ]; then
        sudo -u "$_user" \
            XDG_RUNTIME_DIR="/run/user/$_uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$_uid/bus" \
            systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
    fi
}

if command -v loginctl >/dev/null 2>&1; then
    for u in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $2}'); do
        stop_for_user "$u"
    done
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl --global disable "$UNIT" >/dev/null 2>&1 || true
fi

exit 0
