#!/usr/bin/env bash
# dev-sync-from-n0 runs one at a time: a live run's lock is respected; a lock left by a dead
# process, or by a reused pid that is not a sync, is taken over; the lock goes when the run
# ends. scutil and ssh are stubbed: this host is "book" and n0 is unreachable, so a run that
# gets the lock stops right after it ("n0 unreachable; skipped").
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'kill "${live:-}" 2>/dev/null || true; rm -rf "$t"' EXIT
export HOME="$t/home" ZSH="$here"
mkdir -p "$t/bin" "$HOME/.local/state/dev-sync-from-n0"
printf '#!/bin/sh\necho book\n' > "$t/bin/scutil"
printf '#!/bin/sh\nexit 255\n' > "$t/bin/ssh"
chmod +x "$t/bin/scutil" "$t/bin/ssh"
export PATH="$t/bin:$PATH"
lock="$HOME/.local/state/dev-sync-from-n0/lock.pid"
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }

# A live sync holds the lock: skipped, lock untouched.
bash -c 'exec -a dev-sync-from-n0 sleep 30' & live=$!
sleep 0.2
ln -s "$live" "$lock"
out=$("$here/bin/dev-sync-from-n0" 2>&1)
ok grep -q "another run (pid $live) is active; skipped" <<<"$out"
ok [ "$(readlink "$lock")" = "$live" ]
kill "$live"; wait "$live" 2>/dev/null || true

# The same pid, now dead: taken over, and released at the end.
out=$("$here/bin/dev-sync-from-n0" 2>&1)
ok grep -q 'n0 unreachable; skipped' <<<"$out"
ok [ ! -L "$lock" ]

# A live pid that is not a sync (reused): taken over.
ln -s "$$" "$lock"
out=$("$here/bin/dev-sync-from-n0" 2>&1)
ok grep -q 'n0 unreachable; skipped' <<<"$out"
ok [ ! -L "$lock" ]

# A run of the previous version (mkdir lock + pid file) still going: skipped, and neither
# lock is left behind by this run; a dead one's mkdir lock is cleaned up.
bash -c 'exec -a dev-sync-from-n0 sleep 30' & live=$!
sleep 0.2
mkdir "$HOME/.local/state/dev-sync-from-n0/lock"; echo "$live" > "$HOME/.local/state/dev-sync-from-n0/lock/pid"
out=$("$here/bin/dev-sync-from-n0" 2>&1)
ok grep -q "previous version (pid $live) is active; skipped" <<<"$out"
ok [ -d "$HOME/.local/state/dev-sync-from-n0/lock" ]
ok [ ! -L "$lock" ]
kill "$live"; wait "$live" 2>/dev/null || true
out=$("$here/bin/dev-sync-from-n0" 2>&1)
ok grep -q 'n0 unreachable; skipped' <<<"$out"
ok [ ! -e "$HOME/.local/state/dev-sync-from-n0/lock" ]

# The exit trap removes the lock only while it is this run's: a run that loses the lock to
# another one (simulated by an ssh stub that swaps the link) leaves the other's lock alone.
printf '#!/bin/sh
ln -sfn 99999 "%s"
exit 255
' "$lock" > "$t/bin/ssh"
out=$("$here/bin/dev-sync-from-n0" 2>&1)
ok grep -q 'n0 unreachable; skipped' <<<"$out"
ok [ "$(readlink "$lock" 2>/dev/null)" = 99999 ]
rm -f "$lock"

(( fail == 0 )) && echo "ok dev-sync-lock"
exit "$fail"
