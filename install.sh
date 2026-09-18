#!/bin/sh
# BusyBox/POSIX sh installer. Keep execution in main so truncated downloads
# cannot execute a partially received installer function body.
main() {
    set -eu
    umask 077
    version=v0.1.0
    archive_sha=51c45cdbb184a8553540efb7fbf229b1c50821f0cd06c0db24e52d2b991e640c
    url="https://github.com/eeelin/zn-m180g-tools/releases/download/$version/zn-m180g-ssh.tar.gz"
    install_dir=/usr/data/sshd-csp
    key=
    archive=
    no_start=0
    stage=
    fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
    cleanup() {
        if [ -n "$stage" ]; then rm -rf -- "$stage"; fi
    }
    run_dropbear() { "$install_dir/dropbearmulti" "$@"; }
    usage() {
        cat <<'EOF'
Usage: sh install.sh --key 'ssh-ed25519 AAAA... comment' [options]
       sh install.sh --key-file /path/to/client.pub [options]
Options:
  --dir /absolute/path  Installation directory (default /usr/data/sshd-csp)
  --archive /path       Use a previously downloaded release archive
  --no-start            Install and generate host key without starting SSH
  -h, --help            Show help
Existing installations are never overwritten. Only Ed25519 login keys are
accepted. SSH keeps the installing user's permissions; no root or autostart.
EOF
    }
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --key|--key-file|--dir|--archive)
                [ "$#" -ge 2 ] || fail "Missing value for $1"
                case "$1" in
                    --key) [ -z "$key" ] || fail 'Specify only one public key'; key=$2 ;;
                    --key-file) [ -z "$key" ] || fail 'Specify only one public key'; key=$(cat "$2") || fail 'Cannot read public key' ;;
                    --dir) install_dir=$2 ;;
                    --archive) archive=$2 ;;
                esac
                shift 2 ;;
            --no-start) no_start=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) fail "Unknown argument: $1" ;;
        esac
    done
    [ -n "$key" ] || { usage >&2; fail 'Provide your SSH public key, never the private key'; }
    for cmd in id uname awk base64 od tr wc mkdir chmod cp rm tar sha256sum stat dirname; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
    done
    [ "$(id -u)" != 0 ] || fail 'Run as the existing non-root csp user, not root'
    [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = armv7l ] || fail 'Requires Linux ARMv7 little-endian (armv7l)'
    case "$install_dir" in
        /*) ;;
        *) fail '--dir must be an absolute path' ;;
    esac
    case "$install_dir/" in
        *'/../'*|*'/./'*|*'//'*) fail '--dir must not contain .., ., or empty path components' ;;
    esac
    [ ! -e "$install_dir" ] && [ ! -L "$install_dir" ] || fail "Installation already exists: $install_dir; nothing changed"
    # Reject private keys, multi-line input and unsupported key types.
    printf '%s\n' "$key" | awk 'NR == 1 && $1 == "ssh-ed25519" && NF >= 2 {ok=1} END {exit !(ok && NR == 1)}' || fail 'Expected one ssh-ed25519 public key line'
    key_blob=$(printf '%s\n' "$key" | awk '{print $2}')
    [ "${#key_blob}" = 68 ] || fail 'Invalid Ed25519 public key length'
    case "$key_blob" in *[!A-Za-z0-9+/]*) fail 'Invalid public key base64' ;; esac
    parent=$(dirname -- "$install_dir")
    [ -d "$parent" ] && [ -w "$parent" ] || fail "Parent directory is not writable: $parent"
    stage_candidate="$parent/.zn-m180g-install.$$"
    mkdir "$stage_candidate" || fail 'Cannot reserve temporary directory'
    stage=$stage_candidate
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    printf '%s' "$key_blob" | base64 -d > "$stage/key.blob" || fail 'Invalid public key encoding'
    [ "$(wc -c < "$stage/key.blob" | tr -d ' ')" = 51 ] || fail 'Invalid Ed25519 key data'
    header=$(od -An -tx1 -N19 "$stage/key.blob" | tr -d ' \n')
    [ "$header" = 0000000b7373682d6564323535313900000020 ] || fail 'Invalid Ed25519 key structure'
    printf 'Installing Dropbear from %s into %s\n' "$version" "$install_dir"
    if [ -n "$archive" ]; then
        cp "$archive" "$stage/package.tar.gz" || fail 'Cannot read local archive'
    elif command -v curl >/dev/null 2>&1; then
        curl --fail --location --connect-timeout 15 --max-time 180 "$url" -o "$stage/package.tar.gz" || fail 'HTTPS download failed; use --archive with a manually downloaded package'
    elif command -v wget >/dev/null 2>&1; then
        wget -T 60 -O "$stage/package.tar.gz" "$url" || fail 'HTTPS download failed; use --archive with a manually downloaded package'
    else
        fail 'Need curl or wget, or use --archive'
    fi
    actual=$(sha256sum "$stage/package.tar.gz" | awk '{print $1}')
    [ "$actual" = "$archive_sha" ] || fail 'Archive SHA256 mismatch; refusing to install'
    mkdir "$stage/payload"
    tar -xzf "$stage/package.tar.gz" -C "$stage/payload"
    (cd "$stage/payload" && sha256sum -c SHA256SUMS) || fail 'Package contents failed checksum validation'
    # mkdir is exclusive: a second installer cannot overwrite existing keys.
    mkdir "$install_dir" || fail 'Cannot create installation directory (possibly already exists)'
    chmod 700 "$install_dir"
    cp -R "$stage/payload/." "$install_dir/"
    chmod 700 "$install_dir/dropbearmulti" "$install_dir/start-sshd.sh"
    printf '%s\n' "$key" > "$install_dir/authorized_keys"
    chmod 600 "$install_dir/authorized_keys"
    run_dropbear dropbear -V || fail "Binary cannot run; files kept in $install_dir for inspection"
    run_dropbear dropbearkey -t ed25519 -f "$install_dir/host_ed25519" || fail 'Host key generation failed; installation kept for inspection'
    chmod 600 "$install_dir/host_ed25519"
    printf '%s\n' "$version" > "$install_dir/installed-release"
    if [ "$no_start" = 1 ]; then
        printf 'Installed without starting. Start with: sh "%s/start-sshd.sh"\n' "$install_dir"
        exit 0
    fi
    command -v nohup >/dev/null 2>&1 || fail 'nohup is unavailable; start start-sshd.sh manually'
    nohup sh "$install_dir/start-sshd.sh" > "$install_dir/sshd.log" 2>&1 < /dev/null &
    child=$!
    # Check both the launched process and Dropbear's post-bind PID file.
    count=0
    while [ "$count" -lt 10 ]; do
        if ! kill -0 "$child" 2>/dev/null; then
            cat "$install_dir/sshd.log" >&2
            fail 'SSH startup failed; installation and log kept for inspection'
        fi
        if [ -f "$install_dir/sshd.pid" ] && [ "$(cat "$install_dir/sshd.pid")" = "$child" ]; then
            printf 'SSH started (PID %s). Verify the host fingerprint printed above.\n' "$child"
            printf 'Connect: ssh -T -p 2222 -i /path/to/private_key %s@192.168.1.1\n' "$(id -un)"
            printf 'No boot autostart configured. Logs: %s/sshd.log\n' "$install_dir"
            exit 0
        fi
        sleep 1
        count=$((count + 1))
    done
    # Only signal the process launched by this invocation, never a stale PID.
    kill "$child" 2>/dev/null || :
    fail "Startup timed out; check $install_dir/sshd.log"
}
main "$@"
