# Plan: make switch postmortem logging survive a hard freeze

**Status:** approved, not yet implemented. Written 2026-09-03 after nick's
tenth failed switch attempt.

**Audience:** whoever (human or agent) picks this up next. Every design
decision below was already argued through and settled — this document exists
so you don't have to re-derive them. If you disagree with one, say so before
implementing rather than quietly substituting a different approach.

## The problem

`nick` has frozen hard six times across ten switch attempts. PR #15 added a
background health sampler (memory / loadavg / dirty pages / D-state
processes every 5s, `sync`'d each write) specifically so a freeze would leave
a postmortem trail instead of nothing.

After attempt 10's freeze, **none of that data survived**. The sampler writes
to `/var/log/tricca-switch/`, and on this hardware `/var/log` is
`/dev/zram1` — a RAM-backed filesystem. `sync()` there flushes to RAM, not to
the SD card. Armbian's `armbian-ramlog` rsyncs it out to `/var/log.hdd/` only
from `cron.daily`, so a hard power-cycle discards up to 24 hours of it.

The mitigation does not survive the exact failure mode it was built to catch.

## Correction to the record (do this as part of the work)

`docs/incidents/nick-generation-8-upgrade.md` (attempt 10 section) and
`docs/machines/nick.md` currently claim systemd's journal was also lost to
zram. **That is wrong and must be corrected.** Verified on nick:

- `/var/log/journal` is a **symlink to `/var/log.hdd/journal`** — journald
  writes straight to persistent disk, bypassing zram entirely.
- The journal **did** capture the attempt: 3350 lines in the 16:00–18:05
  window on 2026-09-03, going silent at 17:43:01 mid-wifi-reconnect, which is
  the expected cutoff for a hard freeze on any storage medium.

What was actually lost is narrower: **our own sampler log, and only because of
where it was written.** Fix the wording in both files; the rationale for this
plan reads wrong otherwise.

## Verified facts about this hardware

Gathered on nick 2026-09-03, all worth re-confirming if this sits unimplemented
for long:

| Fact | Value |
|---|---|
| `/var/log` | `/dev/zram1`, ext4, RAM-backed |
| `/var/log.hdd` | `/dev/mmcblk0p2` — real disk, Armbian's staging area |
| `/var/log/journal` | symlink → `/var/log.hdd/journal` (so journald is already persistent) |
| ramlog RAM→HDD sync | `syncToDisk`, `rsync` **without** `--delete`, from `cron.daily` only |
| ramlog HDD→RAM sync | `syncFromDisk`, `rsync --delete`, **every boot** — mirrors `/var/log.hdd` into the 50M zram |
| zram `/var/log` size cap | `SIZE=50M` (`/etc/default/armbian-ramlog`) |
| PSI (`/proc/pressure/*`) | **not available** — needs `psi=1` on the kernel cmdline |
| `netconsole` kernel module | **not built** for `6.18.33-current-sunxi64` — rules out kernel-level UDP log shipping |
| kernel cmdline | already has `console=ttyS0,115200` (serial console live) |
| bash `/dev/udp` on nick | works |
| tooling on nick | `logger` yes; `nc` **no**; `socat` **no** |
| tooling on workstation | `nc` yes; `socat` no |

## Design decisions (settled — do not silently revisit)

### 1. Local logs go to `/var/lib/tricca-switch/`, not `/var/log.hdd/`

Writing into `/var/log.hdd/` would persist correctly (the RAM→HDD rsync has no
`--delete`), but `syncFromDisk` mirrors that tree **into** the 50M zram on every
boot, so our logs would grow against Armbian's log budget. `/var/lib/` is plain
ext4 on `/`, entirely outside armbian-ramlog's machinery in both directions.

`/var/log.hdd` is Armbian's private staging area; we shouldn't be borrowing
someone else's plumbing.

**Retention: 10 days** (`find -mtime +10 -delete`). This runs once at switch
start, not in the sample loop, so forking there is fine.

### 2. Remote UDP streaming is the *primary* channel; local file is backup

The failure mode is every writer piling into D-state on a wedged MMC channel.
A local write may simply never complete at the moment of interest — so local
logging alone cannot be trusted for this.

Evidence the network outlives the disk, from attempt 10: ping stayed alive
until ~17:38, and journald recorded wifi reconnection events at **17:43** —
well into the starvation window where SSH could no longer complete a trivial
command.

UDP is fire-and-forget: no blocking on a dead socket, no disk in the path.

### 3. The sampler must not fork

During attempt 10's starvation, `awk`, `sudo`, `ip`, and `curl` were all
observed in D-state. The current sampler forks `ps`/`grep`/`awk`/`cat` every
cycle, and `fork()`+`exec` off a wedged SD card is plausibly among the first
things to stop working — meaning the sampler dies exactly when the data
becomes interesting.

Requirements:
- Read `/proc` with bash builtins (`read < /proc/meminfo` etc.), no external
  binaries inside the loop.
- Open the UDP fd **once**, before the loop, and hold it across iterations.
- Keep PR #15's stopfile-polling termination (`[ ! -e "$stopfile" ]` is a
  builtin). Signals don't forward reliably through `sudo`, which is why that
  pattern exists.

