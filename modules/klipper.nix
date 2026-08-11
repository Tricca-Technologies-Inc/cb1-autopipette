# Klipper, straight from nixpkgs. No KIAUH.
#
# KIAUH is an interactive bash installer built around apt + git clones +
# venvs — it works, but every install drifts. Here the versions are pinned by
# flake.lock, and "update" means `nix flake update` + switch (with rollback).
#
# Layout (FHS-ish, since this is Armbian not NixOS):
#   /var/lib/moonraker/config/printer.cfg — writable (SAVE_CONFIG, Mainsail editor),
#                                     seeded from the pinned configs repo on first boot
#   /var/lib/moonraker/             — moonraker data dir (see modules/moonraker.nix)

{ pkgs, printer-cfgs, klipperHostMcu, ... }:
let
  user = "pipette"; # created in bootstrap.sh; member of dialout for /dev/serial
in
{
  config = {
    systemd.services = {
      # Klipper host MCU: a second klipper process on the CB1 itself, exposing
      # the board's own GPIO at /tmp/klipper_host_mcu (printer.cfg: [mcu CB1]).
      # Runs as root: -r requests realtime scheduling, and GPIO access needs
      # it anyway. If it crash-loops on this kernel, drop the -r flag first.
      klipper-mcu = {
        description = "Klipper host MCU (Linux process)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${klipperHostMcu}/klipper.elf -r";
          Restart = "always";
          RestartSec = 5;
        };
      };

      klipper = {
        description = "Klipper 3D printer firmware host";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "klipper-mcu.service" ];
        wants = [ "klipper-mcu.service" ];
        preStart = ''
          # printer.cfg lives in MOONRAKER's config dir — Mainsail's config
          # editor only sees files under moonraker's data path, and the whole
          # edit->save->restart loop in the web UI depends on that.
          mkdir -p /var/lib/moonraker/config /run/klipper
          # Seed the config set once from the pinned configs repo; never
          # overwrite — SAVE_CONFIG and Mainsail edits own these afterward.
          # Re-seed a machine: delete printer.cfg here and restart klipper.
          # NOTE: the repo's moonraker.conf is deliberately NOT copied — it
          # describes the legacy KIAUH layout; /etc/klipper/moonraker.conf
          # (nix-managed, modules/moonraker.nix) is authoritative here.
          if [ ! -f /var/lib/moonraker/config/printer.cfg ]; then
            for f in ${printer-cfgs}/*.cfg; do
              install -m 0644 -o ${user} "$f" /var/lib/moonraker/config/
            done
          fi
          # klippy starts before moonraker (moonraker `after`s klipper), so
          # moonraker hasn't created its own data-dir tree yet -- make the
          # logs dir ourselves or klippy's --logfile open below fails on a
          # fresh machine.
          mkdir -p /var/lib/moonraker/logs
          chown -R ${user} /var/lib/moonraker /run/klipper
        '';
        serviceConfig = {
          User = user;
          Group = "dialout";
          # Without --logfile klippy runs with no persistent log at all --
          # journalctl only has its own INFO lines, and klippy itself warns
          # "No log file specified! Severe timing issues may result!" on
          # every start. Found live on nick 2026-08-07 while auditing logs
          # for warnings: no klippy.log existed anywhere on the machine.
          # Path matches moonraker's own log dir (/var/lib/moonraker/logs/)
          # so Mainsail's log viewer picks it up too.
          ExecStart = ''
            ${pkgs.klipper}/bin/klippy \
              --input-tty=/run/klipper/tty \
              --api-server=/run/klipper/api \
              --logfile=/var/lib/moonraker/logs/klippy.log \
              /var/lib/moonraker/config/printer.cfg
          '';
          Restart = "always";
          RestartSec = 5;
          # preStart needs root for chown; drop privileges for main process
          PermissionsStartOnly = true;
        };
      };
    };
  };
}
