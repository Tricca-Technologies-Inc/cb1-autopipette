# Grants `tricca` (the SSH/admin account) enough Nix trust to receive a
# `prime`d closure pushed from a workstation via `nix copy --to
# ssh://tricca@<host>` -- by default only `root` is a trusted user, so an
# unprivileged push is rejected outright. Declarative (ships via `switch`,
# like everything else) rather than a manual one-off `nix.conf` edit or
# enabling root SSH login. See ADR-0009.
#
# min-free/max-free: Determinate Nix's determinate-nixd runs its own
# automatic disk-space-triggered GC in the background, independent of any
# explicit `nix-collect-garbage`. On nick's 15GB SD card, that auto-GC
# firing concurrently with a `prime`d closure landing (nix copy) or a
# `switch` activation reading store paths is a plausible trigger for the
# same class of MMC-controller I/O wedge as the 2026-07-30 incident
# (hung_task/mmc_sd_detect) -- confirmed recurring 2026-08-31 (see nick
# prime incident notes). Raising the threshold so auto-GC only fires with
# real headroom to spare, and caps one sweep's size, reduces the chance it
# lands mid-copy/mid-activation. Not a full fix for the concurrency risk
# itself -- still prefer a manual `nix-collect-garbage` before a big prime.
{
  config = {
    nix.settings.trusted-users = [ "tricca" ];
    nix.settings.min-free = 3 * 1024 * 1024 * 1024; # 3 GiB
    nix.settings.max-free = 6 * 1024 * 1024 * 1024; # 6 GiB
  };
}
