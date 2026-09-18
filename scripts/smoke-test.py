#!/usr/bin/env python3
"""Exercise the ARM server via qemu-user without contacting the router."""
import os
from pathlib import Path
import pwd
import shutil
import socket
import subprocess as sp
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
qemu = os.environ.get('QEMU_ARM', 'qemu-arm-static')
binary = str(ROOT / 'dist/zn-m180g-ssh/dropbearmulti')
assert os.getuid() != 0, 'Run as a normal user to test the non-root deployment'
results = []
with tempfile.TemporaryDirectory(prefix='zn-m180g-test-') as tmp:
    d = Path(tmp)
    def run(args, **kw):
        return sp.run(args, cwd=d, check=True, capture_output=True, text=True, **kw)
    arm = [qemu, '-cpu', 'cortex-a9', binary]
    run(arm + ['dropbear', '-V'])
    run(arm + ['dropbearkey', '-t', 'ed25519', '-f', 'hostkey'])
    for key in ['client', 'wrong']:
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', key])
    shutil.copyfile(d / 'client.pub', d / 'authorized_keys')
    (d / 'authorized_keys').chmod(0o600)
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    with (d / 'server.log').open('w+') as log:
        server = sp.Popen(arm + ['dropbear', '-F', '-D', '.', '-r', 'hostkey',
                                '-p', f'127.0.0.1:{port}', '-P', 'server.pid', '-j', '-k'],
                          cwd=d, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('Server exited: ' + (d / 'server.log').read_text())
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise RuntimeError('Server did not listen')
            user = pwd.getpwuid(os.getuid()).pw_name
            base = ['ssh', '-T', '-p', str(port), '-o', 'BatchMode=yes',
                    '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=accept-new',
                    '-o', f'UserKnownHostsFile={d}/known_hosts', '-o', 'ConnectTimeout=5']
            for label, key, login, expected in [
                ('public key and command', 'client', user, 0),
                ('wrong key rejected', 'wrong', user, 255),
                ('wrong user rejected', 'client', 'root', 255),
                ('writable auth directory rejected', 'client', user, 255),
            ]:
                if label.startswith('writable'):
                    d.chmod(0o777)
                r = sp.run(base + ['-i', str(d / key), f'{login}@127.0.0.1',
                                   'printf SSH_TEST_OK'], capture_output=True, text=True, timeout=15)
                d.chmod(0o700)
                assert r.returncode == expected, (label, r.returncode, r.stderr)
                if expected == 0:
                    assert r.stdout == 'SSH_TEST_OK', r.stdout
                results.append(label + ': PASS')
        finally:
            d.chmod(0o700)
            server.terminate()
            server.wait(timeout=10)
report = '\n'.join(results) + '\nQEMU user-mode only; no device runtime validation.\n'
print(report, end='')
(ROOT / 'dist/SMOKE-TEST.txt').write_text(report)
