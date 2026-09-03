# Shell helpers on every machine, managed by Nix (not bootstrap) so the
# whole fleet gets updates via `switch`. Sourced by login shells from
# /etc/profile.d/. Functions rather than aliases so they can take arguments.
{ pkgs, mantaFirmware, system-managerRev, ioTuningApply, switchHealthSampler, ... }:
let
  # flashtool.py (vendored in Klipper's own source) can trigger the board's
  # built-in "jump to bootloader" request over the currently-running Klipper
  # connection -- works regardless of which bootloader is actually present.
  # On marie this board turned out to use the STM32 ROM DFU (0483:df11), NOT
  # Katapult, so flashing itself goes through dfu-util once the jump lands.
  flashPython = pkgs.python3.withPackages (ps: [ ps.pyserial ]);
  flashtool = "${pkgs.klipper.src}/lib/katapult/flashtool.py";
in
{
  config = {
    environment.etc."profile.d/tricca-aliases.sh".text = ''
      # Tricca AutoPipette shell helpers (nix-managed — edit in the deploy repo)

      # Apply the flake to this machine. Pinned to the exact system-manager
      # rev in flake.lock (bump: nix flake update system-manager) -- an
      # unpinned `nix run github:numtide/system-manager` floats to upstream's
      # latest commit, which can drift out of sync with the system-manager
      # LIBRARY pinned below (used to build the config this CLI activates).
      # --accept-flake-config: system-manager's flake.nix declares
      # nixConfig.extra-substituters = cache.numtide.com (prebuilt
      # aarch64-linux binaries for the CLI). Without this flag Nix ignores
      # that substituter and compiles the Rust CLI from source on-device --
      # rustc/lto1 OOM-kill a 1 GB CB1 outright (bit `nick`'s bootstrap
      # 2026-08-05, see bootstrap.sh), and once caused a kernel panic. A
      # 2026-09-03 attempt that hand-ran switch without this flag hit both
      # the from-source build AND the panic again -- see
      # docs/incidents/nick-generation-8-upgrade.md, attempt 9.
      # Stop kiosk+autopipette first: chromium (kiosk) is a confirmed
      # multi-hundred-MB consumer, and both were among the D-state processes
      # during nick's I/O-collapse freezes -- freeing that RAM measurably
      # delayed (though didn't alone prevent) the collapse. Restarted
      # unconditionally after switch returns, success or failure, so a
      # machine never gets stuck kiosk-less; $rc preserves switch's own exit
      # code so callers still see a real failure. --max-jobs 1 --cores 1
      # --http-connections 2 serialize builds/downloads instead of running
      # them concurrently -- see README's Troubleshooting section and
      # docs/incidents/nick-generation-8-upgrade.md for why: concurrent
      # copy-in I/O is the trigger for the SD-card write collapse, not just
      # raw volume. klipper/moonraker/tapd stay up -- the gantry doesn't
      # need interrupting for a config update, and they weren't implicated.
      # Also, defensively: reapply the dirty-page/ext4-commit tuning live
      # every time (idempotent, near-instant) rather than trusting
      # io-tuning.service alone -- that service only takes effect once a
      # machine is already on a generation that contains it, which isn't
      # true the first time this rolls out to a stuck machine (the exact
      # gap that let attempt 9 above freeze). And run a background health
      # sampler (free/loadavg/dirty-pages/D-state processes every 5s,
      # synced to disk) for the duration, logged alongside switch's own
      # output under /var/log/tricca-switch/ -- so a freeze leaves a
      # postmortem trail instead of nothing.
      switch() {
        local logdir=/var/log/tricca-switch
        sudo mkdir -p "$logdir"
        sudo find "$logdir" -maxdepth 1 -name '*.log' -mtime +30 -delete
        sudo find "$logdir" -maxdepth 1 -name '*.stop' -mmin +60 -delete
        local ts; ts=$(date +%Y%m%dT%H%M%S)
        local logfile="$logdir/switch-$ts.log"
        local stopfile="$logdir/switch-$ts.stop"
        sudo systemctl stop kiosk autopipette
        sudo ${ioTuningApply}
        sudo ${switchHealthSampler} "$logfile" "$stopfile" &
        sudo -i nix run --accept-flake-config \
          --max-jobs 1 --cores 1 --http-connections 2 \
          "github:numtide/system-manager/${system-managerRev}" -- switch --flake /opt/cb1-autopipette \
          2>&1 | sudo tee -a "$logfile"
        local rc=''${PIPESTATUS[0]}
        sudo touch "$stopfile"
        sleep 6
        sudo rm -f "$stopfile"
        sudo systemctl start autopipette kiosk
        echo "Log: $logfile"
        return $rc
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

      # Flash the Manta M8P V2.0 board firmware (built fresh from the same
      # pinned Klipper source as the host, via the mantaFirmware package).
      # Fixes "MCU has deprecated code" warnings caused by the board's
      # firmware drifting behind the host over time. Verified end-to-end on
      # marie 2026-07-27: request-bootloader -> board reboots into the STM32
      # ROM DFU (0483:df11, masked in silicon -- can't be bricked by a bad
      # write) -> dfu-util writes at the 128KiB-bootloader offset -> board
      # reboots back into the new Klipper firmware automatically.
      flash-manta() {
        local devs
        devs=($(ls /dev/serial/by-id/usb-Klipper_stm32h723xx_* 2>/dev/null))
        if [ "''${#devs[@]}" -eq 0 ]; then
          echo "No Klipper MCU found on USB. Is the Manta M8P plugged in and powered?" >&2
          return 1
        elif [ "''${#devs[@]}" -gt 1 ]; then
          echo "Multiple Klipper MCUs found -- not sure which is the Manta:" >&2
          printf '  %s\n' "''${devs[@]}" >&2
          return 1
        fi
        local dev="''${devs[0]}"
        local fw="${mantaFirmware}/klipper.bin"
        echo "==> Stopping klipper.service"
        sudo systemctl stop klipper

        echo "==> Requesting bootloader on $dev"
        local req_out
        req_out=$(sudo ${flashPython}/bin/python3 ${flashtool} -d "$dev" --request-bootloader -v 2>&1)
        echo "$req_out"
        if ! echo "$req_out" | grep -q "Bootloader Request Complete"; then
          echo "Bootloader request failed -- restarting klipper and aborting." >&2
          sudo systemctl start klipper
          return 1
        fi

        echo "==> Waiting for DFU device..."
        for _ in $(seq 1 10); do
          sudo ${pkgs.dfu-util}/bin/dfu-util --list 2>/dev/null | grep -q "0483:df11" && break
          sleep 1
        done
        if ! sudo ${pkgs.dfu-util}/bin/dfu-util --list 2>/dev/null | grep -q "0483:df11"; then
          echo "Board never appeared in DFU mode -- restarting klipper and aborting." >&2
          sudo systemctl start klipper
          return 1
        fi

        echo "==> Flashing $fw"
        # dfu-util exits non-zero even on success here: the final ":leave"
        # reset makes the device vanish mid-status-query, which dfu-util
        # reports as "Error during download get_status" -- cosmetic, not a
        # failure (verified: erase/download both hit 100% first). Check the
        # actual output instead of the exit code.
        local flash_out
        flash_out=$(sudo ${pkgs.dfu-util}/bin/dfu-util -a 0 -s 0x08020000:leave -D "$fw" 2>&1)
        echo "$flash_out"
        if ! echo "$flash_out" | grep -q "File downloaded successfully"; then
          echo "Flash failed. The board's ROM bootloader can't be bricked by this --" >&2
          echo "re-run flash-manta to retry. Not restarting klipper until it succeeds." >&2
          return 1
        fi

        echo "==> Waiting for the board to reboot into the new firmware..."
        sleep 3
        echo "==> Restarting klipper.service"
        sudo systemctl start klipper
        sleep 3
        echo "==> Done. Verify with: logs klipper   (look for 'MCU has deprecated code' -- should be gone)"
      }
    '';
  };
}
