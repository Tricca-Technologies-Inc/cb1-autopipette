{ pkgs, ... }:
{
  config = {
    nixpkgs.hostPlatform = "aarch64-linux";

    # Never build on the CB1 (1 GB RAM). Everything here should come from
    # cache.nixos.org, or be built on a desktop and pushed with `nix copy`.
    environment.systemPackages = with pkgs; [
      git
      htop
    ];
  };
}