The D-state process list is the one field that's awkward without `ps`. Read
`/proc/*/stat` via a bash glob and accept coarser output (count plus comm
names) rather than reintroduce a fork — it was the most diagnostic field in
attempts 4 and 5 ("NetworkManager and chromium are in D-state" is what turned
this from "the build is slow" into "the whole system is wedged").

### 4. UDP first, then local append, and **no `sync`**

Ordering matters structurally. If the local append blocks in D-state, it stalls
the loop and takes the remote stream down with it — losing precisely what
remote logging was added to capture.

Each iteration: **send the datagram first**, then append locally, and drop
PR #15's per-write `sync` entirely. A disk stall can then only cost us the
redundant copy.

### 5. Sample interval: 2s

Down from PR #15's 5s. With no forks and no `sync` in the loop, each iteration
is a handful of `/proc` reads and one datagram. Attempt 4's hand-rolled 2s
monitor did successfully catch the collapse in progress.

### 6. Target address via `SWITCH_LOG_HOST` env var at call time

Both machines are DHCP, so no address can be stored durably without going
stale. Usage: `SWITCH_LOG_HOST=192.168.1.7 switch`. The operator running the
switch already knows their own IP. Sampler degrades cleanly to local-only when
the variable is unset.

### 7. `switch`'s own build output moves too, and also streams

Move it from `/var/log/tricca-switch/` to `/var/lib/tricca-switch/` alongside
the samples, and stream it over the **same** UDP port with a line prefix so the
receiver can split the two into separate files.

Correlating "what nix was doing" against "what the machine was doing" on a
single timeline is most of the diagnostic value. At `--max-jobs 1` nix isn't
especially chatty. The `tee` doing this lives outside the sample loop, so its
forking doesn't compromise decision 3.

### 8. Receiver: a committed `watch-switch.sh`, not ad-hoc `nc`

Lives in the repo, run from the workstation. It should do all three of:

1. listen on the UDP port, timestamp lines, split by prefix, tee to local files;
2. run a ping watchdog against the target machine;
3. print an explicit `*** FROZEN ***` verdict on sustained ping loss.

Parts 2 and 3 are the loop that was improvised by hand during attempt 10 — it's
what actually established when nick died, and it currently exists only in that
session's scrollback. It belongs in the repo.

Workstation has `nc` but not `socat`; write accordingly.

### 9. Enable PSI on nick before attempt 11

`/proc/pressure/{io,memory,cpu}` directly measures the stall mechanism we've
spent ten attempts inferring from D-state lists and dirty-page deltas. Add
`psi=1` to `armbianEnv.txt`'s `extraargs` and reboot.

