# cmd2 4.x: nixpkgs tops out at 3.5.1, but tricca_autopipette's `tap` shell
# depends on cmd2>=4 ("the 4.0 API break already bit once" per upstream's
# pyproject.toml comment) -- 3.x silently fails pythonRuntimeDepsCheckHook.
# Override pulls the current PyPI release instead of waiting on nixpkgs.
{
  cmd2,
  fetchPypi,
  setuptools,
  setuptools-scm,
  prompt-toolkit,
  pyperclip,
  rich,
  rich-argparse,
}:

cmd2.overridePythonAttrs (old: rec {
  version = "4.2.4";
  src = fetchPypi {
    pname = "cmd2";
    inherit version;
    hash = "sha256-mqwRWDmU9rIvq2RkGASQzDozbUbraC8UOKzr48C75T0=";
  };

  # dynamic version via setuptools-scm; no git metadata in a PyPI sdist.
  env = (old.env or { }) // {
    SETUPTOOLS_SCM_PRETEND_VERSION = version;
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # nixpkgs' prompt-toolkit is one patch release behind cmd2's floor
  # (3.0.52 vs >=3.0.53); no functional gap between those two.
  pythonRelaxDeps = [ "prompt-toolkit" ];

  dependencies = [
    prompt-toolkit
    pyperclip
    rich
    rich-argparse
  ];
})
