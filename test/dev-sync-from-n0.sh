#!/usr/bin/env bash
# dev-sync-from-n0 end to end against a fake n0 (a directory reached through the ssh stub in
# test/lib/fake-n0.sh; GitHub is unreachable). Repos missing here are cloned (from origin, else
# from n0 with origin added as the GitHub ssh URL); nested and SYNC_SKIP repos are left out; a
# repo with no reachable origin follows n0; private files come over unless newer here; -n
# changes nothing; a checkout stuck behind origin, a failed listing on n0 and a failed
# ssh-config render fail the run; the run writes last.json and tries the heartbeat.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
. "$here/test/lib/fake-n0.sh"; fake_n0_stubs "$t/bin"
# The run pulls $ZSH and runs $ZSH/bin/dev-pull: a stand-in dotfiles dir (not a git repo) that
# points at this checkout, so the test never pulls the real one.
mkdir "$t/dots"; ln -s "$here/bin" "$t/dots/bin"; ln -s "$here/lib" "$t/dots/lib"
mkdir -p "$t/n0" "$t/book"; ln -s "$t/dots" "$t/n0/.dotfiles"
export HOME="$t/book" ZSH="$t/dots" FAKE_N0_HOME="$t/n0" PATH="$t/bin:$PATH"
export SUBLEVEL_DIR="$t/sublevel" KUMA_URL="http://127.0.0.1:9" SOPS_AGE_KEY_FILE="$t/no-such-key"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
# Local-path upstreams (file transport) are refused unless DEV_PULL_ALLOW_FILE=1; a gh stub
# marks every repo private so WIP snapshots are allowed.
mkdir -p "$t/ghbin"; printf '#!/bin/sh\necho true\n' > "$t/ghbin/gh-private"; chmod +x "$t/ghbin/gh-private"
export DEV_PULL_ALLOW_FILE=1 DEV_PULL_GH="$t/ghbin/gh-private"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
n0=$t/n0/dev; bk=$t/book/dev
repo() {  # <dir> [origin]: a repo with one commit on main
  git init -q -b main "$1"; printf 'r\n' > "$1/README"; git -C "$1" add README; git -C "$1" commit -qm init
  [[ -z "${2:-}" ]] || git -C "$1" remote add origin "$2"
}
commit() { printf '%s\n' "$2" >> "$1/README"; git -C "$1" commit -qam "$2"; }
sync() { "$here/bin/dev-sync-from-n0" "$@" 2>&1; }

repo "$n0/gh" https://github.com/example-invalid/gh.git        # GitHub: unreachable here
git init -q --bare -b main "$t/up/hub.git"; repo "$n0/hub" "$t/up/hub.git"; git -C "$n0/hub" push -q origin main
repo "$n0/solo"                                                 # no origin: follows n0
repo "$n0/app"; repo "$n0/app/vendor/lib"                       # nested checkout
repo "$n0/nightshift"                                           # n0 only (SYNC_SKIP)
printf 'TOKEN=n0\n' > "$n0/gh/.env"; printf 'K=n0\n' > "$n0/solo/secrets.yaml"
printf 'K=n0\n' > "$n0/nightshift/.env"
touch -t 202001010000 "$n0/gh/.env"

# --repos and --manifest (the modes n0 answers): skipped repo left out of both.
list=$(FAKE_HOST=n0 HOME="$t/n0" ZSH='' "$here/bin/dev-sync-from-n0" --repos | tr '\0' '\n')
ok grep -qx 'gh' <<<"$list"; ok grep -qx 'https://github.com/example-invalid/gh.git' <<<"$list"
ok grep -qx 'app/vendor/lib' <<<"$list"; ok bash -c '! grep -q nightshift <<<"$1"' _ "$list"
man=$(HOME="$t/n0" ZSH='' "$here/bin/dev-sync-from-n0" --manifest | tr '\0' '\n')
ok grep -qx 'gh/.env' <<<"$man"; ok grep -qx 'solo/secrets.yaml' <<<"$man"
ok bash -c '! grep -q "nightshift\|README" <<<"$1"' _ "$man"

# Wrong host.
FAKE_HOST=n0 "$here/bin/dev-sync-from-n0" >/dev/null 2>&1 && rc=0 || rc=$?; ok [ "$rc" = 2 ]

# -n on an empty laptop: reports the clones, makes none, writes no last.json.
out=$(sync -n) && rc=0 || rc=$?
ok [ "$rc" = 0 ]
ok grep -q 'would clone gh' <<<"$out"; ok grep -q 'would clone hub' <<<"$out"
ok bash -c '! grep -q "would clone app/vendor/lib\|nightshift" <<<"$1"' _ "$out"
ok [ ! -e "$bk/gh" ]; ok [ ! -e "$HOME/.local/state/dev-sync-from-n0/last.json" ]

