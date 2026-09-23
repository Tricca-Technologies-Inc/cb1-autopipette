# CI runs full aarch64 builds via QEMU on GitHub-hosted runners, not eval-only, and not on a self-hosted runner

Status: accepted

Before this, "verified" meant a human ran `switch` on real hardware and
grepped the output for WARN — there was no automated check at all, and
`nix flake check` (see below) wouldn't have caught the `modules/klipper.nix`
split's module-merge risk even if someone had run it. Settled via a
`/grilling` session, 2026-08-11.

`nix flake check` does not evaluate or build `systemConfigs` — it's a
system-manager output, not part of Nix's recognized flake schema, so it's
silently skipped ("unchecked" warning) regardless of `--all-systems`. CI
therefore always needs an explicit `nix build .#systemConfigs.default` step
no matter which validation tier is chosen; that alone is not a fully
"eval-only, zero-build" option.

Given that, CI does a full real build of both `systemConfigs.default` and
`packages.aarch64-linux.*` (tricca-autopipette, mantaFirmware), on a
standard GitHub-hosted x86_64 runner with QEMU binfmt emulation
(`docker/setup-qemu-action`) registered so the Nix sandbox can execute
aarch64 builders. This is the strongest signal available (catches real
build breakage, not just eval/assertion errors) at a cost judged acceptable
because: the repo is public (GH Actions minutes are free), and most of the
aarch64 closure already substitutes pre-built from cache.nixos.org rather
than compiling (confirmed via a local dry-run build that got well into
downloading substitutes before hitting an unrelated platform-mismatch wall
on this workstation, which lacks aarch64 emulation locally — see README
field notes / [[reference_workstation_and_marie_access]]).

A self-hosted runner on marie was considered and explicitly rejected for
now. GitHub documents self-hosted runners on public repos as a real
security risk: a PR (including from a fork) can get its workflow code
executed on the runner machine. Marie isn't spare compute — it holds a live
Klipper connection to a physical gantry with motor control, so that risk is
a hardware-safety concern, not just a supply-chain one. Revisit only with
an explicit exposure-control plan (leading candidate: marie only builds on
`push` to `main`, i.e. post-merge/already-reviewed code, never on an
arbitrary PR branch) — same "revisit if it becomes worth it" shape as the
deferred attic binary cache idea.

The check is required on `main`'s branch protection from day one (not
phased in informationally first) — this is a solo-maintainer repo where the
check should be reliable rather than flaky, consistent with this repo's
existing rigor (WARN-grepping switch output, treating a clean switch as
necessary-but-not-sufficient).

## Consequences

- Nix hygiene linting (formatter, `statix`/`deadnix`) is deliberately out of
  this workflow — tracked separately as
  [issue #6](https://github.com/Tricca-Technologies-Inc/cb1-autopipette/issues/6)
  so the formatter-choice-plus-repo-wide-reformat diff doesn't get bundled
  into build-correctness CI.
- A build failure in CI (e.g. a broken `packages.aarch64-linux.mantaFirmware`
  derivation) blocks merge even though nothing has touched real hardware —
  this is the intended tradeoff, not a false positive to work around.

## Update, 2026-09-23 — native arm64 runner instead of QEMU

The QEMU half of this decision was the whole cost. Runs took 33–56 min
(all 37 successful runs, 2026-08-12 to 2026-09-09), and in run 34408992658 the
`nix build .#systemConfigs.default` step alone was 53.5 of 54 min: the
system-manager Rust CLI (`system-manager-1.1.0`, not in any binary cache
because this flake makes system-manager follow our nixpkgs) compiled from
source under emulation for ~52 min, with the two Klipper firmware builds and
tricca-autopipette alongside it. The ADR's "most of the closure substitutes"
premise held; the leaves it didn't cover were the expensive part.

CI now runs on GitHub's native `ubuntu-24.04-arm` runner (free for public
repos; all three repos are public) and the QEMU step is gone. Everything
else stands: full real build, not eval-only, and still no self-hosted
runner on marie.

Also corrected: this ADR and the workflow said `nix flake check` builds
`packages.aarch64-linux.*`. It only evaluates them (0.3 min in the run
above). They were still built every run, because all three packages
(`default`, `mantaFirmware`, `tricca-autopipette`) are in
`systemConfigs.default`'s closure, checked 2026-09-23.

The "required on `main` from day one" part lapsed: `flake-check` was
dropped from branch protection's required checks on 2026-08-18 because
runs were too slow, and is still off. Re-enable once native runs prove
fast.
