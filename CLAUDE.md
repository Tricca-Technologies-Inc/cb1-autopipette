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
  (:80), autopipette (:8000), kiosk, plus /etc files and shell helpers.
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
  `sudo -i nix run 'github:numtide/system-manager' -- switch --flake /opt/cb1-autopipette`
- Helpers (modules/aliases.nix → /etc/profile.d): `switch`,
  `splash-preview [s]`, `ap-status`, `logs [unit]`, `ap-restart`, `gc`
- Update pins: on a WORKSTATION only — `nix flake update [tricca-src|printer-cfgs]`,
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

## Current machine

`marie` — Armbian 26.2.1, kernel 6.18.33-current-sunxi64 (post-upgrade),
all services green, boot experience shipped 2026-07-17.

## State: build DONE, first hardware run PENDING

The single unverified seam: the kiosk's protocol bridge. autopipette_kiosk
runs protocols by spawning `python -m tricca_autopipette.cli.main
--local-connect` and piping `run <protocol>\nquit\n` to the cmd2 shell
(verified importable, never executed against the gantry). Next session:
smallest protocol from the touchscreen, nothing valuable under the pipette,
`logs autopipette` open (the shell's .init_pipette startup script output
lands there). Expect the first failures HERE. The owner's own TODO notes a
direct Python call into the AutoPipette class as the better long-term bridge
than the subprocess.

## Style for this project

Owner: James, Edmonton-based, Linux/Doom Emacs, direct communicator —
expects verification over confidence (check the actual file/device state
before asserting; this repo's history includes several bugs from editing
by memory). Conversation-as-documentation matters: when a debugging session
teaches a rule, it goes into README field notes.
