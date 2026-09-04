# Nix-generated units have a nix-store-only PATH — three bugs this bit

**Status: resolved (each instance fixed individually).** Kept here as
worked examples of a general pattern worth watching for when writing new
modules — the pattern itself is called out as a standing rule in
`CLAUDE.md`'s hard-won rules.

Nix-generated systemd units get a `PATH` containing only what's explicitly
declared (via `path = [ ... ]` or an absolute store path) — never the
system's normal `PATH`. Any script or unit that calls a binary by bare name
instead of an absolute path, or without declaring it in `path`, is at risk —
and this isn't limited to third-party/apt tools; it bit our own scripts
just as easily. All three cases below failed with **no error anywhere** —
the call just silently didn't run, or (in the `cmp` case) silently ran a
"succeed unconditionally" fallback path instead of the intended check.

- **kiosk-xinitrc's `xset` calls** (screen blanking/DPMS/screensaver
  disable) silently never ran until pathed to `/usr/bin/xset`
  (commit `0e0f97d`).
- **kiosk's `/etc/chromium.d/dev-shm` hook** couldn't find `findmnt`, fixed
  via `path = [ pkgs.util-linux ]` (commit `201acda`).
- **moonraker's `preStart` PolicyKit-rules idempotency check** (`cmp`, from
  `diffutils`) silently failed every boot, which meant it fell through to
  rewriting the rules file unconditionally instead of only on change
  (commit `40a4f00`).

**Verifying a `path = [...]` fix on an already-running service needs an
explicit `systemctl restart <unit>`** — a plain `switch` reloads the unit
file but doesn't restart what's already running, so the old (broken)
process keeps running with the old PATH until something restarts it.

If a new module calls out to any binary that isn't a Nix derivation output
directly, check this first before assuming the config itself is wrong.
