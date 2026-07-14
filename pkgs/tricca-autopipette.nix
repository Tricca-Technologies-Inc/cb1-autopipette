# Tricca AutoPipette packaged for Nix, per pyproject.toml (2026-07-13).
#
# Remaining TODOs before first build:
#   - hash: run once with lib.fakeHash, paste the printed hash
#   - BLOCKER: main @ 8b2cbbb contains only the core library. The kiosk app
#     lives on the `gui` branch, top-level (not src/), so it is excluded from
#     the wheel. Merge it under src/autopipette_kiosk first — see README.
#
# The CB1 builds this package itself during `switch` — it's pure Python and
# takes seconds. Avoid building anything HEAVY on the CB1 (1 GB RAM): if a
# nixpkgs bump ever cache-misses a big dependency (e.g. opencv), build on a
# desktop and push instead:
#   nix build .#tricca-autopipette --system aarch64-linux
#     (x86_64 desktop: needs qemu binfmt + extra-platforms, or a remote
#      aarch64 builder; see nixos.wiki "cross compiling")
#   nix copy --to ssh://cb1 ./result
#     (your ssh user must be a trusted-user on the CB1's nix.conf, and both
#      machines must share the same committed flake.lock)

{ lib
, python3Packages
, src  # passed from flake input tricca-src, pinned via flake.lock
}:

python3Packages.buildPythonPackage {
  pname = "tricca-autopipette";
  version = "0.1.0";
  pyproject = true;

  inherit src;

  build-system = with python3Packages; [ setuptools ]; # pyproject: setuptools>=80

  dependencies = with python3Packages; [
    aiohttp
    cmd2
    opencv4      # nixpkgs name for the cv2 binding (opencv-python on PyPI)
    pydantic     # v2 in current nixpkgs, satisfies pydantic>=2
    requests
    websockets
    numpy
    fastapi
    uvicorn
  ];

  doCheck = false; # hardware-in-the-loop; tests need Moonraker mocked

  meta = {
    description = "Automation software for the Tricca AutoPipette";
    platforms = lib.platforms.linux;
  };
}
