# Tricca AutoPipette packaged for Nix, per pyproject.toml (2026-07-13).
#
# Remaining TODOs before first build:
#   - hash: run once with lib.fakeHash, paste the printed hash
#   - BLOCKER: main @ 8b2cbbb contains only the core library. The kiosk app
#     lives on the `gui` branch, top-level (not src/), so it is excluded from
#     the wheel. Merge it under src/autopipette_kiosk first — see README.
#
# Build on a desktop, never the CB1:
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

  src = fetchFromGitHub {
    owner = "Tricca-Technologies-Inc";
    repo = "Tricca_AutoPipette";
    # main as of 2026-07-13. NOTE: kiosk app not yet on main — see README.
    rev = "8b2cbbbc822d2650483046ac20c9c4f802396b0b";
    # First build fails printing the real hash — paste it here:
    hash = lib.fakeHash;
  };

  build-system = with python3Packages; [ setuptools ]; # pyproject: setuptools>=80

  dependencies = with python3Packages; [
    aiohttp
    cmd2
    opencv4      # nixpkgs name for the cv2 binding (opencv-python on PyPI)
    pydantic     # v2 in current nixpkgs, satisfies pydantic>=2
    requests
    websockets
    numpy
    # Required by the kiosk app but MISSING from pyproject [project.dependencies]:
    fastapi
    # uvicorn comes from triccaEnv in flake.nix (it's the server, not a lib dep,
    # though adding it to pyproject too is harmless and keeps venv dev workflows working)
  ];

  # requires-python = ">=3.12" — nixpkgs python3 is currently fine; pin
  # python312 explicitly in flake.nix if nixpkgs default ever drifts below.

  doCheck = false; # hardware-in-the-loop; tests need Moonraker mocked

  meta = {
    description = "Automation software for the Tricca AutoPipette";
    platforms = lib.platforms.linux;
  };
}
