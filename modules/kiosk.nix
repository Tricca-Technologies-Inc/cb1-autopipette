# Chromium kiosk on tty1 for non-technical users.
#
# Deliberate impurity: X server and Chromium come from apt (/usr/bin), not
# nixpkgs. Chromium from nixpkgs works on aarch64-linux but is a very large
# closure, and Armbian's apt build is already proven on this board (xinit +
# xserver-xorg quirks were solved on the apt stack). Nix owns the service
# units and scripts; apt owns the two big desktop binaries. Revisit if you
# want a 100%-nix closure.
#
# Boot flow preserves the Plymouth splash-to-kiosk handoff: the kiosk waits
# until the AutoPipette backend answers HTTP before starting X, so the user
# never sees a console or a dead page.

{ pkgs, ... }:
let
  user = "pipette";
  url = "http://127.0.0.1:8000"; # keep in sync with modules/autopipette.nix

  # writeScript, NOT writeText: xinit execs this file as the X client, so it
  # must be executable. writeText (mode 444) makes X start and immediately
  # tear down with no client — a silent ~1s restart loop.
  xinitrc = pkgs.writeScript "kiosk-xinitrc" ''
    #!/bin/sh
    xset s off
    xset -dpms
    xset s noblank
    xsetroot -solid black
    exec /usr/bin/chromium \
      --kiosk \
      --default-background-color=000000 \
      --noerrdialogs \
      --disable-infobars \
      --disable-session-crashed-bubble \
      --check-for-update-interval=31536000 \
      ${url}
  '';

  kioskPre = pkgs.writeShellScript "kiosk-pre" ''
    # Runs as root (PermissionsStartOnly). Block until the backend serves,
    # then drop whichever splash mechanism this image has:
    #  - old blob/kernel-bootsplash world: sysfs node
    #  - new world: plymouth with the armbian theme
    # Neither present -> no-op (console was silenced via armbianEnv.txt).
    until ${pkgs.curl}/bin/curl -sf -o /dev/null ${url}; do
      sleep 1
    done
    if [ -e /sys/devices/platform/bootsplash.0/enabled ]; then
      echo 0 > /sys/devices/platform/bootsplash.0/enabled || true
    elif [ -x /usr/bin/plymouth ]; then
      # ABSOLUTE path, not `command -v`: the unit's PATH is nix-store-only,
      # so PATH lookups can never find apt binaries — the check silently
      # fails, plymouthd keeps the VT/DRM, and X dies instantly.
      # (Same failure class as moonraker needing iproute2 on its path.)
      /usr/bin/plymouth quit --retain-splash || true
    fi
  '';

  kioskScript = pkgs.writeShellScript "kiosk-start" ''
    exec /usr/bin/xinit ${xinitrc} -- /usr/bin/X :0 vt1 -background none -nolisten tcp -nocursor
  '';
in
{
  config = {
    # Debian's plymouth-quit.service kills the splash as soon as boot
    # "finishes" — before the kiosk starts — which un-does the retain-splash
    # handoff and lets console text + Chromium's white first paint show.
    # Neutralize both units (ConditionPathExists never true); the kiosk's
    # pre-script is then the only thing that quits plymouth.
    # Note: if the kiosk ever fails to start, the splash stays on screen —
    # debugging is via SSH/serial by design.
    environment.etc."systemd/system/plymouth-quit.service.d/tricca.conf".text = ''
      [Unit]
      ConditionPathExists=/nonexistent
    '';
    environment.etc."systemd/system/plymouth-quit-wait.service.d/tricca.conf".text = ''
      [Unit]
      ConditionPathExists=/nonexistent
    '';

    systemd.services.kiosk = {
      description = "Chromium kiosk for AutoPipette UI";
      # multi-user.target, NOT graphical.target: the minimal Armbian image's
      # default target is multi-user, so a graphical.target hook never fires
      # and the kiosk sits "inactive (dead)" forever.
      wantedBy = [ "multi-user.target" ];
      after = [ "autopipette.service" "systemd-user-sessions.service" ];
      wants = [ "autopipette.service" ];
      conflicts = [ "getty@tty1.service" ];
      serviceConfig = {
        User = user;
        PAMName = "login";
        TTYPath = "/dev/tty1";
        StandardInput = "tty";
        # X needs the tty on stdin, but stdout/stderr go to the journal —
        # otherwise chromium/xinit errors only flash by on tty1 and
        # journalctl -u kiosk shows nothing useful.
        StandardOutput = "journal";
        StandardError = "journal";
        UtmpIdentifier = "tty1";
        ExecStartPre = "${kioskPre}";
        PermissionsStartOnly = true; # preStart as root (sysfs write); X as ${user}
        ExecStart = kioskScript;
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
