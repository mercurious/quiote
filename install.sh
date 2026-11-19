#!/bin/sh
# Quiote setup. Runs from Quiote's home, the unpacked release:
#
#   tar -xzf quiote-aarch64.tar.gz -C /storage/apps
#   /storage/apps/quiote/install.sh                 fetch the browser if missing, add Ports > Quiote
#   /storage/apps/quiote/install.sh --update-chrome also replace it with Google's latest
#
# portmart runs it as the install hook (PORTMART_HOME set) and writes the
# Ports entry itself. The browser is Google's own Chrome for Linux arm64,
# downloaded from Google and run unmodified; Quiote never ships it.
set -eu

HOME_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
STORAGE=${QUIOTE_STORAGE:-/storage}
PORTS_DIR=${PORTS_DIR:-$STORAGE/roms/ports}
CHROME_URL=${QUIOTE_CHROME_URL:-https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb}

update_chrome=0
case "${1:-}" in
  "") ;;
  --update-chrome) update_chrome=1 ;;
  *) sed -n '2,10s/^# \{0,1\}//p' "$0" >&2; exit 2 ;;
esac

if [ "$(uname -m)" != aarch64 ]; then
  echo "Quiote needs an aarch64 device; this is $(uname -m)." >&2
  exit 1
fi

# The .deb is an ar archive: control.tar.xz (the version) and data.tar.xz
# (the browser, under opt/google/chrome). BusyBox has ar, but its xz can't
# open Google's data.tar.xz (a 256 MiB dictionary), so Python unpacks it.
fetch_chrome() {
  work=$(mktemp -d "$HOME_DIR/.chrome-download.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  echo "Downloading Chrome for Linux arm64 from Google..."
  curl -fL --retry 3 -o "$work/chrome.deb" "$CHROME_URL"
  echo "Unpacking..."
  (cd "$work" && ar x chrome.deb control.tar.xz data.tar.xz && rm chrome.deb)
  python3 - "$work" <<'PY'
import lzma, sys, tarfile
work = sys.argv[1]
with tarfile.open(fileobj=lzma.open(f"{work}/data.tar.xz"), mode="r|") as t:
    t.extractall(work, members=(m for m in t if m.name.startswith("./opt/google/chrome/")), filter="tar")
with tarfile.open(f"{work}/control.tar.xz") as t:
    control = t.extractfile("./control").read().decode()
version = next(l.split(":", 1)[1].strip() for l in control.splitlines() if l.startswith("Version:"))
open(f"{work}/opt/google/chrome/.quiote-version", "w").write(version + "\n")
PY
  if [ ! -x "$work/opt/google/chrome/chrome" ]; then
    echo "The download did not contain opt/google/chrome/chrome." >&2
    exit 1
  fi
  rm -rf "$HOME_DIR/chrome"
  mv "$work/opt/google/chrome" "$HOME_DIR/chrome"
}

mkdir -p "$HOME_DIR/logs"
if [ "$update_chrome" = 1 ] || [ ! -x "$HOME_DIR/chrome/chrome" ]; then
  fetch_chrome
fi
chmod +x "$HOME_DIR"/*.sh

missing=$(ldd "$HOME_DIR/chrome/chrome" 2>&1 | grep 'not found' || true)
if [ -n "$missing" ]; then
  echo "Missing libraries:" >&2
  echo "$missing" >&2
  exit 1
fi

# Apps that run inside Quiote find it here, wherever portmart put it.
mkdir -p "$STORAGE/.config/quiote"
echo "$HOME_DIR" >"$STORAGE/.config/quiote/home"

if [ -z "${PORTMART_HOME:-}" ]; then
  mkdir -p "$PORTS_DIR"
  printf '#!/bin/sh\nexec "%s/launch.sh" "$@"\n' "$HOME_DIR" >"$PORTS_DIR/Quiote.sh"
  chmod +x "$PORTS_DIR/Quiote.sh"
fi

echo "Quiote $(cat "$HOME_DIR/VERSION") ready with Chrome $(cat "$HOME_DIR/chrome/.quiote-version") in $HOME_DIR."
[ -n "${PORTMART_HOME:-}" ] ||
  echo "In EmulationStation: Start > Game Settings > Update Gamelists, then Ports > Quiote."
