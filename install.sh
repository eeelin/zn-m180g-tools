#!/bin/sh
# BusyBox/POSIX sh installer. Keep execution in main so truncated downloads
# cannot execute a partially received installer function body.
main() {
    set -eu
    umask 077
    version=v0.2.0
    archive_sha=43cb5568952b7f16c0bb0bd0d87f513ba642ea3553f9a0bf6725e8a4fb8bc22f
    url="https://github.com/eeelin/zn-m180g-tools/releases/download/$version/zn-m180g-ssh.tar.gz"
    install_dir=/usr/data/sshd-root
    key=
    archive=
    no_start=0
    upgrade=0
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
  --dir /absolute/path  Installation directory (default /usr/data/sshd-root)
  --archive /path       Use a previously downloaded release archive
  --no-start            Install without starting SSH
  --upgrade             Update existing root installation, preserving both keys
  -h, --help            Show help
Fresh installs require an Ed25519 public key. Upgrades preserve existing keys.
Run as root. No boot autostart is configured.
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
            --upgrade) upgrade=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) fail "Unknown argument: $1" ;;
        esac
    done
    if [ "$upgrade" = 0 ]; then
        [ -n "$key" ] || { usage >&2; fail 'Provide your SSH public key, never the private key'; }
    else
        [ -z "$key" ] || fail '--upgrade preserves keys; do not pass --key or --key-file'
    fi
    for cmd in id uname awk base64 od tr wc mkdir chmod cp rm tar sha256sum stat dirname cat mv; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
    done
    [ "$(id -u)" = 0 ] || fail 'Run this installer as root'
    [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = armv7l ] || fail 'Requires Linux ARMv7 little-endian (armv7l)'
    case "$install_dir" in
        /*) ;;
        *) fail '--dir must be an absolute path' ;;
    esac
    case "$install_dir/" in
        *'/../'*|*'/./'*|*'//'*) fail '--dir must not contain .., ., or empty path components' ;;
    esac
    if [ "$upgrade" = 1 ]; then
        [ -d "$install_dir" ] && [ ! -L "$install_dir" ] || fail 'Upgrade requires an existing directory'
        [ "$(stat -c %u "$install_dir")" = 0 ] || fail 'Upgrade directory must be owned by root'
        for f in authorized_keys host_ed25519; do
            [ -f "$install_dir/$f" ] && [ -s "$install_dir/$f" ] && [ ! -L "$install_dir/$f" ] || fail "Missing or symlinked $f"
            [ "$(stat -c %u "$install_dir/$f")" = 0 ] || fail "$f must be owned by root"
        done
    else
        [ ! -e "$install_dir" ] && [ ! -L "$install_dir" ] || fail "Installation already exists: $install_dir; use --upgrade"
        printf '%s\n' "$key" | awk 'NR == 1 && $1 == "ssh-ed25519" && NF >= 2 {ok=1} END {exit !(ok && NR == 1)}' || fail 'Expected one ssh-ed25519 public key line'
        key_blob=$(printf '%s\n' "$key" | awk '{print $2}')
        [ "${#key_blob}" = 68 ] || fail 'Invalid Ed25519 public key length'
        case "$key_blob" in *[!A-Za-z0-9+/]*) fail 'Invalid public key base64' ;; esac
    fi
    parent=$(dirname -- "$install_dir")
    [ -d "$parent" ] && [ -w "$parent" ] || fail "Parent directory is not writable: $parent"
    stage_candidate="$parent/.zn-m180g-install.$$"
    mkdir "$stage_candidate" || fail 'Cannot reserve temporary directory'
    stage=$stage_candidate
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    if [ "$upgrade" = 0 ]; then
        printf '%s' "$key_blob" | base64 -d > "$stage/key.blob" || fail 'Invalid public key encoding'
        [ "$(wc -c < "$stage/key.blob" | tr -d ' ')" = 51 ] || fail 'Invalid Ed25519 key data'
        header=$(od -An -tx1 -N19 "$stage/key.blob" | tr -d ' \n')
        [ "$header" = 0000000b7373682d6564323535313900000020 ] || fail 'Invalid Ed25519 key structure'
    fi
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
    if [ "$upgrade" = 1 ]; then
        # Use the newly verified controller to stop even the old manual root setup.
        SSHD_DIR="$install_dir" sh "$stage/payload/service.sh" stop
    else
        mkdir "$install_dir" || fail 'Cannot create installation directory'
    fi
    chmod 700 "$install_dir"
    # Atomically replace individual program files; never copy over key files.
    # Rename supports upgrading a binary still held open by an older SSH session.
    for source in "$stage/payload/"*; do
        name=${source##*/}
        case "$name" in authorized_keys|host_ed25519|sshd.pid|sshd.state|sshd.log|service.lock) fail 'Unexpected runtime file in package' ;; esac
        [ -f "$source" ] && [ ! -L "$source" ] || fail 'Unexpected non-regular package file'
        temp="$install_dir/.new-$name-$$"
        [ ! -e "$temp" ] && [ ! -L "$temp" ] || fail 'Temporary target already exists'
        (set -C; cat "$source" > "$temp")
        case "$name" in *.sh|dropbearmulti) chmod 700 "$temp" ;; *) chmod 600 "$temp" ;; esac
        mv -f "$temp" "$install_dir/$name"
    done
    if [ "$upgrade" = 0 ]; then
        printf '%s\n' "$key" > "$install_dir/authorized_keys"
        chmod 600 "$install_dir/authorized_keys"
    fi
    run_dropbear dropbear -V || fail "Binary cannot run; files kept in $install_dir for inspection"
    if [ "$upgrade" = 0 ]; then
        run_dropbear dropbearkey -t ed25519 -f "$install_dir/host_ed25519" || fail 'Host key generation failed; installation kept for inspection'
    else
        run_dropbear dropbearkey -y -f "$install_dir/host_ed25519"
    fi
    chmod 600 "$install_dir/authorized_keys" "$install_dir/host_ed25519"
    printf '%s\n' "$version" > "$install_dir/installed-release"
    if [ "$no_start" = 1 ]; then
        printf 'Installed without starting. Start with: sh "%s/start.sh"\n' "$install_dir"
        exit 0
    fi
    sh "$install_dir/start.sh"
    printf 'Connect: ssh -p 2222 -i /path/to/private_key root@192.168.1.1\n'
    printf 'No boot autostart configured. Logs: %s/sshd.log\n' "$install_dir"
}
main "$@"
