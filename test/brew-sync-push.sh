#!/usr/bin/env bash
# The brew wrapper must push its Brewfile commit only when that commit is the one thing
# unpushed; other local commits must never be published by a brew install.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
git init -q --bare "$t/up.git"
git clone -q "$t/up.git" "$t/zsh" 2>/dev/null
cd "$t/zsh"
git config user.email t@example.invalid; git config user.name t
printf '# Brews\nbrew "git"\n' > Brewfile; git add Brewfile; git commit -qm init >/dev/null 2>&1; git push -q origin HEAD 2>/dev/null
mkdir "$t/bin"; printf '#!/bin/sh\nexit 0\n' > "$t/bin/brew"; chmod +x "$t/bin/brew"

run() { PATH="$t/bin:$PATH" ZSH="$t/zsh" zsh -fc "fpath=($here/functions \$fpath); autoload -U brew; brew install $1" >/dev/null 2>&1 || true; }
fail=0
echo wip > private.txt; git add private.txt; git commit -qm "local wip" >/dev/null 2>&1
run jq
git -C "$t/up.git" log --format=%s | grep -qx "local wip" && { echo "FAIL: unrelated commit pushed"; fail=1; }
git push -q origin HEAD 2>/dev/null   # reviewer pushes by hand
run wget
git -C "$t/up.git" log -1 --format=%s | grep -q '^brew: ' || { echo "FAIL: lone Brewfile commit not pushed"; fail=1; }
(( fail == 0 )) && echo "ok brew-sync-push"
exit "$fail"
