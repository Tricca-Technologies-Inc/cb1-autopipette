#!/usr/bin/env bash
# One-time bootstrap for a fresh CB1 (Armbian minimal, kernel >= 6.x image).
# Everything imperative lives HERE; after this script, system-manager owns
# the machine's config and `switch` is the only command you need.
#
# Run over ETHERNET or serial console — wifi handling is reconfigured below.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "run as root: sudo bash bootstrap.sh" >&2; exit 1; fi

REPO_DIR=/opt/cb1-autopipette
LOGO="$REPO_DIR/config/tricca-logo.png"

[ -d "$REPO_DIR" ] || { echo "clone this repo to $REPO_DIR first" >&2; exit 1; }

echo "==> [1/6] hostname"
CURRENT_HOST=$(hostname)
read -rp "    Machine hostname [$CURRENT_HOST]: " NEW_HOST
NEW_HOST="${NEW_HOST:-$CURRENT_HOST}"
if [ "$NEW_HOST" != "$CURRENT_HOST" ]; then
  hostnamectl set-hostname "$NEW_HOST"
  sed -i "s/\b$CURRENT_HOST\b/$NEW_HOST/g" /etc/hosts
  echo "    hostname set to $NEW_HOST (per-machine flake config hook: systemConfigs.\"$NEW_HOST\")"
fi

echo "==> [2/6] apt packages Nix does not manage (NM daemon + desktop + splash)"
apt-get update
apt-get install -y \
  network-manager \
  xserver-xorg xinit x11-xserver-utils \
  chromium \
  plymouth plymouth-themes armbian-plymouth-theme \
  imagemagick \
  curl git

echo "==> [3/6] service user"
if ! id pipette >/dev/null 2>&1; then
  adduser --system --group --home /var/lib/autopipette --shell /usr/sbin/nologin pipette
fi
usermod -aG dialout,video,input,tty pipette   # serial for klipper; video/input/tty for X on tty1

echo "==> [4/6] Determinate Nix (multi-user, flakes enabled by default)"
if ! command -v nix >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> [5/6] first system-manager switch"
# (netplan takeover is handled declaratively: replaceExisting=true backs up
#  any stock armbian.yaml to armbian.yaml.system-manager-backup)
nix run 'github:numtide/system-manager' -- switch --flake "$REPO_DIR"
netplan apply
udevadm control --reload-rules
udevadm trigger --subsystem-match=net
systemctl restart NetworkManager

echo "==> [6/6] boot splash (armbianEnv.txt/initramfs live in /boot — outside system-manager's reach)"
# Owned 'tricca' plymouth theme: watermark + throbber below it. Rebuilds the
# initramfs. Legacy blob-based images (kernel <5.19) are documented in
# splash/README.md but not supported by this script.
bash "$REPO_DIR/splash/install-tricca-theme.sh" "$LOGO"
# Debian's plymouth-quit units kill the splash at multi-user — before the
# kiosk's retain-splash handoff — exposing console text. Mask them: the
# kiosk service is the only thing allowed to end the splash.
systemctl mask plymouth-quit.service plymouth-quit-wait.service
# bootlogo=true makes Armbian's boot.cmd emit "splash plymouth.ignore-serial-consoles"
# (bootlogo=false yields "splash=verbose" and plymouth never starts).
grep -q '^bootlogo=' /boot/armbianEnv.txt \
  && sed -i 's/^bootlogo=.*/bootlogo=true/' /boot/armbianEnv.txt \
  || echo 'bootlogo=true' >> /boot/armbianEnv.txt
# Clean panel: boot console to serial only, quiet kernel. Local debugging is
# then SSH/serial-only — deliberate trade for a kiosk appliance.
grep -q '^console=' /boot/armbianEnv.txt \
  && sed -i 's/^console=.*/console=serial/' /boot/armbianEnv.txt \
  || echo 'console=serial' >> /boot/armbianEnv.txt
grep -q '^extraargs=' /boot/armbianEnv.txt \
  || echo 'extraargs=quiet loglevel=0' >> /boot/armbianEnv.txt

echo
echo "Bootstrap done. Remaining per-machine steps:"
echo "  1. wifi:   sudo nmcli device wifi connect \"SSID\" password \"PASS\" ifname wlan0"
echo "             (persists in NetworkManager; credentials never enter the repo)"
echo "  2. MCU:    set the Manta serial ID via Mainsail's config editor after first boot"
echo "  3. reboot, then log in again — shell helpers (switch, splash-preview, ...) load"
echo "             from /etc/profile.d/tricca-aliases.sh; see README 'Shell helpers'"
echo
echo "verify: nmcli device status   # wlan0 should read 'disconnected' or 'connected'"
