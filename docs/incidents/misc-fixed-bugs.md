# Miscellaneous fixed bugs

Small, one-off bugs that are already fixed and need no ongoing operator
action — kept here rather than in README because there's nothing left to
*do* about any of them, just context in case a similar symptom resurfaces.

## `plymouth-set-default-theme -R` can report success without rebuilding the initramfs

It shells out to `update-initramfs -u -k all`, and on this board `-k all`'s
kernel autodetection finds nothing — it exits 0 regardless ("Nothing to do,
exiting."). The splash theme install script silently did nothing on some
runs as a result. `splash/install-tricca-theme.sh` now rebuilds by exact
kernel version and verifies with `lsinitramfs` instead of trusting the
tool's exit code (commit `65b3580`).

## klippy needs an explicit `--logfile` or you get no persistent log at all

With none set, klippy just logs `WARNING:root:No log file specified! Severe
timing issues may result!` on every start, with nothing to correlate
against future timing anomalies. Fixed by pointing it at
`/var/lib/moonraker/logs/klippy.log` (moonraker's own log dir, so
Mainsail's log viewer picks it up too) and having `klipper.service`'s
`preStart` create that directory itself, since klipper starts before
moonraker in unit ordering and moonraker hasn't created its data-dir tree
yet at that point (commit `9374da0`).

## mainsail-nginx's `[alert] could not open error log file` is cosmetic but still worth fixing at the source

`error_log stderr` already handled real logging, but nginx still tried
(and failed) to open its default error log path if `/var/log/nginx` didn't
exist, firing the alert on every start. `preStart` now creates the
directory (commit `2d5bfe3`).

## A Python package's `Path(__file__).parents[N]` repo-root trick breaks once installed

`tricca_autopipette`'s `DefaultPaths.DIR_REPO_ROOT` assumed a `src/`-layout
git checkout; any installed package (Nix, pip, wheel) drops the `src/`
segment and the count comes up one directory short, with no
`config/`/`protocols/`/`gcode/` underneath it. Fixed upstream via an
explicit `AUTOPIPETTE_REPO_ROOT` environment variable
(`Tricca_AutoPipette@cbd16de`); `modules/tapd.nix` sets it to
`/var/lib/autopipette`.
