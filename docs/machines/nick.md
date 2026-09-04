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

**No diagnostic data survives a freeze right now** — found during attempt
10's postmortem: `/var/log` is zram-backed (RAM disk) on this hardware, so
a hard power-cycle wipes it, including both the custom health-sampler log
and systemd's own journal for that boot, before either syncs to the
persistent `/var/log.hdd` copy. Needs fixing (repoint logging at
`/var/log.hdd/` directly) before the next freeze is worth investigating in
detail.

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
