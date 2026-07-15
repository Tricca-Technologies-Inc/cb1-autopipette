# Tricca AutoPipette packaged for Nix, per pyproject.toml on main.
#
# Source comes from the flake input `tricca-src` (see flake.nix), pinned by
# flake.lock — no hash to maintain here. Bump with: nix flake update tricca-src
#
# Prefer building on a desktop over the CB1:
#   nix build .#tricca-autopipette --system aarch64-linux
#   nix copy --to ssh://cb1 ./result

{ lib
, python3Packages
, src  # passed from flake input tricca-src, pinned via flake.lock
}:

python3Packages.buildPythonPackage {
  pname = "tricca-autopipette";
  version = "0.1.0";
  pyproject = true;

  inherit src;

  # pyproject declares the PyPI name "opencv-python"; nixpkgs provides the
  # same cv2 module via opencv4 (in dependencies below), which doesn't
  # register that dist name — strip it from wheel metadata so the
  # runtime-deps check passes.
  pythonRemoveDeps = [ "opencv-python" ];

  build-system = with python3Packages; [ setuptools ]; # pyproject: setuptools>=80

  dependencies = with python3Packages; [
    aiohttp
    cmd2
    fastapi
    opencv4      # nixpkgs name for the cv2 binding (opencv-python on PyPI)
    pydantic     # v2 in current nixpkgs, satisfies pydantic>=2
    requests
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
