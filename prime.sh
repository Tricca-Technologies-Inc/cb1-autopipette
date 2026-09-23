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

echo "==> [1/4] checking workstation can build aarch64-linux (emulation)"
if ! nix show-config 2>/dev/null | grep -E "^extra-platforms" | grep -q aarch64-linux; then
  cat >&2 <<'EOF'
workstation is missing aarch64-linux build support -- one-time setup:
  sudo apt-get install -y qemu-user-static binfmt-support
  echo 'extra-platforms = aarch64-linux' | sudo tee -a /etc/nix/nix.custom.conf
  sudo systemctl restart nix-daemon
EOF
  exit 1
fi

echo "==> [2/4] checking $HOST's checkout matches this one"
# The machine's `switch` builds ITS checkout's systemConfigs.default. If
# that isn't the exact tree built here, the push below (tens of minutes
# over a hotspot for a fresh machine) primes a closure switch never asks
# for, and switch still refuses with "Not primed yet". Uncommitted edits to
# tracked files count too: a git flake builds them, and the machine can't
# have them. The machine's repo is root-owned, hence safe.directory.
if ! git -C "$REPO_DIR" diff --quiet HEAD; then
  echo "    workstation checkout has uncommitted changes to tracked files --" >&2
  echo "    the machine can't have those; commit+push+pull them, or stash." >&2
  exit 1
fi
LOCAL_REV=$(git -C "$REPO_DIR" rev-parse HEAD)
# shellcheck disable=SC2086  # NIX_SSHOPTS is a word list by design
if ! REMOTE_REV=$(ssh ${NIX_SSHOPTS:-} "$SSH_USER@$HOST" \
     git -c safe.directory=/opt/cb1-autopipette -C /opt/cb1-autopipette rev-parse HEAD); then
  echo "    couldn't read /opt/cb1-autopipette's commit on $HOST (not cloned yet?)" >&2
  exit 1
fi
if [ "$LOCAL_REV" != "$REMOTE_REV" ]; then
  echo "    mismatch: workstation at ${LOCAL_REV:0:7}, $HOST at ${REMOTE_REV:0:7}." >&2
  echo "    Get both onto the same commit (usually: git pull on each), then re-run." >&2
  exit 1
fi
echo "    both at ${LOCAL_REV:0:7}"

echo "==> [3/4] building systemConfigs.default (aarch64-linux, via emulation)"
OUT_PATH=$(nix build "$REPO_DIR"#systemConfigs.default --print-out-paths)
echo "    built: $OUT_PATH"

echo "==> [4/4] pushing to $SSH_USER@$HOST"
# Needs $SSH_USER in the target's `nix.settings.trusted-users` (see
# modules/nix-settings.nix) or the daemon on the far end rejects the push.
# A machine bootstrapped before this repo's bootstrap.sh gained its own
# trusted-users step (2026-09-08) won't have this yet -- give a clear fix
# instead of raw Nix noise if that's what's actually wrong.
#
# nix copy prints nothing while it works (its output is captured below for
# the trust-error check), and a full closure into a fresh machine's empty
# store is ~3 GiB -- tens of silent minutes over a phone hotspot. Run it in
# the background behind a throbber instead -- but only with non-interactive
# (key) SSH auth: a password prompt would land mid-throbber and get drawn
# over. Sharing a pre-authenticated master connection doesn't work around
# that: nix passes `-S none` to ssh, which overrides any ControlPath.
COPY_LOG=$(mktemp)
trap 'rm -f "$COPY_LOG"' EXIT
# shellcheck disable=SC2086  # NIX_SSHOPTS is a word list by design
if [ -t 2 ] && ssh ${NIX_SSHOPTS:-} -o BatchMode=yes -o ConnectTimeout=10 \
     "$SSH_USER@$HOST" true 2>/dev/null; then
  NIX_SSHOPTS="${NIX_SSHOPTS:-} -o BatchMode=yes" \
    nix copy --to "ssh://$SSH_USER@$HOST" "$OUT_PATH" >"$COPY_LOG" 2>&1 &
  COPY_PID=$!
  # Bytes sent = the ssh child's write counter. Only an upper bound is known
  # for the total: paths the machine already has are skipped.
  CLOSURE_MIB=$(( $(nix path-info -S "$OUT_PATH" | awk '{print $2}') / 1048576 ))
  FRAMES="|/-\\"; i=0; START=$SECONDS
  while kill -0 "$COPY_PID" 2>/dev/null; do
    SSH_PID=$(pgrep -P "$COPY_PID" -x ssh | head -1 || true)
    SENT=$(awk '/^wchar/{print $2}' "/proc/${SSH_PID:-0}/io" 2>/dev/null || echo 0)
    printf '\r    %s pushing... %dm%02ds, %d MiB sent (full closure: %d MiB)' \
      "${FRAMES:i++%4:1}" $(( (SECONDS - START) / 60 )) $(( (SECONDS - START) % 60 )) \
      $(( ${SENT:-0} / 1048576 )) "$CLOSURE_MIB" >&2
    sleep 0.25
  done
  printf '\r\033[K' >&2
  COPY_CMD=(wait "$COPY_PID")
else
  [ -t 2 ] && echo "    (no SSH key auth to $HOST -- no progress shown; 'ssh-copy-id $SSH_USER@$HOST' enables it)" >&2
  COPY_CMD=(nix copy --to "ssh://$SSH_USER@$HOST" "$OUT_PATH")
fi
if ! "${COPY_CMD[@]}" >>"$COPY_LOG" 2>&1; then
  COPY_OUT=$(cat "$COPY_LOG")
  echo "$COPY_OUT" >&2
  # ssh's own login failure ("user@host: Permission denied (publickey,...)")
  # also says "permission denied" -- rule it out before blaming Nix trust.
  if echo "$COPY_OUT" | grep -q "Permission denied ("; then
    echo >&2
    echo "SSH login to $SSH_USER@$HOST failed -- check the password/key, not Nix trust." >&2
  elif echo "$COPY_OUT" | grep -qiE "signature|trusted|not allowed|permission denied"; then
    cat >&2 <<EOF

Looks like a trust problem, not a network one: $SSH_USER isn't a trusted
Nix user on $HOST yet. Fix on $HOST (over SSH):
    echo "trusted-users = root $SSH_USER" | sudo tee -a /etc/nix/nix.custom.conf
    sudo systemctl restart nix-daemon
then re-run this script. (bootstrap.sh does this automatically as of
2026-09-08 -- this only bites a machine bootstrapped before that, or one
where prime.sh is run out of the documented order.)
EOF
  fi
  exit 1
fi
echo "    pushed: $OUT_PATH"

echo "==> done -- on $HOST, run: switch   (finds this build already in the store, skips fetching it)"
