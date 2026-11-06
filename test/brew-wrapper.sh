#!/usr/bin/env bash
# The interactive `brew` wrapper (functions/brew) keeps the Brewfile in step: install adds a
# line under its section (casks tap-qualified when not from homebrew/cask), uninstall drops it,
# tap/untap manage the tap section (made when missing); a failed command, BREW_SYNC=0, an
# already-listed package or a subcommand that is not install/uninstall/tap change nothing.
# (test/brew-sync-push.sh pins the commit and push rules.) The real brew is a stub.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir "$t/bin"
cat > "$t/bin/brew" <<'B'
#!/bin/sh
case "$*" in
  "install fails-to-build") exit 1 ;;
  "list --cask --versions "*) case " ${CASKS:-} " in *" $4 "*) exit 0 ;; esac; exit 1 ;;
  "info --cask --json=v2 tapped-app") echo '{"casks":[{"tap":"vendor/tap"}]}' ;;
  "info --cask --json=v2 "*) echo '{"casks":[{"tap":"homebrew/cask"}]}' ;;
esac
exit 0
B
chmod +x "$t/bin/brew"
export ZSH="$t/dots" BF="$t/dots/Brewfile"
git init -q "$ZSH"
printf '# CLI tools\nbrew "git"\n\n# Casks\ncask "firefox"\n' > "$BF"
git -C "$ZSH" add Brewfile; git -C "$ZSH" commit -qm init
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
# No upstream here: each change is committed, never pushed ("no upstream").
b() { PATH="$t/bin:/usr/bin:/bin" zsh -fc "fpath=($here/functions \$fpath); autoload -U brew; brew $*" >/dev/null 2>&1 || true; }
last() { git -C "$ZSH" log -1 --format=%s; }

b install ripgrep
ok [ "$(sed -n '2p' "$BF")" = 'brew "ripgrep"' ]; ok [ "$(last)" = 'brew: add ripgrep' ]
b install --cask iterm2
ok [ "$(sed -n '/^# Casks$/{n;p;}' "$BF")" = 'cask "iterm2"' ]
if command -v jq >/dev/null; then
  b install --cask tapped-app
  ok grep -qx 'cask "vendor/tap/tapped-app"' "$BF"
fi
CASKS=docker b install docker
ok grep -qx 'cask "docker"' "$BF"; ok bash -c '! grep -qx "brew \"docker\"" "$1"' _ "$BF"
b install someone/tap/tool
ok grep -qx 'brew "someone/tap/tool"' "$BF"
b uninstall tool
ok bash -c '! grep -q "tool\"" "$1"' _ "$BF"; ok [ "$(last)" = 'brew: drop tool' ]

# Taps: a section is created at the top, then used; untap removes the line.
b tap acme/tools
ok [ "$(head -2 "$BF")" = $'# Taps\ntap "acme/tools"' ]; ok [ "$(last)" = 'brew: tap acme/tools' ]
b tap other/tap
ok [ "$(sed -n 2p "$BF")" = 'tap "other/tap"' ]; ok [ "$(grep -c '^# Taps$' "$BF")" = 1 ]
b untap acme/tools
ok bash -c '! grep -q acme/tools "$1"' _ "$BF"; ok [ "$(last)" = 'brew: untap acme/tools' ]

# Nothing changes: already listed, failed install, BREW_SYNC=0, another subcommand.
head=$(git -C "$ZSH" rev-parse HEAD); cp "$BF" "$t/before"
b install git; b install fails-to-build; BREW_SYNC=0 b install htop; b upgrade wget; b uninstall not-listed
ok cmp -s "$t/before" "$BF"; ok [ "$(git -C "$ZSH" rev-parse HEAD)" = "$head" ]

(( fail == 0 )) && echo "ok brew-wrapper"
exit "$fail"
