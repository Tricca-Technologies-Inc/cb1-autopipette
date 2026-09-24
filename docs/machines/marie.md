# marie

**2026-09-23 — reinstalled from scratch, running current `main`.**
Armbian 26.8.1 trixie, kernel 6.18.43-current-sunxi64, bootstrapped via
bootstrap.sh + prime.sh. Full story, including three bootstrap gotchas
found along the way:
[docs/incidents/2026-09-23-marie-reinstall.md](../incidents/2026-09-23-marie-reinstall.md).

- **Network:** wifi only, NetworkManager profile for the phone hotspot
  `JamesPhoneNet`. DHCP address changes (was `.16`, then `.17` on
  10.241.253.0/24). SSH key auth from the workstation is set up.
- **Verified after reboot:** all 7 services active, Klipper `ready`,
  splash config in place (`tricca` theme, `bootlogo=true`,
  `console=serial`), no PATH-gap errors, wifi reconnects on boot.
- **Machine-owned config:** `tricca-autopipette.cfg` carries marie's hand
  tuning on top of printer-cfgs `c2b20ee`: endstops `^!PF4`/`^!PF3`,
  run_current 0.400 ×2 / 0.40 ×4. Pre-wipe backup lives in
  `~/marie-backup-2026-09-23/` on the workstation.
- **Manta firmware:** build from 2026-07-27. Klippy logs no "deprecated
  code" warning against the current host, so it hasn't been reflashed.
- **2026-09-24 — #33 + #34 deployed.** `git pull` (no-op, already at
  `d5de11b`), `./prime.sh 10.241.253.17 tricca`, `switch`. Clean, no `WARN`.
  Post-switch Klipper came up `shutdown` ("Lost communication with MCU
  'CB1'"), cascading into a real-MCU shutdown latch that `systemctl
  restart klipper` didn't clear — needed `FIRMWARE_RESTART` explicitly.
  Full forensics:
  [docs/incidents/2026-09-24-marie-switch-mcu-shutdown-cascade.md](../incidents/2026-09-24-marie-switch-mcu-shutdown-cascade.md).
  After that: all 7 services active, Klipper `ready`. Splash eyes-on and
  Ctrl+Alt+F2 → `tap` both confirmed good by James.
- **Not being used for pipette hardware / gantry movement testing for a
  while** (James's call, 2026-09-24) — no real-run verification expected
  in the near term. Pipette hardware still not installed anyway, so
  `home_all`'s plunger homing can't succeed yet; the Z-axis homing issue
  is James's.

## Storage (issue #19)

SD card: `SK32G`, manfid 0x03 / oemid `SD` (SanDisk), made 09/2025, 32 GB.
Measured on-device 2026-09-23, with the issue's exact commands, same as
nick's 2026-09-03 run:

| Measurement | marie | nick (old card, 2026-09-03) |
|---|---|---|
| Sequential write, buffered + fsync | **20.9 MB/s** | 3.0 MB/s |
| Sequential write, O_DIRECT | **21.4 MB/s** | 2.5 MB/s |
| Sequential read, O_DIRECT | 23.8 MB/s | 23.8 MB/s |
| Small-file write, 500 × 32 KB | **16.7 MB/s, 535 files/s** | 2.31 MB/s, 74 files/s |
| Avg write latency (cumulative since boot) | **~45 ms/req** | ~2.9 s/req |
| Avg read latency (cumulative since boot) | ~7 ms/req | 13.8 ms/req |

Read is 23.8 MB/s on both: that's the slot's bus ceiling, not the card.
Writes are 7–8× nick's old card, and small files 7×.

Also checked: `/` 25% used (22 GB free); block scheduler `bfq` (set by
`modules/io-tuning.nix`; `armbian-hardware-optimization` sets `none` at
boot first); `# CONFIG_PSI is not set` (same as nick, so `psi=1` is a
no-op here too). `kernel.hung_task_*` sysctls not read yet.
