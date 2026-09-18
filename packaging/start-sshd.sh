#!/bin/sh
# Run in the foreground. Use nohup externally for background operation.
set -eu
umask 077
cd -- "$(dirname -- "$0")"
if [ "$(id -u)" = 0 ]; then
    echo 'This launcher is intended for the existing non-root csp account.' >&2
    exit 1
fi
if [ "$(stat -c %u .)" != "$(id -u)" ] || [ "$(stat -c %a .)" != 700 ]; then
    echo 'The installation directory must be owned by you and have mode 700.' >&2
    exit 1
fi
for f in authorized_keys host_ed25519; do
    if [ ! -s "$f" ] || [ -L "$f" ]; then
        echo "Missing, empty, or symlinked $f; follow INSTALL-zh.md first." >&2
        exit 1
    fi
    if [ "$(stat -c %u "$f")" != "$(id -u)" ] || [ "$(stat -c %a "$f")" != 600 ]; then
        echo "$f must be owned by you and have mode 600." >&2
        exit 1
    fi
done
# -F preserves cwd; -D . is intentional for csp whose passwd home is /.
# A high port avoids requiring root. Only the management IPv4 is bound.
exec ./dropbearmulti dropbear -F -D . -r ./host_ed25519 \
    -p 192.168.1.1:2222 -P ./sshd.pid -j -k -m -K 60 -I 900
