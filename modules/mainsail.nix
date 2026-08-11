# Mainsail static files, served by nixpkgs nginx on :80, reverse-proxying
# API/websocket traffic through to Moonraker (modules/moonraker.nix).
{ pkgs, ... }:
let
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
    systemd.services.mainsail-nginx = {
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
}
