# Debug consoles, tty2 through tty6. All autolog in as tricca (the existing
# admin/SSH account, real login) with no password -- physical console access
# already implies the same trust level as the kiosk. tty2 drops straight
# into `tap`, tapd's REPL client; tty3-tty6 drop into a normal (bare) shell,
# so a physical keyboard can run `tap` on one VT (Ctrl+Alt+F2) and
# journalctl/htop/etc. on another (Ctrl+Alt+F3..F6) at the same time. tap
# only ever talks to tapd's control-plane websocket
# (ws://127.0.0.1:8765/control), never Moonraker or the MCU serial directly,
# so there's no connection contention between these consoles and the kiosk
# or Mainsail.
#
# Deliberately NOT done by changing tricca's /etc/passwd shell -- that would
# also hijack SSH logins (same account, same shell field) into tap with no
# easy way back to a normal shell for admin work. Instead: tricca's shell
# stays whatever it already is, a profile.d snippet execs tap only when the
# login tty is tty2 specifically, and getty autologin (below) is the only
# thing that differs on tty3-tty6 -- they land in tricca's normal shell.
#
# tty1 is claimed by the kiosk service (kiosk.nix: `conflicts = [
# "getty@tty1.service" ]`); if the kiosk ever dies and getty@tty1 comes back
# up, that login is deliberately left as a normal shell (recovery path),
# not forced into tap or autologin.
{ pkgs, triccaEnv, ... }:
let
  # DIR_REPO_ROOT's src-layout assumption breaks for any installed package
  # (see README field notes / modules/tapd.nix) -- applies to `tap` too,
  # not just tapd.
  tapConsole = pkgs.writeShellScript "tap-console" ''
    export AUTOPIPETTE_REPO_ROOT=/var/lib/autopipette
    exec ${triccaEnv}/bin/tap
  '';

  # Same no-password autologin line for every debug-console tty (tty2-tty6);
  # what tty2 does differently (exec tap) lives in the profile.d script
  # below, not here.
  ttyAutologin = ''
    [Service]
    ExecStart=
    ExecStart=-/sbin/agetty --autologin tricca --noclear %I $TERM
  '';
in
{
  config = {
    environment.etc."profile.d/tricca-console.sh".text = ''
      # Physical-console-only auto-tap (modules/tricca-console.nix). SSH
      # sessions (pts/N) never match this, only a local tty2 VT login does.
      # tty3-tty6 autolog in (see the getty@ttyN drop-ins below) but fall
      # through here into tricca's normal shell.
      if [ "$(id -un)" = tricca ]; then
        case "$(tty 2>/dev/null)" in
          /dev/tty2) exec ${tapConsole} ;;
        esac
      fi
    '';

    # No password: physical console access already implies the same trust
    # level as the kiosk account, and this only affects tty2-tty6 logins --
    # tricca's real password still gates SSH normally.
    environment.etc."systemd/system/getty@tty2.service.d/tricca.conf".text = ttyAutologin;
    environment.etc."systemd/system/getty@tty3.service.d/tricca.conf".text = ttyAutologin;
    environment.etc."systemd/system/getty@tty4.service.d/tricca.conf".text = ttyAutologin;
    environment.etc."systemd/system/getty@tty5.service.d/tricca.conf".text = ttyAutologin;
    environment.etc."systemd/system/getty@tty6.service.d/tricca.conf".text = ttyAutologin;
  };
}
