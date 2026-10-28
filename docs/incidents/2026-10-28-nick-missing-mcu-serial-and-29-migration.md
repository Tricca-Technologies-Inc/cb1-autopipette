# 2026-10-28 — nick: Klipper never started after the Sep 8 re-bootstrap (no `[mcu]` serial), plus the #29 config migration

## Summary

Deploying cb1 `86dfe25` (aiohttp fix, #60) to nick ended with
`Job for kiosk.service failed because a timeout was exceeded`. That error
was a symptom: the kiosk waits for the AutoPipette backend to answer HTTP, and
the backend was waiting on `tapd`, which was crash-looping. While fixing that,
a second problem turned up. Klipper on nick had been in `error` state the whole
time since the Sep 8 card swap, because `printer.cfg` had no `[mcu]` section.

Two separate fixes, both applied by hand on the machine:

1. **#29 schema and unit migration**, the same as marie's
   [2026-10-02 incident](2026-10-02-marie-pipette-config-schema-migration.md),
   plus the matching Klipper change that marie already had.
2. **The `[mcu]` serial was written** with `scripts/write-mcu-serials.sh`.

Afterwards Klipper reported `ready` and `tapd`, `autopipette` and `kiosk` were
all active. The backups are in `/var/lib/autopipette/backup-pre29-20261028131953/`
(pipette and liquid JSONs, `tricca-autopipette.cfg`, `printer.cfg`).

## 1. tapd crash loop: the #29 migration

`journalctl -u tapd` showed the same validation error as marie:

```
[json_config_manager] ERROR: Failed to load default pipette ...
syringe.max_travel_mm
  Field required [type=missing, ...]
```

nick's machine-owned configs under `/var/lib/autopipette/config/` were seeded
before tricca-src's #29, and this was the first deploy of tricca-src
`5859597` to nick. Each file was compared with `5859597`'s copy before
replacing it:

- **Pipettes** (`default_p100`, `default_pipette`, `p100_vertical`). The
  `calibration_volumes` were identical. `calibration_steps[i] * 0.25 ==
  calibration_mm[i]` held exactly. The only other differences were speeds and
  accelerations scaled by exactly 0.25, plus the new `max_travel_mm: 60`.
- **Liquids** (`default_liquids`, `methanol`, `serum`, `water`). The only
  differences were the `calibration_steps` to `calibration_mm` rename and the
  methanol and serum speed overrides scaled by 0.25.
- **System** (`default_system.json`). The only difference is the optional
  `trigger_pins`, so it was left alone.

All seven pipette and liquid files were replaced with upstream's copies.

**The part marie didn't need:** nick's `tricca-autopipette.cfg` still had
`[manual_stepper pipette_stepper] rotation_distance: 8`. The rescaled configs
assume `2`, the real lead of the T8 single-start screw. Old configs with `2`,
or new configs with `8`, give a 4x volume or travel error. The 8 → 2 edit
went in at the same time as the JSON copy, and Klipper was restarted.

## 2. Klipper in `error` since Sep 8: no `[mcu]` serial

After the restart, `printer/info` returned:

```
Option 'serial' in section 'mcu' must be specified
```

This was not caused by the edit above. Every `Start printer` in
`klippy.log.2026-09-08`, `-09-09`, `-09-15` and today's `klippy.log` ends in
this same error. Not one of them reaches `Printer is ready`. `printer.cfg`
(mtime Sep 8 16:49, the card-swap re-bootstrap in
[2026-09-08](2026-09-08-card-swap-ethernet-fix-recurring-mmc-panic.md)) held
only `[mcu CB1]`, the host MCU.

Likely cause: the bootstrap of that time (the pre-#62 inline detection) only
appended `[mcu]` when exactly one `usb-Klipper_*` device was present, and
otherwise printed a warning and carried on. The M8P's
`/dev/serial/by-id/usb-Klipper_stm32h723xx_*` link is dated Sep 15, so the
board probably wasn't enumerated when bootstrap ran on Sep 8. The warning
scrolled past and nothing else ever checked for it.

Fix:

```
sudo bash /opt/cb1-autopipette/scripts/write-mcu-serials.sh
sudo systemctl restart klipper
sudo systemctl restart tapd autopipette
```

The script found exactly one `stm32h723xx` and wrote `[mcu]`. It correctly
skipped `[mcu octopus]`, since nick has no Octopus yet.

## Follow-ups

- **Re-check the calibration on nick before real pipetting.** Home it, then do
  a quick gravimetric dispense, since the syringe scale changed.
- A machine can sit with Klipper in `error` for weeks without anyone noticing.
  `switch` and its health sampler didn't flag it. A post-switch check that
  `printer/info` reports `ready` would have caught it on any deploy since Sep 8.
- These are the same lessons as marie's incident: seeded machine configs
  aren't covered by CI, and schema-breaking tricca-src bumps need a per-machine
  migration step. nick also needed the Klipper-side change, so compare
  `rotation_distance` on every rig when deploying #29.
