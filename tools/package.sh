#!/bin/sh
# Assemble the release: dist/quiote/ (Quiote's home, as installed) and
# dist/quiote-aarch64.tar.gz with its .sha256. The browser is not in it:
# install.sh downloads it on the device.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/dist/quiote"
TARBALL="$ROOT/dist/quiote-aarch64.tar.gz"

rm -rf "$OUT" "$TARBALL" "$TARBALL.sha256"
mkdir -p "$OUT"
cp -R "$ROOT"/app/. "$OUT/"
cp "$ROOT/install.sh" "$ROOT/VERSION" "$ROOT/LICENSE" "$ROOT/README.md" "$OUT/"
tar -C "$ROOT/dist" -czf "$TARBALL" quiote
(cd "$ROOT/dist" && sha256sum quiote-aarch64.tar.gz >quiote-aarch64.tar.gz.sha256)
echo "dist/quiote-aarch64.tar.gz"
