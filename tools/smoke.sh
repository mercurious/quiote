#!/bin/sh
# End-to-end smoke test on a device with Quiote installed (portmart or
# install.sh). No hands needed. It launches Quiote from Ports, reads the
# WebGPU check page's verdict from the window title, and runs an app with
# --serve and gamepad.yaml: the pad presses go in through InputPlumber, and
# the page reports what Chrome's Gamepad API sees. Home exits both sessions,
# and the test checks they clean up. Screenshots land in build/shots/.
#   QUIOTE_HOST  ssh destination (default flip2-12g)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HOST="${QUIOTE_HOST:-flip2-12g}"
SHOTS="$ROOT/build/shots"

status=0
ssh "$HOST" sh -s <<'EOF' || status=$?
export XDG_RUNTIME_DIR=/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1
export SWAYSOCK=/run/0-runtime-dir/sway-ipc.0.sock
IP=org.shadowblip.InputPlumber
PAD=$(busctl tree $IP 2>/dev/null | grep -o '/org/shadowblip/InputPlumber/CompositeDevice[0-9]*' | head -n 1)
KBD=/org/shadowblip/InputPlumber/devices/target/keyboard0
QUIOTE=$(cat /storage/.config/quiote/home)
fails=0

profile() {
  busctl get-property $IP "$PAD" org.shadowblip.Input.CompositeDevice ProfileName |
    sed 's/^s "//; s/"$//'
}
chord() { busctl call $IP "$PAD" org.shadowblip.Input.CompositeDevice SendButtonChord as 1 "$1"; }
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
check_prefix() {
  case "$2" in "$3"*) echo "PASS $1 ($2)" ;; *) echo "FAIL $1: got '$2', want '$3...'"; fails=$((fails + 1)) ;; esac
}
pid() { cat /run/quiote/chrome.pid 2>/dev/null || true; }
window() { # field of Quiote's window: name, rect.width, ...
  p=$(pid)
  [ -n "$p" ] || return 0
  swaymsg -t get_tree | jq -r "[.. | objects | select(.pid? == $p)][0].$1 // empty"
}
wait_title() { # prefix seconds
  i=0
  while [ $i -lt $(($2 * 2)) ]; do
    case "$(window name)" in "$1"*) return 0 ;; esac
    sleep 0.5; i=$((i + 1))
  done
}
shot() { grim "/tmp/quiote-smoke-$1.png"; }
leave() { # Home, through the controller profile and Sway's binding
  # Home: the profiles map Guide to F23, which Sway binds to exit.sh; send F23
  # on InputPlumber's keyboard, as Guide would.
  busctl call $IP "$KBD" org.shadowblip.Input.Keyboard SendKey sb KEY_F23 true
  busctl call $IP "$KBD" org.shadowblip.Input.Keyboard SendKey sb KEY_F23 false
  i=0
  while [ $i -lt 30 ] && [ -n "$(pid)" ]; do sleep 0.5; i=$((i + 1)); done
  sleep 2
  check "$1: closed" "$(pid)" ""
  check "$1: browser stopped" "$(pgrep -f "$QUIOTE/chrome/chrome" >/dev/null && echo running || echo stopped)" stopped
  check "$1: workspace restored" "$(swaymsg -t get_workspaces -r | jq -r '.[] | select(.focused) | .name')" "$start_ws"
  i=0
  while [ $i -lt 20 ] && [ "$(profile)" != "$start_profile" ]; do sleep 0.5; i=$((i + 1)); done
  check "$1: controller restored" "$(profile)" "$start_profile"
}

rm -f /tmp/quiote-smoke-*.png
if [ -n "$(pid)" ] && kill -0 "$(pid)" 2>/dev/null; then
  "$QUIOTE/exit.sh"
  sleep 5
fi
start_ws=$(swaymsg -t get_workspaces -r | jq -r '.[] | select(.focused) | .name')
start_profile=$(profile)

# 1. Ports > Quiote: the WebGPU check page.
setsid /storage/roms/ports/Quiote.sh >/dev/null 2>&1 </dev/null &
wait_title "Quiote: " 30
sleep 3
check_prefix "check page: hardware adapter" "$(window name)" "Quiote: WebGPU qualcomm"
check "check page: fills the screen" "$(window rect.width)x$(window rect.height)" "$(swaymsg -t get_outputs -r | jq -r '.[0].rect | "\(.width)x\(.height)"')"
check "check page: gamepad layout" "$(profile)" "Quiote gamepad"
# The first press makes the pad visible to the page; the page then adds
# " (pad <mapping>)" to its title.
chord Gamepad:Button:South
sleep 1
chord Gamepad:Button:South
sleep 1
check "check page: the pad reaches the page" "$(window name | sed -n 's/.*(pad \(.*\))$/\1/p')" standard
shot 1-check
leave "check page"

# 2. An app: --serve, its own profile, the pad passed through.
app=/tmp/quiote-smoke-app
rm -rf "$app"; mkdir -p "$app"
cat >"$app/index.html" <<'HTML'
<!doctype html><title>pads: none</title><body style="background:#000;color:#fff;font:40px sans-serif">
<p id="o">press a button</p>
<script>
// every button seen pressed, so a short chord can't slip between frames
const seen = new Set();
(function poll() {
  const p = [...navigator.getGamepads()].filter(Boolean)[0];
  if (p) {
    p.buttons.forEach((b, i) => { if (b.pressed) seen.add(i); });
    document.title = `pads: ${p.mapping} ${[...seen].sort((a, b) => a - b).join(',') || 'none'} seen`;
    document.getElementById('o').textContent = `${p.id} ${p.mapping}`;
  }
  requestAnimationFrame(poll);
})();
</script>
HTML
QUIOTE_PROFILE=smoke QUIOTE_CONTROLLER=gamepad.yaml setsid "$QUIOTE/launch.sh" \
  --serve "$app" '--app=@serve@/index.html' >/dev/null 2>&1 </dev/null &
wait_title "pads: " 30
sleep 2
check "app: served page" "$(window name)" "pads: none"
check "app: gamepad layout" "$(profile)" "Quiote gamepad"
# The first press makes the pad visible to the page (the Gamepad API's
# rule); the second one is the one the page sees.
chord Gamepad:Button:South
sleep 1
chord Gamepad:Button:South
wait_title "pads: standard 0" 5 || true
check "app: A reaches the page as standard button 0" "$(window name)" "pads: standard 0 seen"
shot 2-app
leave "app"
check "app: server stopped" "$(curl -fso /dev/null http://127.0.0.1:8737/ && echo up || echo down)" down
rm -rf "$app"
echo "failures: $fails"
[ "$fails" = 0 ]
EOF

mkdir -p "$SHOTS"
scp -q "$HOST:/tmp/quiote-smoke-*.png" "$SHOTS/"
echo "screenshots: build/shots/"
exit $status
