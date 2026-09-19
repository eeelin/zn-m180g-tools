#!/usr/bin/env python3
"""Root installer/control tests in an unprivileged user namespace.

The temporary test copy adapts only CPU detection, QEMU invocation/identity,
and the listen address. No device is contacted; no host mount is changed.
QEMU cannot initgroups in this namespace; authentication is tested separately
by smoke-test.py under the normal host user.
"""
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import signal
import socket
import subprocess as sp
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
QEMU = shutil.which(os.environ.get('QEMU_ARM', 'qemu-arm-static'))
assert QEMU, 'Set QEMU_ARM or install qemu-arm-static'
if os.getuid() != 0:
    os.execvp('unshare', ['unshare', '-Ur', sys.executable, str(Path(__file__).resolve())])
SHELL = shlex.split(os.environ.get('INSTALLER_SHELL', 'sh'))
archive = ROOT / 'dist/zn-m180g-ssh.tar.gz'
results = []
children = set()
with tempfile.TemporaryDirectory(prefix='zn-root-test-') as tmp:
    tmp = Path(tmp)
    sp.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(tmp/'client')], check=True)
    key = (tmp/'client.pub').read_text().strip()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    adapter = tmp/'adapt.py'
    adapter.write_text('''from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('"$BASE/dropbearmulti"', %r)
s=s.replace("sed -n '2p'", "sed -n '5p'")
s=s.replace('exec ./dropbearmulti dropbear', %r)
s=s.replace('192.168.1.1:2222', %r)
p.write_text(s)
''' % (shlex.quote(QEMU), 'exec '+shlex.quote(QEMU)+' -cpu cortex-a9 ./dropbearmulti dropbear', f'127.0.0.1:{port}'))
    src=(ROOT/'dist/install.sh').read_text()
    src=src.replace('"$(uname -m)" = armv7l', '"$(uname -m)" = "$(uname -m)"')
    src=src.replace('run_dropbear() { "$install_dir/dropbearmulti" "$@"; }',
                    f'run_dropbear() {{ {shlex.quote(QEMU)} -cpu cortex-a9 "$install_dir/dropbearmulti" "$@"; }}')
    anchor="    if [ \"$upgrade\" = 1 ]; then\n        # Use the newly verified controller"
    assert anchor in src
    src=src.replace(anchor, f'    python3 {shlex.quote(str(adapter))} "$stage/payload/service.sh"\n'+anchor)
    script=tmp/'install.sh'; script.write_text(src)
    def install(name, args=(), good=True, public_key=key, package=archive):
        dest=tmp/name
        cmd=SHELL+[str(script), '--dir', str(dest), '--archive', str(package), *args]
        if public_key is not None: cmd+=['--key', public_key]
        r=sp.run(cmd,capture_output=True,text=True,timeout=30)
        assert (r.returncode==0)==good,(name,r.returncode,r.stdout,r.stderr)
        return dest,r
    def control(dest, action, expected=0):
        r=sp.run(SHELL+[str(dest/f'{action}.sh')],capture_output=True,text=True,timeout=20)
        assert r.returncode==expected,(action,r.returncode,r.stdout,r.stderr)
        return r
    def pid(dest): return int((dest/'sshd.pid').read_text())
    try:
        dest,_=install('root',['--no-start'])
        assert dest.stat().st_uid==0 and dest.stat().st_mode&0o777==0o700
        before={f:(dest/f).read_bytes() for f in ['authorized_keys','host_ed25519']}
        for f in before: assert (dest/f).stat().st_mode&0o777==0o600
        results.append('root offline install, ownership, key generation: PASS')
        install('root',good=False)
        bad=tmp/'bad.tar.gz';bad.write_bytes(b'corrupted')
        d,r=install('bad-archive',good=False,package=bad)
        assert 'SHA256 mismatch' in r.stderr and not d.exists()
        for name,k in [('invalid','ssh-ed25519 bad'),('multiline',key+'\n'+key)]:
            d,_=install(name,good=False,public_key=k);assert not d.exists()
        link=tmp/'link';link.symlink_to(dest)
        install('link',good=False)
        results.append('corrupt archive, invalid keys, symlinks and repeated install rejected: PASS')
        control(dest,'status',3)
        dest.chmod(0o775); (dest/'authorized_keys').chmod(0o666)
        control(dest,'start'); p=pid(dest);children.add(p)
        assert dest.stat().st_mode&0o777==0o700 and (dest/'authorized_keys').stat().st_mode&0o777==0o600
        control(dest,'status');control(dest,'start');assert pid(dest)==p
        # Exercise the lock while two clients request a start.
        procs=[sp.Popen(SHELL+[str(dest/'start.sh')],stdout=sp.PIPE,stderr=sp.PIPE) for _ in range(2)]
        for proc in procs:
            out,err=proc.communicate(timeout=10);assert proc.returncode==0,(out,err)
        assert pid(dest)==p
        results.append('start, status, permissions repair, repeated/concurrent start: PASS')
        d,r=install('conflict',good=False)
        assert 'startup failed' in r.stderr.lower() and (d/'sshd.log').exists()
        results.append('port conflict reported with retained logs: PASS')
        control(dest,'restart'); new=pid(dest);children.add(new);assert new!=p
        # An incorrect saved starttime must not cause a signal to the daemon.
        state=(dest/'sshd.state').read_text();(dest/'sshd.state').write_text(f'{new} 1\n')
        control(dest,'status',3);control(dest,'stop');os.kill(new,0)
        (dest/'sshd.pid').write_text(f'{new}\n');(dest/'sshd.state').write_text(state)
        control(dest,'stop');control(dest,'status',3);control(dest,'stop')
        results.append('restart, stop, idempotent stop and PID reuse protection: PASS')
        other=sp.Popen(['sleep','60'],cwd=dest)
        try:
            (dest/'sshd.pid').write_text(f'{other.pid}\n')
            control(dest,'status',3);control(dest,'stop');assert other.poll() is None
        finally: other.terminate();other.wait()
        results.append('unrelated process referenced by PID file not signalled: PASS')
        control(dest,'start');children.add(pid(dest))
        # Simulate the previous manual root deployment with no state file.
        (dest/'sshd.state').unlink()
        install('root',['--upgrade','--no-start'],public_key=None)
        control(dest,'status',3)
        for f,b in before.items(): assert (dest/f).read_bytes()==b
        install('root',['--upgrade'],public_key=None);children.add(pid(dest))
        control(dest,'status');control(dest,'stop')
        results.append('manual-root migration and upgrade preserve both keys; optional automatic start: PASS')
        assert not list(tmp.glob('.zn-m180g-install.*'))
    finally:
        for p in children:
            try: os.kill(p,signal.SIGTERM)
            except ProcessLookupError: pass
report='\n'.join(results)+'\nRoot checks use user namespace; QEMU/loopback adaptations; no device execution.\n'
print(report,end='')
(ROOT/'dist/INSTALLER-TEST.txt').write_text(report)
