#!/usr/bin/env bash
# Off-device tests for scripts/switch-health-check.sh (issue #69), using fake
# curl/systemctl/journalctl on PATH. Needs jq. Run by the flake check
# `switch-health-check`, or directly:
#   bash tests/switch-health-check.test.sh [path/to/switch-health-check.sh]
set -euo pipefail

SCRIPT="${1:-$(dirname "$0")/../scripts/switch-health-check.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Fakes read their answers from files in $WORK:
#   printer-info  -> curl's body (missing = Moonraker not answering)
#   down          -> one unit name per line that is not active
cat >"$WORK/bin/curl" <<EOF
#!$BASH
[ -f "$WORK/printer-info" ] || exit 7
cat "$WORK/printer-info"
EOF
cat >"$WORK/bin/systemctl" <<EOF
#!$BASH
[ "\$1" = is-active ] || exit 2
[ "\$2" = -q ] && { shift; q=1; }
if grep -qx "\$2" "$WORK/down" 2>/dev/null; then
  [ -n "\${q:-}" ] || echo failed
  exit 3
fi
[ -n "\${q:-}" ] || echo active
EOF
cat >"$WORK/bin/journalctl" <<EOF
#!$BASH
echo "journal line for \$2"
EOF
chmod +x "$WORK/bin/"*

run() { # sets $rc and $out
  rc=0
  out=$(PATH="$WORK/bin:$PATH" HEALTH_TIMEOUT=0 bash "$SCRIPT" 2>&1) || rc=$?
}
expect_out() { grep -qF -- "$1" <<<"$out" || fail "output lacks '$1'; got:"$'\n'"$out"; }

ready='{"result":{"state":"ready","state_message":"Printer is ready"}}'

# Healthy: all OK, exit 0.
echo "$ready" >"$WORK/printer-info"
: >"$WORK/down"
run
[ "$rc" -eq 0 ] || fail "healthy machine exited $rc: $out"
expect_out "OK    klipper state: ready"
expect_out "OK    kiosk"
grep -q FAIL <<<"$out" && fail "healthy machine printed FAIL: $out"

# nick 2026-10-28: Klipper config error, multi-line state_message.
cat >"$WORK/printer-info" <<'EOF'
{"result":{"state":"error","state_message":"Option 'serial' in section 'mcu' must be specified\n\nOnce the underlying issue is corrected, use the\n\"RESTART\" command to reload the config and restart the host software."}}
EOF
run
[ "$rc" -eq 1 ] || fail "klipper error exited $rc"
expect_out "FAIL  klipper state: error"
expect_out "Option 'serial' in section 'mcu' must be specified"
expect_out "OK    tapd"

# A unit down: FAIL with its journal tail, exit 1.
echo "$ready" >"$WORK/printer-info"
echo tapd >"$WORK/down"
run
[ "$rc" -eq 1 ] || fail "tapd down exited $rc"
expect_out "FAIL  tapd: failed"
expect_out "journal line for tapd"
expect_out "OK    klipper state: ready"

# Moonraker not answering.
rm "$WORK/printer-info"
: >"$WORK/down"
run
[ "$rc" -eq 1 ] || fail "moonraker unreachable exited $rc"
expect_out "FAIL  klipper state: unreachable"

# JSON-RPC error reply instead of a result.
echo '{"error":{"code":503,"message":"Klippy Host not connected"}}' >"$WORK/printer-info"
run
[ "$rc" -eq 1 ] || fail "error reply exited $rc"
expect_out "FAIL  klipper state: unreachable"

echo "switch-health-check: all tests passed"
