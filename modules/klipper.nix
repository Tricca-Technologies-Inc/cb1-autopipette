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
        path = [ pkgs.iproute2 ];
        preStart = ''
          mkdir -p /var/lib/moonraker
          chown -R ${user} /var/lib/moonraker
        '';
        serviceConfig = {
          User = user;
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
        preStart = "mkdir -p /var/cache/mainsail-nginx";
        serviceConfig = {
          ExecStart = "${pkgs.nginx}/bin/nginx -c ${nginxConf}";
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
  };
}
