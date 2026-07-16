#!/usr/bin/env bash
# Build a Tricca bootsplash.armbian using BTT's packer.
# RUN ON AN x86-64 LINUX DESKTOP (packer binary is x86-64). Needs: git, imagemagick.
# Usage: ./make-btt-bootsplash.sh path/to/tricca-logo.png
set -euo pipefail
LOGO="${1:?usage: $0 path/to/logo.png}"
WORK=$(mktemp -d)
git clone -q --depth 1 https://github.com/bigtreetech/armbian-bootlogo "$WORK/bl"
cp "$LOGO" "$WORK/bl/logo.png"   # spinner.gif kept stock: script expects exactly 75 frames
( cd "$WORK/bl" && ./create-bootsplash.sh )
cp "$WORK/bl/bootsplash.armbian" .
rm -rf "$WORK"
echo "OK: ./bootsplash.armbian — scp to the board and follow splash/README.md"
