# Shell helpers on every machine, managed by Nix (not bootstrap) so the
# whole fleet gets updates via `switch`. Sourced by login shells from
# /etc/profile.d/. Functions rather than aliases so they can take arguments.
{ ... }:
{
  config = {
    environment.etc."profile.d/tricca-aliases.sh".text = ''
      # Tricca AutoPipette shell helpers (nix-managed — edit in the deploy repo)

      # Apply the flake to this machine
      switch() {
        sudo -i nix run 'github:numtide/system-manager' -- switch --flake /opt/cb1-autopipette
      }

      # Preview the boot splash for N seconds (default 5), then restore the kiosk
      splash-preview() {
        local secs="''${1:-5}"
        sudo systemctl stop kiosk &&
        sudo plymouthd &&
        sudo plymouth --show-splash &&
        sleep "$secs" &&
        sudo plymouth quit
        sudo systemctl start kiosk
      }

      # Status of the whole AutoPipette stack
      ap-status() {
        systemctl status klipper-mcu klipper moonraker autopipette kiosk mainsail-nginx --no-pager -l
      }

      # Follow logs for one service (default: autopipette)
      logs() {
        journalctl -u "''${1:-autopipette}" -e -f
      }

      # Restart the app-facing services after a config change
      ap-restart() {
        sudo systemctl restart klipper moonraker autopipette && sudo systemctl restart kiosk
      }

      # Reclaim SD-card space from old Nix generations (keeps last 30 days)
      gc() {
        sudo nix-collect-garbage --delete-older-than 30d
      }
    '';
  };
}
