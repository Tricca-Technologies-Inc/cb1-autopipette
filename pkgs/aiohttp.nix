# aiohttp 3.14.5: the pinned nixpkgs ships 3.14.3, which has the aiohttp
# server DoS advisories fixed in 3.14.4/3.14.5 (issue #59), and tapd's
# control plane is an aiohttp server. Bumping nixpkgs instead would move the
# pinned Klipper.
#
# Applied only as tricca-autopipette's own dependency, not as a package-set
# override: aiohttp is a test input of truststore -> httpcore2 -> httpx2 ->
# starlette/fastapi, so overriding it set-wide rebuilds (and reruns the
# timing-sensitive test suites of) all of those under emulation instead of
# taking them from cache. Nothing else in triccaEnv uses aiohttp or yarl.
#
# Drop this file once nixpkgs is bumped deliberately past 3.14.5; the asserts
# fail evaluation as soon as that happens, so it can't linger.
{
  lib,
  aiohttp,
  yarl,
}:

assert lib.versionOlder aiohttp.version "3.14.5";
assert lib.versionOlder yarl.version "1.25.1";

let
  # aiohttp 3.14.5 requires yarl>=1.25.1; pinned nixpkgs has 1.24.5.
  yarl' = yarl.overridePythonAttrs (old: {
    version = "1.25.1";
    src = old.src.override {
      tag = "v1.25.1";
      hash = "sha256-cQsVglP3OqaQW95OYPlbWCFTs5p6L5wOzx7QCIqqJ9U=";
    };
  });
in
(aiohttp.override { yarl = yarl'; }).overridePythonAttrs (old: {
  version = "3.14.5";
  src = old.src.override {
    tag = "v3.14.5";
    hash = "sha256-gSxqab8AYJ6PsMP1PYWUxQ8TJ9KtEehoekLD8ziBt+g=";
  };
  # 3.14.5 moved the coverage warning filter nixpkgs strips from setup.cfg
  # to pytest.ini; --replace-fail errors on the old location.
  postPatch =
    builtins.replaceStrings [ "substituteInPlace setup.cfg" ] [ "substituteInPlace pytest.ini" ]
      old.postPatch;
  # Wall-clock-sensitive; both failed on the workstation's emulated aarch64
  # build (the prime.sh path): a 0.3s shutdown budget took 0.43s, and a
  # cookie-jar loop hit pytest-timeout's 120s.
  disabledTests = old.disabledTests ++ [
    "test_ssl_client_shutdown_timeout"
    "test_cookie_jar_bookkeeping_stays_consistent"
  ];
})
