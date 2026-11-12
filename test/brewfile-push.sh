#!/usr/bin/env bash
# script/brewfile-push publishes unattended Brewfile commits from both Macs (D-022): several
# unpushed Brewfile commits go out together; a commit that is not `brew: ...` or touches another
# file keeps everything local (exit 3); when the other Mac pushed first, the commits are
# rebased and pushed, and the union merge of .gitattributes keeps both Macs' lines (and a
# line dropped elsewhere in the file stays dropped; one dropped right where the other Mac added
# can come back, which is why the wrapper pulls before it edits); with tracked edits in the checkout the rebase waits (exit 1).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git init -q --bare -b master "$t/up.git"; git clone -q "$t/up.git" "$t/a" 2>/dev/null
bf() { printf '%s\n' '# CLI tools' "$@" 'brew "git"' '' '# Casks' 'cask "x"' > Brewfile; }
cd "$t/a"; git checkout -q -b master; bf 'brew "old"'; cp "$here/.gitattributes" .
git add -A; git commit -qm init; git push -q -u origin master 2>/dev/null
git clone -q "$t/up.git" "$t/b" 2>/dev/null
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
push() { out=$("$here/script/brewfile-push" "$1" 2>&1) && rc=0 || rc=$?; }
up() { git -C "$t/up.git" "$@"; }
ok grep -qx 'Brewfile merge=union' "$here/.gitattributes"

# Nothing unpushed: fine. Two Brewfile commits (an install made offline, then another): both go.
push "$t/a"; ok [ "$rc" = 0 ]
bf 'brew "a1"' 'brew "old"'; git commit -qam 'brew: add a1'
bf 'brew "a2"' 'brew "a1"' 'brew "old"'; git commit -qam 'brew: add a2'
push "$t/a"; ok [ "$rc" = 0 ]; ok [ "$(up log -1 --format=%s master)" = 'brew: add a2' ]

# Not a Brewfile commit, a brew: commit touching another file, a brew: commit under a wip one.
echo wip > notes; git add notes; git commit -qm 'local wip'
push "$t/a"; ok [ "$rc" = 3 ]; ok grep -q 'not pushing (1 commit(s) ahead of upstream)' <<<"$out"
bf 'brew "a3"' 'brew "a2"' 'brew "a1"' 'brew "old"'; git commit -qam 'brew: add a3'
push "$t/a"; ok [ "$rc" = 3 ]; ok [ "$(up log -1 --format=%s master)" = 'brew: add a2' ]
git reset -q --hard origin/master
echo x > other; bf 'brew "a3"' 'brew "a2"' 'brew "a1"' 'brew "old"'; git add -A; git commit -qm 'brew: add a3 and more'
push "$t/a"; ok [ "$rc" = 3 ]
git reset -q --hard origin/master

# b is behind and adds a line under the same header, and drops one: rebased, pushed, both kept.
cd "$t/b"; printf '%s\n' '# CLI tools' 'brew "b1"' 'brew "old"' 'brew "git"' '' '# Casks' > Brewfile
git commit -qam 'brew: add b1, drop x'
push "$t/b"; ok [ "$rc" = 0 ]
ok [ "$(up log -1 --format=%s master)" = 'brew: add b1, drop x' ]; ok [ "$(up rev-list --count master)" = 4 ]
for l in a1 a2 b1 git; do ok grep -qx "brew \"$l\"" <(up show master:Brewfile); done
ok bash -c '! grep -q "cask" "$1"' _ <(up show master:Brewfile)
ok [ "$(up show master:Brewfile | grep -c '^# ')" = 2 ]

# a is behind now and has a tracked edit: the rebase waits, nothing is lost, the next call lands.
cd "$t/a"; bf 'brew "a4"' 'brew "a2"' 'brew "a1"' 'brew "old"'; git commit -qam 'brew: add a4'
echo edit >> .gitattributes
push "$t/a"; ok [ "$rc" = 1 ]; ok grep -q 'rebase did not run' <<<"$out"
ok [ "$(git log -1 --format=%s)" = 'brew: add a4' ]; ok grep -qx edit .gitattributes
git checkout -q .gitattributes
push "$t/a"; ok [ "$rc" = 0 ]
for l in a1 a2 a4 b1; do ok grep -qx "brew \"$l\"" <(up show master:Brewfile); done

(( fail == 0 )) && echo "ok brewfile-push"
exit "$fail"
