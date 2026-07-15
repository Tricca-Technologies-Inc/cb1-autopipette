# Encodes cb1-wifi-fix.md declaratively.
#
# NetworkManager itself is installed via apt (see bootstrap.sh) — running the
# NM daemon from nixpkgs on a foreign distro is fragile (D-Bus policies,
# polkit). What Nix owns here is every *file* the fix requires:
#
#   1. udev override forcing rtl8189fs back to NM_UNMANAGED=0
#      (stock /lib/udev/rules.d/85-nm-unmanaged.rules marks it unmanaged,
#      GENERAL.REASON 77)
#   2. Replacement /etc/netplan/armbian.yaml with NO wifis: block and
#      renderer handed to NetworkManager, so systemd-networkd's
#      netplan-wpa-wlan0.service never spawns a competing wpa_supplicant.
#
# bootstrap.sh moves the stock armbian.yaml aside first — system-manager will
# not clobber a pre-existing file it doesn't own.
#
# Verify after switch:
#   sudo udevadm test /sys/class/net/wlan0 2>&1 | grep -i nm_unmanaged   # expect =0 from 99- rule
#   nmcli device status                                                  # wlan0: disconnected, not unmanaged/unavailable
#
# Wifi credentials stay OUT of the repo. Connect once, imperatively; NM
# persists it in /etc/NetworkManager/system-connections/:
#   sudo nmcli device wifi connect "SSID" password "PASS" ifname wlan0

{ ... }:
{
  config = {
    environment.etc = {
      # Driver is rtl8189fs — letter "l", not digit "1". Confirm on new
      # hardware revisions with:
      #   udevadm info -q property /sys/class/net/wlan0 | grep ID_NET_DRIVER
      "udev/rules.d/99-wlan0-managed.rules".text = ''
        ENV{ID_NET_DRIVER}=="rtl8189fs", ENV{NM_UNMANAGED}="0"
      '';

      "netplan/armbian.yaml" = {
        # netplan complains if config is world-readable
        mode = "0600";
        # Take ownership even if a stock/regenerated armbian.yaml is present
        # (backed up to armbian.yaml.system-manager-backup automatically) —
        # otherwise system-manager skips the file with a WARN and the wifi
        # fix silently doesn't apply.
        replaceExisting = true;
        text = ''
          network:
            version: 2
            renderer: NetworkManager
            ethernets:
              all-lan-interfaces:
                match:
                  name: "en*"
                dhcp4: true
                dhcp6: true
        '';
      };
    };
  };
}
