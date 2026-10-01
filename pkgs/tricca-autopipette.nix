# Tricca AutoPipette packaged for Nix, per pyproject.toml on main.
#
# Source comes from the flake input `tricca-src` (see flake.nix), pinned by
# flake.lock — no hash to maintain here. Bump with: nix flake update tricca-src
#
# Prefer building on a desktop over the CB1:
#   nix build .#tricca-autopipette --system aarch64-linux
#   nix copy --to ssh://cb1 ./result

{
  lib,
  python3Packages,
  src, # passed from flake input tricca-src, pinned via flake.lock
}:

let
  cmd2-4 = python3Packages.callPackage ./cmd2.nix { };
in
python3Packages.buildPythonPackage {
  pname = "tricca-autopipette";
  version = "0.2.0";
  pyproject = true;

  inherit src;

  build-system = with python3Packages; [ setuptools ]; # pyproject: setuptools>=80

  dependencies = with python3Packages; [
    aiohttp
    cmd2-4
    fastapi
    pydantic # v2 in current nixpkgs, satisfies pydantic>=2
    uvicorn
    websockets
    numpy
  ];

  doCheck = false; # hardware-in-the-loop; tests need Moonraker mocked

  meta = {
    description = "Automation software for the Tricca AutoPipette";
    platforms = lib.platforms.linux;
  };
}
