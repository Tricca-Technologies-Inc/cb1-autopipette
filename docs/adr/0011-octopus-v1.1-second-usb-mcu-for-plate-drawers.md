# Octopus V1.1 as a second USB MCU for the plate drawers

Status: accepted (2026-10-26)

The AutoPipette axis expansion adds six belt-driven plate drawers (G-code
axes U V W A B C, 350 mm travel each) and binds the pipette plunger to a
G-code axis P. The drawers need six more stepper drivers than the Manta M8P
V2.0 has free, and steppers can't go on the CB1's own GPIO (host-MCU step
timing is poor; plan D1). Source: the
[axis-expansion plan package, Rev L](https://github.com/Tricca-Technologies-Inc/Tricca_AutoPipette/blob/main/docs/plans/axis-expansion/README.md)
and the
[owner addendum of 2026-10-26](https://github.com/Tricca-Technologies-Inc/Tricca_AutoPipette/blob/main/docs/plans/axis-expansion/ADDENDUM-2026-10-26.md),
which overrides the plan where they disagree.

Decided: the drawers go on a **BTT Octopus V1.1 (non-Pro, STM32F446)**
connected to the CB1 over **USB**, as a second Klipper MCU (`[mcu octopus]`).
It has 8 driver slots with drivers already fitted, and the owner already has
one (plan D2). The M8P stays exactly as it is today: a USB MCU (`[mcu]`)
carrying the gantry, the pipette plunger (`pipette_stepper`) and the servo
(`pipette_servo`) on their current pins (addendum D35). The host MCU
(`[mcu CB1]`, `klipper-mcu.service`) is unchanged. So a machine has two
physical Klipper MCUs on USB plus the host MCU.

The two boards can't be confused by name: the M8P enumerates as
`/dev/serial/by-id/usb-Klipper_stm32h723xx_<serial>`, the Octopus as
`usb-Klipper_stm32f446xx_<serial>`. Every tool that has to pick one board
keys on the chip name or the exact path, never a bare `usb-Klipper_*` glob.

## Considered options

- **M8P as a USB-to-CAN bridge, with the plunger and servo moved to an
  EBB42 CAN V1.2 toolboard, plus the Octopus for the drawers.** This was
  the Rev L plan (plan D3, D6; WP3's CB1-6 named the ADR "M8P as USB-to-CAN
  bridge + EBB42 + Octopus V1.1"). **Deferred by the owner on 2026-10-26**
  (addendum D35), not rejected: the work is kept as deferred issues
  [#56](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/56)
  (EBB42 + M8P CAN bridge) and
  [#55](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/55)
  (`can0`). Doing it later means a second ADR that supersedes the M8P half
  of this one: `[mcu]` becomes `canbus_uuid:`, the M8P needs bridge
  firmware, and the flash helpers need a CAN path.
- **A USB-to-CAN adapter (U2C) instead of the M8P bridge.** Listed as an
  alternative in the plan (WP3, CB1-6). Only relevant if CAN is used at all;
  with the EBB42 deferred there is no CAN bus to adapt to.
- **A second USB board without CAN** (also listed in WP3, CB1-6). This is
  what was chosen, with the Octopus as that board.

## Consequences

- **Two Klipper USB MCUs.** Anything that used to assume "the one
  `usb-Klipper_*` device" is now wrong:
  - `bootstrap.sh` must write two sections, `[mcu]` for the H723 and
    `[mcu octopus]` for the F446, identified by chip name, and must refuse
    to guess on zero, several, or unknown matches
    ([issue #51](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/51)).
    Before that lands, today's bootstrap would hit its "multiple MCUs"
    branch on an upgraded machine (plan risk K-OPS-02).
  - Flash helpers must target exactly their own board. `flash-manta`
    keeps its H723-only glob and its refusal on 0 or more than 1 match; the
    new `flash-octopus` targets the exact `serial:` path from the machine's
    `[mcu octopus]` section, never a glob
    ([issue #50](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/50)).
- **Octopus firmware is built from the pinned Klipper source**, the same
  way as the M8P's
  ([ADR-0004](0004-manta-firmware-rebuilt-from-pinned-source.md),
  [issue #49](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/49)).
  Its Kconfig assumes the board's 32 KiB bootloader (application at
  `0x08008000`) and a 12 MHz crystal (plan `reference/firmware/README.md`).
  `mantaFirmware` doesn't change.
- **Both serial IDs stay out of git**, like the M8P's today. They live
  only in the machine's `printer.cfg` (machine-owned,
  [ADR-0005](0005-printer-cfg-seed-once-then-machine-owned.md)) and its
  backup tarball (plan D34). `docs/machines/<host>.md` records the
  axis-expansion values but never an MCU ID.
- **Existing machines don't pick the topology up from a pin bump.** Their
  `printer.cfg` and include files are machine-owned (ADR-0005), so nick and
  marie are migrated by hand per the plan's RB1 §3, and commissioned per
  issues
  [#57](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/57)
  (nick) and
  [#58](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/58)
  (marie).
- **One more board on the E-stop.** The existing E-stop cuts all power,
  including the Octopus (plan R6). After a reset the CB1 boots, Klipper
  starts, and everything is unhomed; README's operator section has the
  recovery steps.
