# Current Build State

Last updated: 2026-11-06 by Claude (repo-state retrofit): state files, justfile verify targets, PR state guard; dev-icloud-backup failure on n0 logged as open.

## Phases

- [x] P0 Topic layout and bootstrap (holman fork)
- [x] P1 Brewfile stays true: `brew` wrapper and `brew-reconcile`
- [x] P2 Security hardening, audit runs 1 to 3 (PRs #1, #4, #5, #6, #7)
- [x] P3 Encrypted nightly iCloud backup of ~/dev
- [x] P4 Two-machine ~/dev sync, GitHub as hub
- [x] P5 Nightly Homebrew upgrade on the laptop
- [~] P6 Repo-state pattern (this retrofit; verify passes, waiting on merge)

## What is true now

- Deployed by symlink: `~/.dotfiles -> ~/dev/dotfiles` on n0. `script/bootstrap` links `*.symlink`
  into `$HOME`; `bin/dot` runs installers and `macos/install-launchd.sh`.
- LaunchAgents (`macos/*.plist`, host-gated by the `dotfiles-hosts` marker, matched on `HostName`
  since 2619b3d):
  - n0: `dev-pull` (every 20 min), `dev-icloud-backup` (nightly), `brew-reconcile`.
  - book: `dev-sync-from-n0`, `brew-nightly` (23:45, sublevel ADR-088; failures fire On Fire
    `upgrade:brew-book`).
  - Observed on n0 2026-11-06: `dev-pull` and `brew-reconcile` last exit 0; `dev-icloud-backup`
    last exit 1 (see Open).
- Brewfile sync: `functions/brew` records interactive installs and pushes only when its Brewfile
  commit is the single unpushed commit (PR #1, #2); `brew-reconcile` catches out-of-band installs
  including Mac App Store apps. Both commit `brew: ...` directly to `master`.
- iCloud backup: plaintext mirror for ordinary files; anything secret-shaped or gitignored goes
  only into an age-encrypted archive, git history as encrypted bundles (PR #3, #5).
- ~/dev sync: GitHub is the hub (sublevel ADR-071). `bin/dev-pull` fast-forwards clean checkouts,
  never resets; untracked files no longer block a fast-forward and a checkout stuck for a day fails
  the run (dc1137d). `bin/dev-sync-from-n0` pulls repos plus private files to the laptop and renders
  the sublevel ssh-config and Turing Pi kubeconfig (22c41f5); `bin/dev-push-to-n0` is the manual
  reverse for private files.
- zsh: projects in `~/dev`, sublevel SOPS env, `KUBECONFIG` points at the Turing Pi K3s cluster
  (0f385fb); SSH sessions use the desktop ssh-agent.
- Tests: `script/test` runs 4 regression tests (`brew-sync-push`, `dev-icloud-backup`, `dev-pull`,
  `untrusted-input`); all pass on n0 2026-11-06.
- No CI existed before this retrofit; `.github/workflows/state-guard.yml` now checks PRs only, so the
  unattended `brew:` pushes to `master` are not gated.

## Verify output (P6, 2026-11-06, n0)

```
$ just check
syntax ok
shellcheck ok
plists ok
ok brew-sync-push
ok dev-icloud-backup
dev-pull: ok
ok untrusted-input
$ just verify-phase-6
ok check-state
verify-phase-6 ok
```

## Open / BLOCKED

- dev-icloud-backup on n0 failed 2026-11-06 08:46Z: writing
  `Backups/n0/git/birdnet-go.refs` in iCloud Drive returned "Resource deadlock avoided" (EDEADLK
  from the iCloud file provider) at `bin/dev-icloud-backup` line 117, and the script exited 1 before
  finishing. Previous 8 nights were exit 0. Next: check tonight's run in
  `~/Library/Logs/dev-icloud-backup.log`; if it repeats, retry the `.refs` write (and the `mv` of
  the bundle) a few times on EDEADLK, or write `.refs` via a temp file plus `mv`, with a test case.
- Legacy holman scripts (`bin/dot`, `bin/git-up`, `bin/mustacheme`, `script/bootstrap`) have
  shellcheck warnings; `just check` lints only the maintained scripts. Clean up or delete unused ones.
- README.md is still holman's upstream text; it does not describe the launchd jobs or the two hosts.

## Next

- Merge this retrofit, then mark P6 done.
- Resolve the iCloud backup EDEADLK item above.
