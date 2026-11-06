# Current Build State

Last updated: 2026-11-06 by Claude (bug sweep, branch fix/bugs-2026-11-06): 12 verified bugs fixed in the sync and backup scripts, the iCloud EDEADLK item resolved, a fifth test (dev-sync-lock).

## Phases

- [x] P0 Topic layout and bootstrap (holman fork)
- [x] P1 Brewfile stays true: `brew` wrapper and `brew-reconcile`
- [x] P2 Security hardening, audit runs 1 to 3 (PRs #1, #4, #5, #6, #7)
- [x] P3 Encrypted nightly iCloud backup of ~/dev
- [x] P4 Two-machine ~/dev sync, GitHub as hub
- [x] P5 Nightly Homebrew upgrade on the laptop
- [x] P6 Repo-state pattern (PR #8)

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
  only into an age-encrypted archive, git history as encrypted bundles (PR #3, #5). Since the
  2026-11-06 bug sweep: gitignored directories and gitignored files of any size get an exclude
  rule (before, they were mirrored in plaintext: TV tokens, private/ dirs, tablet backups);
  small files inside ignored directories are archived, except rebuildable output
  (`DEV_TREE_REBUILDABLE`: target, build, .wrangler, .pio, ...); the archive is gzipped inside
  age (about 200 MB per night measured on n0, was 16 MB; 14 generations kept; restore with
  `tar -xzf -`). Those files inside ignored directories go in a separate list (`ignoredd`)
  that the MacBook sync does not read: the laptop sync scope (`--manifest`, dev-push-to-n0) is
  unchanged by the bug sweep (scratch/, logs/, cache/, private/ dirs stay on their machine). The refs cache
  for git bundles lives in `~/.local/state/dev-icloud-backup/git`, not iCloud; a failed write
  into iCloud, an unreadable directory, a missing age key or a missing ~/dev each end in a
  status code and LAST_RUN.json instead of a silent abort.
- ~/dev sync: GitHub is the hub (sublevel ADR-071). `bin/dev-pull` fast-forwards clean checkouts,
  never resets; untracked files no longer block a fast-forward and a checkout stuck for a day fails
  the run (dc1137d). `bin/dev-sync-from-n0` pulls repos plus private files to the laptop and renders
  the sublevel ssh-config and Turing Pi kubeconfig (22c41f5); `bin/dev-push-to-n0` is the manual
  reverse for private files.
- zsh: projects in `~/dev`, sublevel SOPS env, `KUBECONFIG` points at the Turing Pi K3s cluster
  (0f385fb); SSH sessions use the desktop ssh-agent.
- dev-pull WIP snapshots: files inside secret-named directories are excluded (`<name>/**`); a
  missing gitleaks withholds the push; the local record of a snapshot is dropped only once the
  remote ref is really gone. `DEV_PULL_OWN_RE` / `DEV_PULL_GITLEAKS` exist for the tests.
- dev-sync-from-n0's run lock is a symlink `lock.pid -> <pid>` (atomic; pid checked to be a
  sync process); a stale lock is removed only if it still names the stale pid, the exit trap
  removes it only while it names this run, and a live run of the old mkdir-lock version makes
  the new one skip. dev-push-to-n0 exits 4 when an rsync comparison fails (rsync 23/24, a file
  vanished, are reported and not fatal). A local refs cache entry is seeded once from a matching
  iCloud `.refs`, which is then removed.
- Tests: `script/test` runs 5 regression tests (`brew-sync-push`, `dev-icloud-backup`, `dev-pull`,
  `dev-sync-lock`, `untrusted-input`); all pass on n0 2026-11-06.
- `state-guard.yml` uses `actions/checkout` v7.0.1, SHA pinned (PR #9, 2026-11-06).
- `script/check-state` skips merge commits (`git log --no-merges`), so the chore:/deps:/brew:
  exemption now works on PRs, where HEAD is GitHub's synthetic merge commit (PR #9, self-tested).
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

- After the bug sweep merges: check the next nightly run on n0 (`~/Library/Logs/dev-icloud-backup.log`,
  `LAST_RUN.json` exit 0) and that the mirror no longer holds `tv-fleet/private/`. The leaked
  plaintext copies also sit in iCloud "Recently Deleted" for 30 days; purging them and rotating the
  TV pairing tokens are operator steps (not done by agents).
- Legacy holman scripts (`bin/dot`, `bin/git-up`, `bin/mustacheme`, `script/bootstrap`) have
  shellcheck warnings; `just check` lints only the maintained scripts. Clean up or delete unused ones.
- README.md is still holman's upstream text; it does not describe the launchd jobs or the two hosts.

## Next

- Merge the bug sweep PR; watch the first nightly backup after it (archive size, exit code).
