#!/usr/bin/env bash
# bin/brew-reconcile commits straight to master unattended, so its rules are pinned here:
# formulae (alias-aware), casks (tap-qualified when not from homebrew/cask) and App Store apps
# (name escaped for the Ruby string) missing from the Brewfile are added under their section;
# --dry-run writes nothing; an uncommitted Brewfile edit is never committed; the commit is
# pushed only when it is the one thing unpushed; --no-push never pushes. brew and mas are stubs.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir "$t/bin"
jq=$(command -v jq) || { echo "SKIP brew-reconcile: jq not installed"; exit 0; }
ln -s "$jq" "$t/bin/jq"
cat > "$t/bin/brew" <<'B'
#!/bin/sh
case "$*" in
  "leaves --installed-on-request") printf '%s\n' git kubernetes-cli ${LEAVES:-} ;;
  "list --cask") printf '%s\n' firefox ${CASKS:-} ;;
  "info --json=v2 --formula kubernetes-cli") echo '{"formulae":[{"full_name":"kubernetes-cli","aliases":["kubectl"],"oldnames":[]}]}' ;;
  "info --json=v2 --formula dead-formula"|"info --cask --json=v2 dead-cask") echo "Error: No available formula" >&2; exit 1 ;;
  "info --json=v2 --formula "*) echo "{\"formulae\":[{\"full_name\":\"$4\",\"aliases\":[],\"oldnames\":[]}]}" ;;
  "info --cask --json=v2 my-cask") echo '{"casks":[{"tap":"someone/tap"}]}' ;;
  "info --cask --json=v2 "*) echo '{"casks":[{"tap":"homebrew/cask"}]}' ;;
  *) echo "unexpected brew $*" >&2; exit 1 ;;
esac
B
cat > "$t/bin/mas" <<'M'
#!/bin/sh
[ "$1" = list ] && printf '%s\n' '497799835  Xcode  (16.0)' ${MAS:+"$MAS"}
M
chmod +x "$t/bin/brew" "$t/bin/mas"
export PATH="$t/bin:/usr/bin:/bin" ZSH="$t/dots"
export BREW_APPLY_STATE="$t/state" DOT_UPDATE_ALLOW_FILE=1
git init -q --bare -b master "$t/up.git"; git clone -q "$t/up.git" "$ZSH" 2>/dev/null
cat > "$ZSH/Brewfile" <<'BF'
# Taps
tap "homebrew/bundle"

# CLI tools
brew "git"
brew "kubectl"

# Casks
cask "firefox"

# Mac App Store
mas "Xcode", id: 497799835
BF
git -C "$ZSH" checkout -q -b master; git -C "$ZSH" add Brewfile; git -C "$ZSH" commit -qm init; git -C "$ZSH" push -q -u origin master 2>/dev/null
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
rec() { out=$(zsh -f "$here/bin/brew-reconcile" "$@" 2>&1) && rc=0 || rc=$?; }  # VAR=x rec: stub input
up() { git -C "$t/up.git" log -1 --format=%s master; }
weird='Weird "App" #{x}\'

# In sync: kubernetes-cli is covered by its alias kubectl.
rec; ok [ "$rc" = 0 ]; ok grep -qx 'brew-reconcile: Brewfile already in sync' <<<"$out"
rec --bogus; ok [ "$rc" = 2 ]

# --dry-run: drift reported, nothing written.
LEAVES='jq some/tap/tool' CASKS=my-cask MAS="123  $weird  (1.0)" rec --dry-run
ok [ "$rc" = 0 ]
ok grep -q 'drift detected (4 item(s))' <<<"$out"
for a in 'add jq' 'add tool' 'add my-cask (cask)' "add $weird (mas)"; do ok grep -qxF "  + $a" <<<"$out"; done
ok git -C "$ZSH" diff --quiet; ok [ "$(up)" = init ]

# The real run: lines under their sections, one commit, pushed (it is the only one unpushed).
LEAVES='jq some/tap/tool' CASKS=my-cask MAS="123  $weird  (1.0)" rec
ok [ "$rc" = 0 ]
ok grep -qx 'brew "jq"' "$ZSH/Brewfile"; ok grep -qx 'brew "some/tap/tool"' "$ZSH/Brewfile"
ok grep -qx 'cask "someone/tap/my-cask"' "$ZSH/Brewfile"
ok grep -qxF 'mas "Weird \"App\" \#{x}\\", id: 123' "$ZSH/Brewfile"
ok [ "$(sed -n '/^# Casks$/{n;p;}' "$ZSH/Brewfile")" = 'cask "someone/tap/my-cask"' ]
ok [ "$(sed -n '/^# Mac App Store$/{n;p;}' "$ZSH/Brewfile")" = 'mas "Weird \"App\" \#{x}\\", id: 123' ]
ok git -C "$ZSH" diff --quiet
ok grep -q '^brew: reconcile add jq, add tool' <<<"$(up)"
# The escaped name is a valid Ruby string that reads back as the App Store name.
if command -v ruby >/dev/null; then
  ok [ "$(ruby -e 'puts eval(ARGF.read[/^mas (".*"), id/, 1])' "$ZSH/Brewfile")" = "$weird" ]
