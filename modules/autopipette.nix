# Tricca AutoPipette — FastAPI backend the kiosk points at.
#
# Replaces the current launch:
#   ~/Documents/Tricca_AutoPipette/venv/bin/uvicorn main:app \
#     --host 0.0.0.0 --port 8000 --app-dir .../autopipette_kiosk &
# The trailing `&` meant nothing supervised the process; systemd now restarts
# it on crash and orders it in the boot chain.
{ triccaEnv, tricca-src, ... }:
let
  user = "pipette";
  port = 8000; # keep in sync with modules/kiosk.nix
in
{
  config = {
    systemd.services.autopipette = {
      description = "Tricca AutoPipette FastAPI backend";
      wantedBy = [ "multi-user.target" ];
      after = [ "moonraker.service" "network.target" ];
      wants = [ "moonraker.service" ];
      preStart = ''
        mkdir -p /var/lib/autopipette
        # Seed protocols from the pinned source once; operators add/edit
        # .pipette files here at runtime, so never overwrite after that
        if [ ! -d /var/lib/autopipette/protocols ]; then
          cp -r ${tricca-src}/protocols /var/lib/autopipette/protocols
          chmod -R u+w /var/lib/autopipette/protocols
        fi
        chown -R ${user} /var/lib/autopipette
      '';
      serviceConfig = {
        User = user;
        Environment = [ "AUTOPIPETTE_PROTOCOLS_DIR=/var/lib/autopipette/protocols" ];
        ExecStart = "${triccaEnv}/bin/uvicorn autopipette_kiosk.main:app --host 0.0.0.0 --port ${toString port}";
        WorkingDirectory = "/var/lib/autopipette";
        Restart = "always";
        RestartSec = 5;
        PermissionsStartOnly = true;
      };
    };
  };
}
