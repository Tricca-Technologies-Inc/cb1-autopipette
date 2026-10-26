{
  description = "Tricca AutoPipette — declarative CB1 (Armbian) system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # AutoPipette source, pinned by flake.lock (bump: nix flake update tricca-src)
    tricca-src = {
      url = "github:Tricca-Technologies-Inc/Tricca_AutoPipette";
      flake = false;
    };
    # Klipper config set (printer.cfg + includes), pinned like everything else
    printer-cfgs = {
      url = "github:Tricca-Technologies-Inc/Tricca_Autopipette_Configs";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      system-manager,
      tricca-src,
      printer-cfgs,
      ...
    }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      tricca-autopipette = pkgs.callPackage ./pkgs/tricca-autopipette.nix { src = tricca-src; };
      # One interpreter env holding uvicorn + the app and all its deps.
      # This replaces the venv at ~/Documents/Tricca_AutoPipette/venv.
      triccaEnv = pkgs.python3.withPackages (ps: [
        tricca-autopipette
        ps.uvicorn
      ]);
      # nixpkgs' klipper-firmware, made reproducible. Klipper stamps a version
      # string into every image (klipper.bin's embedded data dictionary).
      # Outside a git checkout -- always the case under Nix -- it falls back
      # to "?" plus the build time and hostname, so no two builds of the
      # same pin hash the same. Use the version klippy itself reports
      # instead: nixpkgs writes "<version>-NixOS" into klippy's .version.
      klipperFirmware =
        args:
        (pkgs.klipper-firmware.override args).overrideAttrs (old: {
          postPatch = old.postPatch + ''
            echo "${pkgs.klipper.version}-NixOS" > klippy/.version
            substituteInPlace scripts/buildcommands.py \
              --replace-fail "    if not cleanbuild:" "    if False:"
          '';
        });
      # Host MCU: klipper.elf built for the "Linux process" target, running on
      # the CB1 itself (printer.cfg: [mcu CB1] serial=/tmp/klipper_host_mcu).
      # Built from the SAME pinned klipper source as klippy, so host-MCU and
      # klippy protocol versions can never mismatch.
      #
      # nixpkgs' klipper-firmware sets dontFixup, so klipper.elf is never
      # stripped: its debug info keeps the include paths of gcc, glibc-dev
      # and linux-headers, pulling ~250 MiB of build toolchain into the
      # runtime closure (issue #30). Strip it at the end of installPhase.
      klipperHostMcu =
        (klipperFirmware {
          mcu = "host";
          firmwareConfig = ./config/klipper-host-mcu.config;
        }).overrideAttrs
          (old: {
            installPhase = old.installPhase + ''
              ''${STRIP:-strip} --strip-debug $out/klipper.elf
            '';
            disallowedReferences = [ pkgs.stdenv.cc.cc ];
          });
      # Manta M8P V2.0 board firmware, built from the SAME pinned Klipper
      # source as klippy/klipperHostMcu -- keeps the physical board's
      # firmware from drifting out of sync with the host (see README field
      # notes: "MCU has deprecated code" means the board needs reflashing).
      # Flashing itself is still manual; this only produces the binary.
      #
      # Ships only klipper.bin (all flash-manta writes): the build's
      # klipper.elf carries debug-info paths into gcc-arm-embedded, which
      # dragged the whole ~1 GiB ARM toolchain onto every machine (#30).
      mantaFirmware =
        pkgs.runCommand "klipper-firmware-manta-m8p-v2-bin"
          {
            disallowedReferences = [ pkgs.gcc-arm-embedded ];
          }
          ''
            install -Dm444 ${
              klipperFirmware {
                mcu = "manta-m8p-v2";
                firmwareConfig = ./config/klipper-manta-mcu.config;
              }
            }/klipper.bin $out/klipper.bin
          '';
      # BTT Octopus V1.1 (non-Pro, STM32F446) board firmware -- the second
      # USB MCU (`[mcu octopus]`, plate drawers) from the AutoPipette axis
      # expansion plan. Same pattern and same pinned Klipper source as
      # mantaFirmware, so this board can't drift from the host either.
      # Kconfig copied verbatim from the plan's
      # reference/firmware/octopus-v1.1-f446.config (Tricca_AutoPipette
      # docs/plans/axis-expansion): 32 KiB bootloader, 12 MHz crystal.
      #
      # Ships only klipper.bin, for the same reason as mantaFirmware (#30).
      octopusFirmware =
        pkgs.runCommand "klipper-firmware-octopus-v1.1-f446-bin"
          {
            disallowedReferences = [ pkgs.gcc-arm-embedded ];
          }
          ''
            install -Dm444 ${
              klipperFirmware {
                mcu = "octopus-v1.1-f446";
                firmwareConfig = ./config/klipper-octopus-mcu.config;
              }
            }/klipper.bin $out/klipper.bin
          '';
      # `switch` invokes the system-manager CLI via `nix run`, which floats
      # to numtide/system-manager's latest commit unless pinned -- that CLI
      # can drift out of sync with the system-manager LIBRARY pinned below
      # (used to build the config it's activating). Pin the CLI to the exact
      # same rev so `switch` always matches what flake.lock says.
      system-managerRev = system-manager.rev;
      # Dirty-page/ext4-commit I/O tuning, shared between the boot-time
      # io-tuning.service (modules/io-tuning.nix) and `switch`'s own
      # defensive reapplication (modules/aliases.nix) -- one script so the
      # two can never drift out of sync. See modules/io-tuning.nix and
      # docs/incidents/nick-generation-8-upgrade.md for the full rationale
      # and history.
      ioTuningApply = pkgs.writeShellScript "io-tuning-apply" ''
        set -eu
        /usr/sbin/sysctl -w vm.dirty_background_bytes=4194304   # 4 MiB
        /usr/sbin/sysctl -w vm.dirty_bytes=16777216              # 16 MiB
        /usr/sbin/sysctl -w vm.dirty_writeback_centisecs=100     # 1s (was 5s)
        /usr/sbin/sysctl -w vm.dirty_expire_centisecs=500        # 5s (was 30s)
        /usr/bin/mount -o remount,commit=5 /
        # Give the block layer a scheduler at all. nick's default is `none`
        # -- FIFO dispatch with zero read/write fairness, so one write flood
        # parks a queue of multi-second requests in front of every read.
        #
        # Measured on nick 2026-09-03, same 512 MB `dd` under each
        # scheduler. bfq is a PARTIAL improvement, not a fix -- claimed
        # accordingly:
        #   throughput      none 3.0 MB/s   bfq 3.0 MB/s  (no change, as expected)
        #   sshd banner     none timed out  bfq 22/22 answered, worst 6.19s
        #   full ssh cmd    (not measured)  bfq 3/5 timed out at 20s,
        #                                   the 2 that landed took 7.6s
        # So bfq keeps the cheapest path (an already-resident sshd
        # accepting and writing its version string) alive, but a real
        # session -- forking a child, reading keys, PAM, spawning a shell,
        # all of it faulting pages off the same wedged card -- still
        # starves. Kept because it costs nothing and measurably helps, NOT
        # because it solves the freeze. The card is the actual problem
        # (2.5-3.0 MB/s write, ~2.9s average write-request latency, against
        # 23.8 MB/s reads at the bus ceiling); see issue #18 and
        # docs/incidents/nick-generation-8-upgrade.md.
        #
        # mq-deadline is the fallback if bfq isn't built. Best-effort --
        # device name and available schedulers vary, and this must never
        # fail a switch.
        for dev in /sys/block/mmcblk*/queue/scheduler; do
          [ -w "$dev" ] || continue
          if /usr/bin/grep -q bfq "$dev"; then
            echo bfq > "$dev" || :
          elif /usr/bin/grep -q mq-deadline "$dev"; then
            echo mq-deadline > "$dev" || :
          fi
        done
      '';
      # Background health sampler for `switch` -- appends free-memory/
      # loadavg/dirty-page/D-state-process snapshots to a log every 5s,
      # `sync`ing each write so the tail survives a hard freeze (the
      # documented failure mode: every writer on the box, including core
      # daemons, piles into D-state with no warning beforehand). $1 = log
      # file, $2 = stop-file marker -- checked each loop rather than relying
      # on signal delivery through `sudo`, which doesn't forward reliably.
      # See docs/incidents/nick-generation-8-upgrade.md.
      switchHealthSampler = pkgs.writeShellScript "switch-health-sampler" ''
        set -u
        logfile="$1"
        stopfile="$2"
        while [ ! -e "$stopfile" ]; do
          {
            echo "=== $(/usr/bin/date -Iseconds) ==="
            /usr/bin/grep -E 'MemFree|MemAvailable|SwapFree|^Dirty|Writeback' /proc/meminfo
            echo "loadavg: $(</proc/loadavg)"
            echo "-- D-state processes --"
            /usr/bin/ps -eo pid,stat,comm | /usr/bin/awk '$2 ~ /^D/'
          } >> "$logfile"
          /usr/bin/sync
          /usr/bin/sleep 5
        done
        echo "=== sampler stopped at $(/usr/bin/date -Iseconds) ===" >> "$logfile"
      '';
    in
    {
      # Applied with the `switch` shell alias (modules/aliases.nix), which
      # pins the system-manager CLI to this same flake.lock rev:
      #   sudo -i nix run "github:numtide/system-manager/<rev>" -- switch --flake /opt/cb1-autopipette
      systemConfigs.default = system-manager.lib.makeSystemConfig {
        modules = [
          ./modules/base.nix
          ./modules/networking.nix
          ./modules/klipper.nix
          ./modules/moonraker.nix
          ./modules/mainsail.nix
          ./modules/tapd.nix
          ./modules/autopipette.nix
          ./modules/kiosk.nix
          ./modules/tricca-console.nix
          ./modules/aliases.nix
          ./modules/nix-settings.nix
          ./modules/io-tuning.nix
        ];
        specialArgs = {
          inherit
            tricca-autopipette
            triccaEnv
            tricca-src
            printer-cfgs
            klipperHostMcu
            mantaFirmware
            octopusFirmware
            system-managerRev
            ioTuningApply
            switchHealthSampler
            ;
        };
      };

      checks.${system} = {
        # Proves the env tapd/the kiosk actually run imports the patched aiohttp
        # (pkgs/aiohttp.nix, issue #59), not just that the override evaluates.
        aiohttp-patched = pkgs.runCommand "aiohttp-patched" { } ''
          ${triccaEnv}/bin/python3 -c '
          from importlib.metadata import version
          import aiohttp, yarl
          assert version("aiohttp") == "3.14.5", version("aiohttp")
          assert version("yarl") == "1.25.1", version("yarl")
          '
          touch $out
        '';
        # Board firmware images, built by CI's `nix flake check` directly
        # rather than relying on some helper in systemConfigs.default
        # happening to reference them: octopusFirmware has no consumer
        # until flash-octopus lands (#50), and a firmware that stops
        # building should fail CI either way.
        inherit mantaFirmware octopusFirmware;
      };

      packages.${system} = {
        inherit tricca-autopipette mantaFirmware octopusFirmware;
        default = tricca-autopipette;
        # aarch64-linux-tricca-autopipette = (import nixpkgs { crossSystem = "aarch64-linux"; }).callPackage ./pkgs/tricca-autopipette.nix { src = tricca-src; };
      };
    };
}
