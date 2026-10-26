# Board-selection logic for the flash helpers (modules/aliases.nix), kept
# as standalone scripts so CI can run them against a fake
# /dev/serial/by-id and fake printer.cfg files (checks.mcu-select in
# flake.nix) instead of only ever being exercised on real hardware.
#
# Why this matters: a CB1 with the axis expansion sees TWO Klipper USB MCUs
# -- the Manta M8P (usb-Klipper_stm32h723xx_*) and the Octopus V1.1
# (usb-Klipper_stm32f446xx_*) -- and both drop into the very same STM32
# ROM DFU ID (0483:df11) when asked to. Writing one board's image at the
# other's offset is the failure every check below exists to prevent
# (issue #50).
#
# Every tool is called by absolute store path: these run from login-shell
# helpers and under sudo, where PATH is not something to rely on.
{ pkgs }:
let
  awk = "${pkgs.gawk}/bin/awk";
  coreutils = "${pkgs.coreutils}/bin";
  grep = "${pkgs.gnugrep}/bin/grep";
in
rec {
  # klipper-cfg-serial <printer.cfg> <section name>
  # Prints the `serial:` value of exactly one [<section name>] section.
  # Exit 2: section missing. 3: section appears more than once. 4: section
  # has no (or an empty) serial. Section headers and keys are only
  # recognised at column 0: Klipper treats an indented line as a
  # continuation of the previous value, so an indented "serial:" (inside a
  # gcode block, say) is not a key. `#*#` SAVE_CONFIG lines start with `#`
  # and are ignored like any other comment.
  klipperCfgSerial = pkgs.writeShellScript "klipper-cfg-serial" ''
    set -u
    [ -r "$1" ] || { echo "Can't read $1" >&2; exit 1; }
    exec ${awk} -v want="$2" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
      /^\[/ {
        h = $0; sub(/^\[/, "", h); sub(/\].*$/, "", h)
        h = trim(h); gsub(/[ \t]+/, " ", h)
        insec = (h == want)
        if (insec) nsec++
        next
      }
      insec && tolower($0) ~ /^serial[ \t]*[:=]/ {
        v = $0; sub(/^[^:=]*[:=]/, "", v); sub(/[#;].*$/, "", v)
        if (!got) { serial = trim(v); got = 1 }
      }
      END {
        if (nsec == 0) exit 2
        if (nsec > 1) exit 3
        if (serial == "") exit 4
        print serial
      }' "$1"
  '';

  # manta-serial [by-id dir, default /dev/serial/by-id]
  # Prints the single Manta M8P (STM32H723) Klipper device. Refuses on zero
  # or more than one match. Matches the chip name, never a bare
  # usb-Klipper_* -- an Octopus (stm32f446xx) present at the same time is
  # never selected; checks.mcu-select proves it.
  mantaSerial = pkgs.writeShellScript "manta-serial" ''
    set -u
    dir="''${1:-/dev/serial/by-id}"
    shopt -s nullglob
    devs=("$dir"/usb-Klipper_stm32h723xx_*)
    if [ "''${#devs[@]}" -eq 0 ]; then
      echo "No Manta M8P (usb-Klipper_stm32h723xx_*) found on USB. Is it plugged in and powered?" >&2
      exit 1
    elif [ "''${#devs[@]}" -gt 1 ]; then
      echo "Multiple Manta-type (STM32H723) Klipper MCUs found -- not sure which is the Manta:" >&2
      printf '  %s\n' "''${devs[@]}" >&2
      exit 1
    fi
    echo "''${devs[0]}"
  '';

  # octopus-serial <printer.cfg>
  # Prints the Octopus V1.1's device path, read from the exact `serial:` in
  # printer.cfg's [mcu octopus] section -- never a glob, so a second
  # F446 board on the bus can't be picked by accident. Refuses unless that
  # path is present, is named as an STM32F446 Klipper device, and isn't the
  # same device as the main [mcu] (the Manta).
  octopusSerial = pkgs.writeShellScript "octopus-serial" ''
    set -u
    cfg="$1"
    serial=$(${klipperCfgSerial} "$cfg" "mcu octopus")
    case $? in
      0) ;;
      2) echo "No [mcu octopus] section in $cfg -- refusing (nothing to flash)." >&2; exit 1 ;;
      3) echo "More than one [mcu octopus] section in $cfg -- refusing." >&2; exit 1 ;;
      4) echo "[mcu octopus] in $cfg has no serial: -- refusing." >&2; exit 1 ;;
      *) echo "Couldn't read [mcu octopus] from $cfg -- refusing." >&2; exit 1 ;;
    esac
    case "$(${coreutils}/basename -- "$serial")" in
      usb-Klipper_stm32f446xx_*) ;;
      *)
        echo "[mcu octopus] serial is $serial, which is not an STM32F446" >&2
        echo "Klipper device (usb-Klipper_stm32f446xx_*) -- refusing." >&2
        exit 1
        ;;
    esac
    if [ ! -e "$serial" ]; then
      echo "$serial (from [mcu octopus]) isn't present. Is the Octopus plugged in and powered?" >&2
      exit 1
    fi
    if main=$(${klipperCfgSerial} "$cfg" "mcu" 2>/dev/null); then
      if [ "$main" = "$serial" ] ||
        [ "$(${coreutils}/readlink -f -- "$main")" = "$(${coreutils}/readlink -f -- "$serial")" ]; then
        echo "[mcu octopus] and [mcu] in $cfg point at the same device ($serial) -- refusing." >&2
        exit 1
      fi
    fi
    echo "$serial"
  '';

  # stm32-dfu-count: reads `dfu-util --list` output on stdin, prints how
  # many distinct STM32 ROM DFU devices (0483:df11) it shows. dfu-util
  # prints one line per alt setting (Internal Flash, Option Bytes, OTP,
  # ...), so one board is several lines -- count distinct USB paths, not
  # lines.
  stm32DfuCount = pkgs.writeShellScript "stm32-dfu-count" ''
    ${grep} -F '[0483:df11]' | ${grep} -o 'path="[^"]*"' | ${coreutils}/sort -u | ${coreutils}/wc -l
  '';
}
