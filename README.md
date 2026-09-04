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
prime.sh                        WORKSTATION-side: build + push a closure to a machine, see below
.github/workflows/ci.yml        builds systemConfigs.default + packages for real, required on main
modules/base.nix                platform + shared packages
modules/networking.nix          udev rule + netplan replacement (replaceExisting)
modules/klipper.nix             klipper-mcu, klipper
modules/moonraker.nix           moonraker API server + PolicyKit rules
modules/mainsail.nix            mainsail static files via nginx on :80
modules/autopipette.nix         FastAPI backend on :8000
modules/kiosk.nix               chromium kiosk on tty1; splash handoff
modules/aliases.nix             shell helpers in /etc/profile.d (fleet-wide)
modules/nix-settings.nix        trusted-users grant for prime.sh's push (see below)
pkgs/tricca-autopipette.nix     python package from tricca-src
config/moonraker.conf           nix-managed, read-only
config/klipper-host-mcu.config  Kconfig for the on-board host MCU build
config/tricca-logo.png          splash watermark source
splash/                         theme installer + splash documentation
docs/adr/                       architecture decision records
docs/incidents/                 past debugging write-ups (see docs/incidents/README.md)
docs/machines/                  live per-machine status (see docs/machines/README.md)
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
- `flash-manta` — reflash the Manta M8P V2.0's board firmware from the
  pinned Klipper source (fixes "MCU has deprecated code" drift warnings).
  Verified end-to-end on marie 2026-07-27: requests the bootloader over the
  running Klipper connection, board reboots into the STM32 ROM DFU
  (masked in silicon — a failed/interrupted write can't brick it, just
  re-run), writes via `dfu-util` at the 128KiB-bootloader offset, board
  reboots back into the new firmware automatically.

## Updating machines after an app change

The app itself (`tricca_autopipette` / `autopipette_kiosk`) lives in the
separate `Tricca_AutoPipette` repo, pinned here as the `tricca-src` flake
input. A change there doesn't reach any machine until its pin is bumped and
that's switched in:

1. **On a workstation**, in this repo: `nix flake update tricca-src`
   (or plain `nix flake update` to pick up everything). Commit
   `flake.lock`, push, PR, merge to `main` — branch protection requires the
   CI build (`.github/workflows/ci.yml`) to pass first.
