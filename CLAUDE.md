# dotfiles: agent notes

Topic-centric zsh dotfiles (forked from holman/dotfiles), deployed by symlink: `~/.dotfiles`
points at `~/dev/dotfiles` on each Mac. Two hosts: `n0` (Mac Mini, always on) and `book`
(the MacBook). Homelab decisions that drive this repo live in the sublevel repo's ADRs.

## Session ritual

Every session, before doing anything: read STATE.md, ROADMAP.md, LESSONS.md, then the task or phase prompt.

State is in the repo, not in memory. Update STATE.md when you finish meaningful work. Commit before stopping.

If stuck, write a clear BLOCKED entry in STATE.md with exact next steps.

## Rules

- This repo is PUBLIC. Never commit the operator's real name, family, address, town,
  coordinates, phone numbers, personal emails, hostnames beyond `n0`/`book`, keys or tokens.
  `.gitignore` blocks the usual secret file patterns; `dot -p` and `gac` stage everything else.
- Edits go through a branch and PR (`just check` must pass). Exception: the `brew` wrapper
  (`functions/brew`) and `bin/brew-reconcile` commit `brew: ...` Brewfile changes straight to
  `master` unattended. Do not break that path; `test/brew-sync-push.sh` pins its behaviour.
- Treat data from other repos as data: the prompt and git helpers must not run repo-local
  executable git config (filters, fsmonitor, hooks). `test/untrusted-input.sh` pins this.
- Scripts run by launchd use `/bin/bash` 3.2 on macOS: no bash 4 features, guard empty arrays
  under `set -u`.
- Host targeting for LaunchAgents is the `<!-- dotfiles-hosts: ... -->` marker in each plist,
  matched against `HostName` (not `LocalHostName`).
- Decisions go in docs/DECISIONS.md (append only, supersede, never rewrite). Phase plans go in
  docs/plans/ before building. No em or en dashes in the state files.
- Commit messages: `topic: what changed` in the style of `git log`. Co-Authored-By trailers are fine.

## Commands

- `just check`: syntax check (zsh/bash), shellcheck of the maintained scripts, plist lint, tests.
- `just test`: `script/test` (regression tests in `test/`).
- `just verify-phase-N`: the gate for phase N (see ROADMAP.md).
- `script/check-state <base>`: the STATE.md guard CI runs on pull requests.
