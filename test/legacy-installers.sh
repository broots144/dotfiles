#!/usr/bin/env bash
# The legacy holman installers (review r3, N5): nothing sets the login shell to a zsh that does
# not exist (/usr/local/bin/zsh, absent on Apple silicon), script/bootstrap's fail() exits
# non-zero, and no script pipes a downloaded installer into a shell, except Homebrew's own
# documented installer in homebrew/install.sh (it runs only when brew is missing).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
cd "$here"
scripts=$(git ls-files | grep -vE '^(docs/|test/|.*\.md$|LICENSE)' | while IFS= read -r f; do
  [[ -f "$f" && ! -L "$f" ]] && grep -Iq . "$f" && printf '%s\n' "$f"; done)
hits=$(xargs grep -nE '(UserShell|chsh).*/usr/local/bin/zsh' <<<"$scripts" || true)
[[ -z "$hits" ]] || { echo "FAIL: login shell set to /usr/local/bin/zsh: $hits"; fail=1; }
hits=$(xargs grep -nE 'curl[^|]*\|[[:space:]]*(ba|z)?sh\b|(ba|z)?sh -c "\$\(curl' <<<"$scripts" | grep -v '^homebrew/install.sh:' || true)
[[ -z "$hits" ]] || { echo "FAIL: downloaded script piped into a shell: $hits"; fail=1; }
[[ ! -e macos/set-shell.sh ]] || { echo "FAIL: macos/set-shell.sh is back"; fail=1; }
# fail() must stop bootstrap with a non-zero status.
rc=0; bash -c "$(sed -n '/^fail () {/,/^}/p' script/bootstrap)"'; fail x' >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 ]] || { echo "FAIL: script/bootstrap fail() exits 0"; fail=1; }
grep -q '^set -o pipefail' script/bootstrap || { echo "FAIL: script/bootstrap lost pipefail (fail() unreachable)"; fail=1; }

(( fail == 0 )) && echo "ok legacy-installers"
exit "$fail"
