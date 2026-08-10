# printer.cfg seeds once, then is machine-owned

printer.cfg needs initial content from the `printer-cfgs` flake input, but is
also live-edited by the running machine (Klipper's `SAVE_CONFIG`, Mainsail's
config editor). It seeds ONCE into `/var/lib/moonraker/config/` on first
setup; after that the repo never overwrites it. Re-seeding on every `switch`
would silently discard calibration and other live machine state that
`SAVE_CONFIG` had written back into the file.
