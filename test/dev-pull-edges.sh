#!/usr/bin/env bash
# dev-pull outcomes the main test (test/dev-pull.sh) does not reach: a repo with no origin is
# reported and left alone; an unreachable origin is "failed" and exits 3; a branch missing on
# origin and a diverged checkout are fetched only, never reset; usage error exits 64; a WIP
# snapshot that gitleaks flags or that origin refuses is withheld, not recorded as pushed.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home" ZSH="$here" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
# Local-path upstreams (file transport) are refused unless DEV_PULL_ALLOW_FILE=1; a gh stub
# marks every repo private so WIP snapshots are allowed.
mkdir -p "$t/ghbin"; printf '#!/bin/sh\necho true\n' > "$t/ghbin/gh-private"; chmod +x "$t/ghbin/gh-private"
export DEV_PULL_ALLOW_FILE=1 DEV_PULL_GH="$t/ghbin/gh-private"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$HOME/dev" "$t/up" "$t/bin"
printf '#!/bin/sh\necho testhost\n' > "$t/bin/scutil"; chmod +x "$t/bin/scutil"; export PATH="$t/bin:$PATH"
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
clone() {  # <name>: upstream with one commit, a clone of it
  git init -q -b main "$t/up/$1"; printf 'a\n' > "$t/up/$1/README"; git -C "$t/up/$1" add README; git -C "$t/up/$1" commit -qm init
  git clone -q "$t/up/$1" "$HOME/dev/$1"
}

git init -q -b main "$HOME/dev/local"                                        # no origin
clone gone; git -C "$HOME/dev/gone" remote set-url origin "$t/up/missing"    # unreachable
clone feat; git -C "$HOME/dev/feat" checkout -q -b topic                     # branch not on origin
clone div; git -C "$HOME/dev/div" commit -q --allow-empty -m mine            # diverged
git -C "$t/up/div" commit -q --allow-empty -m theirs
clone cur                                                                    # current

out=$("$here/bin/dev-pull" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 3 ]
ok grep -q 'dev-pull: 0 ff, 1 current, 1 dirty, 1 diverged, 1 no-origin, 1 failed, 0 stuck' <<<"$out"
ok grep -q '  fetch failed: gone' <<<"$out"
ok grep -q '  branch topic not on origin, fetch only: feat' <<<"$out"
ok grep -q '  diverged from origin/main, fetch only: div' <<<"$out"
ok [ "$(git -C "$HOME/dev/div" log -1 --format=%s)" = mine ]
res="$HOME/.local/state/dev-pull/results"
for l in $'local\tno-origin' $'gone\tfailed' $'feat\tno-branch' $'div\tdiverged' $'cur\tcurrent'; do ok grep -qxF "$l" "$res"; done
ok grep -q '"exit":3' "$HOME/.local/state/dev-pull/last.json"

"$here/bin/dev-pull" -x >/dev/null 2>&1 && rc=0 || rc=$?; ok [ "$rc" = 64 ]

