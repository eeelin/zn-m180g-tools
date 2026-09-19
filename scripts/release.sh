#!/bin/sh
# Publish an already built, tested commit. Requires repository write permission.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:?Usage: scripts/release.sh TAG}
git check-ref-format "refs/tags/$TAG"
[ "$TAG" = "$(cat VERSION)" ] || { echo 'Tag must match VERSION' >&2; exit 1; }
cmp install.sh dist/install.sh || { echo 'Copy dist/install.sh to install.sh and commit it before release' >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo 'Commit all changes before releasing' >&2; exit 1; }
for name in zn-m180g-ssh.tar.gz zn-m180g-ssh-source.tar.gz install.sh; do
  (cd dist && sha256sum -c "$name.sha256")
done
[ -s dist/SMOKE-TEST.txt ] && [ -s dist/INSTALLER-TEST.txt ] || { echo 'Run smoke-test.py and test-installer.py first' >&2; exit 1; }
# Push the actual local commit before creating a release at that commit.
git push origin HEAD:main
COMMIT=$(git rev-parse HEAD)
gh release create "$TAG" --repo eeelin/zn-m180g-tools --target "$COMMIT" \
  --title "ZN-M180G SSH $TAG (Dropbear 2026.94)" \
  --notes-file docs/RELEASE-notes.md \
  dist/zn-m180g-ssh.tar.gz dist/zn-m180g-ssh.tar.gz.sha256 \
  dist/zn-m180g-ssh-source.tar.gz dist/zn-m180g-ssh-source.tar.gz.sha256 \
  dist/install.sh dist/install.sh.sha256 \
  dist/SMOKE-TEST.txt dist/INSTALLER-TEST.txt docs/INSTALL-zh.md
