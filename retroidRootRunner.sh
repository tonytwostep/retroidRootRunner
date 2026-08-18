#!/bin/bash
# retroidRootRunner.sh - send a command to retroidRootRunner and wait for its result.
# Usage:
#   ./retroidRootRunner.sh <command...>   send a command, wait for it to finish, print output
#   ./retroidRootRunner.sh kill           stop the runner and clean up its control files
#
# Waiting is content-based (polls output.log for a completion marker) rather
# than a fixed sleep, so slow commands aren't cut off and fast ones don't
# waste time waiting.

set -uo pipefail

BASE=/sdcard/retroidRootRunner
POLL_INTERVAL="${RRUN_POLL_INTERVAL:-1}"   # seconds between checks
MAX_WAIT="${RRUN_TIMEOUT:-60}"             # seconds before giving up

usage() {
  cat <<EOF
Usage:
  $0 <command...>   send a command, wait for it to finish, print output
  $0 kill           stop the runner and clean up
  $0 -h, --help     show this help

Env vars:
  RRUN_POLL_INTERVAL   seconds between output checks (default: 1)
  RRUN_TIMEOUT         seconds to wait before giving up (default: 60)

Examples:
  $0 'id; getenforce'
  $0 'pm list packages -s'
  $0 kill
EOF
  exit "${1:-1}"
}

case "${1:-}" in
  -h|--help) usage 0 ;;
esac

# size in bytes of output.log right now (0 if missing)
log_size() {
  adb shell "wc -c < $BASE/output.log 2>/dev/null" 2>/dev/null | tr -d '\r\n '
}

# everything appended to output.log since byte offset $1
log_since() {
  adb shell "tail -c +$(( $1 + 1 )) $BASE/output.log 2>/dev/null"
}

# true if runner.sh's pid file exists and that pid is alive on-device
is_running() {
  pid=$(adb shell "cat $BASE/runner.pid 2>/dev/null" | tr -d '\r\n ')
  [ -n "$pid" ] || return 1
  adb shell "[ -d /proc/$pid ]" 2>/dev/null
}

[ $# -ge 1 ] || usage

if [ "$1" = "kill" ]; then
  if ! is_running; then
    echo "Nothing to kill — runner is not running."
    adb shell "rm -f $BASE/cmd $BASE/cmd.run $BASE/stop $BASE/runner.pid" >/dev/null
    exit 0
  fi

  before=$(log_size); before=${before:-0}
  echo "Stopping runner..."
  adb shell "touch $BASE/stop" >/dev/null

  waited=0
  while true; do
    chunk=$(log_since "$before")
    if echo "$chunk" | grep -q "loop exited"; then
      break
    fi
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
    if [ "$waited" -ge "$MAX_WAIT" ]; then
      echo "Timed out waiting for runner to stop (it may already be dead)."
      break
    fi
  done

  adb shell "rm -f $BASE/cmd $BASE/cmd.run $BASE/stop $BASE/runner.pid" >/dev/null
  echo "Stopped and cleaned up."
  exit 0
fi

if ! is_running; then
  echo "Error: runner is not running on device (no live pid at $BASE/runner.pid)." >&2
  echo "Start it via the Retroid 'Run script as root' tool with entrypoint.sh." >&2
  exit 1
fi

CMD="$*"
before=$(log_size); before=${before:-0}

tmp=$(mktemp)
echo "$CMD" > "$tmp"
adb push "$tmp" "$BASE/cmd" >/dev/null 2>&1
rm -f "$tmp"

waited=0
while true; do
  chunk=$(log_since "$before")
  if echo "$chunk" | grep -q "=== exit "; then
    echo "$chunk"
    exit 0
  fi
  if ! is_running; then
    echo "Error: runner stopped responding while waiting for output." >&2
    echo "$chunk"
    exit 1
  fi
  sleep "$POLL_INTERVAL"
  waited=$((waited + POLL_INTERVAL))
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    echo "Timed out after ${MAX_WAIT}s waiting for command to finish. Output so far:"
    echo "$chunk"
    exit 1
  fi
done
