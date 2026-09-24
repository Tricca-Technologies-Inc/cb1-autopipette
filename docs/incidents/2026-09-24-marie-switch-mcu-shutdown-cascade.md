# 2026-09-24 — switch restarts klipper-mcu mid-connection, cascades to a real MCU shutdown (marie)

**Status: resolved**, recovery is a one-command follow-up (`FIRMWARE_RESTART`)
until/unless `switch` is taught to do it automatically. Likely to recur on
any machine, any time `switch` touches `klipper-mcu.service` while Klipper
is running.

## Context

Deploying #33 (closure slimming) + #34 (nixfmt/lint) to marie: `git pull`
(already at `d5de11b`), `./prime.sh 10.241.253.17 tricca`, `switch`. The
switch itself completed clean — no `WARN` lines, all 7 services came back
`active`.

## Symptom

Post-switch, `curl 127.0.0.1:7125/printer/info` showed:

```
"state":"shutdown","state_message":"Lost communication with MCU 'CB1'\n..."
```

`klipper-mcu.service` itself was healthy (`active (running)`, fresh PID).
`journalctl`/`klippy.log` showed the real sequence:

```
=============== Log rollover at Thu Sep 24 10:34:42 2026 ===============
b'Got EOF when reading from device'
Timeout with MCU 'CB1' (eventtime=62805.459867)
Transition to shutdown state: Lost communication with MCU 'CB1'
...
MCU 'mcu' shutdown:
```

`switch`'s service-restart step (`Restarting systemd services`) restarted
`klipper-mcu.service` — a fresh process, fresh PTY — while `klippy`
(`klipper.service`) was still holding the file descriptor to the *old*
`klipper-mcu` process. That FD died from under it (`Got EOF`), which
`klippy` correctly treats as CB1 (the host-side virtual MCU) going dark.

The interesting part: Klipper's shutdown isn't scoped to the one MCU that
faulted. Losing CB1 pushes the whole printer object into `shutdown`, which
sends an actual shutdown command down the wire to the *other* MCU too —
the real Manta board (`'mcu'`), over its physical serial link, completely
unrelated to the CB1 restart race. That board's firmware then latches its
own internal shutdown state, which a plain `systemctl restart klipper`
(or even `systemctl restart klipper-mcu klipper` together) does **not**
clear — both attempts left it in:

```
mcu.error: Can not update MCU 'mcu' config as it is shutdown
```

This matches Klipper's own message verbatim: `Once the underlying issue is
corrected, use the "FIRMWARE_RESTART" command to reset the firmware,
reload the config, and restart the host software.` Restarting the host
software (`klipper.service`) alone re-opens the serial ports but does not
send the actual firmware-level reset/restart sequence that clears a
latched shutdown on a *real* MCU — only `FIRMWARE_RESTART` (via console/API)
does that.

## Fix

```
curl -s -X POST http://127.0.0.1:7125/printer/firmware_restart
```

(equivalent to sending `FIRMWARE_RESTART` from `tap`/Mainsail's console).
Immediately after: `state":"ready","state_message":"Printer is ready"`. All
7 services stayed `active` throughout — this is purely a Klipper-level
firmware-shutdown-latch problem, not a systemd/service problem, so
`systemctl restart` on any of the Klipper-adjacent units doesn't touch it.

## Open question / possible follow-up

Should `switch` (or a wrapper around it) send `FIRMWARE_RESTART` automatically
whenever it restarts `klipper-mcu.service`, instead of leaving the operator to
notice the `shutdown` state and issue it by hand? Not done here — filing this
as a write-up only, per James's ask. If this recurs on `nick` or a future
machine, that's the point to make it automatic.
