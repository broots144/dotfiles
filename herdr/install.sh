#!/bin/sh
#
# herdr (agent multiplexer, D-010, D-011): link the tracked config into ~/.config/herdr and keep
# that directory owner-only (it holds herdr's API and client sockets, session.json and logs).
# Run by script/install (`dot`) on every Mac; idempotent. A regular config.toml already there is
# kept as config.toml.pre-dotfiles before the link replaces it.

set -eu

src="${ZSH:-$HOME/.dotfiles}/herdr/config.toml"
dir="${HERDR_DIR:-$HOME/.config/herdr}"
dst="$dir/config.toml"

mkdir -p "$dir"
chmod 700 "$dir"

# Same pinned herdr on every Mac (D-010): `brew pin` is per machine, and an unpinned MacBook would
# upgrade herdr nightly and meet n0's pinned server with a newer client over `herdr --remote n0`.
BREW="${HERDR_BREW:-brew}"
if command -v "$BREW" >/dev/null 2>&1 && "$BREW" list --versions herdr >/dev/null 2>&1; then
  "$BREW" pin herdr >/dev/null 2>&1 && echo "herdr: brew pin herdr"
fi

# herdr's Claude hook runs `python3 -`, which puts the session's working directory first on
# sys.path: a json.py or socket.py at the root of a repo Claude starts in would run on every
# SessionStart (security audit run-7). Isolated mode (-I) drops the cwd. herdr rewrites the hook
# on reinstall, so this runs on every install and the gate checks it.
HOOK="${HERDR_CLAUDE_HOOK:-$HOME/.claude/hooks/herdr-agent-state.sh}"
if [ -f "$HOOK" ] && grep -q '^HERDR_ACTION=.* python3 - <<' "$HOOK"; then
  tmp="$(mktemp "$HOOK.XXXXXX")"
  sed 's/^\(HERDR_ACTION=.* python3\) - <</\1 -I - <</' "$HOOK" > "$tmp" && chmod 755 "$tmp" && mv "$tmp" "$HOOK"
  echo "herdr: Claude hook runs python3 -I (isolated)"
fi

if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
  echo "herdr: config already linked"
  exit 0
fi
if [ -e "$dst" ] && [ ! -L "$dst" ]; then
  mv "$dst" "$dst.pre-dotfiles"
  echo "herdr: kept the old config as $dst.pre-dotfiles"
fi
ln -sfn "$src" "$dst"
echo "herdr: linked $dst -> $src"
