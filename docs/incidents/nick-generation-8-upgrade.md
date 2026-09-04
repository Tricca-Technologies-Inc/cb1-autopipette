# nick: stuck on generation 8 — upgrade attempt history

**Status as of this writing: unresolved.** `nick` has been running
system-manager generation 8 (built 2026-08-13) since then. The repo has
moved on past `34f36ed`, but every attempt since to run `switch` and
activate a new generation has failed — ten attempts across five sessions
(2026-08-31 through 2026-09-03), documented in full blow-by-blow detail in
session memory. This file is the condensed version: what we tried, why it
failed each time, and what to actually do next time.

This is deliberately *not yet* folded into README's Troubleshooting section
or ADR-0009 — several of the mechanisms below are still not proven fixed by
a real successful switch, only proven *less bad*. Promote the confirmed
parts once a switch actually completes end to end.

## Why this is happening at all

`nick` is a BIGTREETECH CB1 — 1 GB RAM, SD card storage, and (so far) always
on a mobile hotspot or flaky wifi, never a wired connection (the onboard
ethernet PHY has never been detected; a hands-on hardware look is still
outstanding). A `switch` that jumps three weeks of accumulated `main` has to
build/fetch/activate a large closure — hundreds of store paths, multiple
gigabytes — on hardware with very little headroom in any dimension: memory,
disk write throughput, or network bandwidth. Every failure mode below is
some version of "not enough headroom in one of those three dimensions,
under concurrent load."

`marie` (the other machine) has not hit any of this — it has faster storage
and a better network link. This looks specific to `nick`'s hardware/network
situation, not a bug in the switch process itself.

## Timeline and failure modes

### Attempt 1 — 2026-07-30 (pre-dates the prime/switch workflow)
First-ever reference to this class of failure. A `switch` without
`--accept-flake-config` caused Nix to reject `system-manager`'s own
`cache.numtide.com` substituter and compile the Rust CLI from source
on-device instead. `rustc`/`lto1` OOM-killed the 1 GB board outright on
first encounter; a retry caused a genuine kernel panic (`hung_task: blocked
tasks`, `mmc_sd_detect` stuck claiming the MMC host) — sustained heavy write
I/O from unpacking hundreds of store paths wedged the SD card controller
badly enough that `khungtaskd` gave up. **Fix at the time:** add
`--accept-flake-config` to `bootstrap.sh` and the `switch` alias. This is
already documented in README's Troubleshooting section.

