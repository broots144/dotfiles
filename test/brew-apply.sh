#!/usr/bin/env bash
# bin/brew-apply installs what the Brewfile lists and this Mac lacks, unattended (D-022):
# nothing off master; the checkout is fast-forwarded first; in sync means no install; a failed
# install is listed, exits 1 and is not tried again for a day unless the Brewfile changes or
# --force; --dry-run changes nothing; the snapshot keeps entries removed from the Brewfile only
# while they are still installed here. brew is a stub that logs its calls.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir "$t/bin"
# MISSING holds what `bundle check` reports; `bundle install` empties it unless INSTALL_FAILS.
cat > "$t/bin/brew" <<'B'
#!/bin/sh
echo "brew $*" >> "$LOG"
case "$1 $2" in
  "bundle check") [ -s "$MISSING" ] || exit 0   # like brew: the list on stderr, exit 1
     [ "$(cat "$MISSING")" = unnamed ] && exit 1
     while read -r m; do echo "→ $m needs to be installed or updated." >&2; done < "$MISSING"; exit 1 ;;
  "bundle install") [ -t 0 ] && echo "stdin is a tty" >> "$LOG"
     if [ -n "${INSTALL_FAILS:-}" ]; then echo "$INSTALL_FAILS" > "$MISSING"; exit 1; fi; : > "$MISSING" ;;
  "list --formula") printf '%s\n' git ${FORMULAE:-} ;;
  "list --cask") printf '%s\n' firefox ${CASKS:-} ;;
esac
exit 0
B
chmod +x "$t/bin/brew"
export BREW_APPLY_PATH="$t/bin:/usr/bin:/bin:/usr/sbin:/sbin" BREW_APPLY_STATE="$t/state" ZSH="$t/dots"
export LOG="$t/log" MISSING="$t/missing" DOT_UPDATE_ALLOW_FILE=1
git init -q --bare -b master "$t/up.git"; git clone -q "$t/up.git" "$ZSH" 2>/dev/null
git clone -q "$t/up.git" "$t/other" 2>/dev/null
bf() { printf '%s\n' '# CLI tools' 'brew "git"' "$@" '# Casks' 'cask "firefox"' 'mas "Xcode", id: 497799835 if n0'; }
bf > "$ZSH/Brewfile"
git -C "$ZSH" checkout -q -b master; git -C "$ZSH" add Brewfile; git -C "$ZSH" commit -qm init; git -C "$ZSH" push -q -u origin master 2>/dev/null
git -C "$t/other" pull -q 2>/dev/null
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
no() { ! "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: not $*"; fail=1; }; }
run() { : > "$LOG"; out=$("$here/bin/brew-apply" "$@" 2>&1) && rc=0 || rc=$?; }
: > "$MISSING"

# In sync: no install; the snapshot lists every entry (tap prefix dropped, mas by id).
run
ok [ "$rc" = 0 ]; ok grep -q 'brew-apply: in sync' <<<"$out"; no grep -q '^brew bundle install' "$LOG"
ok [ "$(tr '\n' ' ' < "$t/state/snapshot")" = 'brew:git cask:firefox mas:497799835 ' ]
run --bogus; ok [ "$rc" = 2 ]

# The other Mac pushes a new line: this one pulls it, installs it, stdin closed.
bf 'brew "some/tap/jq"' > "$t/other/Brewfile"; git -C "$t/other" commit -qam 'brew: add jq'; git -C "$t/other" push -q 2>/dev/null
echo 'Formula some/tap/jq' > "$MISSING"
run --dry-run
ok [ "$rc" = 0 ]; ok grep -q 'would install: Formula some/tap/jq' <<<"$out"
no grep -q '^brew bundle install' "$LOG"; no grep -q jq "$ZSH/Brewfile"
run
ok [ "$rc" = 0 ]; ok grep -q 'installing: Formula some/tap/jq' <<<"$out"
ok grep -qx "brew bundle install --no-upgrade --file=$ZSH/Brewfile" "$LOG"; no grep -q 'stdin is a tty' "$LOG"
ok grep -qx 'brew:jq' "$t/state/snapshot"; ok grep -q 'jq' "$ZSH/Brewfile"

# An install that fails: listed, exit 1; the same Brewfile waits a day; --force and a changed
# Brewfile try at once; success clears the wait.
echo 'Cask needs-password' > "$MISSING"
: > "$LOG"; out=$(INSTALL_FAILS='Cask needs-password' "$here/bin/brew-apply" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 1 ]; ok grep -q 'not installed (brew bundle exit 1.*): Cask needs-password' <<<"$out"
run
ok [ "$rc" = 0 ]; ok grep -q 'still missing after the last attempt, trying again in 24 h' <<<"$out"
no grep -q '^brew bundle install' "$LOG"
echo "$(cut -d' ' -f1 "$t/state/attempt") $(( $(date +%s) - 90000 ))" > "$t/state/attempt"
run; ok grep -q '^brew bundle install' "$LOG"; ok [ ! -e "$t/state/attempt" ]
echo 'Cask needs-password' > "$MISSING"
out=$(INSTALL_FAILS='Cask needs-password' "$here/bin/brew-apply" 2>&1) || true
run --force; ok grep -q '^brew bundle install' "$LOG"
echo 'Cask needs-password' > "$MISSING"
out=$(INSTALL_FAILS='Cask needs-password' "$here/bin/brew-apply" 2>&1) || true
bf 'brew "some/tap/jq"' 'brew "wget"' > "$t/other/Brewfile"; git -C "$t/other" commit -qam 'brew: add wget'; git -C "$t/other" push -q 2>/dev/null
run; ok grep -q '^brew bundle install' "$LOG"

# jq and wget are dropped from the Brewfile on the other Mac. jq is still installed here: it
# stays in the snapshot (brew-reconcile will not add it back) and is never uninstalled. wget is
# not installed here: forgotten. Once jq is uninstalled here it is forgotten too.
bf > "$t/other/Brewfile"; git -C "$t/other" commit -qam 'brew: drop jq, drop wget'; git -C "$t/other" push -q 2>/dev/null
: > "$MISSING"
: > "$LOG"; out=$(FORMULAE=jq "$here/bin/brew-apply" 2>&1) && rc=0 || rc=$?
ok [ "$rc" = 0 ]; ok grep -q 'removed from the Brewfile (left alone, not listed again): brew:jq $' <<<"$out"
ok grep -qx 'brew:jq' "$t/state/snapshot"; no grep -qx 'brew:wget' "$t/state/snapshot"
no grep -q 'uninstall' "$LOG"
run; no grep -qx 'brew:jq' "$t/state/snapshot"

# A check that fails without naming anything still counts as something missing.
echo unnamed > "$MISSING"
run --dry-run; ok grep -q 'would install: something (brew bundle check failed' <<<"$out"
: > "$MISSING"

# Off master: nothing is installed.
git -C "$ZSH" checkout -q -b topic; echo 'Formula x' > "$MISSING"
run
ok [ "$rc" = 0 ]; ok grep -q "is on 'topic', not master: nothing installed" <<<"$out"; ok [ ! -s "$LOG" ]

(( fail == 0 )) && echo "ok brew-apply"
exit "$fail"
