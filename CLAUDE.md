# CLAUDE.md — Tricca AutoPipette CB1 deployment

Declarative deployment for BIGTREETECH CB1 (Armbian) lab machines running the
Tricca AutoPipette: a Klipper pipette gantry (Manta M8P V2.0) driven by a
FastAPI backend, presented to non-technical users via a Chromium kiosk on the
machine's touchscreen. This repo IS the machine spec; the conversation that
built it doubles as design history, and README.md is the operator doc.

## The three repos

| Repo | Role | Pinned as |
|---|---|---|
| this one (`/opt/cb1-autopipette` on machines) | system config: flake + modules + bootstrap | — |
| `Tricca-Technologies-Inc/Tricca_AutoPipette` | Python app: `tricca_autopipette` (cmd2 shell, `tap` script) + `autopipette_kiosk` (FastAPI, port 8000) | flake input `tricca-src` |
| `Tricca-Technologies-Inc/Tricca_Autopipette_Configs` | printer.cfg + mainsail.cfg + tricca-autopipette.cfg macros | flake input `printer-cfgs` |

## Architecture (do not re-litigate)

- Armbian base + apt for: kernel, NetworkManager, Xorg, Chromium, plymouth.
  Kernel updates are TAKEN (owner's security requirement), treated as
  maintenance events with a verification reboot.
- Everything else is Nix via numtide/system-manager (`systemConfigs.default`;
  per-machine hook: `systemConfigs."<hostname>"`). Services: klipper-mcu
  (host MCU, same pinned src as klippy), klipper, moonraker, mainsail-nginx
  (:80), tapd (control daemon, owns the Moonraker connection), autopipette
  (:8000, thin kiosk client of tapd's control-plane websocket), kiosk, plus
  /etc files and shell helpers.
- tapd (from tricca-src) is a long-running control daemon holding the single
  persistent Moonraker connection; `tap` (interactive shell) and the kiosk
  are both thin clients of its control-plane websocket
  (ws://127.0.0.1:8765/control) instead of talking to Moonraker or spawning
  subprocesses themselves. Needs `AUTOPIPETTE_REPO_ROOT=/var/lib/autopipette`
  (modules/tapd.nix) since tricca_autopipette's path defaults assume a
  src-layout checkout, which breaks for any installed package.
- tty2 is a debug console (modules/tricca-console.nix): Ctrl+Alt+F2
  autologs in as `tricca` (the existing admin/SSH account, no password) and
  execs `tap` instead of a normal shell — a fast path back to control if
  the kiosk (tty1) is misbehaving. Deliberately NOT done by changing
  tricca's `/etc/passwd` shell (that would hijack SSH logins on the same
  account too); instead a profile.d script execs tap only when the tty is
  a physical console (tty2+), never a pts/SSH session. tty1 stays
  kiosk-only; if the kiosk dies and getty@tty1 comes back, that login is
  left as a normal shell (recovery path).
- Manta M8P V2.0 board firmware (STM32H723) drifts from the host's pinned
  Klipper version over time ("MCU has deprecated code" warnings) since it's
  flashed once and never auto-updated. `mantaFirmware` (flake.nix) builds a
  correct binary from the same pinned source; `flash-manta` (shell helper)
  flashes it via the board's STM32 ROM DFU bootloader (masked in silicon —
  can't be bricked by a bad write).
- printer.cfg seeds ONCE from printer-cfgs into /var/lib/moonraker/config/,
  then is machine-owned (SAVE_CONFIG + Mainsail editor rewrite it).
- Wifi: NetworkManager persistent profile, created manually per machine.
  Credentials never enter the repo. netplan is nix-owned (replaceExisting).
- Boot: black → tricca plymouth theme (logo, throbber below) → logo holds
  (plymouth-quit units neutralized; kiosk pre-script quits with
  --retain-splash) → sub-second white blink → kiosk. The white blink is
  Chromium X11 window-clear; ALL mitigations were tested and exhausted
  (flags, dark first-paint, Wayland/cage). Owner has closed this. Do not
  reopen splash/flash work unless explicitly asked.

## Commands

- Deploy to a machine: `switch` (shell helper) =
  `sudo -i nix run "github:numtide/system-manager/<rev>" -- switch --flake /opt/cb1-autopipette`
  — `<rev>` is generated from `flake.lock`'s pinned `system-manager` input
  (flake.nix's `system-managerRev`), NOT floating to upstream's latest. An
  unpinned CLI invocation drifts out of sync with the system-manager
  LIBRARY pinned in flake.lock (used to build the config the CLI
  activates) — this bit us 2026-07-30, see README field notes.
- Helpers (modules/aliases.nix → /etc/profile.d): `switch`,
  `splash-preview [s]`, `ap-status`, `logs [unit]`, `ap-restart`, `gc`,
  `flash-manta` (reflash the Manta board firmware, see Architecture)
- Update pins: on a WORKSTATION only — `nix flake update [tricca-src|printer-cfgs|system-manager]`,
  commit flake.lock, push; machines `git pull && switch`. Never edit the
  lock on a machine.
- New machine: flash Armbian minimal (kernel ≥6.x), ethernet,
  `sudo bash bootstrap.sh` (interactive: hostname), then wifi via nmcli,
  MCU serial via Mainsail, reboot.

## Hard-won rules (violating these cost real debugging days)

1. Nix-generated units have nix-store-only PATH. Call apt binaries by
   ABSOLUTE path (/usr/bin/plymouth, iproute2 via `path = [...]`).
   `command -v` guards fail silently; `|| true` hides it.
2. If a failing derivation hash didn't change, Nix didn't see the change —
   check git status / flake.lock, not the code.
3. A clean switch ≠ machine matches repo. Grep switch output for WARN
   (skipped etc files are warnings).
4. `sudo nix` fails (secure_path); use `sudo -i nix` with explicit
   `--flake /opt/...` since -i lands in /root.
5. Silent `nix build` = cached success (`--print-out-paths` to confirm).
6. Repo on machines is root-owned; libgit2 refuses cross-user reads —
   operate as root there.
7. /boot (armbianEnv.txt, initramfs) is OUTSIDE system-manager — only
   bootstrap.sh or manual commands touch it. Current settings:
   bootlogo=true, console=serial, extraargs=quiet loglevel=0.
8. Never build heavyweight packages on the CB1 (1 GB RAM). Pure-Python app
   builds on-board in seconds; anything compiled comes from cache or a
   desktop (qemu binfmt) + `nix copy` (needs trusted-users + same lock).
9. Python is 3.14 (nixpkgs-unstable default); pyproject says >=3.12.
   opencv-python is satisfied by nixpkgs opencv4 via pythonRemoveDeps.
10. `environment.etc` always creates a symlink into the Nix store.
    `polkitd` (and possibly other daemons that scan a directory for
    config-like files) silently SKIPS symlinks — no error, it just never
    gets read. If a file placed via `environment.etc` doesn't seem to take
    effect and there's no error anywhere, suspect this first; install it via
    a `preStart` copy (`cp`, not `ln -s`) instead.
11. PolicyKit's `subject.isInGroup()` checks the user ACCOUNT's static
    `/etc/group` membership (NSS), not a process-level systemd
    `SupplementaryGroups=` grant. A service-scoped supplementary group
    (granted to one unit, not the user account) is invisible to
    `isInGroup()` — use the `/proc/<pid>/status`-grep technique instead
    (see Moonraker's own `scripts/set-policykit-rules.sh` for the pattern
    modules/klipper.nix now follows).

## Current machine

`marie` — Armbian 26.5.1 trixie, kernel 6.18.33-current-sunxi64, all
services green (klipper-mcu, klipper, moonraker, tapd, autopipette, kiosk,
mainsail-nginx). Manta M8P V2.0 firmware reflashed 2026-07-28 to match the
pinned Klipper source (was severely behind — v0.11.0 firmware against a
0.13.0-unstable host). PolicyKit fully configured (Mainsail's
reboot/shutdown buttons work as a backup control path if the kiosk is
down) — verified end-to-end across two real power cycles. tty2 debug
console (autologin `tricca` → `tap`, see Architecture) shipped and
verified live 2026-07-28: autologin confirmed passwordless, tap process
confirmed connected to tapd's control-plane socket via `ss`, session
respawn-into-fresh-tap confirmed by killing the tap process, SSH as
`tricca` confirmed still a normal shell.

`nick` — second machine, bootstrapped 2026-08-06. First bootstrap attempt
OOM-killed on the unpinned `system-manager` CLI (see README field notes);
fixed in `bootstrap.sh`/`modules/aliases.nix` (rev pin +eval
`--accept-flake-config`, commit 5cb326b) and reproduced/fixed live. A
later retry also hit a kernel panic (`hung_task` on the MMC controller
under heavy build I/O) — recovered via power cycle, no lasting corruption,
switch eventually succeeded with `--max-jobs 1 --cores 1
--http-connections 2` over a mobile hotspot (nick's only network during
this session; wifi/ethernet both unavailable at the time — PHY undetected
for onboard ethernet). Verified live: all 7 services active
(klipper-mcu, klipper, moonraker, tapd, autopipette, kiosk,
mainsail-nginx), Manta M8P MCU serial detected and connected
(`usb-Klipper_stm32h723xx_4B0020000951313339373836-if00`), kiosk
rendering the protocol list. NOT yet done: boot splash setup
(`splash/install-tricca-theme.sh`) and `netplan apply`/NetworkManager
restart (bootstrap.sh's own step 6) — deliberately skipped to avoid
disturbing the fragile hotspot connection mid-session; do these once
`nick` is on stable wifi/ethernet.

## State: tapd control daemon shipped and verified; live hardware runs in progress

The old subprocess-bridge architecture (kiosk spawning `tap` as a
subprocess) is GONE, replaced by tapd (see Architecture) — this was the
owner's own TODO from the last session, now done and pinned. Verified:
kiosk correctly lists `/protocols` and reports `/status` through tapd's
control-plane websocket, homing succeeded, Mainsail jog commands worked
after the MCU serial fix. Not yet verified: a complete, successful
liquid-handling run of a real `.pipette` protocol through the kiosk. Two
things surfaced during initial live testing that are still open:
- A hardware homing issue (Z-axis endstop) the owner called "a known issue"
  and is handling themselves — not a software/deployment bug.
- At least one `.pipette` protocol file has an argument-order mistake
  (flags before positional args cause `--prewet N` to swallow the transfer
  volume) — a protocol-authoring bug, not a tricca_autopipette bug. Worth
  checking other `.pipette` files for the same mistake before a real run.

## Style for this project

Owner: James, Edmonton-based, Linux/Doom Emacs, direct communicator —
expects verification over confidence (check the actual file/device state
before asserting; this repo's history includes several bugs from editing
by memory). Conversation-as-documentation matters: when a debugging session
teaches a rule, it goes into README field notes.
