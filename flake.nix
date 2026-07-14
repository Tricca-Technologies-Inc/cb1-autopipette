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
  };

  outputs = { self, nixpkgs, system-manager, tricca-src, ... }:
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
    in
    {
      # Applied with:  sudo -i nix run 'github:numtide/system-manager' -- switch --flake /opt/cb1-autopipette
      systemConfigs.default = system-manager.lib.makeSystemConfig {
        modules = [
          ./modules/base.nix
          ./modules/networking.nix
          ./modules/klipper.nix
          ./modules/autopipette.nix
          ./modules/kiosk.nix
        ];
        extraSpecialArgs = { inherit tricca-autopipette triccaEnv tricca-src; };
      };

      packages.${system} = {
        inherit tricca-autopipette;
        default = tricca-autopipette;
      };
    };
}
