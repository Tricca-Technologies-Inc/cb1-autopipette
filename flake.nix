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

  outputs = { self, nixpkgs, system-manager, tricca-src, printer-cfgs, ... }:
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
      # Host MCU: klipper.elf built for the "Linux process" target, running on
      # the CB1 itself (printer.cfg: [mcu CB1] serial=/tmp/klipper_host_mcu).
      # Built from the SAME pinned klipper source as klippy, so host-MCU and
      # klippy protocol versions can never mismatch.
      klipperHostMcu = pkgs.klipper-firmware.override {
        mcu = "host";
        firmwareConfig = ./config/klipper-host-mcu.config;
      };
      # Manta M8P V2.0 board firmware, built from the SAME pinned Klipper
      # source as klippy/klipperHostMcu -- keeps the physical board's
      # firmware from drifting out of sync with the host (see README field
      # notes: "MCU has deprecated code" means the board needs reflashing).
      # Flashing itself is still manual; this only produces the binary.
      mantaFirmware = pkgs.klipper-firmware.override {
        mcu = "manta-m8p-v2";
        firmwareConfig = ./config/klipper-manta-mcu.config;
      };
      # `switch` invokes the system-manager CLI via `nix run`, which floats
      # to numtide/system-manager's latest commit unless pinned -- that CLI
      # can drift out of sync with the system-manager LIBRARY pinned below
      # (used to build the config it's activating). Pin the CLI to the exact
      # same rev so `switch` always matches what flake.lock says.
      system-managerRev = system-manager.rev;
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
        ];
        specialArgs = { inherit tricca-autopipette triccaEnv tricca-src printer-cfgs klipperHostMcu mantaFirmware system-managerRev; };
      };

      packages.${system} = {
        inherit tricca-autopipette mantaFirmware;
        default = tricca-autopipette;
        # aarch64-linux-tricca-autopipette = (import nixpkgs { crossSystem = "aarch64-linux"; }).callPackage ./pkgs/tricca-autopipette.nix { src = tricca-src; };
      };
    };
}
