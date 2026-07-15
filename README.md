# Tricca AutoPipette — CB1 machine configuration

Declarative configuration for a BIGTREETECH CB1 (Armbian) driving a Klipper
pipette gantry (Manta M8P V2.0), exposed to non-technical users through a
Chromium kiosk.

## Architecture

Armbian stays the base OS (the CB1 has no NixOS image and vendor blobs like
bootsplash-packer live in apt-land). On top of it:

| Layer | Owner | Why |
|---|---|---|
| Kernel, bootloader, Plymouth daemon | Armbian / apt | board support |
| NetworkManager daemon, Xorg, Chromium | apt (`bootstrap.sh`) | tight D-Bus/polkit/driver coupling to the host distro |
| **Everything else** — udev rules, netplan, klipper, moonraker, mainsail, nginx, the AutoPipette app, all systemd units | **Nix flake via [system-manager](https://github.com/numtide/system-manager)** | pinned by `flake.lock`, reproducible, rollbackable |

system-manager is officially supported on Ubuntu/Debian; Armbian Trixie is
Debian-based and works, but it is not an officially tested target — if a
switch misbehaves, that's the first thing to suspect.

Why not KIAUH: KIAUH is an interactive installer (git clones + venvs + apt).
Fine for one hobby printer, but every machine drifts. Here `flake.lock` *is*
the machine spec; replicating a unit is `bootstrap.sh` + `switch`.

## Repo layout

```
flake.nix                    inputs (nixpkgs, system-manager), systemConfigs.default
bootstrap.sh                 ALL imperative steps, run once per machine
modules/base.nix             platform + shared packages
modules/networking.nix       cb1-wifi-fix.md, declaratively (udev + netplan)
modules/klipper.nix          klipper, moonraker, mainsail(nginx) services
modules/autopipette.nix      FastAPI backend service (:8000)
modules/kiosk.nix            chromium kiosk on tty1, waits for backend
pkgs/tricca-autopipette.nix  python package (scaffold — see TODOs)
config/klipper-host-mcu.config  Kconfig for the on-board host MCU build
(printer.cfg & includes seed from the pinned Tricca_Autopipette_Configs input)
config/moonraker.conf        nix-managed, read-only
```

## Replicating a machine

1. Flash Armbian (minimal) to the CB1, boot with **ethernet**.
2. `git clone <this repo> /opt/cb1-autopipette`
3. `sudo bash /opt/cb1-autopipette/bootstrap.sh`
4. Connect wifi (once; credentials never enter the repo):
   `sudo nmcli device wifi connect "SSID" password "PASS" ifname wlan0`
5. Flash Klipper firmware to the Manta M8P (unchanged from stock Klipper
   docs — MCU flashing is outside Nix's scope), set the serial ID via
   Mainsail's config editor (or in the Tricca_Autopipette_Configs repo).
6. Reboot. Boot chain: Plymouth splash → klipper → moonraker → autopipette →
   kiosk polls :8000 → splash quits → Chromium fullscreen.

Mainsail (maintenance UI): `http://<cb1>` port 80. AutoPipette UI: port 8000.

## Day-2 operations

```bash
# apply config changes
sudo -i nix run 'github:numtide/system-manager' -- switch --flake /opt/cb1-autopipette

# update pinned klipper/moonraker/mainsail/app versions
nix flake update && git commit flake.lock   # then switch

# never build on the CB1 (1 GB RAM) — build on a desktop and push:
nix build .#tricca-autopipette --system aarch64-linux   # needs qemu binfmt or aarch64 remote builder
nix copy --to ssh://cb1 ./result
```

Moonraker's `update_manager` is intentionally absent — updates flow through
`flake.lock`, so a fleet of machines can be byte-identical.

## Known sharp edges

- `pkgs/tricca-autopipette.nix` is a scaffold: `src`, deps, and the console
  script entrypoint must match the real pyproject before first build.
- Verify nixpkgs binary names once (`nix build nixpkgs#klipper && ls result/bin`);
  service `ExecStart`s assume `klippy` and `moonraker`.
- `printer.cfg` is seeded once and then mutable (SAVE_CONFIG). Machines
  diverge there by design; re-seed by deleting `/var/lib/moonraker/config/printer.cfg`.
- Wifi driver name in the udev rule is `rtl8189fs` — letter "l", not digit
  "1". New board revisions: confirm with
  `udevadm info -q property /sys/class/net/wlan0 | grep ID_NET_DRIVER`.
