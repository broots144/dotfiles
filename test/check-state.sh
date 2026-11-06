#!/usr/bin/env bash
# script/check-state (the STATE.md guard CI runs on pull requests): its own self-test (code
# without STATE.md fails; STATE.md, docs-only and chore:/deps:/brew: ranges pass, merge commits
# skipped), plus the edges the self-test does not reach: an empty range, a missing argument.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }

out=$("$here/script/check-state" --self-test 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]; ok grep -qx 'ok check-state' <<<"$out"

"$here/script/check-state" >/dev/null 2>&1 && rc=0 || rc=$?; ok [ "$rc" = 2 ]

git init -q "$t/r"; echo a > "$t/r/x.sh"; git -C "$t/r" add .; git -C "$t/r" commit -qm init
out=$(cd "$t/r" && "$here/script/check-state" HEAD 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]; ok grep -qx 'state-guard: no changes' <<<"$out"
echo b >> "$t/r/x.sh"; git -C "$t/r" commit -qam "fix: y"
out=$(cd "$t/r" && "$here/script/check-state" HEAD~1 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 1 ]; ok grep -q 'code changed without a STATE.md update (commit: fix: y)' <<<"$out"

(( fail == 0 )) && echo "ok check-state"
exit "$fail"
