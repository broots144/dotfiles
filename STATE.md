# Current Build State

Last updated: 2026-11-07 by Claude (security review r2 closed out: PRs #16, #17 merged and deployed on n0; grade A).

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
- iCloud backup, security review 2026-11-07 (F2, L4): the ignored-file scan and the exclude
  rules now cover every working tree, `.git` files included (worktrees in `~/dev/_wt`,
  submodules), not only checkouts with a `.git` directory; a worktree's ignored files were
  mirrored in plaintext before. Their small ignored files go to the archive only (`ignoredd`),
  so the MacBook sync scope is unchanged. A checkout git cannot read (a worktree whose main repo
  moved) is excluded whole and its small files archived. `.build/` is a bulk exclude. rsync runs
  with `-W`; when openrsync stops on "unlinkat: Directory not empty" (an excluded package dir
  such as `.build/*.app` it cannot delete in iCloud) or on "Resource deadlock avoided" (an
  evicted mirror file), those mirror paths are removed with rm and rsync runs again (at most 3
  runs). The nightly run of 2026-11-07 had failed that way (exit 1, mirror partial).
  The first live run after PR #13 (2026-11-07 13:54Z) still hit EDEADLK on a new evicted file
  each attempt (54k evicted files in the mirror, about 2,100 of them stale). So before rsync,
  every evicted (dataless) mirror file whose size or mtime differs from ~/dev, or that ~/dev no
  longer has, is removed; rsync writes it fresh. `DEV_BACKUP_EVICTED_FLAG` is the test hook.
  `DEV_BACKUP_RSYNC` exists for the tests (test/dev-icloud-backup-edges.sh).
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
- dev-pull and untrusted repos (security review 2026-11-07, F1/F3, D-009): it fetches only
  origins on GitHub, plus the EREs in the local, untracked `~/.config/dev-pull/trusted-origins`
  (n0 lists its self-hosted forge there); others are `foreign`, skipped, and the MacBook sync
  follows n0 for them. A repo whose local config names a filter, merge or diff driver, a
  credential helper, a url rewrite, a remote helper, a pushurl, an include or a core.worktree is `unsafe`
  and skipped. Every call runs with hooks off, only the https and ssh transports, the stock
  upload-pack/receive-pack and the askpass/ssh command from the script. The summary line ends in
  `, N skipped`. Third-party clones inside rebuildable output (.pio/libdeps, .build/checkouts)
  are no longer listed as repos (dev_tree_repos prunes DEV_TREE_REBUILDABLE unless the dir is a
  checkout itself), so dev-pull, the bundles and the MacBook sync leave them alone.
  WIP snapshots go only to private repos (`gh api repos/X --jq .private`, cached per day in
  `~/.local/state/dev-pull/visibility`; unknown counts as public and clears an old snapshot).
  Since review r2 (N2) the push asks gh again without the cache, so a repo made public today
  gets no new snapshot. A snapshot already pushed becomes public with the repo: **delete
  `refs/wip/*` on origin before making a repo public** (`git push origin --delete refs/wip/n0
  refs/wip/book`).
- dev-pull and submodules (review r2, N1): git never recurses into a submodule from dev-pull
  (`fetch.recurseSubmodules=false`, `submodule.recurse=false`, `push.recurseSubmodules=no`,
  `diff.ignoreSubmodules=all`, and `--ignore-submodules=all` on every `status`), so a
  submodule's own config (filter, credential helper) is never read by a command that runs it.
  `local_config_unsafe` also scans absorbed submodule configs (`.git/modules/**/config`,
  git's own `core.worktree` there allowed) and skips the repo with `<key> in submodule <name>`.
  Submodules are not updated by dev-pull; run `git submodule update` by hand.
  gitleaks runs with `lib/gitleaks.toml`, an empty ignore dir and `--ignore-gitleaks-allow`, so
  the scanned tree cannot switch rules off. Pinned by test/untrusted-input.sh and
  test/dev-pull-edges.sh (real gitleaks case; CI installs gitleaks). `DEV_PULL_ALLOW_FILE=1`
  and `DEV_PULL_GH` exist for the tests.
- node/install.sh (`sudo npm install spoof -g`, unpinned, as root) deleted (L1).
- dev-sync-from-n0's run lock is a symlink `lock.pid -> <pid>` (atomic; pid checked to be a
  sync process); a stale lock is removed only if it still names the stale pid, the exit trap
  removes it only while it names this run, and a live run of the old mkdir-lock version makes
  the new one skip. dev-push-to-n0 exits 4 when an rsync comparison fails (rsync 23/24, a file
  vanished, are reported and not fatal). A local refs cache entry is seeded once from a matching
  iCloud `.refs`, which is then removed.
- Tests: `script/test` runs 15 regression tests (`brew-nightly`, `brew-reconcile`, `brew-sync-push`,
  `brew-wrapper`, `check-state`, `dev-icloud-backup`, `dev-icloud-backup-edges`, `dev-pull`,
  `dev-pull-edges`, `dev-push-to-n0`, `dev-sync-from-n0`, `dev-sync-lock`, `install-launchd`,
  `untrusted-input`, `workflow-pinning`); all pass on n0 2026-11-07 under /bin/bash 3.2.
  The MacBook sync tests reach a fake n0 (a directory) through an ssh stub
  (`test/lib/fake-n0.sh`), passed as `DEV_SYNC_SSH` so a Homebrew ssh ahead in PATH cannot
  shadow it and reach the real n0; GitHub is unreachable in them; brew, mas, scutil, launchctl and
  onfire-notify are stubs. `bin/brew-nightly` takes `BREW_NIGHTLY_PATH` for its test.
- Coverage: `script/coverage` (`just coverage`, bash 4.1 or later) traces every bash process the
  suite starts and reports approximate line coverage of the maintained bash scripts: 51% before
  this branch (282 of 551 statements), 96% after (534 of 551). The zsh scripts (`brew-reconcile`,
  `functions/brew`, the prompt) are tested but not measured.
- CI: `.github/workflows/tests.yml` runs syntax, shellcheck, plist lint and the suite on
  macos-latest for pull requests and pushes to master (suite under /bin/bash 3.2, coverage in
  the job summary, not gated).
- install-launchd.sh matches the `dotfiles-hosts` marker on whole names: `grep -w n0` also matched
  a marker naming `n0-2` (fixed on this branch, pinned by `test/install-launchd.sh`).
- `state-guard.yml` uses `actions/checkout` v7.0.1, SHA pinned (PR #9, 2026-11-06).
- Actions supply chain (review r2, L3): the repo setting `sha_pinning_required` is true (set
  2026-11-07 with `gh api -X PUT repos/broots144/dotfiles/actions/permissions`), so GitHub
  refuses a workflow that uses an action by tag. `.github/dependabot.yml` updates the
  github-actions pins weekly, grouped, with the `deps:` prefix that state-guard exempts; n0's
  hourly merger (sublevel ADR-089) merges them when green. `test/workflow-pinning.sh` checks
  both in the suite.
- `script/check-state` skips merge commits (`git log --no-merges`), so the chore:/deps:/brew:
  exemption now works on PRs, where HEAD is GitHub's synthetic merge commit (PR #9, self-tested).
- `.github/workflows/state-guard.yml` checks PRs only; `tests.yml` also runs on pushes to master
  (reports, does not block, the unattended `brew:` pushes).

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

## Security grade

Current grade: **A** (security review 2026-11-07 r2; rubric: A = no open Medium or higher and
every open Low documented with a reason; A+ also needs no open finding above Informational).

- r2, fixed and deployed on n0 2026-11-07: N1 (Medium) dev-pull ran a submodule's repo-local
  config through status and fetch (PR #16), N2 (Low) the visibility cache let a repo made public
  get snapshots for up to a day (PR #16), L3 (Low) Actions pinning not enforced and not updated
  (PR #17 plus the repo setting `sha_pinning_required=true`).
- r2 verified live: dev-pull via launchctl kickstart 2026-11-07 15:41Z exit 0, `0 skipped`,
  `workshop144/periphery` (has a submodule) `current`; `gh api .../actions/permissions` shows
  `sha_pinning_required: true`.
- r1, fixed and deployed on n0 2026-11-07: F1 dev-pull ran repo-local git config (PR #12), F3 WIP
  snapshots to public repos (PR #12), L1 `sudo npm install spoof -g` (PR #12), F2 worktree and
  submodule ignored files in the plaintext mirror (PR #13), L4 nightly backup failing (PR #13,
  #14). r1 verified live: dev-icloud-backup run 2026-11-07 14:27Z exit 0 (removed 2,127 stale
  evicted mirror files, no rsync errors); every exclude rule path, including
  `forks/MeshCore-v1.18/.pio`, `StockDock/.build` and `tv-fleet/private`, is gone from the mirror.
- Not A+: the open Lows below remain (one is blocked on the operator), and the CI's Homebrew
  tools are not version-pinned.

Open Lows, each accepted or blocked:

- BLOCKED on the operator (Low): plaintext copies mirrored before the fixes (`tv-fleet/private/`
  before 2026-11-06, worktree ignored files before PR #13) sit in iCloud Drive "Recently Deleted"
  until they are purged or expire after 30 days, and the TV pairing tokens were in them. Purging
  "Recently Deleted" and rotating the pairing tokens are dashboard and device steps for the
  operator. The copies sit only in the operator's own iCloud account; they were never public.
- Accepted (Low): dev-pull's `unsafe_re` is a deny-list of repo-local keys that can name a command.
  A key a future git adds would not be in it. Mitigated by the -c overrides (hooks off, https and
  ssh only, stock upload-pack), the GitHub-only origin rule and GIT_ASKPASS/GIT_SSH_COMMAND from
  the script; test/untrusted-input.sh pins the known vectors. Revisit on a major git upgrade.
- Accepted (Low): dev-sync-from-n0 on the MacBook clones and fast-forwards from n0 (fallback)
  with DEV_TREE_GIT only, not dev-pull's hardened set. n0 is the operator's own machine and a
  clone does not carry n0's repo-local config; the laptop's checkouts are its own.
- Accepted (Low): CI installs age, bash, just, shellcheck, jq and gitleaks from Homebrew without
  version pins (bottles are checksummed; the job has `contents: read` only and no secrets).
  GitHub Actions are pinned by SHA.
- Accepted (Low, procedure): a WIP snapshot already on a repo becomes public the moment the repo
  is made public; dev-pull cannot see that coming. Procedure: delete `refs/wip/*` on origin
  before changing a repo to public (see "What is true now"). Since N2, no new snapshot is pushed
  after the change.
- Accepted (Informational): submodules are not scanned when they are not absorbed (`sub/.git` a directory);
  dev-pull never runs a git command inside one (no recursion, `--ignore-submodules=all`), which
  test/untrusted-input.sh pins.
- Accepted (Informational): gitleaks does not catch personal data or drafts; WIP snapshots now
  go to private repos only, so that content stays in the operator's private GitHub repos.

## Open / BLOCKED

- Operator: purge iCloud Drive "Recently Deleted" (plaintext copies from before the 2026-11-06
  and 2026-11-07 fixes) and rotate the TV pairing tokens (see Security grade).
- Legacy holman scripts (`bin/dot`, `bin/git-up`, `bin/mustacheme`, `script/bootstrap`) have
  shellcheck warnings; `just check` lints only the maintained scripts. Clean up or delete unused ones.
- README.md is still holman's upstream text; it does not describe the launchd jobs or the two hosts.

## Next

- Watch the next nightly backup (`LAST_RUN.json` exit 0, no "removed ... evicted" storm) and the
  first dev-pull WIP snapshot of a private repo (visibility cache in
  `~/.local/state/dev-pull/visibility`).
