# 2026-09-08 — SD card swap, ethernet driver fix, and a recurring MMC hung_task panic (nick)

**Status: open.** Two real problems got fixed this session (bad SD card,
dead ethernet). A third — the actual freeze/panic that's dogged every
`switch` attempt since generation 8 — reproduced again on the new card,
new kernel, with a mitigation applied, so it survives this session's fixes.
Machine is currently down; needs another physical power-cycle before
anything else can be tried.

Context: this follows directly from
[nick-generation-8-upgrade.md](nick-generation-8-upgrade.md) (ten prior
freeze/hang attempts, root-caused 2026-09-03 to a 3 MB/s SD card, issue
[#18](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/18)).
That card has now been replaced. The panic below is **the same call-trace
signature already seen once before**, in
[2026-07-30-oom-corruption-kernel-panic.md](2026-07-30-oom-corruption-kernel-panic.md)
— see "What this isn't" below for why that incident's fix doesn't explain
this recurrence.

## Part 1 — SD card replacement (resolved)

Per issue #18's plan: config backup already existed
(`~/nick-backup-2026-09-03/` on the workstation, taken 2026-09-03).

New card benchmarked via a USB reader on the workstation, same three `dd`
commands as the original diagnosis:

| Measurement | Old card (2026-09-03) | New card (2026-09-08, USB reader) |
|---|---|---|
| Sequential write, buffered + `fsync` | 3.0 MB/s | **36.6 MB/s** |
| Sequential write, `O_DIRECT` | 2.5 MB/s | **37.5 MB/s** |
| Sequential read, `O_DIRECT` | 23.8 MB/s | **88.2 MB/s** |

12-15x better on write, the dimension that mattered. Card was trusted and
flashed.

**Caveat, not yet closed out:** this benchmark ran through the
workstation's USB reader, not nick's own onboard slot/controller, and it's
a sequential pattern — not the small-file shape (`500 x 32 KB`, matching
nix's actual copy-in) that the original diagnosis also measured
separately and found disproportionately worse (2.31 MB/s, 74 files/s) even
relative to the old card's already-bad sequential numbers. That small-file
benchmark has **not** been repeated on the new card, in nick's own slot.
This gap matters — see "Leading theory" below.

## Part 2 — Ethernet driver fix (resolved)

nick's onboard ethernet had never worked on any prior image (PHY never
detected, flagged as an open item since the generation-8 saga began).
Investigated fresh this session rather than re-flashing blind:

- Armbian [PR #10155](https://github.com/armbian/build/pull/10155)
  (merged 2026-07-11) fixes exactly this on the H616 SoC: EMAC1 needed
  rewiring to the **Allwinner AC300 EPHY** via an internal MDIO mux,
  landing in the `sunxi-6.18` and `sunxi-7.0` kernel branches — not
  `sunxi-6.12` ("legacy"), which lacks H616 internal-PHY support entirely.
- The image already on hand (`Armbian_26.2.1_..._trixie_current_6.12.68_minimal.img.xz`,
  downloaded 2026-07-09) was exactly that unfixed 6.12 legacy branch — not
  a bad flash, just the wrong kernel line, downloaded two days before the
  fix even merged.
- Re-downloaded current Armbian for this board:
  `Armbian_26.8.1_Bigtreetech-cb1_trixie_current_6.18.43_minimal.img.xz`
  (kernel 6.18.43, built 2026-08-08, from
  `dl.armbian.com/bigtreetech-cb1/Trixie_current_minimal`), reflashed the
  already-benchmarked card with it.
- **Confirmed working** on boot: `dwmac-sun8i 5030000.ethernet end0:
  Link is Up - 100Mbps/Full`, PHY bound to `Allwinner AC300 EPHY`. First
  time nick has ever had a wired link — removes the wifi/hotspot
  dependency (and its own separate known bug, below) from the bootstrap
  path entirely.

### Related, not yet needed: the wifi bug

While ethernet was still believed dead, nick's first-boot wifi wizard
showed every nearby network as `[Connect to hidden network]` — an empty
scan despite confirmed APs in range. This is also a known CB1 issue,
independent of the ethernet one: `systemd-networkd` races the RTL8189
driver before it's ready during boot, putting the chip in a bad state
(`CTRL_EVENT_SCAN_FAILED`). Documented fix (per the [Armbian CB1 wifi
troubleshooting thread](https://forum.armbian.com/topic/55108-troubleshooting-wifi-failures/)):
switch netplan's renderer from `networkd` to `NetworkManager`. Not
exercised this session since ethernet came up first — worth remembering
if a machine ever needs wifi-only setup again.

## Part 3 — the panic (open, unresolved)

With ethernet working, `git clone` + `sudo bash bootstrap.sh` was run on
nick directly (no `prime.sh`, no hotspot). It reached step 5 (first
`system-manager switch`) and hard-panicked partway through:

```
Call trace:
  __switch_to+0xcc/0x188 (T)
  __schedule+0x348/0xb18
  schedule+0x38/0xe0
  __mmc_claim_host+0xd0/0x258
  mmc_get_card+0x38/0x50
  mmc_sd_detect+0x24/0x98
  mmc_rescan+0x90/0x328
  process_one_work+0x154/0x3b0
  worker_thread+0x194/0x320
  kthread+0x134/0x1f8
  ret_from_fork+0x10/0x20
Kernel panic - not syncing: hung_task: blocked tasks
CPU: 3 UID: 0 PID: 41 Comm: khungtaskd Not tainted 6.18.43-current-sunxi64 #1 PREEMPT
Hardware name: BigTreeTech CB1 (DT)
```

**Investigated and applied a mitigation:** Armbian
[PR #10120](https://github.com/armbian/build/pull/10120) (merged
2026-07-04) fixes a circular MMC/I2C power-management deadlock on
H616/H618 boards — during CPU frequency scaling (DVFS), the cpufreq
governor holds a clock lock while writing to the AXP PMIC over I2C; the
I2C controller's runtime-PM resume path blocks on that same lock, while a
concurrent MMC runtime-suspend worker blocks trying to acquire it too.
Matches the call-trace shape closely. **But this fix targets `sunxi-7.0`
(edge) only — not backported to `sunxi-6.18` (current)**, which is what
nick runs. Pinned the cpufreq governor to `performance` on all cores
(was `schedutil`) as a stopgap — no DVFS events, no trigger, in theory.

**The mitigation did not work.** Retried `git pull` + `bootstrap.sh` with
a live `journalctl -f -k` SSH session held open plus periodic SSH-liveness
polling, specifically to catch this in the act instead of losing it to a
freeze. Observed:

- Load climbed steadily through the nix-switch phase: 0.53 → 6.72 → 7.69
  → 8.26 over about 4 minutes, machine still answering SSH each check
  (progressively slower, but real logins with real output).
- Then SSH stopped completing even at a 45s timeout, while **ping still
  answered** (2ms RTT) — the identical "network alive, userspace dead"
  signature documented for attempt 10 in the generation-8 saga.
- Shortly after, ping itself stopped (`Destination Host Unreachable` from
  the LAN's own router, i.e. nick had dropped off the network entirely —
  more consistent with a full halt than a live machine ignoring pings).
- Physical screen showed the **identical call trace**, this time on
  `6.18.44-current-sunxi64` — one kernel patch version newer than what
  nick booted into, meaning bootstrap.sh's apt step (step 2, kernel
  updates are apt-managed per ADR-0001) pulled a security update and nick
  rebooted into it at some point before crashing again, identically, on
  the new kernel too.

No kernel-log lines for the panic survived anywhere — not in the live
`journalctl -f` stream (which just goes quiet), not in `journalctl -b -1`
after reboot (ends abruptly mid-boot with no panic text, despite
journald's directory being a persistent-disk symlink — a full CPU halt
apparently leaves no window for the final printk to flush even there),
and no `/sys/fs/pstore` (not present/configured on this board). The
photographed on-screen trace remains the only record, and it's a tail —
the earlier frames (what was *holding* the lock the hung task wanted) had
already scrolled off the physical screen before the photo was taken.

### What this isn't

This exact signature — `hung_task`, `mmc_sd_detect` stuck in
`__mmc_claim_host` — already happened once before, in the 2026-07-30
incident, caused by a missing `--accept-flake-config` forcing an on-device
Rust build of system-manager's own CLI, which OOM'd nick's 1 GB RAM and
then panicked on retry under the unpack I/O. **That's not the cause here**
— `bootstrap.sh` line 78 already carries `--accept-flake-config`,
confirmed present in the repo. Whatever's happening now is a second,
independent way to reach the same failure mode.

### Leading theory (unconfirmed)

`mmc_rescan` polls for card insertion/removal on a timer (this board has
no card-detect GPIO) and calls `mmc_claim_host()` unconditionally, with no
apparent bounded wait. If some real — not deadlocked, just very slow — I/O
operation from nix's actual copy-in workload (many small files, unlike the
sequential `dd` pattern used to benchmark the new card) legitimately takes
longer than the kernel's default 120s `hung_task_timeout_secs`, khungtaskd
will panic on a slow card exactly the same way it would on a truly
deadlocked one. This would mean:

- The new card's *sequential* throughput win (12-15x) doesn't necessarily
  carry over to nix's actual small-file write shape, and that shape was
  never re-measured on this card, in nick's own slot.
- The cpufreq-governor pin was a reasonable thing to try given PR #10120's
  description, but its failure to prevent the recurrence is real signal
  against DVFS being the (sole) trigger here — not proof of a specific
  alternative, just an eliminated hypothesis.

Competing, equally unconfirmed possibility: a genuine sunxi-mmc
driver-level bug independent of card quality, in the same general class
PR #10120 addresses but reached through a path not gated purely by
cpufreq DVFS, which edge's broader PM rework happens to also fix as a side
effect. Nothing gathered this session distinguishes between these two.

## Open items / recommended next steps

1. **Re-benchmark the new card in nick's own slot**, and specifically
   repeat the small-file/`nix`-copy-in-shaped write test (`500 x 32 KB`),
   not just sequential `dd` through a USB reader — settles whether the
   card itself is still marginal under the workload shape that's actually
   crashing.
2. **Try the two-phase `prime.sh` approach**, already flagged as worth
   doing in the generation-8 saga's open items: pre-build the closure on a
   workstation and push it, so nick's own `switch` does mostly
   activation/symlink-swap instead of a multi-gigabyte copy-in. Directly
   tests whether cutting the on-device write volume avoids the trigger —
   requires manually splicing bootstrap.sh (run steps 1-4 by hand, prime
   from a workstation targeting `nick`, then run the switch line
   separately) since bootstrap.sh has no built-in pause point for this.
3. **Wire up the serial console** (issue
   [#20](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/20)) —
   the photographed panic is a tail; a UART capture would show the earlier
   frames (what's actually holding the lock) and settle the DVFS/PM-deadlock
   question with real evidence instead of pattern-matching against PR
   descriptions.
4. **Check `sysctl kernel.hung_task_timeout_secs` / `kernel.hung_task_panic`**
   on nick once it's back up — confirms whether this image enables a
   stricter (or just newly-panicking, same-threshold) watchdog than
   whatever nick ran before, which would mean older freezes on the *old*
   card might have been the exact same underlying stall, just silent
   instead of loud.
5. File a dedicated GitHub issue for this recurring panic — it's distinct
   from #18 (card replacement, which is itself done and should be closed
   out on its own terms) since the underlying freeze/panic persists on
   entirely new hardware.
