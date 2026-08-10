# tty2 debug console execs tap via profile.d, not via /etc/passwd

Need a fast recovery path back to control if the kiosk (tty1) misbehaves,
using the existing `tricca` admin/SSH account. Ctrl+Alt+F2 autologs in as
`tricca` and execs `tap` instead of a normal shell — but this is deliberately
NOT done by changing `tricca`'s `/etc/passwd` shell, because that would
hijack SSH logins on the same account too (every SSH session would land in
`tap` instead of a normal shell). Instead a profile.d script execs `tap`
only when the tty is a physical console (tty2+), never a pts/SSH session.

## Considered options

- Change `tricca`'s login shell to `tap` — rejected: breaks SSH for the same
  account.
- profile.d script gated on physical-console tty (chosen).

## Consequences

tty1 stays kiosk-only; if the kiosk dies and getty@tty1 comes back, that
login is left as a normal shell (a second, different recovery path), not
exec'd into `tap`.
