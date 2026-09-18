#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TC="$ROOT/build/armv5-eabi--musl--stable-2025.08-1"
SRC="$ROOT/build/dropbear-2026.94"
OUT="$ROOT/dist/zn-m180g-ssh"
export PATH="$TC/bin:$PATH"
for cmd in curl sha256sum tar make python3; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done
[ "$(uname -sm)" = 'Linux x86_64' ] || { echo 'Requires Linux x86_64' >&2; exit 1; }
mkdir -p "$ROOT/downloads" "$ROOT/build" "$OUT"
fetch() {
  file=$1 url=$2
  if [ ! -f "$ROOT/downloads/$file" ]; then
    curl --fail --location --retry 3 "$url" -o "$ROOT/downloads/$file.part"
    mv "$ROOT/downloads/$file.part" "$ROOT/downloads/$file"
  fi
}
fetch dropbear-2026.94.tar.bz2 https://matt.ucc.asn.au/dropbear/releases/dropbear-2026.94.tar.bz2
fetch armv5-eabi--musl--stable-2025.08-1.tar.xz https://toolchains.bootlin.com/downloads/releases/toolchains/armv5-eabi/tarballs/armv5-eabi--musl--stable-2025.08-1.tar.xz
(cd "$ROOT/downloads" && sha256sum -c "$ROOT/sources.sha256")
if [ ! -d "$TC" ]; then tar -xJf "$ROOT/downloads/armv5-eabi--musl--stable-2025.08-1.tar.xz" -C "$ROOT/build"; fi
# Always use a fresh upstream tree; avoid stale objects after config changes.
if [ -d "$SRC" ]; then rm -rf -- "$SRC"; fi
tar -xjf "$ROOT/downloads/dropbear-2026.94.tar.bz2" -C "$ROOT/build"
cd "$SRC"
cp "$ROOT/config/localoptions.h" localoptions.h
CC=arm-buildroot-linux-musleabi-gcc \
AR=arm-buildroot-linux-musleabi-ar \
RANLIB=arm-buildroot-linux-musleabi-ranlib \
CFLAGS='-Os -march=armv7-a -marm -mfloat-abi=soft -ffunction-sections -fdata-sections' \
LDFLAGS='-static -Wl,--gc-sections' \
./configure --host=arm-buildroot-linux-musleabi --build=x86_64-pc-linux-gnu \
  --enable-static --enable-bundled-libtom --disable-zlib \
  --disable-syslog --disable-shadow --disable-lastlog \
  --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
  --disable-loginfunc --disable-pututline --disable-pututxline
make -j"${JOBS:-4}" PROGRAMS='dropbear dropbearkey' MULTI=1
cp dropbearmulti "$OUT/dropbearmulti"
arm-buildroot-linux-musleabi-strip "$OUT/dropbearmulti"
cp LICENSE "$OUT/LICENSE.dropbear"
cp localoptions.h "$OUT/localoptions.h"
arm-buildroot-linux-musleabi-readelf -h -A -l "$OUT/dropbearmulti" > "$OUT/ELF-info.txt"

python3 "$ROOT/scripts/package.py"