# First run: everything cloned, private files copied, the heartbeat tried (it fails: no sops
# secret here) and reported, not fatal.
out=$(sync) && rc=0 || rc=$?
ok [ "$rc" = 0 ]
ok grep -q 'cloned gh from n0' <<<"$out"; ok grep -q 'cloned hub from origin' <<<"$out"
ok grep -q 'cloned solo from n0' <<<"$out"; ok grep -q 'cloned app from n0' <<<"$out"
ok [ "$(git -C "$bk/gh" remote get-url origin)" = 'git@github.com:example-invalid/gh.git' ]
ok [ "$(git -C "$bk/gh" config remote.pushDefault)" = origin ]
ok [ "$(git -C "$bk/gh" config branch.main.remote)" = origin ]
ok [ "$(git -C "$bk/hub" remote get-url n0)" = 'n0:dev/hub' ]
ok bash -c '! git -C "$1" remote get-url origin >/dev/null 2>&1' _ "$bk/solo"
ok [ ! -e "$bk/app/vendor/lib/.git" ]; ok [ ! -e "$bk/nightshift" ]
ok [ "$(cat "$bk/gh/.env")" = TOKEN=n0 ]; ok [ "$(cat "$bk/solo/secrets.yaml")" = K=n0 ]
ok grep -q 'heartbeat to Kuma via n0 failed' <<<"$out"
ok grep -q '"exit":0,"status":"up"' "$HOME/.local/state/dev-sync-from-n0/last.json"

# n0 moves on: solo (no origin) and gh (origin unreachable) fast-forward from n0; a newer n0
# private file comes over; one newer here is kept and reported, never overwritten.
commit "$n0/solo" two; commit "$n0/gh" two
printf 'K=n0-two\n' > "$n0/solo/secrets.yaml"
printf 'TOKEN=edited-on-book\n' > "$bk/gh/.env"
out=$(sync) && rc=0 || rc=$?
ok [ "$rc" = 0 ]
ok grep -q 'fast-forwarded solo from n0 (1 commits)' <<<"$out"
ok grep -q 'fast-forwarded gh from n0 (1 commits)' <<<"$out"
ok git -C "$bk/solo" diff --quiet HEAD n0/main
ok [ "$(cat "$bk/solo/secrets.yaml")" = K=n0-two ]
ok [ "$(cat "$bk/gh/.env")" = TOKEN=edited-on-book ]; ok [ "$(cat "$n0/gh/.env")" = TOKEN=n0 ]
ok grep -q 'newer here than on n0, kept: gh/.env' <<<"$out"
ok grep -q '1 file(s) newer here: run dev-push-to-n0' <<<"$out"

# Diverged from n0: fetched, reported, nothing reset.
commit "$n0/solo" three; commit "$bk/solo" mine
out=$(sync) || true
ok grep -q 'diverged from n0/main, fetch only: solo' <<<"$out"
ok [ "$(git -C "$bk/solo" log -1 --format=%s)" = mine ]
git -C "$bk/solo" reset -q --hard n0/main

# A checkout behind origin that cannot fast-forward (edits) is stuck at once with
# DEV_PULL_STUCK_HOURS=0: the run fails (exit 3) and last.json says down.
git clone -q "$t/up/hub.git" "$t/hub2"; commit "$t/hub2" upstream; git -C "$t/hub2" push -q origin main
printf 'local edit\n' >> "$bk/hub/README"
out=$(DEV_PULL_STUCK_HOURS=0 sync) && rc=0 || rc=$?
ok [ "$rc" = 3 ]; ok grep -q '1 stuck' <<<"$out"
ok grep -q '"exit":3,"status":"down"' "$HOME/.local/state/dev-sync-from-n0/last.json"
git -C "$bk/hub" checkout -q -- README

# n0 cannot list its repos (its dotfiles are gone): exit 3.
rm "$t/n0/.dotfiles"
out=$(sync) && rc=0 || rc=$?
ok [ "$rc" = 3 ]; ok grep -q 'could not list repos on n0' <<<"$out"
ln -s "$t/dots" "$t/n0/.dotfiles"

# sublevel access files: ssh-config re-rendered when missing; a failing render fails the run;
# the kubeconfig is fetched once (a stand-in `just turingpi`).
if command -v just >/dev/null; then
  mkdir -p "$SUBLEVEL_DIR/.git" "$SUBLEVEL_DIR/scripts" "$SUBLEVEL_DIR/ansible"
  printf '#!/bin/sh\necho "wrote ~/.ssh/sublevel.conf"\n' > "$SUBLEVEL_DIR/scripts/ssh-config.sh"; chmod +x "$SUBLEVEL_DIR/scripts/ssh-config.sh"
  printf 'turingpi *args:\n    mkdir -p "$HOME/.kube" && echo kc > "$HOME/.kube/turingpi.yaml"\n' > "$SUBLEVEL_DIR/justfile"
  out=$(sync) && rc=0 || rc=$?
  ok [ "$rc" = 0 ]; ok grep -q 'ssh-config: wrote' <<<"$out"; ok grep -q 'kubeconfig: wrote' <<<"$out"
  ok [ -s "$HOME/.kube/turingpi.yaml" ]
  printf '#!/bin/sh\necho "inventory broken" >&2; exit 1\n' > "$SUBLEVEL_DIR/scripts/ssh-config.sh"
  out=$(sync) && rc=0 || rc=$?
  ok [ "$rc" = 3 ]; ok grep -q 'ssh-config failed: inventory broken' <<<"$out"
fi

(( fail == 0 )) && echo "ok dev-sync-from-n0"
exit "$fail"
