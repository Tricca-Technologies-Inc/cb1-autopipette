# CB1 GPIO pinout (Manta M8P V2.0 expansion header)

Applies to the Manta M8P V2.0 + CB1 board pairing as a class -- nick,
marie, and any future machine using this exact board -- not to one
machine. See [ADR-0010](../adr/0010-cb1-gpio-pins-identified-via-gpiod-not-fixed-numbering.md)
for why pins are referenced this way at all.

**A new machine needs no manual step for this.** `libgpiod`
(`gpiodetect`/`gpioinfo`/`gpioget`/`gpioset`) and `klipper-mcu` running as
root are both part of `systemConfigs.default`, so `bootstrap.sh`'s first
`switch` already provides everything below out of the box -- confirmed on
marie 2026-09-28 with no device-tree overlay in play (see "What's
confirmed so far"). What's still missing is only the header-pin-label ->
line mapping, which is a one-time, per-board-class, by-hand lookup (see
Status), not anything the deploy tooling needs to do differently.

## Status

**Chip/line layout confirmed; header-pin labels still TODO.** The kernel's
gpiochip/line partition and which lines are already claimed are known (see
below) -- but which physical header pin on the Manta M8P V2.0's CB1
expansion connector corresponds to which line is NOT yet known. sunxi's
pinctrl driver reports every line as `unnamed` (no per-pin names like
RPi's `pinctrl-bcm2835` gives), so that mapping can only come from
physically reading the board's silkscreen/schematic next to a machine and
either cross-referencing against Allwinner's H616 datasheet pin tables or
probing -- neither of which is possible over SSH. That step is still
open; see [issue #36](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/36).

## How this table was produced

- Machine + date: marie, 2026-09-28, repo commit `d5de11b` (before this
  pass's `libgpiod` addition to `modules/base.nix` -- `gpiod`/`libgpiod3`
  were already present via a manual `apt-get install` predating this
  repo's declarative management).
- Raw `gpiodetect`/`gpioinfo` output:
  [marie-gpioinfo-2026-09-28.txt](marie-gpioinfo-2026-09-28.txt).
- Silkscreen/schematic cross-reference: not yet done -- needs someone
  physically at the board (see Status above).
- Klipper pin-naming reminder: `<mcu_name>:gpiochip<n>/gpio<o>` -- e.g.
  printer.cfg's `[mcu CB1]` gives `CB1:gpiochip1/gpio12`.

## What's confirmed so far (marie, 2026-09-28)

- No `overlays=` line in `/boot/armbianEnv.txt` at all -- the default
  board dtb (`sun50i-h616-bigtreetech-cb1-sd.dtb`) loads with no extra
  overlay claiming header pins. Nothing here has forced any dtoverlay
  work in `bootstrap.sh`.
- Two gpiochips: `gpiochip0` (288 lines, `300b000.pinctrl` -- the H616's
  main pin controller) and `gpiochip1` (32 lines, `7022000.pinctrl` --
  the SoC's secondary/always-on pin controller, typically used for
  PMIC/IR-adjacent functions on Allwinner SoCs).
- Of 320 total lines, 29 are claimed: 27 by a generic `kernel` consumer
  (likely default-state hogs, not necessarily anything routed to the
  header), 1 `reset` (output, active-low), 1 `led-0` (output,
  active-low -- almost certainly the board's status LED). The claimed
  ranges (0-9,12 / 160-165 / 192-197 / 210 / 224-225 / 229 on gpiochip0;
  0-1 on gpiochip1) line up with where Allwinner's standard 32-line
  bank convention (bank 0 = PA, bank 5 = PF, bank 6 = PG, bank 7 = PH,
  ...) would put SD-card (PF), UART/console (PH0-1, matching this
  machine's `console=serial`), and a WiFi/PMIC-adjacent reset line (PG) --
  **this bank-letter mapping is inferred from the generic Allwinner
  convention, not confirmed against the H616 datasheet or this board's
  schematic; treat it as a hint, not a fact.**
- The remaining ~291 lines are unclaimed at the kernel level -- but most
  of those aren't physically routed to the Manta M8P V2.0's expansion
  header at all, so this is not "291 pins available for Klipper," just
  "291 lines with no static kernel claim."

Read-only discovery commands (no `gpioset`, no motion):

```bash
ssh tricca@<machine-ip-or-hostname>
cat /boot/armbianEnv.txt   # check for an existing overlays= line
sudo gpiodetect            # list gpiochips the kernel exposes
sudo gpioinfo              # per-line name/direction/consumer
```

## Pin table

| Header pin / silkscreen label | gpiochip | line (offset) | gpioinfo line name | claimed by (gpioinfo consumer) | notes |
|---|---|---|---|---|---|
| TODO | | | | | |

## Known gotchas / re-verify triggers

- Kernel/Armbian updates or a device-tree overlay change can renumber
  gpiochip/line assignments -- re-run `gpioinfo` and diff before trusting
  an old row.
- A line showing a non-empty consumer (i2c/spi/uart/led/mmc/etc.) is
  already claimed by something else in the running kernel and is not free
  for Klipper without a separate, deliberate decision to disable that
  consumer (out of scope here).

## References

- [ADR-0010](../adr/0010-cb1-gpio-pins-identified-via-gpiod-not-fixed-numbering.md)
- Klipper's `RPi_microcontroller.md` -- the pin-naming scheme it documents
  is generic to any Linux-process mcu, not RPi-specific, despite the
  filename.
