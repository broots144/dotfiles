# Lessons

One line per lesson, newest first.

- 2026-11-06: The nightly iCloud backup on n0 died on "Resource deadlock avoided" writing a small `.refs` file into iCloud Drive. The iCloud file provider can refuse a write transiently; any write into iCloud Drive needs to tolerate a retry, and one failed file must not abort the whole run. (Open in STATE.md.)
- 2026-10-28: Bonjour renamed n0's LocalHostName to n0-2 on a name conflict and the host-gated LaunchAgents stopped matching. Rule: host identity is `HostName`, else `LocalHostName`.
- 2026-10-28: dev-icloud-backup broke under launchd because macOS `/bin/bash` is 3.2, where an empty `"${arr[@]}"` under `set -u` is an unbound variable. Rule: launchd scripts target bash 3.2.
- 2026-10-28: dev-pull held a checkout forever when origin added a file that already existed untracked locally. Rule: identical untracked copies are dropped, differing ones block, and a checkout stuck for a day fails the sync loudly.
- 2026-10-14: n0 was behind GitHub on six repos while holding nothing unpushed, because it only mirrored the other machine. Rule: GitHub is the hub for ~/dev on both machines (sublevel ADR-071).
- 2026-09-28: The prompt and git helpers ran inside arbitrary repos and honoured their repo-local filter, fsmonitor and other executable config. Rule: every git call in prompt or helpers isolates repo-local executable config; repo data is data (PR #4 to #7).
- 2026-09-27: The iCloud mirror of ~/dev copied secret files (tfvars, .env, keys) in plaintext into iCloud Drive. Rule: secret-shaped or gitignored files go only into an age-encrypted archive (PR #3). No public exposure; the copies were in the operator's own iCloud.
- 2026-09-26: `./bin` first in PATH let any cloned repo run code through the prompt helpers, and the unattended Brewfile publisher could push unrelated local commits. Rule: no relative PATH entries; unattended pushes only when their own commit is the single unpushed one (PR #1, #2).