fi

# A local commit not yet pushed: the Brewfile commit is made, nothing is pushed.
echo wip > "$ZSH/notes"; git -C "$ZSH" add notes; git -C "$ZSH" commit -qm "local wip"
LEAVES=wget rec
ok [ "$rc" = 0 ]; ok grep -q 'not pushing (2 commit(s) ahead of upstream)' <<<"$out"
ok [ "$(git -C "$ZSH" log -1 --format=%s)" = 'brew: reconcile add wget' ]
ok bash -c '! git -C "$1" log --format=%s master | grep -qx "local wip"' _ "$t/up.git"
git -C "$ZSH" push -q 2>/dev/null

# --no-push: committed locally only.
LEAVES=htop rec --no-push
ok [ "$rc" = 0 ]; ok [ "$(git -C "$ZSH" log -1 --format=%s)" = 'brew: reconcile add htop' ]
ok [ "$(up)" != 'brew: reconcile add htop' ]
git -C "$ZSH" push -q 2>/dev/null

# Uncommitted Brewfile edit: the line is added but nothing is committed or pushed.
printf 'brew "hand-edit"\n' >> "$ZSH/Brewfile"; head=$(git -C "$ZSH" rev-parse HEAD)
LEAVES=tree rec
ok [ "$rc" = 0 ]; ok grep -q 'added lines left uncommitted for review' <<<"$out"
ok [ "$(git -C "$ZSH" rev-parse HEAD)" = "$head" ]; ok grep -qx 'brew "tree"' "$ZSH/Brewfile"

git -C "$ZSH" checkout -q Brewfile

# Two Macs (D-022). The other Mac pushed a line: this run starts from it (fast-forward first).
git clone -q "$t/up.git" "$t/other" 2>/dev/null
printf 'cask "from-book"\n' >> "$t/other/Brewfile"
git -C "$t/other" commit -qam 'brew: add from-book'; git -C "$t/other" push -q 2>/dev/null
rec; ok [ "$rc" = 0 ]; ok grep -q 'cask "from-book"' "$ZSH/Brewfile"
ok [ "$(git -C "$ZSH" rev-parse HEAD)" = "$(git -C "$t/up.git" rev-parse master)" ]

# Installed here, seen in the Brewfile before (brew-apply's snapshot), gone from it now: removed
# on purpose on one of the Macs, so not added back. By alias too. A new install still is.
mkdir "$t/state"; printf '%s\n' brew:nmap cask:gone-cask mas:555 brew:k8s-alias > "$t/state/snapshot"
head=$(git -C "$ZSH" rev-parse HEAD)
LEAVES=nmap CASKS=gone-cask MAS='555  Gone App  (2.0)' rec
ok [ "$rc" = 0 ]; ok grep -q 'not added back: nmap, gone-cask (cask), Gone App (mas)' <<<"$out"
ok [ "$(git -C "$ZSH" rev-parse HEAD)" = "$head" ]; ok git -C "$ZSH" diff --quiet
LEAVES='nmap fresh' rec
ok grep -qx 'brew "fresh"' "$ZSH/Brewfile"; ok bash -c '! grep -q nmap "$1"' _ "$ZSH/Brewfile"
ok [ "$(up)" = 'brew: reconcile add fresh' ]

# An install Homebrew no longer carries could not be installed on the other Mac: not listed.
head=$(git -C "$ZSH" rev-parse HEAD)
LEAVES=dead-formula CASKS=dead-cask rec
ok [ "$rc" = 0 ]; ok grep -q 'gone from Homebrew, not listed: dead-formula, dead-cask (cask)' <<<"$out"
ok [ "$(git -C "$ZSH" rev-parse HEAD)" = "$head" ]; ok git -C "$ZSH" diff --quiet

# A Brewfile commit an earlier run could not push goes out at the start of the next run.
printf 'brew "offline"\n' >> "$ZSH/Brewfile"; git -C "$ZSH" commit -qam 'brew: add offline'
rec; ok [ "$rc" = 0 ]; ok [ "$(up)" = 'brew: add offline' ]

# On a branch the Brewfile is work in progress: nothing is committed (--dry-run still reports).
git -C "$ZSH" checkout -q -b topic; head=$(git -C "$ZSH" rev-parse HEAD)
LEAVES=branchy rec
ok [ "$rc" = 0 ]; ok grep -q "is on 'topic', not master: nothing done" <<<"$out"
ok [ "$(git -C "$ZSH" rev-parse HEAD)" = "$head" ]; ok git -C "$ZSH" diff --quiet
LEAVES=branchy rec --dry-run; ok grep -qxF '  + add branchy' <<<"$out"

(( fail == 0 )) && echo "ok brew-reconcile"
exit "$fail"
