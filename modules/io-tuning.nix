# Aggressive dirty-page writeback + ext4 commit-interval tuning, to stop the
# whole-system I/O collapse seen repeatedly on `nick` during a large `switch`
# (nix build's copy-in phase piling up dirty pages faster than the SD card
# can flush them -- once dirty+swap saturate memory, every writer on the box,
# including core daemons like journald/sshd, piles into D-state waiting on
# the same single-channel MMC device; that's what reads as a full freeze,
# caps-lock LED unresponsive and all). Proven mitigation, not a complete
# fix -- it's cleared every download-heavy attempt since it landed, but
# nick still froze once under a different I/O shape (a local Rust build's
# large sustained writes). Full history: docs/incidents/nick-generation-8-upgrade.md.
#
# The actual tuning script (ioTuningApply) is defined once in flake.nix and
# shared with `switch`'s own defensive reapplication (modules/aliases.nix)
# so the boot-time and switch-time copies can never drift out of sync --
# `switch` needs its own copy because this service only takes effect once a
# machine is already on a generation that contains it, which isn't true the
# first time it's rolled out to a stuck machine.
#
# Applied fleet-wide: pure overhead on marie's faster storage, load-bearing
# on nick's SD card.
{ ioTuningApply, ... }:
{
  config = {
    systemd.services.io-tuning = {
      description = "Dirty-page/ext4-commit tuning (SD-card I/O collapse mitigation)";
      wantedBy = [ "multi-user.target" ];
      before = [ "klipper.service" "moonraker.service" "tapd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${ioTuningApply}";
      };
    };
  };
}
