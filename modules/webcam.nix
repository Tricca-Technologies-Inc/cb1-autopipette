# Deck camera stream (issue #81): plain ustreamer, not crowsnest (a bash/apt
# wrapper whose only usable backend on a CB1 is ustreamer anyway), and not
# nixpkgs' services.ustreamer (NixOS-only, doesn't apply under
# system-manager). MJPEG passthrough from a USB UVC webcam, no re-encode, on
# 127.0.0.1:8080; Mainsail's nginx proxies it at /webcam/
# (modules/mainsail.nix).
#
# Per-rig settings live in the machine-owned /etc/tricca-webcam.env, written
# by the `webcam setup` helper (scripts/webcam.sh): DEVICE (a /dev/v4l/by-id
# path, which carries the camera's serial, so never in the repo), RESOLUTION,
# FPS and V4L2_CTRLS. A rig without that file has no camera, and the unit is
# skipped at boot rather than failed. Nothing depends on it.
{ pkgs, ... }:
let
  envFile = "/etc/tricca-webcam.env";
  # Optional camera controls (e.g. manual focus) before the stream starts.
  applyCtrls = pkgs.writeShellScript "webcam-apply-ctrls" ''
    set -eu
    [ -z "''${V4L2_CTRLS:-}" ] || exec ${pkgs.v4l-utils}/bin/v4l2-ctl -d "$DEVICE" --set-ctrl "$V4L2_CTRLS"
  '';
  start = pkgs.writeShellScript "webcam-start" ''
    set -eu
    : "''${DEVICE:?DEVICE is not set in ${envFile}; run: webcam setup}"
    exec ${pkgs.ustreamer}/bin/ustreamer \
      --device "$DEVICE" \
      --format MJPEG --encoder HW \
      --resolution "''${RESOLUTION:-1280x720}" \
      --desired-fps "''${FPS:-15}" \
      --host 127.0.0.1 --port 8080
  '';
in
{
  config = {
    systemd.services.webcam = {
      description = "Deck camera stream (ustreamer)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      unitConfig.ConditionPathExists = envFile;
      serviceConfig = {
        EnvironmentFile = envFile;
        ExecStartPre = applyCtrls;
        ExecStart = start;
        DynamicUser = true;
        SupplementaryGroups = [ "video" ];
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
