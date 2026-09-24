# 2026-09-23 — marie wiped and reinstalled; three bootstrap gotchas

**Status: resolved.** marie went from a 2026-07-30 build (commit `9f6e9c9`,
Armbian 26.5.1) to a fresh Armbian 26.8.1 install on `main`, via the
documented bootstrap + prime path. Along the way the reinstall surfaced one
real bug that affects every Armbian CB1 (fixed in #32) and two traps that
are easy to fall into on any fresh machine.

## Timeline

1. **Backup.** marie wasn't on the network, but its SD card was already in
   the workstation's USB reader. Copied printer.cfg, mainsail.cfg,
   tricca-autopipette.cfg, protocols and moonraker-sql.db to
   `~/marie-backup-2026-09-23/` on the workstation. printer.cfg had no
   SAVE_CONFIG block, but **tricca-autopipette.cfg had hand edits that
   exist in no upstream version**: endstops `^!PF4`/`^!PF3` (upstream
   `^PF4`/`^PF3`) and run_current 0.400 ×2 / 0.40 ×4 (upstream 0.800 /
   0.650). A reinstall reseeds this file from `printer-cfgs`, so these
   would have been silently reverted. Checked against all four upstream
   revisions of the file.
2. **Card benchmark** (USB 2.0 reader, destructive, card was being wiped
   anyway): 19.2 / 19.1 MB/s sequential write (fsync / O_DIRECT),
   19.7 MB/s read, 330 files/s small-file. Read ≈ write means the reader
   (480M link) was the limit. Card reused. On-device numbers below.
3. **Flash** `Armbian_26.8.1_Bigtreetech-cb1_trixie_current_6.18.43_minimal`.
   Firstrun wizard: user `tricca`, wifi to the phone hotspot.
4. **bootstrap.sh part 1** stopped at "Not primed yet", as designed.
5. **prime.sh** pushed the full 3.0 GiB closure (497 paths) into an empty
   store over the hotspot, ~1–1.5 MB/s, ~40 minutes, completely silent.
   No panic, SSH responsive throughout (see #22). This prompted #29
   (progress display) and #30/#33 (the closure was ~50% build toolchain).
6. **bootstrap.sh part 2 "finished", but only half of it ran** (gotcha 1).
7. **Reboot, and wifi was gone** (gotcha 2).
8. **Re-running bootstrap hit the same error; a manual switch then left 30
   /etc files untracked** (gotcha 3).
9. Fixed all three, re-ran bootstrap cleanly, restored the motor tuning,
   rebooted, verified.

## Gotcha 1: every switch on Armbian exited 1 (fixed, #32)

Photo of the console after re-running bootstrap:

```
Setting file flags is only supported on regular files and directories, cannot set on '/var/log/journal'.
ERROR system_manager_engine::activate] Error during activation of tmp files
ERROR system_manager] Engine command exited with status 1
```

`armbian-ramlog` recreates `/var/log/journal` at every boot as a symlink to
`/var/log.hdd/journal`. Debian's `/usr/lib/tmpfiles.d/journal-nocow.conf`
line 25, `h /var/log/journal - - - - +C`, can't set a file flag on a
symlink, so `systemd-tmpfiles --create` exits 73. system-manager runs
tmpfiles over every config (Debian's included) and treats that as a failed
activation.

Services still start, so the machine looks mostly fine. But `bootstrap.sh`
runs under `set -e` and stopped right after the switch, skipping the MCU
serial detection (Klipper: `Option 'serial' in section 'mcu' must be
specified`) and the entire splash step (`bootlogo=false`, stock theme,
plymouth-quit not masked). The script's output scrolled past on the
touchscreen and the failure was easy to miss.

Confirmed on marie: `systemd-tmpfiles --create` exits 73; with only that
rule masked it exits 0. Fix: `modules/base.nix` places an empty
`/etc/tmpfiles.d/journal-nocow.conf`, which masks the /usr/lib one.
`+C` only matters on btrfs; the CB1s are ext4.

nick runs the same Armbian ramlog setup and almost certainly had this too.
Its "clean" switches may have exited 1 without anyone noticing, because
`switch` isn't run under `set -e`. Not checked.

## Gotcha 2: firstrun-wizard wifi disappears at the first reboot

The Armbian firstrun wizard stores the wifi network in
`/etc/netplan/armbian.yaml`. `modules/networking.nix` replaces that file
(`replaceExisting`) with one that deliberately has no `wifis:` block —
wifi is meant to live in a NetworkManager profile instead (ADR-0006).
Confirmed: the backed-up `armbian.yaml.system-manager-backup` is the one
with the `wifis:` block. The old connection keeps working until the next
reboot, so bootstrap's closing "1. wifi: sudo nmcli device wifi connect …"
step looks unnecessary, and the machine comes back from its reboot with no
network.

Fix on the machine: `sudo nmcli device wifi connect "SSID" password "…"
ifname wlan0`. That profile survives reboots and switches.

## Gotcha 3: a failed first switch leaves /etc files untracked

After the #32 fix, a manual `switch` completed but printed 30 of these:

```
WARN system_manager_engine::activate::etc_files] Error while creating file in /etc:
  Unmanaged path already exists in filesystem, please remove it and run system-manager again: /etc/systemd/system/klipper.service
```

The failed first switch had created the /etc symlinks but never recorded
them in `/var/lib/system-manager/state/system-manager-state.json`
(`fileTree.files` listed only `journal-nocow.conf`). Every later switch
treats them as foreign and skips them. All 30 still pointed into the
current generation's closure, so the content was right today, but any
future change to a unit file or `tricca-aliases.sh` would have been
skipped with only a WARN.

Fix, done over SSH as root: save each link (`path target`) to a file,
remove them, run the pinned switch, and restore the saved links if the
switch fails. Result: 0 WARN, 0 ERROR, 31 files tracked.

## Final state (verified 2026-09-23 17:13 MDT, after a reboot)

- All 7 services active, no failed units, Klipper `ready` (Manta + CB1
  host MCU, marie's restored endstop/current values).
- Splash: `bootlogo=true`, `console=serial`, `extraargs=quiet loglevel=0`,
  theme `tricca`, both plymouth-quit units masked.
- No PATH-gap signatures in the journal. Wifi reconnected on its own.
- `/protocols` lists `home_all`; Mainsail HTTP 200.
- Not yet: eyes-on splash check, Ctrl+Alt+F2 → `tap`, a real pipette run
  (no pipette hardware installed).

## Loose end: missing journal for the bootstrap boots

The persistent journal kept only the first 505 s of the boot where
bootstrap and the prime ran (over two hours), and only 13 s of the next
boot. The next clean `systemctl reboot` kept its boot in full. That points
to the earlier boots ending in hard power-offs rather than clean reboots,
which would matter for #22 if they were freezes. Not established.
