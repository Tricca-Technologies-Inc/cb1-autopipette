# Debug console: Ctrl+Alt+F2 (tty2) autologs in as tricca (the existing
# admin account, real SSH login) and drops straight into `tap`, tapd's REPL
# client, instead of a normal shell. Safe alongside the kiosk (tty1): tap
# only ever talks to tapd's control-plane websocket
# (ws://127.0.0.1:8765/control), never Moonraker or the MCU serial directly,
# so there's no connection contention between this console and the kiosk
# or Mainsail.
#
# Deliberately NOT done by changing tricca's /etc/passwd shell -- that would
# also hijack SSH logins (same account, same shell field) into tap with no
# easy way back to a normal shell for admin work. Instead: tricca's shell
# stays whatever it already is, and a profile.d snippet execs tap only when
# the login tty is a physical console (tty2+), never a pts/SSH session.
#
# tty1 is claimed by the kiosk service (kiosk.nix: `conflicts = [
# "getty@tty1.service" ]`); if the kiosk ever dies and getty@tty1 comes back
# up, that login is deliberately left as a normal shell (recovery path),
# not forced into tap. Add another `getty@ttyN.service.d` drop-in below for
# more concurrent console sessions.
{ pkgs, triccaEnv, ... }:
let
  # DIR_REPO_ROOT's src-layout assumption breaks for any installed package
  # (see README field notes / modules/tapd.nix) -- applies to `tap` too,
  # not just tapd.
  tapConsole = pkgs.writeShellScript "tap-console" ''
    export AUTOPIPETTE_REPO_ROOT=/var/lib/autopipette
    exec ${triccaEnv}/bin/tap
  '';
in
{
  config = {
    environment.etc."profile.d/tricca-console.sh".text = ''
      # Physical-console-only auto-tap (modules/tricca-console.nix). SSH
      # sessions (pts/N) never match this, only local VT logins do.
      if [ "$(id -un)" = tricca ]; then
        case "$(tty 2>/dev/null)" in
          /dev/tty[2-9]) exec ${tapConsole} ;;
        esac
      fi
    '';

    # No password: physical console access already implies the same trust
    # level as the kiosk account, and this only affects the tty2 login --
    # tricca's real password still gates SSH normally.
    environment.etc."systemd/system/getty@tty2.service.d/tricca.conf".text = ''
      [Service]
      ExecStart=
      ExecStart=-/sbin/agetty --autologin tricca --noclear %I $TERM
    '';
  };
}
