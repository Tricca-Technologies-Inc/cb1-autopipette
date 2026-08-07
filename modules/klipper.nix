# Klipper + Moonraker + Mainsail, straight from nixpkgs. No KIAUH.
#
# KIAUH is an interactive bash installer built around apt + git clones +
# venvs — it works, but every install drifts. Here the versions are pinned by
# flake.lock, and "update" means `nix flake update` + switch (with rollback).
# Consequence: Moonraker's update_manager cannot self-update these — that's
# intentional; updates flow through the flake.
#
# Layout (FHS-ish, since this is Armbian not NixOS):
#   /var/lib/moonraker/config/printer.cfg — writable (SAVE_CONFIG, Mainsail editor),
#                                     seeded from the pinned configs repo on first boot
#   /var/lib/moonraker/             — moonraker data dir
#   /etc/klipper/moonraker.conf     — nix-managed, read-only
#   Mainsail static files           — served by nixpkgs nginx on :80

{ pkgs, printer-cfgs, klipperHostMcu, ... }:
let
  user = "pipette"; # created in bootstrap.sh; member of dialout for /dev/serial


  nginxConf = pkgs.writeText "mainsail-nginx.conf" ''
    daemon off;
    worker_processes 1;
    error_log stderr;
    pid /run/mainsail-nginx.pid;
    events { worker_connections 128; }
    http {
      include ${pkgs.nginx}/conf/mime.types;
      client_body_temp_path /var/cache/mainsail-nginx;
      proxy_temp_path       /var/cache/mainsail-nginx;
      fastcgi_temp_path     /var/cache/mainsail-nginx;
      uwsgi_temp_path       /var/cache/mainsail-nginx;
      scgi_temp_path        /var/cache/mainsail-nginx;
      access_log off;
      map $http_upgrade $connection_upgrade {
        default upgrade;
        ""      close;
      }
      server {
        listen 80 default_server;
        root ${pkgs.mainsail}/share/mainsail;
        index index.html;
        client_max_body_size 512M;
        location / {
          try_files $uri $uri/ /index.html;
        }
        location ~ ^/(websocket|server|api|access|machine|printer)(/|$) {
          proxy_pass http://127.0.0.1:7125;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_read_timeout 600s;
        }
      }
    }
  '';

  # Without this, Moonraker warns "not authorized for PolicyKit action" and
  # disables its reboot/shutdown/service-restart API (used by Mainsail's own
  # UI buttons -- the backup control path if the kiosk is down). Scoped to
  # the moonraker-admin supplementary group (see moonraker's
  # SupplementaryGroups below), not the pipette user generally, since
  # autopipette/tapd/kiosk also run as pipette and are network-facing.
  #
  # NOT installed via environment.etc: that always creates a symlink into
  # the Nix store, and polkitd silently SKIPS symlinks when scanning
  # /etc/polkit-1/rules.d/ -- no error logged, it just never counts toward
  # "Finished loading, compiling and executing N rules". Verified live on
  # marie 2026-07-27: a plain regular file in that directory got picked up
  # (rule count 4->5, pkcheck succeeded); the symlinked version never did.
  # So moonraker's preStart below copies this into place as a real file.
  #
  # NOT using subject.isInGroup("moonraker-admin") despite that reading
  # cleaner: isInGroup() checks the USER ACCOUNT's static /etc/group
  # membership, not a process-level systemd SupplementaryGroups= grant --
  # since pipette is deliberately never added to moonraker-admin itself
  # (that's the whole point of scoping it to moonraker's unit only),
  # isInGroup() can never see it and always returns false. Verified this
  # exact failure live via a byte-for-byte reproduction of Moonraker's own
  # CheckAuthorization D-Bus call (dbus_manager.py's real subject: pid +
  # start-time), isolating it down to this one method call. The official
  # Moonraker install script (scripts/set-policykit-rules.sh) avoids this
  # by grepping the live /proc/<pid>/status Groups line instead -- doing
  # the same here, confirmed working with the same reproduction test.
  moonrakerPolkitRules = pkgs.writeText "moonraker.rules" ''
    var MOONRAKER_ADMIN_GID = polkit.spawn(["getent", "group", "moonraker-admin"]).trim().split(":")[2];

    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.halt" ||
            action.id == "org.freedesktop.login1.halt-multiple-sessions") {
            var regex = "^Groups:.+?\\s" + MOONRAKER_ADMIN_GID + "[\\s\\0]";
            var cmdpath = "/proc/" + subject.pid.toString() + "/status";
            try {
                polkit.spawn(["grep", "-Po", regex, cmdpath]);
                return polkit.Result.YES;
            } catch (error) {
                return polkit.Result.NOT_HANDLED;
            }
        }
    });
  '';
