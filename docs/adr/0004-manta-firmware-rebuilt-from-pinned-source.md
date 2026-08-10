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
