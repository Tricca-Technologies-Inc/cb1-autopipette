#!/usr/bin/env bash
# The `webcam` shell helper (modules/aliases.nix) for the deck camera
# (issue #81). Run as root; the helper wraps it in sudo.
#
#   webcam setup [device]  pick the camera, write the settings file, start
#                          the stream and register it with Moonraker
#   webcam status          service state, settings, a test snapshot,
#                          Moonraker's entry and the camera's controls
#   webcam off             stop the stream, delete the settings file and
#                          remove the Moonraker entry
#
# The device is a /dev/v4l/by-id path, which carries the camera's serial, so
# it lives only in the machine-owned settings file (/etc/tricca-webcam.env),
# never in the repo. `setup` keeps any RESOLUTION, FPS or V4L2_CTRLS already
# in that file, so tune it by editing the file and re-running `webcam setup`.
#
# BY_ID_DIR, ENV_FILE, MOONRAKER and STREAM override the real locations; only
# the tests use them.
set -euo pipefail

BY_ID_DIR="${BY_ID_DIR:-/dev/v4l/by-id}"
ENV_FILE="${ENV_FILE:-/etc/tricca-webcam.env}"
MOONRAKER="${MOONRAKER:-http://127.0.0.1:7125}"
STREAM="${STREAM:-http://127.0.0.1:8080}"
UNIT=webcam
CAM_NAME=deck

say() { echo "    $*"; }
warn() { echo "    $*" >&2; }

setup() {
  local dev=${1:-}
  if [ -z "$dev" ]; then
    shopt -s nullglob
    local cams=("$BY_ID_DIR"/*-video-index0)
    shopt -u nullglob
    if [ "${#cams[@]}" -eq 0 ]; then
      warn "No camera found in $BY_ID_DIR. Plug in the USB webcam, then re-run:"
      warn "  webcam setup"
      return 1
    elif [ "${#cams[@]}" -gt 1 ]; then
      warn "More than one camera found. Pick the deck camera:"
      printf '      webcam setup %s\n' "${cams[@]}" >&2
      return 1
    fi
    dev=${cams[0]}
  fi
  if [ ! -e "$dev" ]; then
    warn "$dev does not exist. List cameras with: ls $BY_ID_DIR"
    return 1
  fi

  local RESOLUTION="" FPS="" V4L2_CTRLS=""
  if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
  fi
  RESOLUTION=${RESOLUTION:-1280x720}
  FPS=${FPS:-15}

  local formats mjpeg
  formats=$(v4l2-ctl -d "$dev" --list-formats-ext)
  # Only the sizes listed under the MJPG format count.
  mjpeg=$(awk '/^[[:space:]]*\[[0-9]+\]:/ { m = /MJPG/ } m' <<<"$formats")
  if [ -z "$mjpeg" ]; then
    warn "$dev doesn't offer MJPEG, so it can't stream without re-encoding."
    warn "Use a UVC webcam with MJPEG output."
    return 1
  fi

  printf 'DEVICE=%s\nRESOLUTION=%s\nFPS=%s\nV4L2_CTRLS=%s\n' \
    "$dev" "$RESOLUTION" "$FPS" "$V4L2_CTRLS" >"$ENV_FILE"
  say "Wrote $ENV_FILE (camera $dev, $RESOLUTION at $FPS fps)."

  if ! grep -q "Discrete $RESOLUTION\$" <<<"$mjpeg"; then
    systemctl stop "$UNIT" || :
    warn "The camera has no MJPEG mode at $RESOLUTION. Its MJPEG sizes:"
    grep -o 'Discrete [0-9]*x[0-9]*' <<<"$mjpeg" | sort -u | sed 's/^Discrete /      /' >&2
    warn "Set RESOLUTION to one of them in $ENV_FILE, then re-run: webcam setup"
    return 1
  fi

  systemctl restart "$UNIT"
  local up=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS -o /dev/null "$STREAM/?action=snapshot"; then
      up=1
      break
    fi
    sleep 1
  done
  if [ "$up" -eq 0 ]; then
    warn "The stream isn't answering. Check: logs $UNIT"
    return 1
  fi
  say "Stream is up."

  curl -fsS -o /dev/null -X POST "$MOONRAKER/server/webcams/item" \
    -H 'Content-Type: application/json' \
    -d "{\"name\": \"$CAM_NAME\", \"service\": \"mjpegstreamer\", \"target_fps\": $FPS, \"stream_url\": \"/webcam/?action=stream\", \"snapshot_url\": \"/webcam/?action=snapshot\"}"
  say "Registered webcam '$CAM_NAME' with Moonraker. Mainsail and the kiosk Run tab show it."
  say "Watch it from a laptop at http://$(uname -n)/webcam/?action=stream"
}

status() {
  systemctl status "$UNIT" --no-pager -l || :
  echo
  if [ ! -f "$ENV_FILE" ]; then
    say "Not set up ($ENV_FILE is missing). Run: webcam setup"
    return 0
  fi
  say "Settings ($ENV_FILE):"
  sed 's/^/      /' "$ENV_FILE"
  if curl -fsS -o /dev/null "$STREAM/?action=snapshot"; then
    say "Stream: answering."
  else
    say "Stream: not answering. Check: logs $UNIT"
  fi
  say "Moonraker webcams:"
  curl -fsS "$MOONRAKER/server/webcams/list" |
    jq -r '.result.webcams[] | "      \(.name): \(.stream_url) (enabled: \(.enabled))"' ||
    say "  (Moonraker didn't answer)"
  local DEVICE=""
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  if [ -e "$DEVICE" ]; then
    say "Camera controls (set them with V4L2_CTRLS=name=value,... in $ENV_FILE):"
    v4l2-ctl -d "$DEVICE" --list-ctrls | sed 's/^/  /'
  else
    say "Camera $DEVICE is not plugged in."
  fi
}

off() {
  systemctl stop "$UNIT" || :
  rm -f "$ENV_FILE"
  curl -fsS -o /dev/null -X DELETE "$MOONRAKER/server/webcams/item?name=$CAM_NAME" || :
  say "Camera off: stream stopped, $ENV_FILE removed, Moonraker entry removed."
}

case "${1:-}" in
  setup) shift && setup "$@" ;;
  status) status ;;
  off) off ;;
  *)
    echo "usage: webcam setup [/dev/v4l/by-id/<camera>] | webcam status | webcam off" >&2
    exit 2
    ;;
esac
