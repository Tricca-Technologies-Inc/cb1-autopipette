# Machine status

Live snapshots of the fleet — overwrite these in place as status changes,
don't append history here. Incident write-ups and hard-won lessons belong
in [`docs/incidents/`](../incidents/) instead; README's Troubleshooting
section holds the short evergreen version of any lesson worth a human
knowing before they debug from scratch.

- [nick.md](nick.md)
- [marie.md](marie.md)

## Fleet-wide feature status

**tapd control daemon: shipped and verified; live hardware runs in progress.**
The old subprocess-bridge architecture (kiosk spawning `tap` as a
subprocess) is gone, replaced by tapd (see CLAUDE.md's Architecture
section) — this was the owner's own TODO from an earlier session, now done
and pinned. Verified: kiosk correctly lists `/protocols` and reports
`/status` through tapd's control-plane websocket, homing succeeded,
Mainsail jog commands worked after the MCU serial fix. **Not yet verified:**
a complete, successful liquid-handling run of a real `.pipette` protocol
through the kiosk.

## Axis-expansion record (template)

Every machine that gets the plate drawers (axis expansion, issues
[#57](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/57)
and [#58](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/58))
carries the section below in its `<host>.md`, filled in by a small PR during
commissioning. The fields follow the plan's
[RB1 §6](https://github.com/Tricca-Technologies-Inc/Tricca_AutoPipette/blob/main/docs/plans/axis-expansion/RB1-migration-and-operations.md),
with the EBB42 / CAN-bridge / Katapult firmware rows dropped (deferred,
[addendum D35](https://github.com/Tricca-Technologies-Inc/Tricca_AutoPipette/blob/main/docs/plans/axis-expansion/ADDENDUM-2026-10-26.md))
and the per-plate tip-safe stops added (addendum D39). Topology:
[ADR-0011](../adr/0011-octopus-v1.1-second-usb-mcu-for-plate-drawers.md).

**These files are in git, so they never hold an MCU serial ID** (no
`/dev/serial/by-id/...` value for either board). The IDs live only in the
machine's `printer.cfg` and its backup tarball. Leave a field as `—` until
it's measured; don't guess.

```markdown
## Axis expansion

No MCU serial IDs in this file: they live only in this machine's
printer.cfg and its backup tarball.

- Phase 0 survey: — (date; printer-cfgs rev the machine was seeded from;
  local config edits found; results, IDs left out)
- Migration path: — (A re-seed | B hand merge; date; operator)
- Backup tarball: — (file name; where it's stored off the machine)
- Previous M8P firmware (rollback): — (mantaFirmware store path, RB1 §2)
- Firmware SHA-256:
  - M8P (`mantaFirmware`, USB): —
  - Octopus V1.1 F446 (`octopusFirmware`): —
- `_PLATE_CFG.z_safe`: — (plan default 0.0)
- Drawer travel (`position_max`): — (plan default 350 mm; list only plates
  that differ)
- Tip-safe stops (`_PLATE_CFG`, per plate; default `[0, position_max]`):
  - plate1 (U): —
  - plate2 (V): —
  - plate3 (W): —
  - plate4 (A): —
  - plate5 (B): —
  - plate6 (C): —
- `_PIPETTE_CFG.home_dir`: — (plan default +1; record only if Phase 0
  measured −1)
- Powered checks (RB1 §3.7): — (pass/fail, date)
- Commissioning tests M-01…M-19, M-23: — (pass/fail, date; link the signed
  commissioning sheet). M-18 is the E-stop recovery drill.
- Stage 2 deployed: — (date, CB1-7 PR)
```
