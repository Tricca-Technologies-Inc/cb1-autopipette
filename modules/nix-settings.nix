# Grants `tricca` (the SSH/admin account) enough Nix trust to receive a
# `prime`d closure pushed from a workstation via `nix copy --to
# ssh://tricca@<host>` -- by default only `root` is a trusted user, so an
# unprivileged push is rejected outright. Declarative (ships via `switch`,
# like everything else) rather than a manual one-off `nix.conf` edit or
# enabling root SSH login. See ADR-0009.
{
  config = {
    nix.settings.trusted-users = [ "tricca" ];
  };
}
