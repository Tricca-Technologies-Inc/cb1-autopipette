#!/usr/bin/env bash
# Off-device tests for scripts/write-mcu-serials.sh (issue #51), using a fake
# /dev/serial/by-id directory and a temp printer.cfg. Run by the flake check
# `write-mcu-serials`, or directly:
#   bash tests/write-mcu-serials.test.sh [path/to/write-mcu-serials.sh]
# The serial IDs below are made-up placeholders, not real boards.
set -euo pipefail

SCRIPT="${1:-$(dirname "$0")/../scripts/write-mcu-serials.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

M8P=usb-Klipper_stm32h723xx_TESTM8P0000000000000000-if00
M8P2=usb-Klipper_stm32h723xx_TESTM8P0000000000000001-if00
OCT=usb-Klipper_stm32f446xx_TESTOCTOPUS00000000000000-if00
UNKNOWN=usb-Klipper_stm32g0b1xx_TESTUNKNOWN000000000000-if00

# Shaped like the seeded printer.cfg from printer-cfgs (it has [mcu CB1], the
# host MCU, but no [mcu] or [mcu octopus]).
SEED='[include mainsail.cfg]

[mcu CB1]
serial = /tmp/klipper_host_mcu

[include tricca-autopipette.cfg]
'

failures=0
fail() {
  echo "FAIL [$case_name]: $*" >&2
  failures=$((failures + 1))
}

# setup <case name> <devices...>: fresh by-id dir (dangling symlinks, like the
# real ones point at ../../ttyACMn) and printer.cfg = $SEED.
setup() {
  case_name=$1
  shift
  rm -rf "$WORK/by-id" "$WORK/printer.cfg" "$WORK/out" "$WORK/err"
  mkdir -p "$WORK/by-id"
  local n=0 dev
  for dev in "$@"; do
    ln -s "../../ttyACM$n" "$WORK/by-id/$dev"
    n=$((n + 1))
  done
  printf '%s' "$SEED" >"$WORK/printer.cfg"
}

run() {
  BY_ID_DIR="$WORK/by-id" PRINTER_CFG="$WORK/printer.cfg" \
    bash "$SCRIPT" >"$WORK/out" 2>"$WORK/err" || fail "exited non-zero"
}

expect_cfg() {
  local want=$1
  if ! cmp -s <(printf '%s' "$want") "$WORK/printer.cfg"; then
    fail "printer.cfg differs from expected:"
    diff <(printf '%s' "$want") "$WORK/printer.cfg" >&2 || true
  fi
}

# Byte-exact copy of printer.cfg ($(cat) alone would drop trailing newlines).
snapshot() {
  before=$(
    cat "$WORK/printer.cfg"
    printf x
  )
  before=${before%x}
}

expect_err() {
  grep -qF -- "$1" "$WORK/err" || fail "stderr lacks '$1'; got: $(cat "$WORK/err")"
}

expect_count() { # <exact header line> <count>
  local got
  got=$(grep -cxF -- "$1" "$WORK/printer.cfg" || true)
  [ "$got" -eq "$2" ] || fail "'$1' appears $got times, want $2"
}

MCU_BLOCK=$'\n[mcu]\nserial: '"$WORK/by-id/$M8P"$'\n'
OCT_BLOCK=$'\n[mcu octopus]\nserial: '"$WORK/by-id/$OCT"$'\n'

setup "both boards" "$M8P" "$OCT"
run
expect_cfg "$SEED$MCU_BLOCK$OCT_BLOCK"
expect_count "[mcu CB1]" 1

# Same bytes bootstrap.sh appended before this change.
setup "Octopus absent: [mcu] only, as before, plus a note" "$M8P"
run
expect_cfg "$SEED$(printf '\n[mcu]\nserial: %s\n' "$WORK/by-id/$M8P")"$'\n'
expect_err "no Octopus V1.1"

setup "M8P absent: [mcu octopus] only" "$OCT"
run
expect_cfg "$SEED$OCT_BLOCK"
expect_err "no Manta M8P"

setup "two H723s: no [mcu], Octopus still written" "$M8P" "$M8P2" "$OCT"
run
expect_cfg "$SEED$OCT_BLOCK"
expect_err "more than one stm32h723xx"

setup "two F446s: no [mcu octopus], M8P still written" "$M8P" "$OCT" \
  usb-Klipper_stm32f446xx_TESTOCTOPUS00000000000001-if00
run
expect_cfg "$SEED$MCU_BLOCK"
expect_err "more than one stm32f446xx"

setup "unknown usb-Klipper device: write nothing" "$M8P" "$OCT" "$UNKNOWN"
run
expect_cfg "$SEED"
expect_err "$UNKNOWN"

setup "unknown device alone (was written as [mcu] before): write nothing" "$UNKNOWN"
run
expect_cfg "$SEED"
expect_err "$UNKNOWN"

setup "no devices at all"
run
expect_cfg "$SEED"
expect_err "no Manta M8P"

setup "re-run is idempotent" "$M8P" "$OCT"
run
run
expect_cfg "$SEED$MCU_BLOCK$OCT_BLOCK"
expect_count "[mcu]" 1
expect_count "[mcu octopus]" 1

setup "[mcu octopus] present, [mcu] missing" "$M8P" "$OCT"
printf '\n[mcu octopus]\nserial: /dev/serial/by-id/EXISTING\n' >>"$WORK/printer.cfg"
snapshot
run
expect_cfg "$before$MCU_BLOCK"
expect_count "[mcu octopus]" 1

setup "[mcu] present, [mcu octopus] missing" "$M8P" "$OCT"
printf '\n[mcu]\nserial: /dev/serial/by-id/EXISTING\n' >>"$WORK/printer.cfg"
snapshot
run
expect_cfg "$before$OCT_BLOCK"
expect_count "[mcu]" 1

setup "both present: nothing written, even with an unknown device" "$M8P" "$OCT" "$UNKNOWN"
printf '\n[mcu]\nserial: A\n\n[mcu octopus]\nserial: B\n' >>"$WORK/printer.cfg"
snapshot
run
expect_cfg "$before"

setup "commented-out [mcu] doesn't count" "$M8P"
printf '\n#[mcu]\n#serial: /dev/serial/by-id/OLD\n' >>"$WORK/printer.cfg"
snapshot
run
expect_cfg "$before$MCU_BLOCK"

setup "inserted above the SAVE_CONFIG block" "$M8P" "$OCT"
autosave='
#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.
#*#
#*# [tmc2209 stepper_x]
#*# run_current = 0.800
'
printf '%s' "$autosave" >>"$WORK/printer.cfg"
run
# The blank line Klipper leaves above its header stays above the new sections.
expect_cfg "$SEED"$'\n'"$MCU_BLOCK$OCT_BLOCK$autosave"

setup "printer.cfg missing: not created" "$M8P" "$OCT"
rm "$WORK/printer.cfg"
run
[ ! -e "$WORK/printer.cfg" ] || fail "printer.cfg was created"
expect_err "does not exist"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "write-mcu-serials: all tests passed"
