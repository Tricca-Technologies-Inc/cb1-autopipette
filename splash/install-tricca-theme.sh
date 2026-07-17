#!/usr/bin/env bash
# Fork the armbian plymouth theme (two-step plugin) into a Tricca-owned theme:
# custom watermark, throbber positioned BELOW the logo. Run ON THE BOARD as root.
# Re-runnable: rebuilds the tricca theme from the pristine armbian one each time.
#
# Usage: sudo ./install-tricca-theme.sh [path/to/tricca-logo.png]
# Tune, re-run, and preview WITHOUT rebooting:
#   systemctl stop kiosk
#   plymouthd && plymouth --show-splash && sleep 5 && plymouth quit
#   systemctl start kiosk
set -euo pipefail

LOGO_V=".42"      # WatermarkVerticalAlignment: logo center, fraction of screen height
THROB_V=".68"     # VerticalAlignment: throbber center — below the logo
LOGO_WIDTH=""     # optional: resize logo to this pixel width (needs imagemagick);
                  # leave empty to use the PNG as-is (pre-size it in an editor).
                  # Panel resolution: cat /sys/class/graphics/fb0/virtual_size

SRC=/usr/share/plymouth/themes/armbian
DST=/usr/share/plymouth/themes/tricca
LOGO="${1:-}"

[ -d "$SRC" ] || { echo "armbian theme missing — apt install armbian-plymouth-theme" >&2; exit 1; }
rm -rf "$DST"
cp -r "$SRC" "$DST"
mv "$DST/armbian.plymouth" "$DST/tricca.plymouth"

sed -i 's|^Name=.*|Name=Tricca|' "$DST/tricca.plymouth"
sed -i "s|$SRC|$DST|g" "$DST/tricca.plymouth"       # ImageDir etc.

set_key() { # set_key KEY VALUE — replace if present, else append under [two-step]
  if grep -q "^$1=" "$DST/tricca.plymouth"; then
    sed -i "s|^$1=.*|$1=$2|" "$DST/tricca.plymouth"
  else
    sed -i "/^\[two-step\]/a $1=$2" "$DST/tricca.plymouth"
  fi
}
set_key WatermarkHorizontalAlignment .5
set_key WatermarkVerticalAlignment "$LOGO_V"
set_key HorizontalAlignment .5
set_key VerticalAlignment "$THROB_V"

if [ -n "$LOGO" ] && [ -f "$LOGO" ]; then
  if [ -n "$LOGO_WIDTH" ] && command -v convert >/dev/null 2>&1; then
    convert "$LOGO" -resize "''${LOGO_WIDTH}x" "$DST/watermark.png"
  else
    install -m 0644 "$LOGO" "$DST/watermark.png"
  fi
  cp "$DST/watermark.png" "$DST/bgrt-fallback.png"
fi

plymouth-set-default-theme -R tricca
echo "tricca theme installed and initramfs rebuilt — reboot (or live-preview) to see it"