in
{
  config = {
    environment.etc."klipper/moonraker.conf".source = ../config/moonraker.conf;

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
          # (nix-managed) is authoritative here.
          if [ ! -f /var/lib/moonraker/config/printer.cfg ]; then
            for f in ${printer-cfgs}/*.cfg; do
              install -m 0644 -o ${user} "$f" /var/lib/moonraker/config/
            done
          fi
          chown -R ${user} /var/lib/moonraker /run/klipper
        '';
        serviceConfig = {
          User = user;
          Group = "dialout";
          ExecStart = ''
            ${pkgs.klipper}/bin/klippy \
              --input-tty=/run/klipper/tty \
              --api-server=/run/klipper/api \
              /var/lib/moonraker/config/printer.cfg
          '';
          Restart = "always";
          RestartSec = 5;
          # preStart needs root for chown; drop privileges for main process
          PermissionsStartOnly = true;
        };
      };

      moonraker = {
        description = "Moonraker API server for Klipper";
        wantedBy = [ "multi-user.target" ];
        after = [ "klipper.service" "network.target" ];
        wants = [ "klipper.service" ];
        # Moonraker's machine component shells out to `ip` for network info;
        # without this the journal fills with ShellCommandError tracebacks
        # from _parse_network_interfaces (non-fatal but noisy).
        # diffutils: preStart's own `cmp` below (idempotency check for the
        # polkit rules file) -- bare-name lookup on this unit's otherwise
        # nix-store-only PATH, so it silently no-oped ("cmp: command not
        # found") and the rules file was rewritten unconditionally on every
        # switch instead of only on change. Found live on nick 2026-08-07.
        path = [ pkgs.iproute2 pkgs.diffutils ];
        preStart = ''
          mkdir -p /var/lib/moonraker
          chown -R ${user} /var/lib/moonraker

          mkdir -p /etc/polkit-1/rules.d
          # Force a real file: if a prior switch left the old symlinked
          # version in place, `cmp` would follow it and (mis)report the
          # content as unchanged, leaving the broken symlink in place.
          if [ -L /etc/polkit-1/rules.d/moonraker.rules ] || \
             ! cmp -s ${moonrakerPolkitRules} /etc/polkit-1/rules.d/moonraker.rules; then
            rm -f /etc/polkit-1/rules.d/moonraker.rules
            cp ${moonrakerPolkitRules} /etc/polkit-1/rules.d/moonraker.rules
            chmod 644 /etc/polkit-1/rules.d/moonraker.rules
            /usr/bin/systemctl try-restart polkit.service || true
          fi
        '';
        serviceConfig = {
          User = user;
          # Grants PolicyKit-gated reboot/shutdown/service-restart to THIS
          # process specifically (see moonraker.rules below) -- not to the
          # pipette user generally, since autopipette/tapd/kiosk also run as
          # pipette and are network-facing; scoping to a supplementary group
          # keeps that surface from also gaining host-reboot capability.
          # Group must already exist (bootstrap.sh: groupadd -f moonraker-admin).
          SupplementaryGroups = [ "moonraker-admin" ];
          ExecStart = ''
            ${pkgs.moonraker}/bin/moonraker \
              --datapath /var/lib/moonraker \
              --configfile /etc/klipper/moonraker.conf
          '';
          Restart = "always";
          RestartSec = 5;
          PermissionsStartOnly = true;
        };
      };

      mainsail-nginx = {
        description = "nginx serving Mainsail on :80";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        # /var/log/nginx: nginx's actual error logging goes to stderr (see
        # error_log stderr above, captured by the journal) -- but nginx
        # still tries to open its compile-time-default error log path
        # (/var/log/nginx/error.log) during its pre-config bootstrap phase,
        # before it's even read our -c config file. Missing dir -> a
        # harmless "[alert] could not open error log file" on every start.
        preStart = "mkdir -p /var/cache/mainsail-nginx /var/log/nginx";
        serviceConfig = {
          ExecStart = "${pkgs.nginx}/bin/nginx -c ${nginxConf}";
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
  };
}
