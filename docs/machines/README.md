# Machine status

Live snapshots of the fleet — overwrite these in place as status changes,
don't append history here. Incident write-ups and hard-won lessons belong
in [`docs/incidents/`](../incidents/) instead; README's Troubleshooting
section holds the short evergreen version of any lesson worth a human
knowing before they debug from scratch.

- [nick.md](nick.md)
- [marie.md](marie.md)

## Fleet-wide feature status

**tapd control daemon: shipped and verified; live hardware runs in progress.**
The old subprocess-bridge architecture (kiosk spawning `tap` as a
subprocess) is gone, replaced by tapd (see CLAUDE.md's Architecture
section) — this was the owner's own TODO from an earlier session, now done
and pinned. Verified: kiosk correctly lists `/protocols` and reports
`/status` through tapd's control-plane websocket, homing succeeded,
Mainsail jog commands worked after the MCU serial fix. **Not yet verified:**
a complete, successful liquid-handling run of a real `.pipette` protocol
through the kiosk.
