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
modules/klipper.nix             klipper-mcu, klipper
modules/moonraker.nix           moonraker API server + PolicyKit rules
modules/mainsail.nix            mainsail static files via nginx on :80
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
- `flash-manta` — reflash the Manta M8P V2.0's board firmware from the
  pinned Klipper source (fixes "MCU has deprecated code" drift warnings).
  Verified end-to-end on marie 2026-07-27: requests the bootloader over the
  running Klipper connection, board reboots into the STM32 ROM DFU
  (masked in silicon — a failed/interrupted write can't brick it, just
  re-run), writes via `dfu-util` at the 128KiB-bootloader offset, board
  reboots back into the new firmware automatically.

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
- **`mcu 'mcu': Unable to connect` at Klipper startup means a serial-ID
  mismatch, not a wiring/permissions problem.** The Manta's USB serial ID is
  unique per physical board, so it can never live in the shared
  `tricca-autopipette.cfg` macros file — `bootstrap.sh` now auto-detects it
  from `/dev/serial/by-id/usb-Klipper_*` and writes it into printer.cfg
  (machine-owned) instead. Check `dmesg | grep -i acm` and
  `/dev/serial/by-id/` against printer.cfg's `[mcu]` section if this recurs.
- **A Python package's `Path(__file__).parents[N]` repo-root trick breaks once
  installed.** `tricca_autopipette`'s `DefaultPaths.DIR_REPO_ROOT` assumed a
  `src/`-layout git checkout; any installed package (Nix, pip, wheel) drops
  the `src/` segment and the count comes up one directory short, with no
  `config/`/`protocols/`/`gcode/` underneath. Fixed upstream via
  `AUTOPIPETTE_REPO_ROOT` (Tricca_AutoPipette@cbd16de); `modules/tapd.nix`
  sets it to `/var/lib/autopipette`.
- **`Error during activation: EOF while parsing a value at line 1 column 0`
  while "Reading etc file definitions" means a 0-byte manifest, not a config
  error.** `wc -c` the generation's `etcFiles.json`/`services.json` under its
  store path to confirm. Cause: a build got interrupted (OOM-prone on the
  CB1's 1GB RAM) leaving Nix's local store DB marking an output "valid" when
  it's actually empty/corrupt. `nix store verify --repair` can't fix this —
  these are local-only derivations with no substituter to re-fetch from, so
  it just reports the mismatch and exits 0. The real fix is forcing a genuine
  local rebuild of the whole closure: `nix build .#systemConfigs.default
  --repair -o <path>`, then `switch` again. Verify it's *not* hardware
  bit-rot first: `dmesg` for I/O errors, and check whether the *currently
  active* generation's copies of the same files are healthy (2026-07-30
  incident: only outputs from the one bad build session were affected).
- **`switch` pins the system-manager CLI to the exact rev in `flake.lock`
  (`system-managerRev` in flake.nix), not upstream's latest.** An unpinned
  `nix run github:numtide/system-manager` floats independently of the
  system-manager *library* pinned in flake.lock (used to build the config
  the CLI activates) — a real gap, though in the 2026-07-30 incident above
  it turned out not to be the actual cause (pinning the CLI to the exact
  flake.lock rev reproduced the identical corruption).
