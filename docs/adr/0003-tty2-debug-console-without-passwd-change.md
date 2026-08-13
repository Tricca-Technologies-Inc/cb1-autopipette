# Debug consoles (tty2-tty6) via getty autologin, not /etc/passwd shell change

Need a fast recovery path back to control if the kiosk (tty1) misbehaves,
using the existing `tricca` admin/SSH account. Ctrl+Alt+F2 autologs in as
`tricca` and execs `tap` instead of a normal shell — but this is deliberately
NOT done by changing `tricca`'s `/etc/passwd` shell, because that would
hijack SSH logins on the same account too (every SSH session would land in
`tap` instead of a normal shell). Instead a profile.d script execs `tap`
only when the tty is tty2 specifically, never a pts/SSH session.

tty3 through tty6 get the same no-password autologin (same account, same
"physical console access already implies the same trust level" reasoning)
but land in `tricca`'s normal shell instead of `tap` — a second control
channel there would just contend with tty2, whereas a bare shell lets a
physical keyboard run `tap` on one VT and `journalctl`/`htop`/etc. on
another at the same time. This is a difference in what the login *runs*,
not in the trust model, so it's covered here rather than as a separate ADR.

## Considered options

- Change `tricca`'s login shell to `tap` — rejected: breaks SSH for the same
  account, and would put tty3-tty6 in `tap` too with no way to get a plain
  shell on a physical console at all.
- profile.d script gated on physical-console tty, getty autologin drop-in
  per tty (chosen). tty2's drop-in execs `tap` via profile.d; tty3-tty6's
  drop-ins are identical autologin lines but profile.d only matches tty2,
  so they fall through to a normal shell.

## Consequences

tty1 stays kiosk-only; if the kiosk dies and getty@tty1 comes back, that
login is left as a normal shell (a third, independent recovery path), not
exec'd into `tap` or autologged in.

Adding a debug console on a further tty (tty7+) means adding one more
`getty@ttyN.service.d` drop-in in `modules/tricca-console.nix` — the
profile.d tty match doesn't need to change unless the new tty should also
run `tap`.
