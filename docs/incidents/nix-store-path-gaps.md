# Nix-generated units have a nix-store-only PATH — three bugs this bit

**Status: resolved (each instance fixed individually).** Kept here as
worked examples of a general pattern worth watching for when writing new
modules — the pattern itself is called out as a standing rule in
`CLAUDE.md`'s hard-won rules.

Nix-generated systemd units get a `PATH` containing only what's explicitly
declared (via `path = [ ... ]` or an absolute store path) — never the
system's normal `PATH`. Any script or unit that calls a binary by bare name
instead of an absolute path, or without declaring it in `path`, is at risk —
and this isn't limited to third-party/apt tools; it bit our own scripts
just as easily. All three cases below failed with **no error anywhere** —
the call just silently didn't run, or (in the `cmp` case) silently ran a
"succeed unconditionally" fallback path instead of the intended check.

- **kiosk-xinitrc's `xset` calls** (screen blanking/DPMS/screensaver
  disable) silently never ran until pathed to `/usr/bin/xset`
  (commit `0e0f97d`).
- **kiosk's `/etc/chromium.d/dev-shm` hook** couldn't find `findmnt`, fixed
  via `path = [ pkgs.util-linux ]` (commit `201acda`).
- **moonraker's `preStart` PolicyKit-rules idempotency check** (`cmp`, from
  `diffutils`) silently failed every boot, which meant it fell through to
  rewriting the rules file unconditionally instead of only on change
  (commit `40a4f00`).

**Verifying a `path = [...]` fix on an already-running service needs an
explicit `systemctl restart <unit>`** — a plain `switch` reloads the unit
file but doesn't restart what's already running, so the old (broken)
process keeps running with the old PATH until something restarts it.

If a new module calls out to any binary that isn't a Nix derivation output
directly, check this first before assuming the config itself is wrong.

## Related: system-manager's PATH only reaches login shells (2026-11-27)

Same family, from the other side: not a unit's PATH, but an SSH command's.
Found while reviewing PR #84 (issue #74, `tap` on PATH), by reading the
pinned system-manager source rather than on a rig.

system-manager puts `environment.systemPackages` in
`/run/system-manager/sw/bin` and adds that to PATH in exactly two places
(`nix/modules/environment.nix`):

- `/etc/profile.d/system-manager-path.sh`, read only by login shells;
- `/etc/environment.d/10-system-manager.conf`, read only by systemd user
  sessions.

`ssh tricca@<rig> tap` runs a non-login, non-interactive `bash -c`. Debian's
bash does read `~/.bashrc` for SSH commands, but the stock `.bashrc` returns
immediately when the shell isn't interactive. So the command gets sshd's
default PATH (`/usr/local/bin:/usr/bin:/bin:...`) and fails with
`bash: tap: command not found`. This applies to every Nix-provided binary
(`gpiodetect`, `htop`, ...), not just `tap`. `ssh <rig>` followed by typing
the command works, because that shell is a login shell.

Fix used for `tap`: a tmpfiles rule,
`L+ /usr/local/bin/tap - - - - /run/system-manager/sw/bin/tap`, in
`modules/tricca-console.nix`. system-manager's activation runs
`systemd-tmpfiles --create`, so the link appears on the first switch.
Pointing it at the profile path rather than a store path means it follows
every later switch without changing.

**Still to confirm on nick:** `ssh tricca@nick 'command -v gpiodetect'`
printing nothing before the switch, and `ssh tricca@nick 'command -v tap'`
printing `/usr/local/bin/tap` after it (PR #84's rig checklist).

## Related: system-manager owns root's login shell (2026-11-27, issue #85)

Found right after the `tap` PATH finding, while working out why `bash` and
`sh` were in the system profile. Confirmed by evaluating
`systemConfigs.default` and reading the pinned system-manager and userborn
sources; the rig state was not checked.

- system-manager imports NixOS's `users-groups` module, which declares
  `root` (shell `users.defaultUserShell = pkgs.bashInteractive`) and
  `nobody` (shell: a `nologin` package), and enables userborn by default.
- Userborn's generated config gave root
  `/run/system-manager/sw/bin/bash` and nobody
  `/run/system-manager/sw/bin/nologin`. In mutable mode userborn still
  updates an existing user's shell, home and description
  (`update_user` in userborn's `src/main.rs`), so a switch rewrites
  Armbian's own entries.
- That shell path lives on a tmpfs and only exists after system-manager's
  activation has run on this boot. If activation fails, or on a rescue
  boot, root has no working login shell: console login, `sudo -i` (which
  the `switch` helper uses) and `su -` all fail.
- The module also installs every user shell that is a package, which put
  `bash`, `sh` and `nologin` in `/run/system-manager/sw/bin`, ahead of
  Armbian's `/bin/bash` and `/bin/sh` (dash) in every login shell.

Fix (`modules/base.nix`): `users.users.root.shell = "/bin/bash"` and
`users.users.nobody.shell = "/usr/sbin/nologin"`, as path strings. Userborn
writes those on the next switch, which also repairs rigs it already
changed, and string shells aren't installed as packages.
`checks.system-shells` asserts both values and that the profile has no
`bin/bash`, `bin/sh` or `bin/nologin`.

Not changed: userborn also sets root's description to "System
administrator" and nobody's home to `/var/empty` (Debian: `root` and
`/nonexistent`). Both are harmless.

**Still to confirm on nick:** `getent passwd root nobody` before the switch
(does root actually have the Nix bash?), and after it.