# WIP snapshots of an own repo: a gitleaks finding withholds it; a push origin refuses is
# reported; neither leaves a local record claiming a pushed snapshot.
rm -rf "$HOME/dev/gone" "$HOME/dev/div" "$HOME/dev/feat" "$HOME/dev/local"
clone wip; printf 'b\n' >> "$HOME/dev/wip/README"
printf '#!/bin/sh\necho "finding" >&2; exit 1\n' > "$t/leaks"; chmod +x "$t/leaks"
printf '#!/bin/sh\nexit 0\n' > "$t/clean"; chmod +x "$t/clean"
rec="$HOME/.local/state/dev-pull/wip/wip"
out=$(DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/leaks" "$here/bin/dev-pull" 2>&1) || true
ok grep -q 'snapshot withheld, gitleaks finding: wip' <<<"$out"
ok [ -z "$(git -C "$t/up/wip" for-each-ref 'refs/wip/*')" ]; ok [ ! -e "$rec" ]
printf '#!/bin/sh\nexit 1\n' > "$t/up/wip/.git/hooks/pre-receive"; chmod +x "$t/up/wip/.git/hooks/pre-receive"
out=$(DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/clean" "$here/bin/dev-pull" 2>&1) || true
ok grep -q 'snapshot push failed: wip' <<<"$out"; ok [ ! -e "$rec" ]
rm "$t/up/wip/.git/hooks/pre-receive"
out=$(DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/clean" "$here/bin/dev-pull" 2>&1) || true
ok grep -q 'snapshot pushed to refs/wip/testhost: wip (1 modified, 0 new)' <<<"$out"; ok [ -s "$rec" ]
out=$(DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/clean" "$here/bin/dev-pull" 2>&1) || true
ok grep -q 'snapshot unchanged: wip' <<<"$out"
# Dirty only by a secret-named file: no snapshot, and the old one is cleared.
git -C "$HOME/dev/wip" checkout -q -- README; printf 'S=1\n' > "$HOME/dev/wip/.env"
out=$(DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/clean" "$here/bin/dev-pull" 2>&1) || true
ok grep -q 'dirty only by excluded files, no snapshot: wip' <<<"$out"
ok [ ! -e "$rec" ]; ok [ -z "$(git -C "$t/up/wip" for-each-ref 'refs/wip/*')" ]

# Snapshots go to private repos only: a public repo, or one whose visibility gh cannot tell,
# gets none, and a snapshot pushed while it was private is deleted. The answer is cached for
# the day (gh asked once).
printf '#!/bin/sh\necho "$*" >> %s/gh.calls; echo false\n' "$t" > "$t/gh-public"; chmod +x "$t/gh-public"
printf '#!/bin/sh\nexit 1\n' > "$t/gh-down"; chmod +x "$t/gh-down"
wp() { DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/clean" "$here/bin/dev-pull" 2>&1 || true; }
rm -f "$HOME/dev/wip/.env"; printf 'c\n' >> "$HOME/dev/wip/README"
out=$(wp); ok grep -q 'snapshot pushed to refs/wip/testhost: wip' <<<"$out"; ok [ -s "$rec" ]
rm -rf "$HOME/.local/state/dev-pull/visibility"
out=$(DEV_PULL_GH="$t/gh-down" wp)
ok grep -q 'no snapshot, repo public or visibility unknown: wip' <<<"$out"
ok [ ! -e "$rec" ]; ok [ -z "$(git -C "$t/up/wip" for-each-ref 'refs/wip/*')" ]
printf 'd\n' >> "$HOME/dev/wip/README"
out=$(DEV_PULL_GH="$t/gh-public" wp); DEV_PULL_GH="$t/gh-public" wp >/dev/null
ok grep -q 'no snapshot, repo public or visibility unknown: wip' <<<"$out"
ok [ -z "$(git -C "$t/up/wip" for-each-ref 'refs/wip/*')" ]
ok [ "$(cat "$t/gh.calls")" = "api repos/up/wip --jq .private" ]
rm -rf "$HOME/.local/state/dev-pull/visibility"
# Made public today, after the cache said private (review r2, N2): the push asks gh again
# without the cache, so no new snapshot goes up and the old one is deleted.
out=$(wp); ok grep -q 'snapshot pushed to refs/wip/testhost: wip' <<<"$out"; ok [ -s "$rec" ]
ok grep -q ' true$' "$HOME/.local/state/dev-pull/visibility/up__wip"
printf 'd2\n' >> "$HOME/dev/wip/README"
out=$(DEV_PULL_GH="$t/gh-public" wp)
ok grep -q 'no snapshot, repo public or visibility unknown: wip' <<<"$out"
ok [ ! -e "$rec" ]; ok [ -z "$(git -C "$t/up/wip" for-each-ref 'refs/wip/*')" ]
ok grep -q ' false$' "$HOME/.local/state/dev-pull/visibility/up__wip"
rm -rf "$HOME/.local/state/dev-pull/visibility"

# gitleaks gets this repo's config, an empty ignore dir and --ignore-gitleaks-allow, so the
# dirty tree it scans cannot switch its rules off.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %s/leaks.args\n' "$t" > "$t/rec-leaks"; chmod +x "$t/rec-leaks"
printf 'e\n' >> "$HOME/dev/wip/README"
DEV_PULL_OWN_RE='/up/wip$' DEV_PULL_GITLEAKS="$t/rec-leaks" "$here/bin/dev-pull" >/dev/null 2>&1 || true
ok grep -qxF -- "$here/lib/gitleaks.toml" "$t/leaks.args"; ok grep -qx -- --ignore-gitleaks-allow "$t/leaks.args"
ok grep -qx -- --gitleaks-ignore-path "$t/leaks.args"
# With the real scanner (CI installs it): a planted .gitleaks.toml that allowlists every path,
# a .gitleaksignore and a gitleaks:allow comment do not let a token through.
if command -v gitleaks >/dev/null; then
  ok gitleaks dir --no-banner --config "$here/lib/gitleaks.toml" "$here/lib/gitleaks.toml" >/dev/null 2>&1
  printf '[allowlist]\npaths = [""".*"""]\n' > "$HOME/dev/wip/.gitleaks.toml"
  printf '*\n' > "$HOME/dev/wip/.gitleaksignore"
  tok="ghp_$(printf 'Zq8Tn3Lw0Rb7Yc5Kd2Xf9Hj4Mv6Ps1Ga8Ue3Wo')"
  printf 'GITHUB_TOKEN=%s # gitleaks:allow\n' "$tok" > "$HOME/dev/wip/deploy.sh"
  out=$(DEV_PULL_OWN_RE='/up/wip$' "$here/bin/dev-pull" 2>&1) || true
  ok grep -q 'snapshot withheld, gitleaks finding: wip' <<<"$out"
  ok bash -c '! git -C "$1" for-each-ref --format="%(refname)" "refs/wip/*" | xargs -n1 -I{} git -C "$1" grep -q ghp_ {} 2>/dev/null' _ "$t/up/wip"
else
  echo "  (gitleaks not installed: real-scanner case skipped)"
fi

(( fail == 0 )) && echo "ok dev-pull-edges"
exit "$fail"
