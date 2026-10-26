# Manta firmware is rebuilt from the pinned Klipper source, flashed via ROM DFU

Manta M8P V2.0 board firmware (STM32H723) drifts from the host's pinned
Klipper version over time ("MCU has deprecated code" warnings), since it's
flashed once at setup and never auto-updated afterwards. `mantaFirmware`
(flake.nix) builds a correct binary from the same pinned Klipper source used
for klippy and the host MCU, so host/board protocol versions can never
mismatch; `flash-manta` (shell helper) flashes it via the board's STM32 ROM
DFU bootloader. That bootloader is masked in silicon, so a bad flash can't
brick the board — reflashing is a routine, low-risk maintenance operation
rather than something to avoid.

## Update, 2026-10-26 — second board: Octopus V1.1 (F446)

The AutoPipette axis expansion adds a second USB Klipper MCU, a BTT Octopus
V1.1 (non-Pro, STM32F446) driving the plate drawers (`[mcu octopus]`). The
same decision applies to it, for the same reason: `octopusFirmware`
(flake.nix) builds its `klipper.bin` from the same pinned Klipper source as
klippy, the host MCU and `mantaFirmware`, from
`config/klipper-octopus-mcu.config` (copied verbatim from the plan's
reference Kconfig: 32 KiB bootloader, 12 MHz crystal, USB on PA11/PA12).
Like `mantaFirmware` it ships only `klipper.bin`, with `gcc-arm-embedded` in
`disallowedReferences` so the ARM toolchain can't leak into the runtime
closure (#30).

The two boards differ only in what the flashing step has to get right:
the M8P's application starts at `0x08020000` (128 KiB bootloader), the
Octopus's at `0x08008000` (32 KiB bootloader). Both drop into the same
STM32 ROM DFU ID (`0483:df11`) when asked, so the flash helpers must
identify their own board before touching anything (issue #50). The
Manta stays a plain USB MCU; the M8P CAN bridge and the EBB42 are
deferred (plan addendum D35).

## Update, 2026-10-26 — reproducible images

Klipper stamps a version string into every image. Outside a git checkout,
which is always the case under Nix, that string is `?` plus the build time
and hostname, so two builds of the same pin never had the same SHA-256 and
a workstation build could not be checked against a CI build. flake.nix's
`klipperFirmware` wrapper now fixes the string to the version klippy itself
reports (`<klipper version>-NixOS`) and drops the time/hostname suffix, for
all three images (host MCU, M8P, Octopus). `nix build --rebuild` of the M8P
and Octopus images produced byte-identical output.

At nixpkgs `c59305b` (Klipper `7bc4d09`, `0.13.0-unstable-2026-09-28`),
`klipper.bin` hashes are:

| Image | SHA-256 |
|---|---|
| `mantaFirmware` | `8ab63676a0e0b21f5210aa817d1c1ee0f4221efa442274f7a74b6b0fa713bd10` |
| `octopusFirmware` | `5e585bf3ac7d15b1c60cc6c7ca3621e2e6db24ff94bdc365ce10e79c15bf39bf` |

Any change to the nixpkgs pin, the Kconfig or the ARM toolchain changes
these. Re-record them here, and in the machine records, when one moves.
