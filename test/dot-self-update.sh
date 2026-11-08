#!/usr/bin/env bash
# script/self-update (D-021): `dot` fast-forwards a clean master checkout that is behind origin
# and reports it (exit 10); every other case leaves HEAD alone and exits 0 so `dot` goes on.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home" GIT_CONFIG_GLOBAL=/dev/null DOT_UPDATE_ALLOW_FILE=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DOT_NO_PULL
mkdir -p "$HOME"
su="$here/script/self-update"
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
run() { rc=0; out="$("$su" "$1" 2>&1)" || rc=$?; }
head_of() { git -C "$1" rev-parse HEAD; }

# A clone one commit behind its upstream.
setup() {  # <name>
  git init -q -b master "$t/up-$1"
  printf 'a\n' > "$t/up-$1/f"; git -C "$t/up-$1" add f; git -C "$t/up-$1" commit -qm one
  git clone -q "$t/up-$1" "$t/$1"
  printf 'b\n' > "$t/up-$1/f"; git -C "$t/up-$1" commit -qam two
}

# 1. Behind and clean: fast-forwarded, exit 10, says so.
setup behind; run "$t/behind"
ok [ "$rc" = 10 ]; ok [ "$(head_of "$t/behind")" = "$(head_of "$t/up-behind")" ]
ok grep -q 'dotfiles updated' <<<"$out"
# 2. Up to date: exit 0, quiet.
run "$t/behind"; ok [ "$rc" = 0 ]; ok [ -z "$out" ]

# 3. Tracked edits: untouched.
setup edits; printf 'mine\n' > "$t/edits/f"; before="$(head_of "$t/edits")"; run "$t/edits"
ok [ "$rc" = 0 ]; ok [ "$(head_of "$t/edits")" = "$before" ]; ok grep -q 'uncommitted edits' <<<"$out"
ok grep -qx mine "$t/edits/f"

# 4. Local commits origin lacks: untouched.
setup diverged; printf 'x\n' > "$t/diverged/g"; git -C "$t/diverged" add g; git -C "$t/diverged" commit -qm local
before="$(head_of "$t/diverged")"; run "$t/diverged"
ok [ "$rc" = 0 ]; ok [ "$(head_of "$t/diverged")" = "$before" ]; ok grep -q 'commits origin/master lacks' <<<"$out"

# 5. Off master: untouched.
setup branch; git -C "$t/branch" switch -q -c work; before="$(head_of "$t/branch")"; run "$t/branch"
ok [ "$rc" = 0 ]; ok [ "$(head_of "$t/branch")" = "$before" ]; ok grep -q "on 'work'" <<<"$out"

# 6. Origin unreachable: untouched, dot goes on.
setup offline; rm -rf "$t/up-offline"; before="$(head_of "$t/offline")"; run "$t/offline"
ok [ "$rc" = 0 ]; ok [ "$(head_of "$t/offline")" = "$before" ]; ok grep -q 'could not reach origin' <<<"$out"

# 7. DOT_NO_PULL=1: no fetch at all.
setup optout; before="$(head_of "$t/optout")"
rc=0; DOT_NO_PULL=1 "$su" "$t/optout" || rc=$?
ok [ "$rc" = 0 ]; ok [ "$(head_of "$t/optout")" = "$before" ]

# 8. Repo hooks never run, and the file transport stays refused without the test opt-in.
setup hooks; printf '#!/bin/sh\ntouch "%s/ran"\n' "$t" > "$t/hooks/.git/hooks/post-merge"
chmod +x "$t/hooks/.git/hooks/post-merge"; run "$t/hooks"
ok [ "$rc" = 10 ]; ok [ ! -e "$t/ran" ]
setup nofile; before="$(head_of "$t/nofile")"
rc=0; DOT_UPDATE_ALLOW_FILE='' "$su" "$t/nofile" 2>/dev/null || rc=$?
ok [ "$rc" = 0 ]; ok [ "$(head_of "$t/nofile")" = "$before" ]

# 9. bin/dot calls it before installing anything and re-runs itself once on a move.
ok grep -q 'script/self-update' "$here/bin/dot"
ok grep -q 'DOT_SELF_UPDATED=1 exec' "$here/bin/dot"
[ "$(grep -n 'script/self-update' "$here/bin/dot" | head -1 | cut -d: -f1)" -lt "$(grep -n 'set-defaults.sh$' "$here/bin/dot" | cut -d: -f1)" ] || { echo "FAIL: self-update runs after set-defaults"; fail=1; }

[ "$fail" = 0 ] && echo "dot-self-update ok"
exit "$fail"
