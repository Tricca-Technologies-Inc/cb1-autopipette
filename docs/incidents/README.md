# Incident write-ups

Historical debugging narratives — root-cause forensics, timelines, and
resolved-bug context that's too long or too dated to belong in the main
README. The README's Troubleshooting section links here for the full story
behind any of its short gotchas; check here first if you hit something new
that isn't in README at all.

- [2026-10-28-nick-missing-mcu-serial-and-29-migration.md](2026-10-28-nick-missing-mcu-serial-and-29-migration.md) —
  resolved. The kiosk timed out on a deploy because tapd was crash-looping
  on the #29 schema; nick also needed `rotation_distance` 8 → 2. Separately,
  Klipper had been in `error` since the Sep 8 re-bootstrap with no `[mcu]`
  serial. Fixed with `write-mcu-serials.sh`.
- [2026-09-24-marie-switch-mcu-shutdown-cascade.md](2026-09-24-marie-switch-mcu-shutdown-cascade.md) —
  resolved, recovery is one command. `switch` restarting `klipper-mcu.service`
  raced klippy's live connection to it, dropping CB1 (the host virtual MCU);
  Klipper's shutdown then cascaded to the real Manta MCU too, which only
  `FIRMWARE_RESTART` (not `systemctl restart klipper`) clears.
- [2026-09-23-marie-reinstall.md](2026-09-23-marie-reinstall.md) —
  resolved. marie wiped and bootstrapped fresh. Found: every Armbian
  switch exiting 1 on a tmpfiles rule (fixed, #32), firstrun-wizard wifi
  vanishing at the first reboot, and /etc files left untracked by a failed
  first switch.
- [2026-09-08-card-swap-ethernet-fix-recurring-mmc-panic.md](2026-09-08-card-swap-ethernet-fix-recurring-mmc-panic.md) —
  closed 2026-09-24, root cause never found. SD card replaced (12-15x write improvement) and ethernet fixed
  (dead since day one), but the same MMC hung_task panic that's dogged
  nick since generation 8 recurred anyway, on new hardware, with a
  cpufreq-governor mitigation applied. Priming avoids it and is enforced permanently (ADR-0009).
- [nick-generation-8-upgrade.md](nick-generation-8-upgrade.md) — resolved
  2026-09-08 by priming. Nick was stuck on system-manager generation 8 from 2026-08-13; ten switch
  attempts across five sessions, the mitigation stack that's worked so far,
  and what's still unresolved.
- [2026-07-30-oom-corruption-kernel-panic.md](2026-07-30-oom-corruption-kernel-panic.md) —
  resolved. A corrupt store output from an interrupted build, then a kernel
  panic from a retry missing `--accept-flake-config`.
- [nix-store-path-gaps.md](nix-store-path-gaps.md) — resolved (each
  instance individually). Three bugs from Nix-generated systemd units
  having a nix-store-only `PATH`, as worked examples of the general
  pattern.
- [misc-fixed-bugs.md](misc-fixed-bugs.md) — resolved. Small one-off fixes
  with no ongoing operator action needed.
