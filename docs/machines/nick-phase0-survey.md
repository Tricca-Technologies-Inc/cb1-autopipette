# nick — Phase 0 survey (axis expansion)

Survey form `docs/plans/axis-expansion/phase0-survey.md` (Tricca_AutoPipette, Rev L), filled in for nick. Checklist issue: [#57](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/57). There are no MCU serial IDs here (D34).

| Machine | nick | Surveyor | James (§4 physical, §5, §7) / Claude (remote) | Date | 2026-10-29 |
|---|---|---|---|---|---|

**Open items are marked ☐.** Everything marked ✓ was read remotely over SSH on 2026-10-29.

## 2. Software versions

| ✓ | Item | Value |
|---|---|---|
| ✓ | cb1-autopipette generation | system-manager generation 5 (2026-10-28), from cb1 `86dfe25`. OS: Armbian 26.8.3, kernel 6.18.44, Determinate Nix 3.24.1 |
| ✓ | Klipper (host) | `0.13.0-unstable-2026-09-28-NixOS` |
| ✓ | `printer-cfgs` rev it was seeded from | `c2b20ee` (the cb1 pin at the Sep 8 re-bootstrap) |
| ✓ | tapd rev | tricca-src `5859597` |
| ✓ | M8P firmware on the board | `v0.13.0-595-gb0e6ca45`, built with Debian's arm-none-eabi gcc 14.2. That's the pre-Nix flash, not a `mantaFirmware` build. Klippy logs no "deprecated code" warning |
| ✓ | `mantaFirmware` store path at the current pin (what `flash-manta` would write) | `/nix/store/ixadx0r7way7xayx2qwm7lpq57mxkf0v-klipper-firmware-manta-m8p-v2-bin` |

For rollback, keep in mind that the board isn't running a `mantaFirmware` image now. Rolling back means going back to the board's current firmware, which this repo has no copy of.

## 3. Config state

| ✓ | Item | Value |
|---|---|---|
| ✓ | RB1 §2 backup | `moonraker-config-20261029-180642.tgz` (sha256 `e6efcf5e2b5af7ae…`), in `/root/` on nick and `~/tricca-rig-backups/nick/` on the yogurt workstation |
| ✓ | Diff vs `c2b20ee` | `printer.cfg`: only the `[mcu]` serial block (written 2026-10-28 by `write-mcu-serials.sh`). `tricca-autopipette.cfg`: only `[manual_stepper pipette_stepper] rotation_distance: 8 → 2` (the #29 fix, 2026-10-28). `mainsail.cfg`: none |
| ✓ | `SAVE_CONFIG` block | no |
| ✓ | **Path** | **A (re-seed).** The only local edit besides `[mcu]` is `rotation_distance: 2`, and the new pin `6681d79` has the same value. After the re-seed, re-run `write-mcu-serials.sh`, because the new `printer.cfg` has no `[mcu]` |

## 4. Hardware as built

| ✓ | Item | Plan expects | Found |
|---|---|---|---|
| ☐ | Controller | Manta M8P **V2.0** + CB1 | MCU reports `stm32h723xx`, which matches V2.0. **Check the board's silkscreen** |
| ☐ | Gantry motors / slots | X, Y, Z×4 on 6 slots; pipette on a 7th; 1 spare | |
| ✓ | Run currents | X/Y 0.8 A; Z 0.65 A; pipette 0.65 A | X/Y 0.800, Z×4 0.650, pipette 0.650. **Matches** |
| ✓ | Pipette endstop | `^!PB10` | `^!PB10`. **Matches** |
| ✓ | Servo | MG996R on PE9 | `[servo pipette_servo] pin: PE9`. ☐ Check the model is MG996R |
| ☐ | Servo supply 24 → 6 V converter rated current (≥ 3 A to reuse, D29) | | A |
| ☐ | PSU label | 24 V, ≥ 200 W | V / W |
| ☐ | E-stop cuts all machine power | | |
| ☐ | Electronics in the top bay | | |
| ☐ | Room in the top bay for the Octopus, fuse block and wiring | | |
| ☐ | Octopus label and chip | "Octopus V1.1", STM32F446 (⛔ if F429) | |
| ☐ | Octopus SD: copy `FIRMWARE.CUR`/`firmware.bin` off | | |
| ☐ | Photos: M8P wiring, pipette head | | |

## 5. Pipette reference

| ✓ | Item | Value |
|---|---|---|
| ☐ | 5.1 Plunger moves **up / down** while homing; photo of zero | |
| ☐ | 5.2 `MOVE=-1` moves the plunger toward / away from the switch, so `home_dir` is | +1 / −1 |
| ☐ | 5.2 Travel measured for `MOVE=-10` | mm. 10 mm is expected now that `rotation_distance` is 2; 2.5 mm would mean it's still 8 |
| ☐ | D46: deepest safe plunger position (small steps) | mm |
| ✓ | 5.3 Servo angles (tapd's pipette config, all three files) | eject 130°, retract 100°, wait 850 ms. ☐ Photos |
| ☐ | 5.4 Gravimetric: volume, mean ± SD over 10 dispenses, balance | |
| ☐ | 5.5 Tip ejection: clean ejections out of 20, tip type | |

## 6. Load check (WP1 §4 method, 1.65 Ω)

| ✓ | Item | Value |
|---|---|---|
| ✓ | Run currents match §4 | yes |
| ☐ | PSU rating from its label | W |
| ✓ | Typical / servo-stall peak | ≈ 100 W / ≈ 115 W, the same as WP1 §4 (currents match). Against 200 W that's 50% / 57.5%, so it **passes**, right at the 50% limit. The method slightly overestimates (A/B motors are 1.1 Ω). ☐ Confirm once the PSU rating is read |

## 7. Cable lengths (route + 20%)

☐ Drawers 1–6 motor / switch; ☐ CB1 → Octopus USB. The M8P → pipette head CAN run doesn't apply, because the EBB42 is deferred (D35).

## 8. Sign-off

☐ Survey complete and every ⛔ resolved.
