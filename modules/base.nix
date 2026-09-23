{ pkgs, ... }:
{
  config = {
    nixpkgs.hostPlatform = "aarch64-linux";

    # Never build on the CB1 (1 GB RAM). Everything here should come from
    # cache.nixos.org, or be built on a desktop and pushed with `nix copy`.
    environment.systemPackages = with pkgs; [
      git
      htop
    ];

    # Mask Debian's journal-nocow.conf (same-name file in /etc overrides
    # /usr/lib/tmpfiles.d). Its `h /var/log/journal - - - - +C` fails on
    # Armbian: armbian-ramlog recreates /var/log/journal as a symlink to
    # /var/log.hdd/journal on every boot, and tmpfiles can't set file flags
    # on a symlink ("Setting file flags is only supported on regular files
    # and directories"), exits 73, and system-manager's activation treats
    # that as a failed switch -- which stopped bootstrap.sh (set -e) right
    # after marie's first switch, 2026-09-23. +C (no copy-on-write) only
    # does anything on btrfs; the CB1s are ext4.
    environment.etc."tmpfiles.d/journal-nocow.conf" = {
      text = "# masked by cb1-autopipette (modules/base.nix)\n";
      # Take ownership even if one was placed by hand while debugging.
      replaceExisting = true;
    };
  };
}