Note `/boot` is outside system-manager (CLAUDE.md hard-won rule 7) — this is a
manual edit, and it must **also** be added to `bootstrap.sh` so future machines
get it automatically. Add the PSI fields to the sampler's output once live.

**marie is deferred** — no reason to reboot a healthy machine today for a
diagnostic only nick needs. It picks this up next time it's touched.

### 10. Fleet-wide, via `systemConfigs.default`

Same as `io-tuning.nix` and the `switch` alias already are. marie runs the
identical Armbian zram layout, it costs nothing there, and marie's own large
switch is still pending — it will want the same trail. (The `psi=1` cmdline
piece is the one exception, per decision 9.)

## Implementation order

1. Correct the journald claim in `docs/incidents/nick-generation-8-upgrade.md`
   and `docs/machines/nick.md` (see "Correction to the record" above).
2. Rewrite `switchHealthSampler` in `flake.nix` per decisions 3, 4, 5 —
   fork-free, UDP-first, no `sync`, 2s.
3. Update the `switch` function in `modules/aliases.nix` — new log directory,
   10-day retention, `SWITCH_LOG_HOST` plumbing, build output teed to both the
   new path and the UDP stream with a prefix.
4. Add `watch-switch.sh` at the repo root (alongside `prime.sh`, which is the
   existing precedent for a workstation-side script).
5. Hand-edit `psi=1` into nick's `armbianEnv.txt`; add the same to
   `bootstrap.sh`; reboot nick; confirm `/proc/pressure/io` exists.
6. Smoke test (below).
7. Commit, PR, merge.

## Smoke test — this gates "done"

Non-negotiable. This code only ever runs during an event we cannot reproduce
on demand, so shipping it untested risks attempt 11 producing another blank.

Run the sampler standalone on nick — no switch involved — and confirm:

- datagrams actually arrive at the workstation and `watch-switch.sh` writes them;
- the local file under `/var/lib/tricca-switch/` is written and survives a
  **clean** reboot (proves it's off zram);
- PSI fields are present and populated (after step 5);
- the stopfile terminates the loop;
- `watch-switch.sh`'s ping watchdog prints its `FROZEN` verdict when the target
  is genuinely unreachable — test by pointing it at an unused IP, not by
  freezing nick.

## Out of scope (deliberately)

- **Serial console capture.** `console=ttyS0,115200` is already on the kernel
  cmdline, and a UART capture from a second machine is the only channel that
  survives a true kernel-level hang — it would catch a panic tail that both
  disk and network miss. Wanted, but it needs a USB-TTL adapter and physical
  access to nick's UART pins, and James explicitly won't be doing it for
  attempt 11. File as a GitHub Issue (this repo tracks TODOs as Issues) and
  cross-reference it from the incident doc's open items.
- **Attempt 11's strategy.** Whether to repeat attempt 10's WAN-substitution
  approach or switch to the two-phase idea (pre-build system-manager's own CLI
  closure on a workstation and prime just that, so the on-device switch
  involves no Rust toolchain at all) is a separate unsettled decision. It
  deserves its own discussion informed by whatever this new logging actually
  shows — deciding it now would be guessing ahead of the data.
- **Disabling `armbian-ramlog`.** Considered and rejected: it changes Armbian's
  stock layout fleet-wide to serve one narrow need, and the zram log buffer
  genuinely spares the SD card routine log churn. Not worth trading card
  lifespan for.
- **Logging via journald instead.** Considered and rejected: journald's
  watchdog killed it three times during attempt 4's collapse — it dies exactly
  when needed — and `SystemMaxUse=20M` is already at 20M, so rotation could
  evict the window of interest.

## Why this matters

Ten attempts, six freezes, and attempt 10 — the first run with every mitigation
flag correct throughout — still told us almost nothing about its final fifteen
minutes. The entire value of attempt 11 is the data it produces. Running it
before this lands spends a power-cycle for nothing.
