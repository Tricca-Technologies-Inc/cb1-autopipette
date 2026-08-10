# apt owns the base OS, Nix owns everything else

The CB1 needs both a stable board-supported base (kernel, drivers, browser)
and a fully declarative, reproducible service layer for the AutoPipette
stack. Armbian + apt owns the kernel, NetworkManager, Xorg, Chromium, and
plymouth; everything else (klipper-mcu, klipper, moonraker, mainsail-nginx,
tapd, autopipette, kiosk, plus /etc files and shell helpers) is Nix via
numtide/system-manager. Kernel/apt updates are deliberately TAKEN rather than
pinned — the owner's security requirement is to track upstream patches, not
freeze them — and are treated as maintenance events with a verification
reboot, outside `switch`'s reach.

## Consequences

Kernel/apt state can drift independently of the pinned flake; a clean
`switch` only proves the Nix-owned half matches the repo (see CLAUDE.md
hard-won rule #3).
