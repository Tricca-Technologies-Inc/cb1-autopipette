# CB1 AutoPipette Deployment

The domain of this repo: the physical CB1 machine (Armbian + Nix-managed
services) that runs one Tricca AutoPipette rig, and the deploy/ownership
model that keeps it reproducible. This is the deployment context only — see
`Tricca_AutoPipette/CONTEXT.md` for the app-level domain (rig internals, tip
state, operator personas).

## Language

### Physical machine

**Machine**:
One physical BIGTREETECH CB1 unit running Armbian, with this repo checked
out at `/opt/cb1-autopipette`, driving exactly one rig. Named individually
(marie, nick — see CLAUDE.md's `## Current machines`). The app repo's
`Tricca_AutoPipette/CONTEXT.md` calls this same referent "host" (the
computer running `tapd`) — same thing, different repo's established word;
use "machine" within this repo.
_Avoid_: host, box, rig (rig is the app-context term for the physical
pipetting hardware the machine drives, not the machine itself).

**Flash** (image) vs **reflash** (firmware):
Two unrelated operations that share a verb. "Flash" the CB1 means writing
the Armbian OS image to its SD card — a one-time step before `bootstrap.sh`
runs. "Reflash" the Manta board means rewriting the M8P V2.0's own firmware
via `flash-manta`, an on-demand maintenance step for firmware drift (ADR-0004)
— different tool (`dfu-util` vs an SD-card writer), different target, no
relationship to the OS. Say which one explicitly; bare "flash" is ambiguous
in this repo.

### Deploy model

**Switch**:
The single deploy operation: applying this repo's pinned flake to a machine
via system-manager (the `switch` shell alias). The only way config changes
take effect — `git pull` alone changes nothing on a machine until followed
by `switch`.
_Avoid_: deploy, apply, provision — "switch" is the actual command name.

**Pin / pinned**:
A dependency version locked in `flake.lock` (`nixpkgs`, `system-manager`,
`tricca-src`, `printer-cfgs`). Reproducible and rollbackable by construction;
updating a pin is a deliberate act on a workstation (`nix flake update
<input>`, commit, push), never a drift the way apt packages can.
_Avoid_: version, dependency — too generic; "pin" specifically means
flake.lock-controlled.

**Seed / machine-owned**:
The one-time-copy pattern used for printer.cfg, tapd's config, and
autopipette's protocols: copied from a pinned input into a mutable location
on FIRST boot only, then never touched again by the flake — ownership
passes to the machine (SAVE_CONFIG, Mainsail's config editor, an operator
dropping in a new `.pipette` file). Re-seeding means deleting the
machine-owned copy and re-switching or restarting the owning service.
_Avoid_: sync, initialize — both imply repeated/ongoing action; seeding is
deliberately one-shot.

**apt/Nix boundary**:
Which parts of a machine's software apt owns (kernel, NetworkManager, Xorg,
Chromium, plymouth — deep distro/hardware coupling, kernel security updates
taken deliberately) vs. which parts this flake owns (everything else, via
system-manager). See ADR-0001. Moving a package across this boundary needs
a new ADR, not a one-off module change.
_Avoid_: "system packages" vs "app packages" — imprecise; the real boundary
is apt vs. Nix, not system vs. app.

### Runtime architecture

**Control-plane websocket**:
tapd's `ws://127.0.0.1:8765/control` endpoint — the one interface both `tap`
and the kiosk use to reach Moonraker and the rig, instead of either
connecting to Moonraker directly or spawning subprocesses. See ADR-0002.
_Avoid_: API, backend connection.

**Thin client**:
What `tap` and the kiosk both are with respect to tapd: no state of their
own, no direct Moonraker connection, nothing but a control-plane websocket
session. Neither is allowed to talk to Moonraker or spawn subprocesses
itself — that's the whole point of tapd existing.
_Avoid_: frontend — misses that `tap` (a shell, not a UI) is a thin client
too, by the same rule as the kiosk.

**Debug console**:
tty2 (Ctrl+Alt+F2): auto-logs in as `tricca` and execs `tap` directly
instead of a normal shell — the fast path back to control when the kiosk
(tty1) is unresponsive. See ADR-0003.
_Avoid_: recovery console, serial console — this is a local tty, not the
machine's physical serial port.
