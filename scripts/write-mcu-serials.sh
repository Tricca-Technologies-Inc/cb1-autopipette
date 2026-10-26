#!/usr/bin/env bash
# Write the USB MCU serial sections into the machine's printer.cfg, picking
# each board out by the chip name in its /dev/serial/by-id path:
#
#   usb-Klipper_stm32h723xx_*  ->  [mcu]          Manta M8P V2.0
#   usb-Klipper_stm32f446xx_*  ->  [mcu octopus]  Octopus V1.1 (non-Pro)
#
# USB serial IDs are unique per physical board, so they only ever go into the
# machine-owned printer.cfg (ADR-0005), never into the repo or the shared
# printer-cfgs files.
#
# Never guesses. Nothing is written for a board whose chip matches zero or
# more than one device, and nothing at all is written while any other
# usb-Klipper_* device is plugged in. Instructions go to stderr instead.
# A section that is already in printer.cfg is left alone, so re-running is
# safe. New sections go in above Klipper's SAVE_CONFIG block, if there is one.
#
# Called by bootstrap.sh. Also safe to run on its own, as root:
#   sudo bash /opt/cb1-autopipette/scripts/write-mcu-serials.sh
#
# BY_ID_DIR and PRINTER_CFG override the real paths; only the tests use them.
set -euo pipefail

BY_ID_DIR="${BY_ID_DIR:-/dev/serial/by-id}"
PRINTER_CFG="${PRINTER_CFG:-/var/lib/moonraker/config/printer.cfg}"
M8P_CHIP=stm32h723xx
OCTOPUS_CHIP=stm32f446xx

say() { echo "    $*"; }
warn() { echo "    $*" >&2; }

if [ ! -f "$PRINTER_CFG" ]; then
  warn "WARNING: $PRINTER_CFG does not exist, so klipper has not seeded it yet."
  warn "  Don't create it by hand: klipper only seeds it when it's missing."
  warn "  Run 'systemctl restart klipper', then re-run:"
  warn "    sudo bash $0"
  exit 0
fi

# Is section [$1] in printer.cfg? A header line only: commented-out lines and
# SAVE_CONFIG's '#*#' lines don't count. "mcu" never matches [mcu octopus] or
# [mcu CB1], and "mcu octopus" never matches [mcu].
has_section() {
  local name_re=${1// /[[:space:]]+}
  grep -Eiq "^[[:space:]]*\[[[:space:]]*${name_re}[[:space:]]*\]" "$PRINTER_CFG"
}

shopt -s nullglob
m8p=("$BY_ID_DIR"/usb-Klipper_"$M8P_CHIP"_*)
octopus=("$BY_ID_DIR"/usb-Klipper_"$OCTOPUS_CHIP"_*)
unknown=()
for dev in "$BY_ID_DIR"/usb-Klipper_*; do
  case "${dev##*/}" in
    usb-Klipper_"$M8P_CHIP"_* | usb-Klipper_"$OCTOPUS_CHIP"_*) ;;
    *) unknown+=("$dev") ;;
  esac
done
shopt -u nullglob

need_m8p=1
need_octopus=1
if has_section "mcu"; then
  need_m8p=0
  say "[mcu] is already in printer.cfg; left unchanged."
fi
if has_section "mcu octopus"; then
  need_octopus=0
  say "[mcu octopus] is already in printer.cfg; left unchanged."
fi
[ "$need_m8p" -eq 0 ] && [ "$need_octopus" -eq 0 ] && exit 0

if [ "${#unknown[@]}" -gt 0 ]; then
  warn "WARNING: found Klipper USB devices that are neither the Manta M8P"
  warn "  ($M8P_CHIP) nor the Octopus V1.1 ($OCTOPUS_CHIP):"
  printf '      %s\n' "${unknown[@]}" >&2
  warn "  Not writing any MCU section. Unplug or identify those, then re-run:"
  warn "    sudo bash $0"
  warn "  or add the sections by hand in $PRINTER_CFG:"
  warn "    [mcu]          serial: <the usb-Klipper_${M8P_CHIP}_... path>"
  warn "    [mcu octopus]  serial: <the usb-Klipper_${OCTOPUS_CHIP}_... path>"
  exit 0
fi

block=""
if [ "$need_m8p" -eq 1 ]; then
  if [ "${#m8p[@]}" -eq 1 ]; then
    block+=$(printf '\n[mcu]\nserial: %s\n' "${m8p[0]}")$'\n'
    say "M8P serial set ([mcu]): ${m8p[0]}"
  elif [ "${#m8p[@]}" -eq 0 ]; then
    warn "WARNING: no Manta M8P ($M8P_CHIP) found on USB. Plug it in, then:"
    warn "  ls $BY_ID_DIR/   # find the usb-Klipper_${M8P_CHIP}_... entry"
    warn "  add [mcu] / serial: <that path> to $PRINTER_CFG"
  else
    warn "WARNING: more than one $M8P_CHIP device found on USB; pick the M8P:"
    printf '      %s\n' "${m8p[@]}" >&2
    warn "  add [mcu] / serial: <path> to $PRINTER_CFG"
  fi
fi
if [ "$need_octopus" -eq 1 ]; then
  if [ "${#octopus[@]}" -eq 1 ]; then
    block+=$(printf '\n[mcu octopus]\nserial: %s\n' "${octopus[0]}")$'\n'
    say "Octopus serial set ([mcu octopus]): ${octopus[0]}"
  elif [ "${#octopus[@]}" -eq 0 ]; then
    warn "NOTE: no Octopus V1.1 ($OCTOPUS_CHIP) found on USB, so no [mcu octopus]."
    warn "  That's expected on a machine without the plate-drawer upgrade. Once"
    warn "  its config (octopus-plates.cfg) is in use, Klipper won't start"
    warn "  without [mcu octopus]. Plug the Octopus in and re-run:"
    warn "    sudo bash $0"
  else
    warn "WARNING: more than one $OCTOPUS_CHIP device found on USB; pick the Octopus:"
    printf '      %s\n' "${octopus[@]}" >&2
    warn "  add [mcu octopus] / serial: <path> to $PRINTER_CFG"
  fi
fi
[ -n "$block" ] || exit 0

# Klipper's SAVE_CONFIG keeps its values in a '#*#' block at the end of the
# file and ignores the whole block if anything follows it, so insert above
# it. 'cat >' keeps the file's owner and mode.
if grep -q '^#\*# <-* SAVE_CONFIG -*>' "$PRINTER_CFG"; then
  tmp=$(mktemp)
  BLOCK="$block" awk '
    !done && /^#\*# <-* SAVE_CONFIG -*>/ { printf "%s\n", ENVIRON["BLOCK"]; done = 1 }
    { print }
  ' "$PRINTER_CFG" >"$tmp"
  cat "$tmp" >"$PRINTER_CFG"
  rm -f "$tmp"
else
  printf '%s' "$block" >>"$PRINTER_CFG"
fi
