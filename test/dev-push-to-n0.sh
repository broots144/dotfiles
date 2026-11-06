#!/usr/bin/env bash
# dev-push-to-n0 carries private files (what git does not hold) from the laptop to n0 with
# rsync --update: -n lists, never moves; a file newer on n0 is listed and left alone; tracked
# files and SYNC_SKIP repos never move; wrong host exits 2, unreachable n0 1, a failed rsync 4.
# n0 is a directory here (test/lib/fake-n0.sh stubs ssh and scutil).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
. "$here/test/lib/fake-n0.sh"; fake_n0_stubs "$t/bin"
export HOME="$t/book" ZSH="$here" FAKE_N0_HOME="$t/n0" PATH="$t/bin:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
old() { touch -t 202001010000 "$@"; }

# The same repo on both machines; private files differ.
for h in book n0; do
  mkdir -p "$t/$h/dev/app" "$t/$h/dev/nightshift"
  git init -q "$t/$h/dev/app"; git init -q "$t/$h/dev/nightshift"
  printf 'readme\n' > "$t/$h/dev/app/README"; git -C "$t/$h/dev/app" add README; git -C "$t/$h/dev/app" commit -qm init
  printf 'TOKEN=old\n' > "$t/$h/dev/app/.env"; printf 'v = "n0"\n' > "$t/$h/dev/app/prod.tfvars"
  old "$t/$h/dev/app/.env" "$t/$h/dev/app/prod.tfvars"
done
printf 'TOKEN=new-on-book\n' > "$t/book/dev/app/.env"                 # newer here
printf '{"serial":2}\n' > "$t/book/dev/app/main.tfstate"              # only here
printf 'v = "book"\n' > "$t/book/dev/app/prod.tfvars"; old "$t/book/dev/app/prod.tfvars"
printf 'v = "n0, newer"\n' > "$t/n0/dev/app/prod.tfvars"              # newer on n0
printf 'edited on book\n' > "$t/book/dev/app/README"                  # tracked: git's job
printf 'K=1\n' > "$t/book/dev/nightshift/.env"                        # n0-only repo

# -n: lists both directions and the state-file note, moves nothing.
out=$("$here/bin/dev-push-to-n0" -n 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]
ok grep -q '^newer here, would move to n0:' <<<"$out"
ok grep -qx '  app/.env' <<<"$out"
ok grep -qx '  app/main.tfstate' <<<"$out"
ok grep -q '^newer on n0, left alone' <<<"$out"
ok grep -qx '  app/prod.tfvars' <<<"$out"
ok grep -q 'NOTE: an OpenTofu state is among them' <<<"$out"
ok bash -c '! grep -q "nightshift\|README" <<<"$1"' _ "$out"
ok [ "$(cat "$t/n0/dev/app/.env")" = "TOKEN=old" ]
ok [ ! -e "$t/n0/dev/app/main.tfstate" ]

# The real run: newer-here files move, n0's newer file stays, tracked and skipped files stay.
out=$("$here/bin/dev-push-to-n0" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]
ok grep -q '^newer here, moving to n0:' <<<"$out"
ok grep -q '^moved 2 file(s) to n0$' <<<"$out"
ok [ "$(cat "$t/n0/dev/app/.env")" = "TOKEN=new-on-book" ]
ok [ "$(cat "$t/n0/dev/app/main.tfstate")" = '{"serial":2}' ]
ok [ "$(cat "$t/n0/dev/app/prod.tfvars")" = 'v = "n0, newer"' ]
ok [ "$(cat "$t/n0/dev/app/README")" = readme ]
ok [ ! -e "$t/n0/dev/nightshift/.env" ]

# Nothing newer here any more: reported, nothing moved, exit 0.
out=$("$here/bin/dev-push-to-n0" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]; ok grep -qx 'nothing newer here' <<<"$out"; ok bash -c '! grep -q "^moved" <<<"$1"' _ "$out"

# Wrong host, unreachable n0, failed rsync.
FAKE_HOST=n0 "$here/bin/dev-push-to-n0" >/dev/null 2>&1 && rc=0 || rc=$?; ok [ "$rc" = 2 ]
FAKE_N0_DOWN=1 "$here/bin/dev-push-to-n0" >/dev/null 2>&1 && rc=0 || rc=$?; ok [ "$rc" = 1 ]
printf 'TOKEN=newer-again\n' > "$t/book/dev/app/.env"
out=$(FAKE_N0_RSYNC_FAIL=1 "$here/bin/dev-push-to-n0" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 4 ]; ok grep -q 'rsync failed' <<<"$out"
ok [ "$(cat "$t/n0/dev/app/.env")" = "TOKEN=new-on-book" ]

(( fail == 0 )) && echo "ok dev-push-to-n0"
exit "$fail"
