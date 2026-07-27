# tapd — the Tricca AutoPipette control daemon. Owns the single persistent
# Moonraker connection; both `tap` (interactive shell) and the kiosk talk to
# its control-plane WebSocket (ws://127.0.0.1:8765/control) instead of
# connecting to Moonraker themselves. Must be up before autopipette (see
# modules/autopipette.nix's After=/Requires=tapd.service).
#
# AUTOPIPETTE_REPO_ROOT overrides tricca_autopipette's DefaultPaths, which
# otherwise assumes it's running from a src-layout git checkout (breaks for
# any installed package, Nix included) -- fixed upstream in
# Tricca_AutoPipette@cbd16de. Pointing it at /var/lib/autopipette means
# DIR_PROTOCOL resolves to the same directory autopipette.nix already seeds
# protocols into, so only config/ needs seeding here.
{ triccaEnv, tricca-src, ... }:
let
  user = "pipette";
in
{
  config = {
    systemd.services.tapd = {
      description = "Tricca AutoPipette control daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "moonraker.service" "network.target" ];
      wants = [ "moonraker.service" ];
      preStart = ''
        mkdir -p /var/lib/autopipette/gcode
        # Seed config from the pinned source once; operators tune per-machine
        # gantry/pipette settings here afterward, so never overwrite after
        # first boot (same pattern as protocols in autopipette.nix).
        if [ ! -d /var/lib/autopipette/config ]; then
          cp -r ${tricca-src}/config /var/lib/autopipette/config
          chmod -R u+w /var/lib/autopipette/config
        fi
        chown -R ${user} /var/lib/autopipette
      '';
      serviceConfig = {
        User = user;
        Environment = [ "AUTOPIPETTE_REPO_ROOT=/var/lib/autopipette" ];
        ExecStart = "${triccaEnv}/bin/tapd --local-connect --log-file /var/lib/autopipette/tapd.log";
        WorkingDirectory = "/var/lib/autopipette";
        Restart = "always";
        RestartSec = 5;
        PermissionsStartOnly = true;
      };
    };
  };
}
