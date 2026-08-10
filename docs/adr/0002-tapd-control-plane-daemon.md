# tapd holds the one Moonraker connection; kiosk and tap are thin clients

Status: accepted — supersedes the earlier subprocess-bridge architecture
(kiosk spawning `tap` as a subprocess), which is now removed.

Both the kiosk and the interactive `tap` shell need to drive Moonraker, and
doing that by spawning subprocesses or opening independent Moonraker
connections invited connection-thrashing and lifecycle bugs. `tapd` (from
tricca-src) is instead a long-running daemon holding the single persistent
Moonraker connection; `tap` and the kiosk are both thin clients of tapd's
control-plane websocket (`ws://127.0.0.1:8765/control`) rather than talking
to Moonraker or spawning subprocesses themselves. This also gives both
surfaces — kiosk touchscreen and the tty2 debug shell (see
[0003](0003-tty2-debug-console-without-passwd-change.md)) — a consistent
view of machine state.

## Consequences

tapd needs `AUTOPIPETTE_REPO_ROOT=/var/lib/autopipette` (modules/tapd.nix)
since tricca_autopipette's own path defaults assume a src-layout checkout,
which breaks for any installed package.
