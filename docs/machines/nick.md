# nick

Bootstrapped 2026-08-06. All 7 services green and running, but the running
config is **stuck on system-manager generation 8 (built 2026-08-13)** —
repo is current at `main`, but ten switch attempts across five sessions
(2026-08-31 through 2026-09-03) have all failed to activate a new
generation — six of the ten have hard-frozen the machine outright
(physical power cycle required each time; filesystem has survived every
one so far with no corruption). The tenth attempt was the first with every
mitigation flag correctly applied for the whole run (no from-source build,
full I/O tuning, kiosk/autopipette stopped) — it still froze after ~80
minutes of otherwise-healthy operation, ruling out attempt 9's from-source-
build confound and confirming a real, separate I/O ceiling remains. Full
attempt-by-attempt history, root causes, and the mitigation stack:
[docs/incidents/nick-generation-8-upgrade.md](../incidents/nick-generation-8-upgrade.md).

**Root cause found 2026-09-03: the SD card.** Measured on an otherwise idle
nick (SanDisk `SC16G`, 16 GB, manufactured 12/2022):

| Measurement | nick |
|---|---|
| Sequential write, buffered + `fsync` | **3.0 MB/s** |
| Sequential write, `O_DIRECT` | **2.5 MB/s** |
| Sequential read, `O_DIRECT` | 23.8 MB/s (at the high-speed bus ceiling) |
| Small-file write, 500 × 32 KB (nix copy-in shape) | 2.31 MB/s, 74 files/s |
| Average write-request latency (`/sys/block/mmcblk0/stat`) | **~2.9 s** |
| Average read-request latency | 13.8 ms |

Reads run at line rate while writes are ~200× slower per request, so the
host controller, bus and driver are all fine — the card's own flash/
controller is the bottleneck. A plain `dd` of 512 MB was enough to
reproduce the exact starvation signature from the upgrade attempts
(`Connection timed out during banner exchange`, ping dropping rounds) on a
machine doing nothing else. No nix involved. A board that writes at
3 MB/s with multi-second write latency cannot absorb a multi-gigabyte
closure copy-in, and that is the whole incident history.

Contributing factors on the same card: `/` is at **81% used, 2.7 GB free**
(ext4 allocation degrades when full, and there is little room for a large
closure), and the block queue had **no I/O scheduler** (`none`) — FIFO
dispatch with zero read/write fairness, so one write flood parks a queue of
multi-second requests in front of every read. `bfq` is now selected by
`modules/io-tuning.nix`; measured under the same 512 MB `dd`, it leaves
throughput unchanged (3.0 MB/s either way) and keeps sshd's banner
answering (22/22, worst 6.19 s, versus timing out under `none`), but **full
SSH sessions still starve** — 3 of 5 timed out at 20 s during the flood.
A partial mitigation worth keeping, not a fix.

**Action: replace the card.** Software mitigations narrow the window; they
cannot make a 3 MB/s card absorb this workload.

**PSI is not available on this kernel** — `/proc/config.gz` says
`# CONFIG_PSI is not set`, so adding `psi=1` to `armbianEnv.txt` would do
nothing. `/sys/block/mmcblk0/stat` (which is populated, and is where the
latency numbers above came from) is the substitute. `CONFIG_BLK_CGROUP_IOLATENCY`,
`CONFIG_BLK_CGROUP_IOCOST` and `CONFIG_IOSCHED_BFQ` are all `y`, and cgroup v2
exposes `cpuset cpu io memory pids misc`, so per-cgroup I/O limiting is
available if wanted.

**Postmortem logging still doesn't survive a freeze** — found during attempt
10: `/var/log` is zram-backed (RAM disk) on this hardware, so a hard
power-cycle wipes the custom health-sampler log before `armbian-ramlog`'s
`cron.daily` rsync copies it out to `/var/log.hdd`. **systemd's journal is
*not* affected** — `/var/log/journal` is a symlink to
`/var/log.hdd/journal`, so journald writes straight to persistent disk and
did capture attempt 10 (3350 lines, going silent at 17:43:01 mid-wifi-
reconnect, the expected cutoff for a hard freeze on any medium). Only our
own sampler log was lost, and only because of where it was written. Fix
plan: [docs/plans/switch-postmortem-logging-fix.md](../plans/switch-postmortem-logging-fix.md).

Still on a mobile hotspot: no wired NIC detected, PHY undetected on onboard
ethernet — worth a hands-on hardware look, may also explain the link
flakiness seen during several attempts (though attempt 10 found nick's own
WAN to be reliably good; it's the local workstation<->nick wifi hop that's
been the flaky part most recently).

Splash rebuild verified at the system level (theme active, plymouth-quit
masked, kernel cmdline has `splash`); on-screen appearance not eyes-on
verified.

`modules/aliases.nix`, `modules/io-tuning.nix`, and their `flake.nix`
wiring are committed on `main` (PR #15) — but gen 8 predates them, so the
new `switch` alias isn't live on nick yet (chicken-and-egg: it only
activates once a switch actually succeeds). Until then, any attempt has to
run the equivalent command by hand with the same flags.
