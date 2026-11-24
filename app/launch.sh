#!/bin/sh
# Quiote launcher: runs Google's Chrome build under ROCKNIX's Sway session
# with WebGPU on the device's Vulkan driver (Turnip on the Adreno 650),
# full screen on its own workspace, with Quiote's controller layout.
# Everything Quiote changes on the way in is put back on the way out.
#
#   launch.sh                          the WebGPU check page
#   launch.sh [chrome args] [URL]      e.g. --app=https://example.org/
#   launch.sh --serve DIR [args]       serve DIR at http://127.0.0.1:PORT;
#                                      "@serve@" in the args becomes that
#                                      address (default: --app=@serve@/)
#
# Apps that run inside Quiote set these:
#   QUIOTE_PROFILE=<name>     own Chrome profile, /storage/.config/quiote/<name>
#   QUIOTE_CONTROLLER=<yaml>  InputPlumber profile for the session: a path, or
#                             a file in Quiote's controller/ (gamepad.yaml
#                             passes the pad through as a standard gamepad)
#   QUIOTE_SCALE=<n>          device scale factor (default 1)
#   QUIOTE_PORT=<n>           port for --serve (default 8737)
#   QUIOTE_ANGLE=vulkan|gl    ANGLE backend for WebGL and canvas (default
#                             vulkan, which WebGPU needs; gl for WebGL apps:
#                             on Turnip, antialiased WebGL canvases never
#                             reach the screen with ANGLE on Vulkan)
#   QUIOTE_FLAGS="<flags>"    extra Chrome flags, split on spaces

. /etc/profile

APP=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
CHROME="$APP/chrome/chrome"
RUN=/run/quiote
LOG="$APP/logs/quiote.log"
WORKSPACE="96:quiote"
KEY_F23=201 # Home, sent by the controller profiles (evdev code + 8)

PROFILE_NAME=${QUIOTE_PROFILE:-quiote}
case "$PROFILE_NAME" in
  *[!a-z0-9._-]* | [._-]*) echo "Quiote: bad QUIOTE_PROFILE '$PROFILE_NAME'" >&2; exit 2 ;;
esac
PROFILE=/storage/.config/quiote/$PROFILE_NAME
SCALE=${QUIOTE_SCALE:-1}
case "$SCALE" in
  *[!0-9.]* | "" | .*) echo "Quiote: bad QUIOTE_SCALE '$SCALE'" >&2; exit 2 ;;
esac
PORT=${QUIOTE_PORT:-8737}
case "$PORT" in
  *[!0-9]* | "") echo "Quiote: bad QUIOTE_PORT '$PORT'" >&2; exit 2 ;;
esac
ANGLE=${QUIOTE_ANGLE:-vulkan}
case "$ANGLE" in
  vulkan | gl) ;;
  *) echo "Quiote: bad QUIOTE_ANGLE '$ANGLE' (vulkan or gl)" >&2; exit 2 ;;
