# Prime: build on a workstation, push the closure, don't build on-machine

Status: accepted

`switch` builds `systemConfigs.default` on the machine itself, which means
fetching/building its whole closure (nixpkgs deps, not just the pure-Python
app) over whatever internet that machine has. Both `marie` and `nick` are
lab machines on wifi/hotspot only — no ethernet option — and hotspot
bandwidth/reliability made `switch` slow enough to be a real problem,
independent of the CB1's own 1GB-RAM build constraint (rule 8) that already
ruled out building heavyweight packages on-device.

Alternatives considered:

- **Reuse CI's build** (`.github/workflows/ci.yml` already builds the full
  aarch64 closure every push, see ADR-0008). Rejected: CI pushes its build
  to no durable cache (no cachix/attic step), and the GitHub-hosted runner
  has no LAN path to either machine — reusing it would need new cache-push
  plumbing that still ends in a WAN hop to the machine, which doesn't solve
  the actual problem.
- **Self-hosted attic cache.** Considered and parked before (see repo
  memory, 2026-08-10) pending fleet growth; the trigger here is connection
  quality, not machine count, so left parked again — ad hoc `nix copy` is
  simpler and sufficient for two machines. Revisit informally if it becomes
  real friction, no fixed threshold set.
- **Root SSH login on the machine**, to let a `nix copy` push land without
  a trust grant. Rejected: bigger security-surface change (touches sshd)
  for a problem `nix.settings.trusted-users` solves declaratively.
- **Store signing** (`nix store sign` + `trusted-public-keys`) instead of a
  trust grant. More correct for an adversarial multi-tenant setup; skipped
  as unnecessary infra for two machines under active development. The
  `trusted-users` grant is easy to replace with signing later if it ever
  matters.

Decided: a workstation builds `systemConfigs.default` (needs a one-time
local fix — `qemu-user-static`/`binfmt-support` + `extra-platforms =
aarch64-linux`, see `prime.sh`'s own preflight check) and pushes the
closure to the machine over local-network SSH (`nix copy --to
ssh://tricca@<host>`, wifi or hotspot — same network, not routed over the
internet) via the new `./prime.sh` script. The machine trusts the push via
`modules/nix-settings.nix` (`nix.settings.trusted-users = [ "tricca" ]`),
shipped declaratively like everything else in this repo rather than a
manual per-machine `nix.conf` edit.

`switch` itself is unchanged — see CONTEXT.md's **Switch** entry. It still
builds `systemConfigs.default` first; priming just means that build is
already satisfied locally, so switch is fast. Intended pilot: `nick` first
(the machine actually hotspot-constrained); not yet run on either machine.

## Consequences

- New workstation-side prerequisite: aarch64 build emulation, one-time
  setup, not managed by this flake (workstation isn't a machine this repo
  configures).
- `bootstrap.sh`'s "switch is the only command you need" is no longer
  quite the whole story for a hotspot-only machine — priming is optional
  but expected in practice for `marie`/`nick`.
- Adds one trusted, non-root local user (`tricca`) on every machine, via
  `modules/nix-settings.nix`.
