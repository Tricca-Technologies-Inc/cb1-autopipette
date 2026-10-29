#!/usr/bin/env bash
# Post-switch health summary (issue #69). Waits up to HEALTH_TIMEOUT seconds
# (default 60) for Klipper to report `ready` and for every unit below to be
# active, then prints one line per check. For a unit that isn't active it
# also prints the tail of its journal. Exits 1 if anything is unhealthy.
# It only reports and never fixes anything.
#
# Called by the `switch` alias (modules/aliases.nix), as root so journalctl
# can read every unit. Also safe to run on its own:
#   sudo bash /opt/cb1-autopipette/scripts/switch-health-check.sh
#
# HEALTH_TIMEOUT and PRINTER_INFO_URL can be overridden; the tests set them.
set -uo pipefail

TIMEOUT="${HEALTH_TIMEOUT:-60}"
URL="${PRINTER_INFO_URL:-http://127.0.0.1:7125/printer/info}"
UNITS=(klipper-mcu klipper moonraker tapd autopipette kiosk)

klipper_state() {
  # Prints "<state>\t<state_message>", or "unreachable" if Moonraker doesn't
  # answer with JSON.
  local out
  out=$(curl -s --max-time 5 "$URL" |
    jq -r '.result | select(.) | "\(.state)\t\(.state_message // "")"' 2>/dev/null)
  echo "${out:-unreachable}"
}

all_healthy() {
  [ "$(klipper_state | head -n 1 | cut -f1)" = ready ] || return 1
  for u in "${UNITS[@]}"; do
    systemctl is-active -q "$u" || return 1
  done
}

deadline=$((SECONDS + TIMEOUT))
until all_healthy || [ "$SECONDS" -ge "$deadline" ]; do
  sleep 2
done

echo "==> health after switch"
rc=0
state=$(klipper_state)
kstate=${state%%$'\t'*}
if [ "$kstate" = ready ]; then
  echo "    OK    klipper state: ready"
else
  rc=1
  echo "    FAIL  klipper state: $kstate"
  # state_message can span lines; the first few say what's wrong.
  if [ "$state" != "$kstate" ]; then
    printf '%s\n' "${state#*$'\t'}" | head -n 3 | sed 's/^/            /'
  fi
fi
for u in "${UNITS[@]}"; do
  s=$(systemctl is-active "$u" 2>/dev/null)
  if [ "$s" = active ]; then
    echo "    OK    $u"
  else
    rc=1
    echo "    FAIL  $u: ${s:-unknown}"
    journalctl -u "$u" -n 5 --no-pager -o cat 2>/dev/null | sed 's/^/            /'
  fi
done
[ "$rc" -eq 0 ] || echo "    Machine is NOT healthy. See the FAIL lines above."
exit "$rc"
