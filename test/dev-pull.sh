#!/usr/bin/env bash
# dev-pull fast-forwards a checkout that only has new (untracked) files: a copy identical to
# what origin adds is dropped, one that differs blocks the merge and turns "stuck" after
# DEV_PULL_STUCK_HOURS; edits to tracked files still hold the checkout. The private-file
# manifest leaves out a file that is tracked on an origin branch but not checked out here.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home" ZSH="$here" GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$HOME/dev" "$t/up"
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }

# One upstream per case; each clone sits one commit behind, then upstream adds secrets/x.enc.yaml.
setup() {  # <name>
  git init -q -b main "$t/up/$1"
  printf 'a\n' > "$t/up/$1/README"; git -C "$t/up/$1" add README; git -C "$t/up/$1" commit -qm init
  git clone -q "$t/up/$1" "$HOME/dev/$1"
  mkdir -p "$t/up/$1/secrets"; printf 'enc: one\n' > "$t/up/$1/secrets/x.enc.yaml"
  git -C "$t/up/$1" add secrets; git -C "$t/up/$1" commit -qm secret
}
setup same;  mkdir "$HOME/dev/same/secrets";  printf 'enc: one\n' > "$HOME/dev/same/secrets/x.enc.yaml"
setup diff;  mkdir "$HOME/dev/diff/secrets";  printf 'enc: two\n' > "$HOME/dev/diff/secrets/x.enc.yaml"
setup other; printf 'scratch\n' > "$HOME/dev/other/notes.txt"
setup edits; printf 'b\n' > "$HOME/dev/edits/README"

out=$(DEV_PULL_STUCK_HOURS=0 "$here/bin/dev-pull" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 5 ]
ok grep -q 'dev-pull: 2 ff, 0 current, 2 dirty, 0 diverged, 0 no-origin, 0 failed, 2 stuck' <<<"$out"
ok [ "$(git -C "$HOME/dev/same" status --porcelain)" = "" ]
ok git -C "$HOME/dev/same" diff --quiet HEAD origin/main
ok git -C "$HOME/dev/other" diff --quiet HEAD origin/main
ok [ -f "$HOME/dev/other/notes.txt" ]
ok [ "$(cat "$HOME/dev/diff/secrets/x.enc.yaml")" = "enc: two" ]
ok grep -q 'untracked files differ from origin/main, fetch only: diff (secrets/x.enc.yaml)' <<<"$out"
ok [ "$(git -C "$HOME/dev/edits" rev-list --count HEAD..origin/main)" = 1 ]
ok grep -q 'STUCK 0h behind origin/main: edits' <<<"$out"

# A dry run calls a diverged checkout diverged, not a fast-forward.
git -C "$HOME/dev/edits" stash -q
git -C "$HOME/dev/edits" commit -q --allow-empty -m local
out=$("$here/bin/dev-pull" -n 2>&1)
ok grep -q 'diverged from origin/main, fetch only: edits' <<<"$out"
git -C "$HOME/dev/edits" reset -q --hard HEAD^; git -C "$HOME/dev/edits" stash pop -q

# Under the threshold: reported, not stuck. Clearing the blocker clears the record.
out=$("$here/bin/dev-pull" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]; ok grep -q ', 0 stuck' <<<"$out"
rm "$HOME/dev/diff/secrets/x.enc.yaml"
"$here/bin/dev-pull" >/dev/null 2>&1
ok [ ! -e "$HOME/.local/state/dev-pull/stuck/diff" ]

# Manifest: `edits` holds secrets/x.enc.yaml untracked, but origin/main tracks it; and an
# untracked secret that nothing tracks.
mkdir "$HOME/dev/edits/secrets"; printf 'enc: three\n' > "$HOME/dev/edits/secrets/x.enc.yaml"
printf 'k\n' > "$HOME/dev/edits/secrets.local"
. "$here/lib/dev-tree.sh"
mkdir "$t/w"; dev_tree_lists "$HOME/dev/" "$t/w"
list=$(dev_tree_private_files "$HOME/dev/" "$t/w" | tr '\0' '\n')
ok grep -qx 'edits/secrets.local' <<<"$list"
ok bash -c '! grep -q "x.enc.yaml" <<<"$1"' _ "$list"

(( fail == 0 )) && echo "dev-pull: ok"
exit "$fail"
