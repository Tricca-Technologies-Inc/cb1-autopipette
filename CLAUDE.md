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

## Architecture (do not re-litigate — rationale is in `docs/adr/`)

- Armbian base + apt for: kernel, NetworkManager, Xorg, Chromium, plymouth.
  Kernel updates are TAKEN (owner's security requirement), treated as
  maintenance events with a verification reboot. Everything else is Nix
  via numtide/system-manager (`systemConfigs.default`; per-machine hook:
  `systemConfigs."<hostname>"`). See
  [ADR-0001](docs/adr/0001-apt-vs-nix-boundary.md).
- Services: klipper-mcu (host MCU, same pinned src as klippy), klipper,
  moonraker, mainsail-nginx (:80), tapd (control daemon, owns the
  Moonraker connection), autopipette (:8000, thin kiosk client of tapd's
  control-plane websocket), kiosk, plus /etc files and shell helpers.
- tapd (from tricca-src) is a long-running control daemon holding the
  single persistent Moonraker connection; `tap` (interactive shell) and
  the kiosk are both thin clients of its control-plane websocket
  (ws://127.0.0.1:8765/control) instead of talking to Moonraker or
  spawning subprocesses themselves. Needs
  `AUTOPIPETTE_REPO_ROOT=/var/lib/autopipette` (modules/tapd.nix) since
  tricca_autopipette's path defaults assume a src-layout checkout, which
  breaks for any installed package. See
  [ADR-0002](docs/adr/0002-tapd-control-plane-daemon.md).
- tty2 is a debug console (modules/tricca-console.nix): Ctrl+Alt+F2
  autologs in as `tricca` (the existing admin/SSH account, no password)
  and execs `tap` instead of a normal shell — a fast path back to control
  if the kiosk (tty1) is misbehaving. See
  [ADR-0003](docs/adr/0003-tty2-debug-console-without-passwd-change.md).
- Manta M8P V2.0 board firmware (STM32H723) drifts from the host's pinned
  Klipper version over time ("MCU has deprecated code" warnings) since
  it's flashed once and never auto-updated. `mantaFirmware` (flake.nix)
  builds a correct binary from the same pinned source; `flash-manta`
  (shell helper) flashes it via the board's STM32 ROM DFU bootloader. See
  [ADR-0004](docs/adr/0004-manta-firmware-rebuilt-from-pinned-source.md).
- printer.cfg seeds ONCE from printer-cfgs into /var/lib/moonraker/config/,
  then is machine-owned (SAVE_CONFIG + Mainsail editor rewrite it). See
  [ADR-0005](docs/adr/0005-printer-cfg-seed-once-then-machine-owned.md).
- Wifi: NetworkManager persistent profile, created manually per machine.
  Credentials never enter the repo. netplan is nix-owned (replaceExisting).
  See [ADR-0006](docs/adr/0006-wifi-credentials-never-in-repo.md).
- Boot: black → tricca plymouth theme (logo, throbber below) → logo holds
  (plymouth-quit units neutralized; kiosk pre-script quits with
  --retain-splash) → sub-second white blink → kiosk. Do not reopen
  splash/flash work unless explicitly asked. See
  [ADR-0007](docs/adr/0007-boot-splash-white-blink-closed.md).

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

## Current machines

Live snapshot only — overwrite these in place as status changes, don't
append history here. Incident write-ups and hard-won lessons belong in
README's `## Field notes (hard-won)` instead.

- `marie` — Armbian 26.5.1 trixie, kernel 6.18.33-current-sunxi64. Last
  confirmed live 2026-07-28: all 7 services green, Manta firmware
  reflashed to match the pinned Klipper source, PolicyKit + tty2 debug
  console verified end-to-end. Not re-switched since — missing nick's
  PATH-gap/splash/klippy-logfile fixes and this session's agent-skills+ADR
  docs work; machine state not reverified this session.
- `nick` — bootstrapped 2026-08-06. Last confirmed live 2026-08-10: all 7
  services green, repo at commit `40a4f00`. `main` has since moved to
  `c09b92d` (agent-skills config + ADR split) — not yet pulled/switched on
  nick. Still on a mobile hotspot: no wired NIC detected, PHY undetected
  on onboard ethernet, worth a hands-on hardware look. Splash rebuild
  verified at the system level (theme active, plymouth-quit masked,
  kernel cmdline has `splash`); on-screen appearance not eyes-on verified.

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

## Agent skills

### Issue tracker

Issues live as GitHub Issues on `Tricca-Technologies-Inc/cb1-autopipette`; use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), unmapped. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