esac
case "${QUIOTE_CONTROLLER:-}" in
  "") PAD_LAYOUT=$APP/controller/browse.yaml ;;
  */*) PAD_LAYOUT=$QUIOTE_CONTROLLER ;;
  *) PAD_LAYOUT=$APP/controller/$QUIOTE_CONTROLLER ;;
esac
[ -f "$PAD_LAYOUT" ] || { echo "Quiote: no controller layout $PAD_LAYOUT" >&2; exit 2; }

SERVE=""
if [ "${1:-}" = --serve ]; then
  [ -n "${2:-}" ] && [ -d "$2" ] || { echo "Quiote: --serve needs a directory" >&2; exit 2; }
  SERVE=$(CDPATH= cd -- "$2" && pwd)
  shift 2
fi

CHROME_PID=""
SERVE_PID=""
PRIOR_WORKSPACE=""
PAD_PROFILE_LOADED=0

if [ ! -x "$CHROME" ]; then
  echo "Quiote: the browser is missing from $APP/chrome. Run $APP/install.sh." >&2
  exit 1
fi
# One session at a time: a second one would share the controller and the
# Sway binding, and its cleanup would tear down the first.
if pid=$(cat "$RUN/chrome.pid" 2>/dev/null) && [ -n "$pid" ] &&
  kill -0 "$pid" 2>/dev/null; then
  echo "Quiote is already running (pid $pid); leave it first (Home)." >&2
  exit 1
fi

mkdir -p "$APP/logs" "$RUN" "$PROFILE"
exec >>"$LOG" 2>&1
echo
echo "== Quiote $(cat "$APP/VERSION" 2>/dev/null) $(date '+%F %T') profile=$PROFILE scale=$SCALE angle=$ANGLE pad=$PAD_LAYOUT serve=${SERVE:-none}"

# Launched from EmulationStation these are already set; over SSH they are
# not, so find the running session.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/0-runtime-dir}"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
    case "$sock" in *.lock) continue ;; esac
    [ -S "$sock" ] && WAYLAND_DISPLAY=$(basename "$sock") && break
  done
fi
if [ -z "${SWAYSOCK:-}" ]; then
  for sock in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do
    [ -S "$sock" ] && SWAYSOCK="$sock" && break
  done
fi
export WAYLAND_DISPLAY SWAYSOCK
[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ] &&
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
echo "wayland=$WAYLAND_DISPLAY sway=$SWAYSOCK"

export HOME=/storage
export XDG_CACHE_HOME=/storage/.cache
export XDG_CONFIG_HOME=/storage/.config
export XDG_DATA_HOME=/storage/.local/share

QUIOTE_PAD=$(busctl tree org.shadowblip.InputPlumber 2>/dev/null |
  grep -o '/org/shadowblip/InputPlumber/CompositeDevice[0-9]*' | head -n 1)

load_pad_profile() {
  [ -n "$QUIOTE_PAD" ] || return 1
  busctl call org.shadowblip.InputPlumber "$QUIOTE_PAD" \
    org.shadowblip.Input.CompositeDevice LoadProfilePath s "$1"
}

cleanup() {
  trap - EXIT INT TERM HUP
  swaymsg -q "unbindcode --no-repeat $KEY_F23"
  rm -f "$RUN/chrome.pid"
  if [ -n "$SERVE_PID" ]; then
    kill "$SERVE_PID" 2>/dev/null
    wait "$SERVE_PID" 2>/dev/null
  fi
  # Restarting InputPlumber rebuilds the stock gamepad + keyboard targets,
  # which loading the default profile alone does not.
  [ "$PAD_PROFILE_LOADED" = 1 ] && systemctl restart inputplumber.service
  command -v set_kill >/dev/null && set_kill stop
  [ -n "$PRIOR_WORKSPACE" ] && swaymsg -q "workspace $PRIOR_WORKSPACE"
  echo "== Quiote closed $(date '+%F %T')"
}

on_signal() {
  [ -n "$CHROME_PID" ] && kill "$CHROME_PID" 2>/dev/null
  exit 130
}

trap cleanup EXIT
trap on_signal INT TERM HUP

if [ -n "$SERVE" ]; then
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE" \
    >>"$APP/logs/serve.log" 2>&1 &
  SERVE_PID=$!
  tries=0
  until curl -fso /dev/null "http://127.0.0.1:$PORT/"; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ] || ! kill -0 "$SERVE_PID" 2>/dev/null; then
      echo "Quiote: the server for $SERVE did not start on port $PORT"
      exit 1
    fi
    sleep 0.1
  done
  # Swap "@serve@" for the address in every argument.
  url="http://127.0.0.1:$PORT"
  n=$#
  [ "$n" -gt 0 ] || { set -- '--app=@serve@/'; n=1; }
  while [ "$n" -gt 0 ]; do
    a=$1
    shift
    while :; do
      case "$a" in
        *@serve@*) a="${a%%@serve@*}$url${a#*@serve@}" ;;
        *) break ;;
      esac
    done
    set -- "$@" "$a"
    n=$((n - 1))
  done
fi
[ "$#" -gt 0 ] || set -- "--app=file://$APP/page/index.html"

# Until a page first paints, Chrome's window is white, and its first frame
# is Chrome's default window size in the top-left corner. --window-size makes
# the first frame fill the screen, and every --app page opens through
# page/start.html: black, it goes on to the app once it has painted, and
# Chrome keeps showing it until the app paints.
n=$#
while [ "$n" -gt 0 ]; do
  a=$1
  shift
  case "$a" in
    --app=?*) a="--app=file://$APP/page/start.html#${a#--app=}" ;;
  esac
  set -- "$@" "$a"
  n=$((n - 1))
done

# ROCKNIX's global exit chord (L1 + Select + Start) also closes Quiote.
command -v set_kill >/dev/null && set_kill set "chrome"

load_pad_profile "$PAD_LAYOUT" && PAD_PROFILE_LOADED=1
swaymsg -q "bindcode --no-repeat $KEY_F23 exec $APP/exit.sh"

PRIOR_WORKSPACE=$(swaymsg -t get_workspaces -r |
  jq -r '.[] | select(.focused) | .name' | head -n 1)
swaymsg -q "workspace $WORKSPACE"
WINDOW_SIZE=$(swaymsg -t get_outputs -r |
  jq -r '.[] | select(.focused) | "\(.rect.width) \(.rect.height)"' |
  awk -v s="$SCALE" 'NR == 1 { printf "--window-size=%d,%d", $1 / s, $2 / s }')

# WebGPU needs Dawn on Vulkan (--enable-features=Vulkan) and ANGLE on Vulkan
# too: with ANGLE on GL, sharing the canvas with the compositor fails and the
# GPU device is lost. WebGL apps pick ANGLE on GL instead (QUIOTE_ANGLE): on
# Vulkan, Turnip never shows antialiased WebGL canvases.
# --enable-unsafe-webgpu gets past the adapter blocklist.
# Root is the only user on ROCKNIX, and Chrome's sandbox refuses root;
# --test-type drops the infobar that --no-sandbox brings.
# shellcheck disable=SC2086
"$CHROME" --user-data-dir="$PROFILE" --no-sandbox --test-type \
  --no-first-run --no-default-browser-check --password-store=basic \
  --ozone-platform=wayland --enable-features=Vulkan --use-angle="$ANGLE" \
  --enable-unsafe-webgpu --ignore-gpu-blocklist \
  --autoplay-policy=no-user-gesture-required \
  --force-device-scale-factor="$SCALE" $WINDOW_SIZE \
  ${QUIOTE_FLAGS:-} "$@" &
CHROME_PID=$!
echo "$CHROME_PID" >"$RUN/chrome.pid"

tries=0
while [ "$tries" -lt 30 ] && kill -0 "$CHROME_PID" 2>/dev/null; do
  if swaymsg -t get_tree | jq -e "[.. | objects | select(.pid? == $CHROME_PID)] | length > 0" >/dev/null; then
    # Alone and borderless on its own workspace, the window fills the screen.
    # Sway's fullscreen would do the same but makes Chrome show its "press
    # and hold Esc" bubble, which a pad can't answer.
    swaymsg -q "[pid=$CHROME_PID] move container to workspace $WORKSPACE"
    swaymsg -q "workspace $WORKSPACE"
    swaymsg -q "[pid=$CHROME_PID] focus, border none"
    break
  fi
  tries=$((tries + 1))
  sleep 0.5
done

wait "$CHROME_PID"
