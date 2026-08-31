#!/usr/bin/env bash
# Run from a WORKSTATION checkout of this repo (not on a CB1). Builds
# systemConfigs.default locally and pushes the closure straight into a
# machine's Nix store over SSH -- so the `switch` that follows finds the
# build already present and skips fetching/building it from the internet.
# For when a machine only has wifi/hotspot internet too slow or unreliable
# for `switch` to build on-device directly. See ADR-0009 and README's
# "Updating machines" section.
#
# Requires: workstation and the target machine joined to the same local
# network (wifi or hotspot -- doesn't need to be ethernet, does need to be
# the same network, not routed over the internet).
set -euo pipefail

usage() { echo "usage: ./prime.sh <machine-hostname-or-ip> [ssh-user]" >&2; exit 1; }

HOST="${1:-}"; [ -n "$HOST" ] || usage
SSH_USER="${2:-tricca}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/3] checking workstation can build aarch64-linux (emulation)"
if ! nix show-config 2>/dev/null | grep -E "^extra-platforms" | grep -q aarch64-linux; then
  cat >&2 <<'EOF'
workstation is missing aarch64-linux build support -- one-time setup:
  sudo apt-get install -y qemu-user-static binfmt-support
  echo 'extra-platforms = aarch64-linux' | sudo tee -a /etc/nix/nix.custom.conf
  sudo systemctl restart nix-daemon
EOF
  exit 1
fi

echo "==> [2/3] building systemConfigs.default (aarch64-linux, via emulation)"
OUT_PATH=$(nix build "$REPO_DIR"#systemConfigs.default --print-out-paths)
echo "    built: $OUT_PATH"

echo "==> [3/3] pushing to $SSH_USER@$HOST"
# Needs $SSH_USER in the target's `nix.settings.trusted-users` (see
# modules/nix-settings.nix) or the daemon on the far end rejects the push.
nix copy --to "ssh://$SSH_USER@$HOST" "$OUT_PATH"

echo "==> done -- on $HOST, run: switch   (finds this build already in the store, skips fetching it)"
