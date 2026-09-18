#!/usr/bin/env python3
"""Test installer on a desktop: ARM execution via QEMU, bind to loopback.

Only architecture detection, ARM invocation and the startup launcher are
adapted in a temporary copy. Downloads, checksums, extraction, key generation,
permissions, refusal paths and startup checks use the real installer logic.
"""
import os
from pathlib import Path
import pwd
import shlex
import shutil
import signal
import socket
import subprocess as sp
import tempfile

ROOT = Path(__file__).resolve().parents[1]
QEMU = shutil.which(os.environ.get('QEMU_ARM', 'qemu-arm-static'))
assert QEMU, 'Set QEMU_ARM or install qemu-arm-static'
assert os.getuid() != 0, 'Run tests as a non-root user'
archive = ROOT / 'dist/zn-m180g-ssh.tar.gz'
assert archive.exists(), 'Download the pinned v0.1.0 release into dist/ first'
SHELL = shlex.split(os.environ.get('INSTALLER_SHELL', 'sh'))
results = []
with tempfile.TemporaryDirectory(prefix='zn-installer-test-') as tmp:
    tmp = Path(tmp)
    sp.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(tmp/'client')], check=True)
    key = (tmp/'client.pub').read_text().strip()
    src = (ROOT/'install.sh').read_text()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    src = src.replace('"$(uname -m)" = armv7l', '"$(uname -m)" = "$(uname -m)"')
    src = src.replace('run_dropbear() { "$install_dir/dropbearmulti" "$@"; }',
                      f'run_dropbear() {{ {shlex.quote(QEMU)} -cpu cortex-a9 "$install_dir/dropbearmulti" "$@"; }}')
    original = 'nohup sh "$install_dir/start-sshd.sh" > "$install_dir/sshd.log" 2>&1 < /dev/null &'
    replacement = f'''(cd "$install_dir" && exec nohup {shlex.quote(QEMU)} -cpu cortex-a9 ./dropbearmulti dropbear -F -D . -r ./host_ed25519 -p 127.0.0.1:{port} -P ./sshd.pid -j -k) > "$install_dir/sshd.log" 2>&1 < /dev/null &'''
    assert original in src
    src = src.replace(original, replacement)
    script = tmp/'install-test.sh'
    script.write_text(src)
    def install(name, extra=(), good=True, public_key=key, package=archive):
        path = tmp/name
        r = sp.run(SHELL + [str(script), '--dir', str(path), '--key', public_key,
                    '--archive', str(package), *extra], capture_output=True, text=True, timeout=30)
        assert (r.returncode == 0) == good, (name, r.returncode, r.stdout, r.stderr)
        return path, r
    path, _ = install('offline', ['--no-start'])
    assert path.stat().st_mode & 0o777 == 0o700
    for f in ['host_ed25519', 'authorized_keys']:
        assert (path/f).stat().st_mode & 0o777 == 0o600
    before = (path/'host_ed25519').read_bytes()
    results.append('verified offline installation and host key generation: PASS')
    _, r = install('offline', ['--no-start'], good=False)
    assert 'already exists' in r.stderr and (path/'host_ed25519').read_bytes() == before
    results.append('existing installation and host key preserved: PASS')
    corrupt = tmp/'bad.tar.gz'; corrupt.write_bytes(b'not the release')
    path, r = install('corrupt', good=False, package=corrupt)
    assert 'SHA256 mismatch' in r.stderr and not path.exists()
    results.append('corrupted archive rejected before installation: PASS')
    path, r = install('bad-key', good=False, public_key='ssh-ed25519 invalid')
    assert not path.exists()
    path, r = install('multiline', good=False, public_key=key+'\n'+key)
    assert not path.exists()
    results.append('invalid and multiline keys rejected: PASS')
    link = tmp/'symlink'; link.symlink_to(tmp/'offline', target_is_directory=True)
    install('symlink', good=False)
    assert (tmp/'offline/host_ed25519').read_bytes() == before
    results.append('symlink destination rejected: PASS')
    path, r = install('running')
    pid = int((path/'sshd.pid').read_text())
    try:
        login = pwd.getpwuid(os.getuid()).pw_name
        ssh = sp.run(['ssh', '-T', '-p', str(port), '-i', str(tmp/'client'),
                      '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
                      '-o', 'StrictHostKeyChecking=accept-new', '-o', f'UserKnownHostsFile={tmp}/known_hosts',
                      f'{login}@127.0.0.1', 'printf INSTALLER_SSH_OK'], capture_output=True, text=True, timeout=10)
        assert ssh.returncode == 0 and ssh.stdout == 'INSTALLER_SSH_OK', ssh.stderr
        results.append('installer starts server; public-key SSH command succeeds: PASS')
        path, r = install('port-conflict', good=False)
        assert 'startup failed' in r.stderr.lower(), (r.stdout, r.stderr)
        assert (path/'host_ed25519').exists() and (path/'sshd.log').exists()
        results.append('occupied port reported; keys and log retained: PASS')
    finally:
        os.kill(pid, signal.SIGTERM)
    assert not list(tmp.glob('.zn-m180g-install.*')), 'Temporary directories leaked'
print('\n'.join(results))
