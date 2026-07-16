#!/usr/bin/env bash
# One-time bootstrap for a fresh CB1 (Armbian, minimal image).
# Everything imperative lives HERE and only here; after this script,
# system-manager owns the machine's config.
#
# Run over ETHERNET or serial console — step 4 reconfigures wifi handling.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "run as root" >&2; exit 1; fi

REPO_DIR=/opt/cb1-autopipette

echo "==> [1/7] apt packages Nix does not manage (NM daemon + desktop binaries)"
apt-get update
apt-get install -y \
  network-manager \
  xserver-xorg xinit \
  chromium \
  curl git

echo "==> [2/7] service user"
if ! id pipette >/dev/null 2>&1; then
  adduser --system --group --home /var/lib/autopipette --shell /usr/sbin/nologin pipette
fi
usermod -aG dialout,video,input,tty pipette   # serial for klipper; video/input/tty for X on tty1

echo "==> [3/7] Determinate Nix (multi-user, flakes enabled by default)"
if ! command -v nix >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> [4/7] hand netplan ownership to system-manager"
# system-manager refuses to clobber files it doesn't own; move the stock
# config aside so modules/networking.nix can place its replacement.
if [ -f /etc/netplan/armbian.yaml ] && [ ! -L /etc/netplan/armbian.yaml ]; then
  mv /etc/netplan/armbian.yaml /root/armbian.yaml.pre-nix.bak
fi

echo "==> [5/7] first system-manager switch"
if [ ! -d "$REPO_DIR" ]; then
  echo "clone this repo to $REPO_DIR first" >&2; exit 1
fi
nix run 'github:numtide/system-manager' -- switch --flake "$REPO_DIR"

netplan apply
udevadm control --reload-rules
udevadm trigger --subsystem-match=net
systemctl restart NetworkManager

echo "==> [6/7] boot splash — Tricca logo (armbianEnv.txt/initramfs are outside system-manager's reach)"
# Two mechanisms exist depending on image generation (BTT wiki):
#   OLD (pre-v3.0.0 / kernel <5.19): bootsplash.armbian blob, packed by
#       github.com/bigtreetech/armbian-bootlogo from a logo.png
#   NEW (this image, 26.2.1 / 6.12): plymouth 'armbian' theme — replace
#       watermark.png / bgrt-fallback.png, hold the package so apt upgrades
#       don't revert the logo
LOGO=/opt/cb1-autopipette/config/tricca-logo.png   # TODO: add logo to repo
if [ -d /sys/devices/platform/bootsplash.0 ]; then
  echo "    old blob world detected — use github.com/bigtreetech/armbian-bootlogo:"
  echo "    put ${LOGO} in the repo as logo.png, run create-bootsplash.sh,"
  echo "    back up then replace /usr/lib/firmware/bootsplash.armbian, update-initramfs -u"
  sed -i 's/^bootlogo=.*/bootlogo=true/' /boot/armbianEnv.txt || echo 'bootlogo=true' >> /boot/armbianEnv.txt
else
  apt-get install -y plymouth armbian-plymouth-theme
  if [ -f "$LOGO" ]; then
    install -m 0644 "$LOGO" /usr/share/plymouth/themes/armbian/watermark.png
    install -m 0644 "$LOGO" /usr/share/plymouth/themes/armbian/bgrt-fallback.png
  fi
  apt-mark hold armbian-plymouth-theme
  # bootlogo=true is the Armbian-native switch: boot.cmd then emits
  # "splash plymouth.ignore-serial-consoles" on the kernel cmdline.
  # (bootlogo=false yields "splash=verbose" and plymouth never starts —
  # do NOT hand-manage these tokens via extraargs.)
  grep -q '^bootlogo=' /boot/armbianEnv.txt \
    && sed -i 's/^bootlogo=.*/bootlogo=true/' /boot/armbianEnv.txt \
    || echo 'bootlogo=true' >> /boot/armbianEnv.txt
  update-initramfs -u
fi

echo "==> [7/7] wifi (credentials stay off the repo — NM persists them locally)"
echo "    sudo nmcli device wifi connect \"SSID\" password \"PASS\" ifname wlan0"
echo
echo "verify: nmcli device status   # wlan0 should read 'disconnected' or 'connected'"
echo "        sudo udevadm test /sys/class/net/wlan0 2>&1 | grep -i nm_unmanaged   # expect =0"
