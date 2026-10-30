# marie — Phase 0 survey (axis expansion)

Survey form `docs/plans/axis-expansion/phase0-survey.md` (Tricca_AutoPipette, Rev L), filled in for marie. Checklist issue: [#58](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/58). There are no MCU serial IDs here (D34).

| Machine | marie | Surveyor | James (§4 physical, §5, §7) / Claude (remote) | Date | 2026-10-29 |
|---|---|---|---|---|---|

**Open items are marked ☐.** Everything marked ✓ was read remotely over SSH on 2026-10-29.

## 2. Software versions

| ✓ | Item | Value |
|---|---|---|
| ✓ | cb1-autopipette generation | system-manager generation 6 (2026-10-28), from cb1 `86dfe25`. OS: Armbian 26.8.3, kernel 6.18.44, Determinate Nix 3.24.1 |
| ✓ | Klipper (host) | `0.13.0-unstable-2026-09-28-NixOS` |
| ✓ | `printer-cfgs` rev it was seeded from | `c2b20ee` (the 2026-09-23 reinstall) |
| ✓ | tapd rev | tricca-src `5859597` |
| ✓ | M8P firmware on the board | Build `20260727_214501` (Arm GNU Toolchain 15.2), from the 2026-07-27 `flash-manta`. No "deprecated code" warning |
| ✓ | `mantaFirmware` store path at the current pin | `/nix/store/ixadx0r7way7xayx2qwm7lpq57mxkf0v-klipper-firmware-manta-m8p-v2-bin` |

## 3. Config state

| ✓ | Item | Value |
|---|---|---|
| ✓ | RB1 §2 backup | `moonraker-config-20261029-180634.tgz` (sha256 `733bc1a8cfe868a8…`), in `/root/` on marie and `~/tricca-rig-backups/marie/` on the yogurt workstation |
| ✓ | Diff vs `c2b20ee` | `printer.cfg`: only the bootstrap `[mcu]` block. `mainsail.cfg`: none. `tricca-autopipette.cfg`, hand edits: X/Y endstops `^PF4`/`^PF3` → `^!PF4`/`^!PF3`; run currents X/Y 0.8 → 0.4, Z×4 0.65 → 0.40; pipette `rotation_distance: 8 → 2` (the #29 fix, 2026-10-29); **added** `[manual_stepper plate]` + `[tmc2209 manual_stepper plate]` on the M8P (step PB8, dir PB7, enable !PE0, endstop ^!PD14, 0.4 A, rotation_distance 32); **added** `[output_pin n2_valve]` on PF7 |
| ✓ | `SAVE_CONFIG` block | no |
| ✓ | **Path** | **B (hand merge).** ⛔ The owner must approve the diff (RB1 §3 step 3) |

**⛔ Decisions for the owner before the Path B merge:**
1. **`[manual_stepper plate]` on the M8P.** A single prototype drawer drive on M8P pins. CFG-1 puts all six plates on the Octopus as `plate1..6`. Remove it, or does that drive become one of the six?
2. **`[output_pin n2_valve]` on PF7.** Keep it. It doesn't conflict with CFG-1. For tapd's `trigger` command, add it to the system config's `trigger_pins`.
3. **Run currents (0.4 A) are below the plan (0.8 / 0.65).** Intended for marie's motors? See §4.

## 4. Hardware as built

| ✓ | Item | Plan expects | Found |
|---|---|---|---|
| ☐ | Controller | Manta M8P **V2.0** + CB1 | MCU reports `stm32h723xx`, which matches V2.0. **Check the board's silkscreen** |
| ☐ | Gantry motors / slots | X, Y, Z×4 on 6 slots; pipette on a 7th; 1 spare | Config also has a `plate` stepper on the M8P (§3) |
| ✓ | Run currents | X/Y 0.8 A; Z 0.65 A; pipette 0.65 A | X/Y 0.400, Z×4 0.40, pipette 0.650. **⛔ Differs: tell the owner** |
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

As of 2026-09-24 marie's pipette hardware wasn't installed (`marie.md`). ☐ Confirm whether it is now. If not, §5 waits.

| ✓ | Item | Value |
|---|---|---|
| ☐ | 5.1 Plunger moves **up / down** while homing; photo of zero | |
| ☐ | 5.2 `MOVE=-1` moves the plunger toward / away from the switch, so `home_dir` is | +1 / −1 |
| ☐ | 5.2 Travel measured for `MOVE=-10` | mm. 10 mm is expected now that `rotation_distance` is 2 |
| ☐ | D46: deepest safe plunger position (small steps) | mm |
| ✓ | 5.3 Servo angles (tapd's pipette config) | eject 130°, retract 100°, wait 850 ms. ☐ Photos |
| ☐ | 5.4 Gravimetric: volume, mean ± SD over 10 dispenses, balance | |
| ☐ | 5.5 Tip ejection: clean ejections out of 20, tip type | |

## 6. Load check (WP1 §4 method, 1.65 Ω)

| ✓ | Item | Value |
|---|---|---|
| ✓ | Run currents match §4 | no (lower) |
| ☐ | PSU rating from its label | W |
| ✓ | Recomputed typical / servo-stall peak | X/Y 2 × 2.5 W, Z 4 × 2.5 W, pipette 3.4 W, and the M8P `plate` stepper 2.5 W, plus the WP1 rows unchanged (six plates 33 W, logic 17 W, fans 10 W, servo 6 W, display 10 W). Total ≈ 97 W typical, ≈ 108 W at a servo stall. Against 200 W that's 48% / 54%, so it **passes**. If 0.4 A goes back to the plan's currents, the result is the same as nick's (≈ 100 / 115 W). ☐ Confirm once the PSU rating is read |

## 7. Cable lengths (route + 20%)

☐ Drawers 1–6 motor / switch; ☐ CB1 → Octopus USB. The M8P → pipette head CAN run doesn't apply (D35).

## 8. Sign-off

☐ Survey complete and every ⛔ resolved.