- **Pinning the system-manager CLI rev is not enough on its own — pass
  `--accept-flake-config` too, or it silently compiles the CLI from source.**
  system-manager's own `flake.nix` declares `nixConfig.extra-substituters =
  cache.numtide.com` (prebuilt aarch64-linux binaries for the CLI, including
  its Rust build deps like `userborn`). Without `--accept-flake-config`, Nix
  refuses to trust that substituter (`warning: ignoring untrusted flake
  configuration setting`) and falls back to building the Rust CLI on-device
  instead — `rustc`/`lto1` OOM-killed `nick`'s 1GB RAM outright on first
  encounter, and on a retry caused an actual kernel panic
  (`hung_task: blocked tasks`, `mmc_sd_detect` stuck claiming the MMC host —
  the sustained heavy write I/O from unpacking hundreds of store paths wedged
  the SD card controller badly enough that `khungtaskd` gave up and panicked
  rather than hang forever). Both `bootstrap.sh` and the `switch` alias now
  pass `--accept-flake-config`; verified this pulls the CLI as a single fast
  `cache.numtide.com` fetch instead of a multi-minute local Rust build.
- **On a slow/lossy link (mobile hotspot, weak wifi), also add `--max-jobs 1
  --cores 1 --http-connections 2`.** Nix's default `http-connections = 25`
  opens up to 25 simultaneous downloads — fine on real wifi, but on a bad
  link it causes many files to fail at once (`Failed sending data to the
  peer`, `Stream error in the HTTP/2 framing layer`) and cascades into
  `Cannot build '<drv>'. Reason: 1 dependency failed.` A stalled-looking log
  (no new "copying path" line for minutes) is not necessarily hung — Nix
  only prints on a download's *error* or *completion*, so a large file (e.g.
  `rustc`, ~250MB) downloading normally over a slow link produces no output
  for a long time. Check `ps -o stat,wchan` on the switch process before
  assuming a hang: `S` (interruptible sleep) with no D-state processes means
  it's waiting on network I/O, not actually stuck.
- **PATH gaps in Nix units aren't only apt tools — our own scripts hit them
  too.** Nix-generated systemd units get a nix-store-only `PATH`; any
  absolute-path-free call is at risk, not just vendor scripts. Found in
  three places so far: kiosk-xinitrc's `xset` calls (screen blanking/DPMS/
  screensaver) silently never ran until pathed to `/usr/bin/xset` (commit
  0e0f97d); kiosk's `/etc/chromium.d/dev-shm` hook couldn't find `findmnt`,
  fixed via `path = [ pkgs.util-linux ]` (commit 201acda); moonraker's
  `preStart` polkit-rules idempotency check (`cmp`, from `diffutils`)
  silently failed every boot, rewriting the rules file unconditionally
  instead of only on change (commit 40a4f00). All three failed with no
  error anywhere. Verifying a `path = [...]` fix on an already-running
  service needs an explicit `systemctl restart <unit>` — a plain `switch`
  reloads the unit file but doesn't restart what's already running.
- **`plymouth-set-default-theme -R` can report success without rebuilding
  the initramfs.** It shells out to `update-initramfs -u -k all`, and on
  this board `-k all`'s kernel autodetection finds nothing — it exits 0
  regardless ("Nothing to do, exiting."). `splash/install-tricca-theme.sh`
  now rebuilds by exact kernel version and verifies with `lsinitramfs`
  instead of trusting the tool's exit code (commit 65b3580).
- **klippy needs an explicit `--logfile` or you get no persistent log at
  all.** With none set it just logs `WARNING:root:No log file specified!
  Severe timing issues may result!` on every start, with nothing to
  correlate against future timing anomalies. Point it at
  `/var/lib/moonraker/logs/klippy.log` — moonraker's own log dir, so
  Mainsail's log viewer picks it up too — and have `klipper.service`'s
  `preStart` create that dir itself (klipper starts before moonraker in
  unit ordering, so moonraker hasn't created its data-dir tree yet)
  (commit 9374da0).
- **A burst of klippy "Resetting prediction variance" clock resyncs on
  `klipper-mcu.service` is not a motion-timing issue.** That unit is the
  host-emulated `CB1` MCU (no real oscillator) — not the physical Manta
  board — so resyncs there carry no motion-timing risk. On a 1GB-RAM box,
  swap pressure is the likely trigger; check swap usage before chasing it
  as a hardware problem.
- **mainsail-nginx's `[alert] could not open error log file` is cosmetic
  but still worth fixing at the source.** `error_log stderr` already
  handles real logging, but nginx still tries (and fails) to open its
  default error log path if `/var/log/nginx` doesn't exist, firing the
  alert on every start. `preStart` now creates the directory (commit
  2d5bfe3).
