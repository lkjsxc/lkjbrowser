#!/bin/sh
# Source this helper from a launcher. Never put the bridge credential in shell
# variables, argv, environment, logs, or a file that outlives preparation.
# FD 8 and FD 9 are independent read descriptions of one unlinked 32-byte token.
wayland_auth_close() {
    exec 8<&- 9<&-
    # A launcher's EXIT/signal cleanup also removes an interrupted preparation.
    if test -n "${_wayland_auth_dir:-}"; then
        rm -f "$_wayland_auth_dir/token" 8<&- 9<&- || true
        rmdir "$_wayland_auth_dir" 8<&- 9<&- || true
    fi
    if test -n "${_wayland_auth_umask:-}"; then
        umask "$_wayland_auth_umask"
    fi
    unset _wayland_auth_dir _wayland_auth_umask
}
wayland_auth_prepare() {
    wayland_auth_close
    _wayland_auth_umask=$(umask)
    umask 077
    if ! _wayland_auth_dir=$(mktemp -d "${TMPDIR:-/tmp}/lkjbrowser-auth.XXXXXXXX"); then
        wayland_auth_close
        return 1
    fi
    if ! chmod 700 "$_wayland_auth_dir" ||
       ! dd if=/dev/urandom of="$_wayland_auth_dir/token" bs=32 count=1 iflag=fullblock status=none ||
       test "$(wc -c <"$_wayland_auth_dir/token")" -ne 32 ||
       ! command exec 8<"$_wayland_auth_dir/token" ||
       ! command exec 9<"$_wayland_auth_dir/token"; then
        wayland_auth_close
        return 1
    fi
    # Both descriptions retain the bytes; no credential pathname survives launch.
    # The cleanup subprocesses do not inherit either credential description.
    if ! rm -f "$_wayland_auth_dir/token" 8<&- 9<&- ||
       ! rmdir "$_wayland_auth_dir" 8<&- 9<&-; then
        wayland_auth_close
        return 1
    fi
    umask "$_wayland_auth_umask"
    unset _wayland_auth_dir _wayland_auth_umask
}
