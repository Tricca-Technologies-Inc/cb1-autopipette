# 2026-07-30 — OOM, corrupt store output, and a kernel panic (nick)

**Status: resolved.** Both root causes below are fixed permanently in the
repo (`--accept-flake-config` on every `switch`/`bootstrap.sh` invocation,
plus the repair procedure documented for the corruption case). Kept here as
a record of what the symptoms looked like and why, in case either
recurs.

This predates the [generation-8 stuck saga](nick-generation-8-upgrade.md) by
about two weeks — nick was still on an earlier generation at the time.

## Symptom 1: activation fails with an EOF parse error

```
Error during activation: EOF while parsing a value at line 1 column 0
while "Reading etc file definitions"
```

This means a 0-byte manifest (`etcFiles.json`/`services.json` under the
generation's store path), not a config error — confirm with `wc -c` on the
file. Cause: a build got interrupted (OOM-prone on the CB1's 1 GB RAM),
leaving Nix's local store database marking an output "valid" when it's
actually empty/corrupt. `nix store verify --repair` can't fix this on its
own — these are local-only derivations with no substituter to re-fetch
from, so it just reports the mismatch and exits 0.

**Fix:** force a genuine local rebuild of the whole closure —
`nix build .#systemConfigs.default --repair -o <path>`, then `switch`
again. Before assuming this is the cause, rule out hardware bit-rot:
check `dmesg` for I/O errors, and check whether the *currently active*
generation's copies of the same files are healthy — in this incident, only
outputs from the one interrupted build session were affected.

## Symptom 2: a retry then compiles the Rust CLI from source and panics the kernel

Retrying without realizing `system-manager`'s own `flake.nix` declares
`nixConfig.extra-substituters = cache.numtide.com` (prebuilt aarch64-linux
binaries for the CLI, including its Rust build deps like `userborn`) is a
trap: without `--accept-flake-config`, Nix refuses to trust that
substituter —

```
warning: ignoring untrusted flake configuration setting 'extra-substituters'
```

— and silently falls back to building the Rust CLI on-device instead.
`rustc`/`lto1` OOM-killed nick's 1 GB RAM outright on first encounter, and
on a second retry caused an actual kernel panic: `hung_task: blocked
tasks`, `mmc_sd_detect` stuck claiming the MMC host — the sustained heavy
write I/O from unpacking hundreds of store paths wedged the SD card
controller badly enough that `khungtaskd` gave up and panicked rather than
hang forever.

**Fix:** both `bootstrap.sh` and the `switch` shell alias now always pass
`--accept-flake-config`. Verified this pulls the CLI as a single fast
`cache.numtide.com` fetch instead of a multi-minute local Rust build. This
is now load-bearing on every machine, every switch — see README's
troubleshooting section for the one-line rule.

## Note

Pinning the system-manager CLI to the exact rev in `flake.lock`
(`system-managerRev` in `flake.nix`) was suspected as a contributing gap at
the time (an unpinned `nix run github:numtide/system-manager` floats
independently of the system-manager *library* pinned in `flake.lock`, used
to build the config the CLI activates) but turned out not to be the actual
cause here — pinning the CLI to the exact `flake.lock` rev reproduced the
identical corruption. The pin is still correct/required for its own reasons
(keeping CLI and library in sync), just wasn't what caused this particular
incident.
