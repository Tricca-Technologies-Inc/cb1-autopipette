# CB1 GPIO pins identified via gpiod, not fixed numbering

The Manta M8P V2.0's CB1 GPIO expansion header exposes pins straight from
the Allwinner H616 SoC, not through any fixed/RPi-style numbering scheme,
and no BTT-published pin table exists for it. Klipper's host-mcu (the
already-running `klipper-mcu` service, "Linux process" target) references
these pins purely through the kernel's GPIO character device --
`gpiochip<n>/gpio<o>`, prefixed with the mcu name from printer.cfg's
`[mcu CB1]` (e.g. `CB1:gpiochip1/gpio12`) -- discovered with
`gpiodetect`/`gpioinfo` (from `libgpiod`, `modules/base.nix`) rather than
assumed from any datasheet or RPi convention. Because the actual chip/line
layout depends on the SoC's pinctrl driver and whatever the running device
tree has already claimed, the silkscreen-label -> gpiochip/line mapping is
derived once, by hand, per board+SoC class (Manta M8P V2.0 + CB1) by
cross-referencing `gpioinfo`'s per-line consumer/name output against the
board's silkscreen and schematic on real hardware, and recorded in
`docs/hardware/cb1-gpio-pinout.md` -- not in any individual machine's file,
since the mapping is a property of the board class, not the machine.
`CONFIG_MACH_LINUX=y` (already the entirety of
`config/klipper-host-mcu.config`) is confirmed sufficient for this --
Klipper's `src/linux/Kconfig` unconditionally selects `HAVE_GPIO` under
`MACH_LINUX`; no firmware Kconfig change or rebuild is needed.

## Consequences

Any future `printer.cfg` pin reference must be looked up in
`docs/hardware/cb1-gpio-pinout.md` first, not guessed from a header pin
number. If a kernel/Armbian update or a device-tree overlay change ever
reshuffles gpiochip/line numbering, that doc's table must be re-verified
with `gpioinfo` before being trusted again -- it is a snapshot, not a spec.

Nothing here is a manual per-machine step: `libgpiod` (`modules/base.nix`)
and `klipper-mcu` running as root (`modules/klipper.nix`) are both part of
`systemConfigs.default`, so a brand-new machine gets both automatically
the first time `bootstrap.sh` runs `switch` -- the identical config path
already verified on marie 2026-09-28 (see
[docs/hardware/cb1-gpio-pinout.md](../hardware/cb1-gpio-pinout.md)). No
device-tree overlay is required: the stock Armbian image's own
`sun50i-h616-bigtreetech-cb1-sd.dtb` already exposes both gpiochips with
no header pin pre-claimed by anything but the SoC's own internal
functions. If a future board revision or Armbian image ever needs an
overlay to free a pin, that belongs in `bootstrap.sh` (per ADR-0001 /
CLAUDE.md hard-won rule #7), not in a `modules/*.nix` file.
