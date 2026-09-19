#!/bin/sh
# Root-only BusyBox/POSIX service controller. No boot configuration changes.
set -eu
umask 077
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'Run this service as root'
BASE=${SSHD_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)}
[ -d "$BASE" ] && [ ! -L "$BASE" ] || fail 'Invalid installation directory'
cd "$BASE"
BASE=$(pwd -P)
[ "$(stat -c %u .)" = 0 ] || fail 'Installation directory must be owned by root'
chmod 700 .
for f in service.lock sshd.pid sshd.state sshd.log; do
    [ ! -L "$f" ] || fail "Refusing symlink: $f"
done
command -v flock >/dev/null 2>&1 || fail 'BusyBox flock is required'
exec 9>service.lock
flock -x 9

# Validate executable, cwd, uid and argv before signalling a PID. A saved
# start time additionally detects PID reuse for services started here.
identity() {
    pid=$1
    case "$pid" in ''|*[!0-9]*|0|1) return 1 ;; esac
    [ -r "/proc/$pid/stat" ] || return 1
    [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = "$BASE/dropbearmulti" ] || return 1
    [ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" = "$BASE" ] || return 1
    [ "$(awk '/^Uid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)" = 0 ] || return 1
    [ "$(tr '\000' '\n' < "/proc/$pid/cmdline" | sed -n '2p')" = dropbear ] || return 1
    # /proc stat comm may contain spaces; remove everything through the last ).
    started=$(sed 's/.*) //' "/proc/$pid/stat" | awk '{print $20}')
    [ -n "$started" ] || return 1
    if [ -f sshd.state ]; then
        [ "$(cat sshd.state)" = "$pid $started" ] || return 1
    fi
}
current() {
    [ -f sshd.pid ] || return 1
    identity "$(cat sshd.pid)"
}
stop_service() {
    if ! current; then
        echo 'Not running (missing, stale, or unrelated PID); no process signalled.'
        rm -f sshd.pid sshd.state
        return 0
    fi
    target=$pid
    kill "$target"
    n=0
    while identity "$target"; do
        n=$((n + 1))
        [ "$n" -lt 10 ] || fail 'Server did not stop; refusing to force-kill'
        sleep 1
    done
    rm -f sshd.pid sshd.state
    echo 'Stopped listener. Existing SSH sessions may remain until they exit.'
    # Do not unmount devpts: it is shared with other terminal users.
}
start_service() {
    if current; then echo "Already running (PID $pid)"; return 0; fi
    rm -f sshd.pid sshd.state
    for f in dropbearmulti authorized_keys host_ed25519; do
        [ -f "$f" ] && [ -s "$f" ] && [ ! -L "$f" ] || fail "Missing or symlinked $f"
        [ "$(stat -c %u "$f")" = 0 ] || fail "$f must be owned by root"
    done
    chmod 700 dropbearmulti
    chmod 600 authorized_keys host_ed25519
    if ! awk '$2=="/dev/pts" && $3=="devpts" {ok=1} END {exit !ok}' /proc/mounts; then
        if ! mount -t devpts devpts /dev/pts -o mode=0600; then
            echo 'WARNING: devpts unavailable; connect with ssh -T.' >&2
        fi
    fi
    # Close lock descriptor in the daemon; retaining it would block stop/status.
    nohup sh -c 'cd "$1"; exec ./dropbearmulti dropbear -F -D . -r ./host_ed25519 -p 192.168.1.1:2222 -P ./sshd.pid -j -k -m -K 60 -I 900' sh "$BASE" 9>&- >sshd.log 2>&1 < /dev/null &
    child=$!
    n=0
    while [ "$n" -lt 10 ]; do
        if ! kill -0 "$child" 2>/dev/null; then
            cat sshd.log >&2
            fail 'SSH startup failed; see sshd.log'
        fi
        if current && [ "$pid" = "$child" ]; then
            printf '%s %s\n' "$pid" "$started" >sshd.state
            echo "Running (PID $pid), root@192.168.1.1:2222"
            return 0
        fi
        sleep 1
        n=$((n + 1))
    done
    # Child was launched by this shell; do not use an unverified PID file.
    kill "$child" 2>/dev/null || :
    fail 'SSH startup timed out; see sshd.log'
}
case "${1:-status}" in
    start) start_service ;;
    stop) stop_service ;;
    restart) stop_service; start_service ;;
    status)
        if current; then echo "Running (PID $pid), root@192.168.1.1:2222";
        else echo 'Not running (missing, stale, or unrelated PID)'; exit 3; fi ;;
    *) fail 'Usage: service.sh {start|stop|status|restart}' ;;
esac
