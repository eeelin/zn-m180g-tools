#!/usr/bin/env python3
"""Package the compiled server and a rebuildable source archive."""
import hashlib
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist'
PKG = OUT / 'zn-m180g-ssh'
assert (PKG / 'dropbearmulti').is_file(), 'Run scripts/build.sh first'
for p in (ROOT / 'licenses').glob('LICENSE.*'):
    shutil.copy2(p, PKG / p.name)
shutil.copy2(ROOT / 'packaging/start-sshd.sh', PKG / 'start-sshd.sh')
shutil.copy2(ROOT / 'docs/INSTALL-zh.md', PKG / 'INSTALL-zh.md')
shutil.copy2(ROOT / 'docs/VALIDATION-original.txt', PKG / 'VALIDATION-original.txt')
(PKG / 'start-sshd.sh').chmod(0o755)
# Explicit allowlist prevents accidental packaging of runtime keys or logs.
names = ['dropbearmulti', 'ELF-info.txt', 'localoptions.h', 'start-sshd.sh',
         'INSTALL-zh.md', 'VALIDATION-original.txt']
names += [p.name for p in sorted((ROOT / 'licenses').glob('LICENSE.*'))]
(PKG / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.sha256((PKG / n).read_bytes()).hexdigest()}  {n}\n' for n in names))
with tarfile.open(OUT / 'zn-m180g-ssh.tar.gz', 'w:gz') as tar:
    for n in names + ['SHA256SUMS']:
        tar.add(PKG / n, arcname=n)
with tarfile.open(OUT / 'zn-m180g-ssh-source.tar.gz', 'w:gz') as tar:
    for n in ['README.md', 'sources.sha256', 'scripts', 'config', 'docs',
              'packaging', 'licenses', 'downloads/dropbear-2026.94.tar.bz2']:
        tar.add(ROOT / n, arcname=n, filter=lambda i: None if '__pycache__' in i.name else i)
for n in ['zn-m180g-ssh.tar.gz', 'zn-m180g-ssh-source.tar.gz']:
    p = OUT / n
    (OUT / (n + '.sha256')).write_text(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {n}\n')
    print(f'{n}: {p.stat().st_size} bytes')
