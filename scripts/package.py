#!/usr/bin/env python3
"""Create deterministic root-owned packages and pin the standalone installer."""
import gzip
import hashlib
from pathlib import Path
import re
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist'
PKG = OUT / 'zn-m180g-ssh'
assert (PKG / 'dropbearmulti').is_file(), 'Run scripts/build.sh first'
version = (ROOT / 'VERSION').read_text().strip()
for p in (ROOT / 'licenses').glob('LICENSE.*'):
    shutil.copy2(p, PKG / p.name)
for p in (ROOT / 'packaging').glob('*.sh'):
    shutil.copy2(p, PKG / p.name)
for name in ['INSTALL-zh.md', 'VALIDATION-original.txt']:
    shutil.copy2(ROOT / 'docs' / name, PKG / name)
names = ['dropbearmulti', 'ELF-info.txt', 'localoptions.h', 'INSTALL-zh.md', 'VALIDATION-original.txt']
names += [p.name for p in sorted((ROOT / 'packaging').glob('*.sh'))]
names += [p.name for p in sorted((ROOT / 'licenses').glob('LICENSE.*'))]
(PKG / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.sha256((PKG / n).read_bytes()).hexdigest()}  {n}\n' for n in names))

def normalize(info):
    if '__pycache__' in info.name or info.name.endswith('.pyc'):
        return None
    info.uid = info.gid = 0
    info.uname = info.gname = 'root'
    info.mtime = 0
    info.mode = 0o755 if info.isdir() or info.name.endswith('.sh') or info.name == 'dropbearmulti' else 0o644
    return info

def pack(dest, files):
    with dest.open('wb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.GNU_FORMAT) as tar:
            for path, name in files:
                tar.add(path, arcname=name, filter=normalize)

pack(OUT / 'zn-m180g-ssh.tar.gz', [(PKG/n, n) for n in names + ['SHA256SUMS']])
archive_sha = hashlib.sha256((OUT/'zn-m180g-ssh.tar.gz').read_bytes()).hexdigest()
installer = (ROOT/'install.sh').read_text()
installer = re.sub(r'^    version=.*$', f'    version={version}', installer, flags=re.M)
installer = re.sub(r'^    archive_sha=.*$', f'    archive_sha={archive_sha}', installer, flags=re.M)
(OUT/'install.sh').write_text(installer)
source_names = ['README.md', 'VERSION', 'sources.sha256', 'scripts', 'config', 'docs',
                'packaging', 'licenses', 'downloads/dropbear-2026.94.tar.bz2']
pack(OUT/'zn-m180g-ssh-source.tar.gz', [(ROOT/n, n) for n in source_names] + [(OUT/'install.sh', 'install.sh')])
for n in ['zn-m180g-ssh.tar.gz', 'zn-m180g-ssh-source.tar.gz', 'install.sh']:
    p = OUT / n
    (OUT / (n + '.sha256')).write_text(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {n}\n')
    print(f'{n}: {p.stat().st_size} bytes')