2. **On the machine**: `git pull` in `/opt/cb1-autopipette` (changes nothing
   by itself — see CONTEXT.md's **Switch** entry), then either:
   - **Good internet**: just `switch`. It builds `systemConfigs.default` and
     fetches whatever it needs on-device.
   - **Wifi/hotspot too slow or unreliable** (`marie`, `nick` — no ethernet
     option on either): **prime first**. From the same workstation checkout,
     same network as the machine (wifi or hotspot both work, doesn't need to
     be ethernet — just the same local network, not routed over the
     internet):
     ```
     ./prime.sh <machine-hostname-or-ip>
     ```
     Builds `systemConfigs.default` locally and pushes the closure straight
     into the machine's Nix store over SSH. Then `switch` on the machine as
     normal — it finds the build already done and just activates it. See
     [ADR-0009](docs/adr/0009-prime-workstation-build-push.md) and
     CONTEXT.md's **Prime** entry.

     One-time workstation setup `prime.sh` needs and checks for itself:
     ```
     sudo apt-get install -y qemu-user-static binfmt-support
     echo 'extra-platforms = aarch64-linux' | sudo tee -a /etc/nix/nix.custom.conf
     sudo systemctl restart nix-daemon
     ```
     The machine side of the trust needed for the push (`nix.settings.trusted-users`
     for the `tricca` account) ships declaratively via
     `modules/nix-settings.nix` — nothing to set up by hand there, it's live
     after that module's first `switch`.

Moonraker's update_manager is intentionally absent — this pull+prime+switch
flow is the only update path, deliberately.

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

## Troubleshooting

Short, evergreen gotchas — things worth knowing before you go debug from
scratch. Past incidents (root-cause forensics, dates, commit-by-commit
walkthroughs) live in [`docs/incidents/`](docs/incidents/) instead; check
there for the full story behind any of these, or if a new issue doesn't
match anything below.

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
- **`mcu 'mcu': Unable to connect` at Klipper startup means a serial-ID
  mismatch, not a wiring/permissions problem.** The Manta's USB serial ID is
  unique per physical board, so it can never live in the shared
  `tricca-autopipette.cfg` macros file — `bootstrap.sh` auto-detects it from
  `/dev/serial/by-id/usb-Klipper_*` and writes it into printer.cfg
  (machine-owned) instead. Check `dmesg | grep -i acm` and
  `/dev/serial/by-id/` against printer.cfg's `[mcu]` section if this recurs.
- **`Error during activation: EOF while parsing a value at line 1 column 0`
  while "Reading etc file definitions" means a 0-byte manifest** (an
  interrupted build left a corrupt output), not a config error. Fix:
  `nix build .#systemConfigs.default --repair -o <path>`, then `switch`
  again. Full forensics:
  [2026-07-30 incident](docs/incidents/2026-07-30-oom-corruption-kernel-panic.md).
- **`switch` always needs `--accept-flake-config`** (the `switch` helper and
  `bootstrap.sh` already pass it) — without it, Nix rejects
  system-manager's own binary-cache substituter and silently compiles its
  Rust CLI from source on-device instead, which has caused both an OOM-kill
  and a kernel panic on a 1GB-RAM machine. Also pins the CLI to the exact
  rev in `flake.lock` (`system-managerRev` in `flake.nix`), not upstream's
  latest, so it can't drift out of sync with the pinned system-manager
  *library* used to build the config it activates. Full story:
  [2026-07-30 incident](docs/incidents/2026-07-30-oom-corruption-kernel-panic.md).
- **On a slow/lossy link (mobile hotspot, weak wifi), also add `--max-jobs 1
  --cores 1 --http-connections 2`** (also already in the `switch` helper).
  Nix's default `http-connections = 25` opens up to 25 simultaneous
  downloads — fine on real wifi, but on a bad link it causes many files to
  fail at once and cascades into `Cannot build '<drv>'. Reason: 1 dependency
  failed.` A stalled-looking log (no new "copying path" line for minutes) is
  not necessarily hung — Nix only prints on a download's *error* or
  *completion*. Check `ps -o stat,wchan` on the switch process before
  assuming a hang: `S` (interruptible sleep) with no D-state processes means
  it's waiting on network I/O, not actually stuck.
- **PATH gaps in Nix units aren't only apt tools — our own scripts hit them
  too.** Nix-generated systemd units get a nix-store-only `PATH`; any call
  to a binary by bare name (not an absolute path or a declared `path =
  [...]`) is at risk, and fails with no error anywhere. Worked examples:
  [nix-store-path-gaps.md](docs/incidents/nix-store-path-gaps.md).
  Verifying a fix on an already-running service needs an explicit
  `systemctl restart <unit>` — a plain `switch` reloads the unit file but
  doesn't restart what's already running.
- **A burst of klippy "Resetting prediction variance" clock resyncs on
  `klipper-mcu.service` is not a motion-timing issue.** That unit is the
  host-emulated `CB1` MCU (no real oscillator) — not the physical Manta
  board — so resyncs there carry no motion-timing risk. On a 1GB-RAM box,
  swap pressure is the likely trigger; check swap usage before chasing it
  as a hardware problem.
- **A large `switch` (e.g. a multi-week jump on `nick`) can wedge the whole
  machine, not just the build** — this is an active, only-partially-solved
  problem specific to low-RAM/SD-card machines, not a quick gotcha. See
  [nick's generation-8 upgrade history](docs/incidents/nick-generation-8-upgrade.md)
  for the full mitigation stack (dirty-page tuning, stopping the kiosk
  first, throttled builds) before attempting one.
