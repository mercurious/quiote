#!/bin/sh
# Close Quiote's browser; launch.sh notices and cleans up after it.
pid=$(cat /run/quiote/chrome.pid 2>/dev/null)
case "$pid" in
  '' | *[!0-9]*) exit 1 ;;
esac
kill -TERM "$pid"
