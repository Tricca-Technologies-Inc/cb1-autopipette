# Moonraker API server for Klipper, straight from nixpkgs. Versions pinned
# by flake.lock, same rationale as modules/klipper.nix -- Moonraker's own
# update_manager cannot self-update this install; updates flow through the
# flake instead.
{ pkgs, ... }:
let
  user = "pipette"; # created in bootstrap.sh

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

    systemd.services.moonraker = {
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
  };
}
