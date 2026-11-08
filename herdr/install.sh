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
# The pin is herdr/VERSION, not whatever happens to be installed: a mismatch or a failed pin is
# reported loudly, but the installer still exits 0. An exit 1 aborted `dot` (script/install runs
# installers under set -e) before the LaunchAgents and everything after herdr, and Homebrew
# cannot downgrade to fix it. The n0 gate and the zsh wrapper's --remote guard enforce the pin
# (code review 2026-11-08).
BREW="${HERDR_BREW:-brew}"
want="$(cat "${ZSH:-$HOME/.dotfiles}/herdr/VERSION")"
if command -v "$BREW" >/dev/null 2>&1 && "$BREW" list --versions herdr >/dev/null 2>&1; then
  # The installed binary's own version: `brew list --versions` prints keg names, so a
  # Homebrew revision (0.9.5_1) or a second keg would read as a mismatch (code review 2026-11-08).
  have="$("$("$BREW" --prefix)/opt/herdr/bin/herdr" --version 2>/dev/null | awk '{print $2}')"
  if "$BREW" pin herdr >/dev/null 2>&1; then echo "herdr: brew pin herdr ($have)"; else echo "herdr: WARNING: brew pin herdr FAILED" >&2; fi
  if [ "$have" != "$want" ]; then
    echo "herdr: WARNING: installed ${have:-nothing}, but herdr/VERSION pins $want: herdr --remote stays refused here until they match (brew unpin herdr && brew upgrade herdr, or move the pin)" >&2
  fi
fi

# The remote agent-detection cache cannot exist: a read-only placeholder file takes its path
# (D-012 addendum; bin/herdr-server and the gate do the same check).
ad="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/agent-detection"
mkdir -p "$ad"
[ -d "$ad/remote" ] && rm -rf "$ad/remote"
[ -f "$ad/remote" ] || : > "$ad/remote"
chmod 444 "$ad/remote"

# The Claude hook runs python3 -I (isolated), see herdr/patch-claude-hook.sh (audit run-7, run-8).
sh "${ZSH:-$HOME/.dotfiles}/herdr/patch-claude-hook.sh" || true  # it warns; never abort dot

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
