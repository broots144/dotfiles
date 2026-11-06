# Decisions

Append only. A later decision supersedes an earlier one; earlier entries are never rewritten.
Homelab-wide decisions live in the sublevel repo as ADRs and are cited as `sublevel ADR-NNN`.

- D-001 (2026-06-09): The Brewfile is the record of installed Homebrew and Mac App Store software. The interactive `brew` wrapper records installs; `brew-reconcile` on a LaunchAgent catches everything installed out of band. Both commit `brew: ...` straight to `master`.
- D-002 (2026-09-26): Unattended publishing pushes only when its own Brewfile commit is the single unpushed commit, and commits only the Brewfile. Pinned by test/brew-sync-push.sh.
- D-003 (2026-09-27): The off-site copy of ~/dev is a nightly copy into iCloud Drive; secret-shaped and gitignored files and git history go only into age-encrypted archives. Private keys (~/.ssh, ~/.config/sops) are never copied there.
- D-004 (2026-09-28): Repo data is data: prompt and git helpers never execute repo-local git config. Pinned by test/untrusted-input.sh.
- D-005 (2026-10-14): GitHub is the hub for ~/dev on both Macs (sublevel ADR-069, ADR-071). dev-pull only fast-forwards; it never resets. Private files move by rsync with `--update`, from n0 to the laptop on a schedule and back only by hand (`dev-push-to-n0`).
- D-006 (2026-10-28): LaunchAgents are host-gated by a `dotfiles-hosts` marker in the plist, matched against `HostName`.
- D-007 (2026-10-30): The MacBook upgrades Homebrew nightly at 23:45 (sublevel ADR-088); macOS itself stays manual.
- D-008 (2026-11-06): Repo-state pattern adopted. STATE.md is the single source of current truth. A CI guard on pull requests fails when code changes without a STATE.md change, except PRs whose commits are all `chore:`, `deps:` or `brew:`. Direct `brew:` pushes to `master` are not gated.
