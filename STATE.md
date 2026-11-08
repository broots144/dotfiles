# Current Build State

Last updated: 2026-11-08 by Claude (security audit run-8 fixes on fix/herdr-audit-run8: the gate binds launchd's job to the serving process). Before: 2026-11-08 by Claude (security audit run-7 fixes on herdr/audit-run7-fixes). Before: 2026-11-08 by Claude (security audit run-6 fixes: verify-herdr never prints the owner name; D-012 purge right before exec; herdr pinned on every Mac). Before: herdr agent-detection rules bundled only, D-012; audit sandbox recorded, D-013). Before: 2026-11-07 by Claude (P8 herdr done: PR #24 merged and deployed on n0, `just verify-phase-8` passes, output below). Before: security review r3 closed out, PRs #18 to #22, grade A.

## Phases

- [x] P0 Topic layout and bootstrap (holman fork)
- [x] P1 Brewfile stays true: `brew` wrapper and `brew-reconcile`
- [x] P2 Security hardening, audit runs 1 to 3 (PRs #1, #4, #5, #6, #7)
- [x] P3 Encrypted nightly iCloud backup of ~/dev
- [x] P4 Two-machine ~/dev sync, GitHub as hub
- [x] P5 Nightly Homebrew upgrade on the laptop
- [x] P6 Repo-state pattern (PR #8)
- [x] P8 herdr on n0 (plan docs/plans/P8-herdr.md, D-010, D-011, PR #24)

## What is true now

- herdr (P8, D-010, D-011, docs/herdr.md): Homebrew herdr 0.9.5 installed on n0 and pinned
  (`herdr/VERSION`). Claude integration v11 installed and read first: one hook file and one
  `SessionStart` entry in `~/.claude/settings.json`. Verified live 2026-11-07 with two Claude
  sessions in herdr panes: working, blocked (Write permission prompt, folder-trust prompt) and
  idle all read correctly through the API, and the sidebar draws blocked as a red filled dot and
  idle as a green ring. No shell file auto-attaches tmux; `test/herdr.sh` fails on one that would
  without the `HERDR_ENV` guard. `herdr/config.toml` (linked by `herdr/install.sh`), the n0
  LaunchAgent `com.broots.herdr-server` (`bin/herdr-server`, sets `~/.config/herdr` to 0700) and
  agent-detection rules come only from the pinned binary (D-012: `bin/herdr-server` drops a
  remote rule cache, the gate checks every rule is `bundled`; the Phase 0 `p0test` session that had
  refilled that cache from herdr.dev is stopped and deleted, the cache removed, rules reloaded on
  n0 2026-11-08). Audits run target code only in the sandbox of D-013.
  Security audit run-6 (2026-11-08, ~/security-audit-skill/dotfiles/run-6, scoped to the herdr
  work): 2 confirmed, both fixed on `herdr/audit-run6-fixes`, each with a regression test in
  test/herdr.sh: (low) `script/verify-herdr` printed the account name in FAIL lines that go into
  this public STATE.md (it now compares uids and says owner me/other, and masks the name anyway);
  (informational) the D-012 cache purge ran before the wait for a hand-started server (now right
  before exec; docs restart the server with `launchctl kickstart`, never a bare `herdr`).
  Lead resolved by fixing it: `herdr/install.sh` now `brew pin`s herdr on every Mac, so the
  MacBook's nightly upgrade cannot put a newer client against n0's pinned server over
  `herdr --remote n0` (the run's needs_validation lead `herdr-remote-attach-installs-unpinned-binary-on-n0`).
  Security audit run-7 (final-run candidate, 2026-11-08): (low) the gate's stderr still carried
  paths and the account name (shasum on a missing hook, test failures); now `exec 2>/dev/null` in
  the gate, masked test failures, and test 5b reads 2>&1. (low) The gate checked the binary on
  PATH, not the running server: it now compares `herdr status server`'s version with the pin,
  checks /opt/homebrew/bin/herdr (the LaunchAgent's), and fails on a ~/.local/bin/herdr (test 5c).
  (lead, reproduced and fixed) herdr's Claude hook ran `python3 -`, so a json.py at the root of a
  repo where Claude starts inside herdr ran on every SessionStart; herdr/install.sh now patches the
  installed hook to `python3 -I` on every install, and the gate checks it (test 4e).
  (lead, fixed) herdr/install.sh pinned whatever version was installed and hid a failed pin; it now
  compares with herdr/VERSION and exits 1 with the fix on a mismatch or a failed pin (test 4d).
  (lead, fixed where it can be) a bare `herdr` with the server down started its own server from the
  calling shell; on n0 `herdr` is now a zsh function that starts the LaunchAgent first (test 4f).
  Security audit run-8 (2026-11-08, superseded by run-9 after these fixes): (low, confirmed) the
  gate took launchd's `running` as proof the LaunchAgent served herdr, but the wrapper waits
  behind any server already on the socket; it now needs the job's process to be
  `/opt/homebrew/bin/herdr server` and to hold herdr.sock (test 5d).
  (needs_validation, fixed) `herdr --remote` from a Mac whose herdr is not the pin would meet a
  different protocol generation and herdr offers (default yes) to install its own unpinned
  binary on the host; the zsh `herdr` wrapper now refuses `--remote` unless the local herdr is
  herdr/VERSION. (needs_validation, fixed) `herdr integration install` rewrites the Claude hook
  without the `python3 -I` patch until the next `dot`; the patch is now
  herdr/patch-claude-hook.sh, run by install.sh and by the wrapper right after an integration
  install (test 4g).
  (needs_validation, fixed) after a clean `herdr server stop` the LaunchAgent stayed down and
  the next SSH or `--remote` attach started its own server outside the fixed environment and the
  D-012 purge; the job is now always kept alive (D-015, test 5).
  (needs_validation, by design, to be settled by run-9's verifiers) pane code can drive other
  panes through herdr.sock: every pane is the operator's uid, and Claude Code on n0 runs with
  `bypassPermissions` and no sandbox (checked 2026-11-08), so pane code already holds the
  operator's full authority.
  Code review (/code-review max, 2026-11-08) fixes, one commit each:
  - install-launchd.sh reloads an agent only when its rendered plist changed or the job is not
    loaded; every `dot` on n0 used to boot out the herdr server and end every pane (herdr-
    server.log: SIGTERM at both run-7 and run-8 deploys). Test: test/install-launchd.sh
    'unchanged' cases.
  - The herdr server is a session leader (D-017): bin/herdr-server forks it through a
    /usr/bin/perl setsid shim that stays the launchd job, so `herdr --remote n0` no longer offers
    to restart (and end every pane of) n0's server. The gate finds the server as the job's child
    and checks detached_server_daemon. Tests 4a and 5d.
  - install.sh reads the installed version from $(brew --prefix)/opt/herdr/bin/herdr --version,
    not from keg names, so a Homebrew revision (0.9.5_1) or a second keg no longer reads as a
    mismatch (test 4d).
  - herdr/install.sh warns loudly on a version mismatch or failed pin but exits 0: its exit 1
    aborted `dot` (set -e) before the LaunchAgents and later installers, and Homebrew cannot
    downgrade. The n0 gate and the --remote guard enforce the pin (test 4d).
  - test/herdr.sh test 3 runs install.sh with HERDR_BREW and HERDR_CLAUDE_HOOK pointed at nothing,
    so the suite no longer re-pins or patches the host's herdr, needs Homebrew's network API, or
    dies on a herdr that is not the pin.
  - herdr/patch-claude-hook.sh fails loudly (exit 1, temp file removed) when the rewrite fails or
    the hook's python line matches neither form, instead of printing success; install.sh keeps
    going after its warning (test 4e2).
  - New LaunchAgent com.broots.herdr-hook-patch (every Mac): WatchPaths on the Claude hook runs
    herdr/patch-claude-hook.sh whenever herdr rewrites it from the CLI, the TUI or the API; the
    gate checks it is loaded (test 5a).
  - D-016 supersedes D-015: KeepAlive is SuccessfulExit=false again (always-on respawned herdr
    mid-shutdown after its deliberate exit 0), and the zsh wrapper refuses a plain `herdr server
    stop`, pointing at launchctl kickstart -k or bootout (tests 4f, 5).
  - The zsh wrapper never falls through to a shell-started server: a failed kickstart or a server
    not up after 10 s is reported and returns 1, and `--session default`, `--session=default` and
    `session attach default` count as a bare attach (test 4h).
  Residual, documented: `herdr --remote n0` and named sessions still autostart (upstream).
  The gate `just verify-phase-8` (alias `verify-herdr`) is merged (PR #24) and deployed on n0
  2026-11-07: `herdr/install.sh` linked the config (the old one kept as
  `config.toml.pre-dotfiles`), `macos/install-launchd.sh` loaded `com.broots.herdr-server`.
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
- iCloud backup, review r3 (N2): a file listed by the scan but gone by the time tar runs
  (Night Shift writes under ~/dev during the 08:46Z run) no longer discards the encrypted
  archive. bsdtar's exit 1 counts as success when every stderr line is "Cannot stat: No such
  file or directory"; the log line says `N gone since the scan`. Any other tar error, or age
  failing, still ends in status 4 with the previous archive kept. `DEV_BACKUP_TAR` is the test
  hook (test/dev-icloud-backup-edges.sh).
- iCloud backup, 2026-11-07 17:34Z deploy check: the mirror rsync exited 23 on evicted
  package directories (`ClaudeGlance.xcodeproj/...: fstatat: Resource deadlock avoided`), which
  `icloud_fix` did not match (it knew open, mmap, read, unlink, rename). stat, fstatat and lstat
  EDEADLK paths are now removed from the mirror and rsync runs again, like the others
  (test/dev-icloud-backup-edges.sh). The archive and bundles in that run were fine.
  The 17:51Z rerun showed the reported paths are children of an evicted (dataless) mirror
  directory, which under launchd cannot be stat'ed at all; so a reported path that does not
  exist now stands for its nearest evicted ancestor in the mirror, which is removed (left
  alone if that ancestor is not evicted).
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
- dev-pull and the origin remote (review r3, N1, N6): a repo with more than one
  `remote.origin.url` is `unsafe` and skipped (`git push origin` pushes to every url, and only
  the first is checked, so a planted second url got the WIP snapshot). Fetches pass their own
  refspecs with `--refmap=`: the configured `remote.origin.fetch` lines that write only
  remote-tracking refs (refs/heads into refs/remotes/origin, or a tag onto the same name; a
  shallow single-branch clone such as birdnet-go stays narrow), else the default, plus
  `refs/wip/*` for own repos; a planted mapping onto refs/heads is ignored. `drop_identical`
  diffs with `--no-renames`, so an identical untracked copy of a file renamed into place no
  longer blocks the fast-forward. Pinned by test/untrusted-input.sh and test/dev-pull.sh.
- node/install.sh (`sudo npm install spoof -g`, unpinned, as root) deleted (L1).
- dev-sync-from-n0 (review r3, N3): each clone, fetch, merge and rsync writes its own stderr
  file, so one repo blocked by untracked files no longer makes every later diverged repo read
  "untracked files block" (pinned by test/dev-sync-from-n0.sh).
- dev-sync-from-n0's run lock is a symlink `lock.pid -> <pid>` (atomic; pid checked to be a
  sync process); a stale lock is removed only if it still names the stale pid, the exit trap
  removes it only while it names this run, and a live run of the old mkdir-lock version makes
  the new one skip. dev-push-to-n0 exits 4 when an rsync comparison fails (rsync 23/24, a file
  vanished, are reported and not fatal). A local refs cache entry is seeded once from a matching
  iCloud `.refs`, which is then removed.
- Tests: `script/test` runs 16 regression tests (`brew-nightly`, `brew-reconcile`, `brew-sync-push`,
  `brew-wrapper`, `check-state`, `dev-icloud-backup`, `dev-icloud-backup-edges`, `dev-pull`,
  `dev-pull-edges`, `dev-push-to-n0`, `dev-sync-from-n0`, `dev-sync-lock`, `install-launchd`,
  `legacy-installers`, `untrusted-input`, `workflow-pinning`); all pass on n0 2026-11-07 under
  /bin/bash 3.2.
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
- install-launchd.sh (review r3, N4): after `launchctl bootout` it waits (up to 5 s) until
  `launchctl print` no longer finds the job, then tries the bootstrap 3 times; an agent that
  still fails ("Bootstrap failed: 5") is reported, the remaining agents still load, and the
  run exits 1 (before, set -e stopped at the first failure). Pinned by test/install-launchd.sh.
- Legacy installers (review r3, N5): `macos/set-shell.sh` (set UserShell to the missing
  /usr/local/bin/zsh, piped the unpinned oh-my-zsh installer from master into sh) deleted;
  `script/bootstrap` sets the login shell to /bin/zsh with chsh only when it differs, its
  fail() exits 1, and pipefail makes the dependency step's failure reach it.
  test/legacy-installers.sh pins this and allows a downloaded installer piped into a shell
  only in homebrew/install.sh (Homebrew's documented installer, run only when brew is missing).
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

## Verify output (P8, 2026-11-07, n0)

```
$ just verify-phase-8
test/herdr.sh
ok herdr
script/verify-herdr
ok   herdr 0.9.5 (pin herdr/VERSION 0.9.5)
ok   brew pin herdr
ok   integration claude: current (v11) (~/.claude/hooks/herdr-agent-state.sh)
ok   settings.json has 1 herdr SessionStart hook; hook sha256 7a7b3a7150dde3e4
ok   launchd com.broots.herdr-server: running
ok   server running
ok   API socket answers (workspace.list)
ok   ~/.config/herdr mode 700, owner me
ok   herdr.sock: socket 600, owner me
ok   herdr-client.sock: socket 600, owner me
ok   config.toml linked to dotfiles
ok   herdr config check
verify-phase-8 ok
```

## Security grade

Current grade: **A** (security review 2026-11-07 r3; rubric: A = no open Medium or higher and
every open Low documented with a reason; A+ also needs no open finding above Informational).

- r3, fixed and deployed on n0 2026-11-07: N1 (Low) a second `remote.origin.url` received the
  WIP snapshot, and a planted `remote.origin.fetch` could move or prune local branches (PR #18);
  N6 (Low) `drop_identical` missed files renamed into place (PR #18); N2 (Info) one vanished
  file discarded the encrypted archive (PR #19); N3 (Info) dev-sync-from-n0 misreported why a
  fast-forward failed (PR #19); N4 (Low) install-launchd.sh stopped on the bootout/bootstrap
  race (PR #20); N5 (Info) legacy installers set a missing login shell and piped an unpinned
  installer into sh (PR #20). Each has a regression test.
- r3 deploy follow-ups (found by the live check, fixed forward): the mirror rsync exited 23 on
  an evicted package directory in iCloud (`fstatat: Resource deadlock avoided`); PR #21 and
  PR #22 remove the nearest evicted ancestor and retry.
- r3 verified live on n0: dev-pull via `launchctl kickstart` 2026-11-07 17:08Z and the 18:02Z
  scheduled run exit 0, `0 failed, 0 skipped` (no n0 repo has a second origin url; the
  single-branch clones birdnet-go, ComfyUI, SwarmUI and frigate keep their narrow refspecs);
  `macos/install-launchd.sh` run live exit 0 with all three n0 agents loaded;
  dev-icloud-backup via kickstart 18:15Z exit 0 in 883 s (11,665 files archived, the evicted
  `ClaudeGlance.xcodeproj` removed from the mirror and rewritten on the retry).
  dev-sync-from-n0 (N3) runs on the MacBook only; covered by test/dev-sync-from-n0.sh, live on
  its next run there.

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
  tools are not version-pinned. No r3 finding is open.

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
- Accepted (Informational): `homebrew/install.sh` pipes Homebrew's own installer
  (`raw.githubusercontent.com/Homebrew/install/HEAD`) into bash, unpinned. It is Homebrew's
  documented install path and runs only when brew is missing (a fresh Mac, interactively);
  test/legacy-installers.sh allows that one file and fails on any other download piped into a
  shell.
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