### Attempt 2 — 2026-08-31, first prime/switch test
First live test of the new `prime.sh` local-network-push workflow (ADR-0009,
PR #12). `prime.sh` pushed ~2.6 GiB / ~460 store paths to nick over the local
link successfully. `switch`, run over a live SSH session, died mid-flight —
the SSH session itself dropped (`Broken pipe`), and nick was confirmed
completely frozen at the physical console, not just network-unreachable.
Extensive journal forensics afterward found no `hung_task`/`mmc` crash
signature and no explicit error anywhere — the journal just goes silent
mid-sentence. Leading theory at the time: `determinate-nixd`'s automatic
disk-pressure-triggered garbage collection may have been deleting store
paths concurrently with prime's copy-in and switch's activation, on a card
already fairly full (67% used). Never conclusively proven.

### Attempt 3 — 2026-09-01, plain `switch` (no prime)
After landing a `min-free`/`max-free` GC-headroom fix (PR #13), tried a plain
`switch` picking up three weeks of accumulated `main` (~648 store paths,
nick's largest jump yet). Froze again, identical signature (kernel hang, no
keyboard response, no caps-lock LED response) — this time with **no**
`prime.sh` involved, which ruled out prime's push mechanism specifically and
pointed at the sheer *volume* of concurrent copy-in I/O as the real trigger.
The min-free/max-free fix never got to prove itself, since the switch never
reached activation.

### Attempt 4 — 2026-09-01, throttled retry
Retried with `--max-jobs 1 --cores 1 --http-connections 2` (serialize
builds/downloads instead of running them concurrently) from the physical
console this time, with a monitor script logging memory/load/D-state
processes to disk every 2 seconds so the tail would survive a hard freeze.
**This produced the first concrete root-cause evidence.** The monitor log's
last entries before the freeze showed swap completely exhausted
(`SwapFree: 0 kB`), RAM at 878–937 MiB of 969 MiB used, load average 26–32 on
a 4-core board, and a D-state process list that included not just Nix's own
build workers but `NetworkManager`, `chromium` (the kiosk), `sshd-session`,
`cron`, and more — i.e. the *entire system*, not just the build.
`systemd-journald` itself was killed by its own watchdog three times in a
row. **Conclusion: whole-system memory exhaustion cascading into an SD-card
I/O pileup.** With only 969 MB of RAM total, running a multi-GB build while
the kiosk, moonraker, klipper, tapd, autopipette, and mainsail-nginx are all
still live and competing for memory leaves no headroom; once swap (zram,
capped at 484 MiB) fills, everything doing I/O — including core daemons —
piles into an uninterruptible wait on the same single MMC channel.

### Attempt 5 — 2026-09-01, same day, kiosk+autopipette stopped first
Stopped `kiosk` and `autopipette` before retrying, freeing RAM headroom from
roughly 90–150 MiB available to 605–673 MiB. This **delayed** the freeze
(ran healthy for ~32 minutes vs. 15–20 minutes previously) but did **not**
prevent it. The new diagnostic detail: `Dirty` (unwritten) page counts were
climbing steadily while `Writeback` never drained between samples — dirty
pages were accumulating faster than the SD card could flush them, and swap
still hit near-zero despite the RAM headroom. **Revised conclusion: this is
not primarily a RAM problem — it's an SD card write-throughput ceiling.**
Freeing RAM buys time before the ceiling is hit; it doesn't remove the
ceiling. This machine had now failed 5 of 5 large closure-copy attempts.

### Attempt 6 — 2026-09-01 evening, dirty-page/ext4-commit tuning (the mitigation that actually worked)
Applied a new, previously-untested mitigation live via `sysctl -w` + `mount
-o remount` (not yet in the repo at this point): pushed dirty-page writeback
to start almost immediately instead of letting pages build up toward the
default ~5–10% of RAM before flushing even starts
(`vm.dirty_background_bytes=4 MiB`, `vm.dirty_bytes=16 MiB`,
`vm.dirty_writeback_centisecs=100`, `vm.dirty_expire_centisecs=500`), and
switched the ext4 journal commit interval from the default 120 seconds down
to 5 seconds, for smaller and more frequent flushes instead of one large
burst. Also kept kiosk/autopipette stopped. **Result: ran clean and quiet
for ~2.5 hours** — far longer and calmer than any prior attempt. It
eventually failed anyway, but via a completely different and much less
severe mechanism: `cache.numtide.com` (system-manager's own binary cache)
started failing mid-transfer, Nix fell back to building several of
system-manager's own Rust dependencies from source, and the kernel's
OOM-killer caught the resulting memory pressure cleanly (`Out of memory:
Killed process ... (nix)`) — a graceful recovery, no freeze, no unclean
shutdown. **This confirmed the dirty-page tuning as a real, working
mitigation for the freeze/hang failure mode specifically** — with writeback
kept drained, the OOM-killer could actually act instead of the box wedging
first.

### Attempt 7 — 2026-09-01, same night
Same command, failed the same clean way (no freeze) — this time both
`cache.numtide.com` and `cache.nixos.org` hit the identical
`Failed sending data to the peer` transfer-failure signature, pointing at
nick's own (documented, flaky) network link rather than either CDN being
down. Two clean failures in a row, zero freezes, versus five freezes before
the tuning. Session ended with the tuning still live-only (not committed),
lost on the next reboot.

### Attempt 8 — 2026-09-02, tuning codified + prime/switch combined
This session wrote the dirty-page tuning into the repo permanently
(`modules/io-tuning.nix`, a oneshot systemd unit that reapplies the same
values on every boot before klipper/moonraker/tapd start) and folded the
kiosk-stop + throttle flags into the `switch` shell alias itself
(`modules/aliases.nix`), so the whole mitigation stack becomes the default
going forward rather than something to remember to apply by hand each time.
Combined this with `prime.sh` for the first time under the new stack:
manually re-applied the tuning live (since the new module wasn't active yet
on nick's stale generation), pushed the closure from the workstation over a
**multiplexed** SSH connection (a bare per-call `sshpass ssh` wrapper had
choked mid-transfer on an earlier attempt this same session), copied the
same uncommitted repo files onto nick's own checkout (critical: `switch`
re-evaluates the flake from *nick's* checkout, not the one that was primed
from), and launched switch detached (`nohup`/`disown`) with a live health
poll since there was no physical console access. **Result: ran for ~22
minutes under real load (peak loadavg ~5.6 on 4 cores) with zero freeze
signature** — the longest and calmest run yet. It died to a clean error: nick's
WAN itself was down (confirmed via direct-IP `curl` bypassing DNS, both
wifi interfaces affected identically) — an outage, not a bug. Session ended
with the workstation repo and nick's own checkout both left with the same 3
files uncommitted (`flake.nix`, `modules/aliases.nix`,
`modules/io-tuning.nix`), pending a real success to confirm against before
committing.

### Attempt 9 — 2026-09-03 (this session) — **a mistake to flag clearly**
WAN was confirmed good this time (`200` from `cache.nixos.org`, unlike
attempt 8's outage), so the strategy pivoted: rather than fight nick's flaky
*local* wifi link to push the full closure via `prime.sh` (which stalled
twice with dead, un-recovering SSH sockets despite `ControlMaster` and
keepalive settings), the plan became "let nick fetch large generic packages
straight from `cache.nixos.org` over its own now-confirmed-working WAN,
since that's a real CDN and should be faster and more reliable than the
local relay."

That reasoning was sound, but **the actual command run to do it was wrong**:
a bare
```
sudo -i nix run "github:numtide/system-manager/<rev>" -- switch --flake /opt/cb1-autopipette
```
— missing both `--accept-flake-config` and the
`--max-jobs 1 --cores 1 --http-connections 2` throttle. The
`--accept-flake-config` omission is **exactly the attempt-1 failure mode**,
already documented in README's Troubleshooting section and already fixed in the
uncommitted `switch` alias in `modules/aliases.nix` — it just wasn't used,
because the alias only becomes available *after* a successful switch onto a
generation that contains it, and nick is stuck on generation 8, which
predates it. The warning Nix printed
(`warning: ignoring untrusted flake configuration setting 'extra-substituters'`)
was seen and, wrongly, dismissed as cosmetic in the moment — it is not
cosmetic; it's the exact precondition for Nix falling back to compiling
system-manager's own Rust CLI from source on a 1 GB board.

The predictable consequence followed: partway through, nick started
building `system-manager`'s own Rust build dependencies from source
(`nixbld1`, `cp -Lr --reflink=auto cargo-vendor-dir`, sustained D-state).
For a while this looked contained rather than cascading into a full freeze
— SSH from the workstation became intermittently unresponsive (keepalive
timeouts, "server not responding") while the physical console, confirmed
directly by James at the machine, stayed responsive, and ICMP ping never
lost a full round. **That held for roughly an hour, then nick froze
completely anyway** — ping went to 100% loss, SSH reported "No route to
host", and James confirmed at the physical console: caps-lock LED
completely unresponsive, the same tell as every prior freeze in this
history.

This is the first freeze *since* the dirty-page/ext4-commit tuning was
introduced at attempt 6 — the previous three attempts under that tuning
(6, 7, 8) all failed cleanly instead of freezing. **The tuning is not a
universal fix for the freeze mechanism, just a mitigation for the I/O
pattern it was tuned against** (large numbers of small downloaded/copied
store paths). A local Rust build's `cargo-vendor-dir` reflink copy is a
different I/O shape — a smaller number of much larger sustained writes —
and evidently found a way to exhaust the same resource anyway. Combined
with the fact that this specific build should never have been happening at
all (see the `--accept-flake-config` gap above), this freeze doesn't
disprove the tuning so much as confirm that avoiding the from-source build
entirely remains the more important fix.

Also worth recording as process mistakes from this session, independent of
the flake-config gap:
- **A 10-minute hard cap applies to backgrounded shell tasks in this
  environment even when explicitly requested to run in the background** —
  not just the initial wait before a command is moved to background. A
  supposedly-long-running retry loop got silently killed by this after
  10 minutes. Fix: fully detach with `setsid nohup ... & disown`, writing
  to a log file, rather than trusting the tool's own backgrounding.
- **SSH connection multiplexing (`ControlMaster`) is a liability on a link
  that drops intermittently** — when the shared master dies, *every*
  session sharing that socket dies with it, including unrelated health
  checks running at the same time as the actual transfer. Plain
  per-connection SSH with aggressive keepalive
  (`ServerAliveInterval 5`, `ServerAliveCountMax 3`) proved more robust once
  key-based auth was set up (nick had no `authorized_keys` for `tricca` at
  all at the start of this session — installed one).
- **When checking whether a long-running remote process has stalled, prefer
  checking local evidence of progress (log file growth, CPU time in
  `/proc/<pid>/stat`) over opening new SSH connections** — a new-connection
  attempt can time out due to transient contention on the *remote* box
  while the actual process you care about is still fine, and repeatedly
  retrying new connections adds more load to an already I/O-pressured
  machine.
- **A remote command launched over a plain SSH session should always be
  explicitly detached on the remote side** (`nohup`/`disown`/`setsid`), not
  just assumed to survive if the SSH tunnel drops. This session's switch
  happened to survive an SSH drop (most likely because `sudo -i` gave it its
  own session), but that was luck, not something to rely on next time.

**Outcome: froze, same signature as every prior freeze** (caps-lock LED
unresponsive, confirmed at the physical console; ping and SSH both dead).
Required a physical power cycle. Generation still stuck at gen 8. This is
the sixth freeze overall and the first since the dirty-page tuning was
introduced — see the note above for why that doesn't disprove the tuning,
just shows it wasn't tuned for this particular I/O pattern, and that the
real fix here was never letting the from-source build start in the first
place.

### Attempt 10 — 2026-09-03, later same session — flags finally correct throughout, froze anyway

Full mitigation stack applied correctly for the first time: `--accept-flake-config`
present from the start (no from-source build this time — the child `nix
build` process's argv confirmed it inherited `--extra-substituters
https://cache.numtide.com`), `--max-jobs 1 --cores 1 --http-connections 2`,
kiosk+autopipette stopped first, dirty-page/ext4-commit tuning applied live
by hand (gen 8 predates `io-tuning.service`, and the new `switch` alias
itself isn't live yet either — same chicken-and-egg gap noted in attempt 8).
`prime.sh`'s local-network push was tried first but abandoned partway
through: the TCP send queue to nick was draining at under 1 KB/s on a large
package (confirmed via `ss -tnp` byte-counter deltas, not just a hunch) —
the same dead-local-link failure mode from attempt 9's prime.sh stalls.
Pivoted to letting nick fetch directly from `cache.nixos.org`/
`cache.numtide.com` over its own WAN instead, after confirming that WAN was
actually healthy (`curl` returned `200` from both caches in well under half
a second).

Since gen 8 predates the new `switch` alias, the equivalent command had to
be run by hand, detached (`setsid nohup ... & disown`) so a dropped SSH
session couldn't kill it, logging to `/var/log/tricca-switch-manual/`. Two
real bugs surfaced getting this launched, both worth remembering:
- **`echo password | ssh host 'sudo -S tee file' <<HEREDOC` does not work**
  — the remote command's own `echo password |` pipe supplies `tee`'s stdin,
  so the heredoc content attached to the *local* `ssh` process's stdin has
  no path to reach it. The file gets created but stays 0 bytes, silently.
  Fix: write the script locally and `scp` it over instead of piping it
  through a remote `tee`.
- **Root's non-login shell (`sudo bash script.sh`) has no `nix` in `PATH`**
  — same nix-store-PATH-gap class of bug as
  [nix-store-path-gaps.md](nix-store-path-gaps.md), just hitting a manually
  hand-run command instead of a Nix-generated systemd unit this time. Fix:
  call `/nix/var/nix/profiles/default/bin/nix` by absolute path.

A third non-fatal bug: the process-liveness check (`pgrep -f
"nix run.*system-manager"`) went stale once `nix run` `exec`'d into the
built `system-manager` binary — its argv becomes `system-manager switch
--flake ...` with no `nix run` in it anymore, and the actual heavy lifting
happens in a *child* `nix ... build .../systemConfigs.default` process with
neither `nix run` nor `system-manager` in its argv either. This produced
false `NOT_RUNNING` readings that, in an early version of the watch script,
would have ended monitoring prematurely. Fixed by matching on `system-manager
switch|nix .*systemConfigs.default` instead. Relatedly: when the switch log
itself looked frozen on a single stale `copying path ...` line for over 20
minutes, checking `/proc/<pid>/io` (`rchar`/`wchar`/`read_bytes`/`write_bytes`)
showed hundreds of MB of real read/write activity in that window — nix's
progress reporting doesn't flush per-line without a TTY, so a static-looking
log is not itself evidence of a stall. Prefer `/proc/<pid>/io` deltas over
log-tail text when judging whether a backgrounded nix process is still
doing real work.

The run itself: launched 16:17 MDT, confirmed doing real work throughout
(load ~4-5 on 4 cores, memory tightening but not exhausted, D-state limited
to expected kworker/flush/nix processes, no full-system pileup) for about
30 minutes with SSH still mostly working. Then SSH began failing
intermittently (`Connection timed out during banner exchange` — confirmed
via a raw `/dev/tcp/host/22` read that TCP itself connects fine but sshd
never gets scheduled in time to send its version banner, i.e. genuine
host-side CPU/scheduling starvation, not a network problem this time).
Ping and the physical console (caps-lock LED) both stayed responsive
through **50 straight minutes** of SSH being unable to complete even
trivial commands — far longer than any precedent in this history (the
closest prior comparison, attempt 9's SSH-degraded-but-console-alive
stretch, lasted roughly an hour before it turned into a real freeze; this
one went further before either recovering or failing). It never recovered:
ping itself then started dropping, confirmed sustained over several
minutes, and James confirmed at the physical console that the caps-lock
LED had stopped responding — the same tell as every prior freeze. Power
cycle required. **Total elapsed from launch to confirmed freeze: ~80
minutes, the longest run yet, and the first time the full stack (including
correct flags) ran the whole way through without any operator error.**

**New finding, and a real gap in the PR #15 mitigation:** the postmortem
health-sampler log (and this session's hand-rolled equivalent) writes to
`/var/log/tricca-switch-manual/`, `sync`ing every 5 seconds specifically so
a hard freeze wouldn't lose the trail. It didn't work. `mount` after reboot
showed `/var/log` on this hardware is `/dev/zram1` — a RAM-backed
filesystem, presumably Armbian's stock ram-log setup, periodically
synced back to a real on-disk copy at `/var/log.hdd` (or at clean
shutdown). `sync()` inside a RAM-backed filesystem flushes to RAM, not to
the SD card — it does nothing to protect against power loss. Confirmed the
scope of the problem via `journalctl --list-boots` after the reboot: the
boot spanning this entire attempt (16:17–17:53ish) is missing/truncated in
journald's own persistent record too, for the identical reason. **There is
currently no way to recover any diagnostic data from a hard freeze on this
hardware** — not our custom log, not even systemd's own journal — because
both live on zram and a hard power-cycle happens before either gets synced
to `/var/log.hdd`. This defeats the entire point of the postmortem-logging
half of PR #15 for exactly the failure mode it exists to catch. Needs
fixing: point the health sampler (and ideally `switch`'s own log) at
`/var/log.hdd/tricca-switch-manual/` directly, bypassing zram, so a freeze
actually leaves a trail next time.

Also notable: this is the **first attempt where `--accept-flake-config` and
the throttle flags were correctly present for the entire run**, ruling out
attempt 9's confound (the from-source Rust build). It froze anyway, under
ordinary cache-fetch I/O — the same general shape as attempts 2–5, before
the dirty-page tuning existed. This doesn't disprove the tuning (it's still
the reason this run lasted 80 minutes under real load instead of 15–30),
but it does confirm the tuning narrows the ceiling rather than removing it,
now with the from-source-build variable fully controlled for.

## What's confirmed to work, and should always be used together

1. **`--accept-flake-config`** on every `switch` invocation, no exceptions —
   without it, Nix silently compiles system-manager's own Rust CLI from
   source on-device, which has caused both an OOM-kill and a kernel panic on
   this board. Already in README's Troubleshooting section and in the (currently
   uncommitted) `switch` alias.
2. **`--max-jobs 1 --cores 1 --http-connections 2`** — serializes
   builds/downloads instead of running them concurrently. Reduces (does not
   eliminate) the concurrent-I/O pressure that triggers the SD-card
   write-collapse mechanism.
3. **Stop `kiosk` and `autopipette` before switching, restart unconditionally
   after** — frees several hundred MB of RAM (chromium was a confirmed
   D-state participant in every freeze) and buys time before any collapse,
   even though it doesn't remove the underlying ceiling by itself.
   `klipper`/`moonraker`/`tapd` can stay up; they weren't implicated.
4. **The dirty-page/ext4-commit tuning** (`vm.dirty_background_bytes=4 MiB`,
   `vm.dirty_bytes=16 MiB`, `vm.dirty_writeback_centisecs=100`,
   `vm.dirty_expire_centisecs=500`, ext4 `commit=5`) — real, but not
   universal: clean (no freeze) for attempts 6, 7, and 8, all of which were
   download-heavy I/O; attempt 9 froze anyway under a different I/O pattern
   (a local Rust source build's large sustained writes). Worth keeping —
   still 3-for-4 clean since introduction versus 0-for-5 before it — but
   don't treat it as removing the ceiling entirely; it narrows when the
   ceiling gets hit, and which I/O pattern triggers it. Codified as
   `modules/io-tuning.nix`, applying automatically on every boot — but
   **this only takes effect once a switch successfully activates a
   generation containing it**, so it must also be applied live by hand
   (`sysctl -w` + `mount -o remount`) before any attempt made from nick's
   current stale generation.
5. **Run switch detached on the remote side** (`nohup ... & disown`, or
   equivalent), logging to a file, so a dropped SSH session can't kill the
   activation. Don't rely on `sudo -i` incidentally providing this.
6. **Prefer local-network `prime.sh` push over relying on nick's own WAN
   when nick's WAN quality is unknown or has recently been bad** — but if
   the *local* wifi link to nick is itself flaky, and nick's WAN is
   confirmed good, letting nick substitute directly from `cache.nixos.org`
   is a reasonable alternative for large generic (non-repo-specific)
   packages. Either way, **always include `--accept-flake-config` and the
   throttle flags** regardless of which path is feeding the store.
7. If using `prime.sh`, remember: **it isn't enough to push the built
   closure — the uncommitted files it was built from must also be copied
   onto nick's own `/opt/cb1-autopipette` checkout**, or `switch` will
   re-evaluate the flake from stale files and mostly waste the push.

## Open items

- **Postmortem logging doesn't survive a freeze** (found in attempt 10):
  `/var/log` is zram-backed and wiped by a hard power-cycle before it syncs
  to `/var/log.hdd`. Repoint the health sampler and switch's own log output
  at `/var/log.hdd/tricca-switch-manual/` directly. Until this lands, a
  freeze leaves zero diagnostic trail — not our log, not the journal.
- Nick's onboard ethernet PHY has never been detected — a wired link would
  remove the local-wifi-flakiness variable entirely. Still needs a hands-on
  hardware look.
- `modules/aliases.nix`, `modules/io-tuning.nix`, and the `flake.nix` wiring
  for it are already committed (PR #15, `49817ea`) — but attempt 10 shows
  the mitigation stack alone isn't sufficient: this was the first attempt
  with every flag correct throughout, and it still froze after ~80 minutes
  under ordinary cache-fetch I/O, no from-source build involved. The
  from-source-build failure mode (attempts 1 and 9) is now fully ruled out
  as a confound — whatever's left is a real, separate I/O ceiling.
- Given ten attempts and six freezes, worth seriously considering the
  two-phase approach floated after attempt 9: pre-build system-manager's
  own CLI closure on a workstation and prime *only* that small piece ahead
  of time, so the on-device `switch` run is pure config-copy-in with no
  Rust toolchain involved at all — reduces what's being asked of the board
  in a single run, even if it doesn't address the underlying ceiling.
- Once a switch actually succeeds end to end under this full stack: fold
  the confirmed parts of this write-up into README's Troubleshooting
  section and/or ADR-0009 (the dirty-page tuning in particular deserves a
  permanent record — the `--accept-flake-config` and throttle-flag lessons
  are already there).
- Why `system-manager`'s own pinned Rust build isn't consistently a
  cache-hit from `cache.numtide.com`/`cache.nixos.org` is still not fully
  understood — a pinned rev should be stably cached. If this keeps forcing
  from-source builds even with `--accept-flake-config` present (e.g. due to
  transient CDN issues, as in attempts 6/7), consider pre-building
  system-manager on a workstation and priming just that small closure ahead
  of the main switch, as an extra layer of insurance.
