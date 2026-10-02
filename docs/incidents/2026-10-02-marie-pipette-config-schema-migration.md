# 2026-10-02 — marie: tapd crash-loop after tricca-src bump, machine-owned pipette configs needed a schema migration

## Summary

Deploying tricca-src `5859597` to marie (#47) put `tapd.service` into a
crash-restart loop: every startup failed `PipetteModel` validation with
`syringe.max_travel_mm — Field required`. Root cause: marie's three
machine-owned pipette config files under
`/var/lib/autopipette/config/pipettes/` were seeded once from an older
tricca-src rev (see `modules/tapd.nix`'s seed-once pattern, same as
`printer.cfg` per ADR-0005) and predated a breaking upstream schema change.
Fixed by copying upstream's current shared pipette configs onto marie —
verified first that they were the *same* calibration data, just migrated,
not different numbers.

## Timeline

1. Bumped tricca-src in PR #41 (`efb3e2c` → `b2a084a`) alongside an
   unrelated cmd2 packaging fix. #41 was opened from a branch that had
   already been (separately, partially) merged as #40 — squash-merging
   #41 against post-#40 main dropped the tricca-src hunk silently; only
   the nixpkgs bump and cmd2 fix landed. Main stayed pinned at `efb3e2c`.
   Caught by re-checking flake.lock after deploying, not by any error —
   worth remembering that a squash-merge diff against a moving base can
   silently drop a hunk with no conflict marker if the base already
   contains equivalent-looking content.
2. Re-bumped straight to upstream main (`5859597`) in #47, merged clean.
3. Primed + pushed to marie, ran `switch`. Activation itself succeeded
   (all services registered), but `tapd.service` immediately crash-looped:

   ```
   [json_config_manager] ERROR: Failed to load default pipette default_p100.json: 1 validation error for PipetteModel
   syringe.max_travel_mm
     Field required [type=missing, ...]
   ```

   `autopipette.service` came up but couldn't reach tapd's control-plane
   websocket (`127.0.0.1:8765`) as a result — "Cannot connect to host
   127.0.0.1:8765", retrying with backoff.

4. Traced to three commits that landed between `efb3e2c` and `b2a084a`
   (so this was always pending, just never actually deployed until this
   bump actually took):
   - `feat!: syringe travel limit (max_travel_mm), real-mm syringe units,
     steps→mm rename` — adds `max_travel_mm` as a **required** field,
     renames `calibration_steps` → `calibration_mm`.
   - `fix(config)!: express syringe quantities in real millimetres` —
     rescales every syringe distance/speed/accel value by exactly `0.25`
     (marie's `[manual_stepper pipette_stepper]` uses
     `rotation_distance: 2` on a 2 mm-lead screw; the old values were
     computed for `rotation_distance: 8`, so they were 4× inflated).

5. Compared marie's live `default_p100.json` against upstream's current
   `config/pipettes/default_p100.json` (same path, now shipped inside
   tricca-src itself): same `calibration_volumes` array, and
   `live.calibration_steps[i] * 0.25 == upstream.calibration_mm[i]`
   exactly, for all three files. Upstream's shared default **is** this
   rig's own calibration, already migrated — not a guess, not a generic
   template. `max_travel_mm: 60.0` matches the Hamilton 100 µL's real
   stroke (also what `modules/`-side kiosk settings bounds to, per
   tricca-src's `CLAUDE.md`).
6. Copied upstream's three pipette JSON files onto marie (`scp` to
   `/tmp`, then `cp` into place as root, `chown pipette:root`,
   `chmod 644` — matching the existing files' ownership), restarted
   `tapd.service` and `autopipette.service`. Clean start, no further
   errors. Klipper came up `ready` this time (no MCU-shutdown latch, see
   contrast with
   [2026-09-24's cascade](2026-09-24-marie-switch-mcu-shutdown-cascade.md)).

## Why this didn't show up in CI or the nix build

`nix build .#tricca-autopipette` only packages the Python code; it
doesn't validate a machine's actual `/var/lib/autopipette/config/*`
against the new pydantic schema, because that data isn't nix-managed —
it's seeded once per machine and then owned by the machine (deliberately,
so operators can hand-tune calibration without nix churning it). A
schema-breaking change in tricca-src is therefore invisible to this
repo's build/lint/CI until it actually runs against a real machine's
seeded config.

## Takeaway

When bumping `tricca-src` past a commit that changes the shape of
anything under `config/` (pipette/gantry/liquid/system JSON), check
whether any already-deployed machine's seeded copy under
`/var/lib/autopipette/config/` needs the same migration upstream applied
to its own shared defaults — `git log` the relevant `config/` subpath
between the old and new pin, not just `src/`. If the old and new shared
defaults carry the *same* calibration data (as they did here), that's a
strong signal the fix is "copy upstream's new version across," not
"invent new numbers."
