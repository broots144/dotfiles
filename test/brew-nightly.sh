#!/usr/bin/env bash
# brew-nightly upgrades formulae then casks; a cask that cannot upgrade unattended is listed,
# not fatal; a formula still outdated afterwards (pinned ones aside) or a failed `brew update`
# fails the run (exit 1) and fires On Fire, a good run resolves it; on n0 it refuses (exit 2).
# brew, scutil and sublevel's onfire-notify.sh are stubs that log their calls.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home" SUBLEVEL_DIR="$t/sublevel" BREW_NIGHTLY_PATH="$t/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$t/bin" "$HOME" "$SUBLEVEL_DIR/scripts"
printf '#!/bin/sh\necho "${FAKE_HOST:-book}"\n' > "$t/bin/scutil"
# brew stub: logs argv; BREW_FAIL=<subcommand> fails that one; outdated/pinned lists from env.
cat > "$t/bin/brew" <<'B'
#!/bin/sh
echo "brew $*" >> "$LOG"
case "$*" in
  "${BREW_FAIL:-none}"*) exit 1 ;;
  "outdated --formula --quiet") [ -n "${OUTDATED:-}" ] && printf '%s\n' $OUTDATED ;;
  "outdated --cask --quiet") echo some-pkg-cask ;;
  "outdated --quiet") printf '%s\n' ${OUTDATED:-} ;;
  "list --pinned") [ -n "${PINNED:-}" ] && printf '%s\n' $PINNED ;;
esac
exit 0
B
printf '#!/bin/sh\necho "onfire $*" >> "$LOG"\n' > "$SUBLEVEL_DIR/scripts/onfire-notify.sh"
chmod +x "$t/bin/scutil" "$t/bin/brew" "$SUBLEVEL_DIR/scripts/onfire-notify.sh"
export LOG="$t/log"
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
run() { : > "$LOG"; out=$(env "$@" "$here/bin/brew-nightly" 2>&1) && rc=0 || rc=$?; }

# A good night: update, formulae, casks (stdin closed), cleanup; On Fire resolved.
run
ok [ "$rc" = 0 ]
ok grep -qx 'brew update --quiet' "$LOG"; ok grep -qx 'brew upgrade --formula' "$LOG"
ok grep -qx 'brew upgrade --cask' "$LOG"; ok grep -qx 'brew cleanup --prune=30 --quiet' "$LOG"
ok grep -q '^onfire upgrade:brew-book resolved warning' "$LOG"
ok grep -q 'brew-nightly: exit 0' <<<"$out"

# A cask needs a password: listed, the run still succeeds.
run BREW_FAIL='upgrade --cask'
ok [ "$rc" = 0 ]; ok grep -q 'casks not upgraded unattended (password or GUI needed): some-pkg-cask' <<<"$out"

# A pinned formula stays outdated on purpose: fine. An unpinned one fails the run and fires.
run OUTDATED=pinned-one PINNED=pinned-one
ok [ "$rc" = 0 ]
run OUTDATED='pinned-one stale-one' PINNED=pinned-one
ok [ "$rc" = 1 ]; ok grep -q 'formulae still outdated: stale-one $' <<<"$out"
ok grep -q '^onfire upgrade:brew-book firing warning .*exit 1; see' "$LOG"

# brew update fails: nothing upgraded, exit 1.
run BREW_FAIL=update
ok [ "$rc" = 1 ]; ok bash -c '! grep -q "^brew upgrade" "$1"' _ "$LOG"

# No sublevel checkout: the run still works, no notification.
run SUBLEVEL_DIR="$t/none"
ok [ "$rc" = 0 ]; ok bash -c '! grep -q "^onfire" "$1"' _ "$LOG"

# On n0: refused before brew runs.
run FAKE_HOST=n0
ok [ "$rc" = 2 ]; ok [ ! -s "$LOG" ]; ok grep -q "this is n0" <<<"$out"

(( fail == 0 )) && echo "ok brew-nightly"
exit "$fail"
