# Tricca AutoPipette — CB1 machine configuration

Declarative configuration for a BIGTREETECH CB1 (Armbian) driving a Klipper
pipette gantry (Manta M8P V2.0), exposed to non-technical users through a
Chromium kiosk with a Tricca boot splash.

## Architecture

Armbian stays the base OS. On top of it:

| Layer | Owner | Why |
|---|---|---|
| Kernel, bootloader, initramfs, splash theme install | Armbian / apt / bootstrap | board support; /boot is outside system-manager's reach |
| NetworkManager daemon, Xorg, Chromium, plymouth | apt (`bootstrap.sh`) | tight distro coupling; security updates via apt |
| Everything else — netplan, udev, klipper (+ host MCU), moonraker, mainsail, nginx, the AutoPipette app, kiosk, shell helpers | Nix flake via [system-manager](https://github.com/numtide/system-manager) | pinned by `flake.lock`, reproducible, rollbackable |

Pinned inputs: `nixpkgs`, `system-manager`, `tricca-src` (the AutoPipette app
repo) and `printer-cfgs` (the Klipper configs repo). `flake.lock` is the
machine spec; commit it always.

## Repo layout

```
flake.nix                       inputs + systemConfigs.default
bootstrap.sh                    ALL imperative steps; run once per machine (interactive)
modules/base.nix                platform + shared packages
modules/networking.nix          udev rule + netplan replacement (replaceExisting)
modules/klipper.nix             klipper-mcu, klipper, moonraker, mainsail(nginx)
modules/autopipette.nix         FastAPI backend on :8000
modules/kiosk.nix               chromium kiosk on tty1; splash handoff
modules/aliases.nix             shell helpers in /etc/profile.d (fleet-wide)
pkgs/tricca-autopipette.nix     python package from tricca-src
config/moonraker.conf           nix-managed, read-only
config/klipper-host-mcu.config  Kconfig for the on-board host MCU build
config/tricca-logo.png          splash watermark source
splash/                         theme installer + splash documentation
```

Klipper's `printer.cfg` (+ `mainsail.cfg`, `tricca-autopipette.cfg`) seed
ONCE from the pinned `printer-cfgs` input into `/var/lib/moonraker/config/`,
then belong to the machine: SAVE_CONFIG and Mainsail's editor rewrite them
there. Re-seed by deleting the file and restarting klipper.

## Replicating a machine

1. Flash Armbian minimal (kernel >= 6.x) to the CB1; first boot on **ethernet**;
   complete Armbian's firstrun wizard.
2. `sudo git clone <this repo> /opt/cb1-autopipette`
3. `sudo bash /opt/cb1-autopipette/bootstrap.sh` — prompts for hostname, then
   installs apt packages, the `pipette` user, Nix, runs the first switch, and
   installs the splash. Expect the first switch to download closures and
   compile the small host-MCU firmware.
4. Per-machine steps the script prints at the end: wifi via `nmcli` (credentials
   never enter the repo), MCU serial ID via Mainsail, reboot.

Boot chain: u-boot → Tricca splash (throbber below logo) → services
(klipper-mcu → klipper → moonraker → autopipette) → kiosk waits for :8000 →
splash retained until Chromium paints. Mainsail on port 80.

## Day-2 operations — shell helpers

Defined in `modules/aliases.nix`, landed at `/etc/profile.d/tricca-aliases.sh`
on every machine (log out/in after the first switch to pick them up):

- `switch` — apply the flake to this machine (the only deploy command)
- `splash-preview [secs]` — stop kiosk, show the splash, restore the kiosk
- `ap-status` — status of the whole stack
- `logs [unit]` — follow a unit's journal (default: autopipette)
- `ap-restart` — restart klipper/moonraker/autopipette/kiosk after config edits
- `gc` — delete Nix generations older than 30 days (SD-card hygiene)

Updating pinned software: `nix flake update` (or `nix flake update tricca-src`
for just the app) on a desktop, commit `flake.lock`, push, `switch` on each
machine. Moonraker's update_manager is intentionally absent.

Building the app off-board: `nix build .#tricca-autopipette --system
aarch64-linux` needs qemu binfmt or an aarch64 remote builder on x86-64;
`nix copy --to ssh://<host> ./result` needs your ssh user in the CB1's
`trusted-users` and both ends on the same committed `flake.lock`. The CB1
builds the pure-Python package itself in seconds during `switch`, so this
path is only for heavyweight cache misses.

## apt vs Nix, and kernel updates

The Nix half is pinned; the apt half (kernel, NM, Xorg, Chromium, plymouth)
follows Debian/Armbian. Kernel updates are taken deliberately for security
but treated as maintenance events: run them, reboot promptly, and verify
wifi (`nmcli device status` — the rtl8189fs driver is the likely casualty),
the stack (`ap-status`), and the kiosk. The previous kernel remains bootable
from u-boot if a regression bites.

## Per-machine state (never in the repo)

hostname · wifi credentials (NetworkManager) · Manta MCU serial ID ·
SAVE_CONFIG calibration values · TLS/tailscale identities if added.
Everything else must come from this repo — if a machine works and the repo
doesn't say why, that's a bug in the repo.

## Field notes (hard-won)

- **If the failing drv hash didn't change, Nix didn't see your change.**
  Check `git status` — with a git-based flake, uncommitted/unpulled state
  (including `flake.lock`) is the usual cause.
- **A clean switch means "applied what it owns", not "machine matches repo".**
  Grep switch output for `WARN` — a skipped etc file is a warning, not an error.
- **`sudo nix` fails; `sudo -i nix` works** (secure_path strips the Nix profile).
  The `switch` helper does this for you.
- **`nix build` printing nothing means cached success**, not a hang:
  `--print-out-paths` to confirm.
- **Nix builds from a root-owned `/opt` repo require root** (libgit2 ownership
  check); keep the repo root-owned and use the helpers.
- **`warning: unknown setting 'eval-cores'/'lazy-trees'`** — harmless
  Determinate-Nix settings read by upstream Nix components.
