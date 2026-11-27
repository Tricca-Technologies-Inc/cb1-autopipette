#!/usr/bin/env bash
# Off-device tests for scripts/webcam.sh (issue #81), using a fake
# /dev/v4l/by-id directory and fake v4l2-ctl, systemctl and curl. Run by the
# flake check `webcam`, or directly:
#   bash tests/webcam.test.sh [path/to/webcam.sh]
# The camera serials below are made-up placeholders.
set -euo pipefail

SCRIPT="${1:-$(dirname "$0")/../scripts/webcam.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CAM=usb-Test_Webcam_TESTCAM00000000-video-index0
CAM2=usb-Test_Webcam_TESTCAM00000001-video-index0

# v4l2-ctl --list-formats-ext, shaped like a real UVC webcam's. MJPG offers
# 1280x720 and 640x480; YUYV offers 1920x1080, which must not count.
FORMATS_MJPG="ioctl: VIDIOC_ENUM_FMT
	Type: Video Capture

	[0]: 'YUYV' (YUYV 4:2:2)
		Size: Discrete 1920x1080
			Interval: Discrete 0.200s (5.000 fps)
	[1]: 'MJPG' (Motion-JPEG, compressed)
		Size: Discrete 1280x720
			Interval: Discrete 0.033s (30.000 fps)
		Size: Discrete 640x480
			Interval: Discrete 0.033s (30.000 fps)"
FORMATS_YUYV="ioctl: VIDIOC_ENUM_FMT
	Type: Video Capture

	[0]: 'YUYV' (YUYV 4:2:2)
		Size: Discrete 1280x720
			Interval: Discrete 0.100s (10.000 fps)"

mkdir -p "$WORK/bin"
# Each fake logs its arguments to $WORK/calls.
cat >"$WORK/bin/v4l2-ctl" <<'EOF'
#!/usr/bin/env bash
echo "v4l2-ctl $*" >>"$WORK/calls"
case "$*" in
  *--list-formats-ext*) printf '%s\n' "$FAKE_FORMATS" ;;
esac
EOF
cat >"$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$WORK/calls"
EOF
cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$WORK/calls"
case "$*" in
  *action=snapshot*) [ -z "${FAKE_STREAM_DOWN:-}" ] ;;
esac
EOF
cat >"$WORK/bin/sleep" <<'EOF'
#!/usr/bin/env bash
EOF
chmod +x "$WORK/bin"/*

failures=0
fail() {
  echo "FAIL [$case_name]: $*" >&2
  failures=$((failures + 1))
}

# setup <case name> <cameras...>: fresh by-id dir, no settings file, no calls.
setup() {
  case_name=$1
  shift
  rm -rf "$WORK/by-id" "$WORK/webcam.env" "$WORK/calls" "$WORK/out" "$WORK/err"
  mkdir -p "$WORK/by-id"
  touch "$WORK/calls"
  local n=0 cam
  for cam in "$@"; do
    touch "$WORK/video$n"
    ln -s "$WORK/video$n" "$WORK/by-id/$cam"
    n=$((n + 1))
  done
  FAKE_FORMATS=$FORMATS_MJPG
  FAKE_STREAM_DOWN=
}

# run <expected exit code> <args...>
run() {
  local want=$1 rc=0
  shift
  WORK="$WORK" FAKE_FORMATS="$FAKE_FORMATS" FAKE_STREAM_DOWN="$FAKE_STREAM_DOWN" \
    PATH="$WORK/bin:$PATH" BY_ID_DIR="$WORK/by-id" ENV_FILE="$WORK/webcam.env" \
    MOONRAKER=http://moonraker STREAM=http://stream \
    bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err" || rc=$?
  [ "$rc" -eq "$want" ] || fail "exit $rc, expected $want; stderr: $(cat "$WORK/err")"
}

expect_env() {
  if ! cmp -s <(printf '%s' "$1") "$WORK/webcam.env"; then
    fail "webcam.env differs from expected:"
    diff <(printf '%s' "$1") "$WORK/webcam.env" >&2 || true
  fi
}
expect_no_env() { [ ! -e "$WORK/webcam.env" ] || fail "webcam.env was written"; }
expect_call() { grep -qF -- "$1" "$WORK/calls" || fail "no call matching: $1"; }
expect_no_call() { ! grep -qF -- "$1" "$WORK/calls" || fail "unexpected call: $1"; }

setup "no camera"
run 1 setup
expect_no_env
expect_no_call "systemctl restart"

setup "one camera: defaults, stream started, Moonraker entry posted" "$CAM"
run 0 setup
expect_env "DEVICE=$WORK/by-id/$CAM
RESOLUTION=1280x720
FPS=15
V4L2_CTRLS=
"
expect_call "systemctl restart webcam"
expect_call "curl -fsS -o /dev/null -X POST http://moonraker/server/webcams/item"
expect_call '"name": "deck", "service": "mjpegstreamer", "target_fps": 15, "stream_url": "/webcam/?action=stream", "snapshot_url": "/webcam/?action=snapshot"'

setup "two cameras, none named: refused" "$CAM" "$CAM2"
run 1 setup
expect_no_env
grep -qF "webcam setup $WORK/by-id/$CAM2" "$WORK/err" || fail "didn't list the cameras"

setup "two cameras, one named" "$CAM" "$CAM2"
run 0 setup "$WORK/by-id/$CAM2"
grep -qx "DEVICE=$WORK/by-id/$CAM2" "$WORK/webcam.env" || fail "wrong device"

setup "named camera missing" "$CAM"
run 1 setup "$WORK/by-id/$CAM2"
expect_no_env

setup "re-run keeps tuned settings" "$CAM"
printf 'DEVICE=/dev/v4l/by-id/old\nRESOLUTION=640x480\nFPS=10\nV4L2_CTRLS=focus_automatic_continuous=0,focus_absolute=30\n' >"$WORK/webcam.env"
run 0 setup
expect_env "DEVICE=$WORK/by-id/$CAM
RESOLUTION=640x480
FPS=10
V4L2_CTRLS=focus_automatic_continuous=0,focus_absolute=30
"
expect_call '"target_fps": 10'

setup "no MJPEG: refused" "$CAM"
FAKE_FORMATS=$FORMATS_YUYV
run 1 setup
expect_no_env
expect_no_call "systemctl restart"

setup "resolution only offered as YUYV: stopped, sizes listed" "$CAM"
printf 'RESOLUTION=1920x1080\n' >"$WORK/webcam.env"
run 1 setup
expect_call "systemctl stop webcam"
expect_no_call "systemctl restart"
grep -q "1280x720" "$WORK/err" || fail "didn't list the MJPEG sizes"
grep -qx "RESOLUTION=1920x1080" "$WORK/webcam.env" || fail "lost the RESOLUTION to fix"

setup "stream never answers: not registered" "$CAM"
FAKE_STREAM_DOWN=1
run 1 setup
expect_no_call "webcams/item"

setup "off" "$CAM"
printf 'DEVICE=x\n' >"$WORK/webcam.env"
run 0 off
expect_no_env
expect_call "systemctl stop webcam"
expect_call "curl -fsS -o /dev/null -X DELETE http://moonraker/server/webcams/item?name=deck"

setup "unknown subcommand" "$CAM"
run 2 bogus

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all webcam tests passed"
