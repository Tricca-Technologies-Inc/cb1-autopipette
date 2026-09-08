# Incident write-ups

Historical debugging narratives — root-cause forensics, timelines, and
resolved-bug context that's too long or too dated to belong in the main
README. The README's Troubleshooting section links here for the full story
behind any of its short gotchas; check here first if you hit something new
that isn't in README at all.

- [2026-09-08-card-swap-ethernet-fix-recurring-mmc-panic.md](2026-09-08-card-swap-ethernet-fix-recurring-mmc-panic.md) —
  **open.** SD card replaced (12-15x write improvement) and ethernet fixed
  (dead since day one), but the same MMC hung_task panic that's dogged
  nick since generation 8 recurred anyway, on new hardware, with a
  cpufreq-governor mitigation applied. Root cause still not confirmed.
- [nick-generation-8-upgrade.md](nick-generation-8-upgrade.md) — **open.**
  Nick stuck on system-manager generation 8 since 2026-08-13; ten switch
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
