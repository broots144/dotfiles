#!/bin/sh
#
# herdr (agent multiplexer, D-010, D-011): copy the tracked config into ~/.config/herdr and keep
# that directory owner-only (it holds herdr's API and client sockets, session.json and logs).
# Run by script/install (`dot`) on every Mac; idempotent. A copy, not a link: herdr writes its
# settings (theme, toasts) back to config.toml, and through a link that dirtied the deployed
# checkout, which stops bin/dev-pull from moving n0's dotfiles (code review 2026-11-08). A
# config.toml that differs from the tracked one is kept as config.toml.pre-dotfiles first; the
# gate compares the contents.

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

# herdr's remote attach installs the client's own binary at ~/.local/bin/herdr on the host when
# the protocol generations differ (default yes), whatever the client's zsh guard says, e.g. from a
# stale or unguarded client (security audit run-10). Take that path first: an immutable symlink to
# the pinned Homebrew binary (chflags uchg; the owner can clear it). Discovery then finds the
# pinned herdr there, and the installer's final rename onto the path fails (D-019).
lb="${HERDR_LOCAL_BIN:-$HOME/.local/bin}"
pinned="${HERDR_PINNED_BIN:-/opt/homebrew/bin/herdr}"
if [ -x "$pinned" ]; then
  if [ -L "$lb/herdr" ] && [ "$(readlink "$lb/herdr")" = "$pinned" ]; then
    chflags -h uchg "$lb/herdr" 2>/dev/null || echo "herdr: WARNING: cannot lock $lb/herdr (chflags uchg)" >&2
  elif [ -e "$lb/herdr" ] || [ -L "$lb/herdr" ]; then
    echo "herdr: WARNING: $lb/herdr is not the locked link to $pinned (an unpinned remote install?); move it away and rerun" >&2
  else
    mkdir -p "$lb" && ln -s "$pinned" "$lb/herdr" && chflags -h uchg "$lb/herdr" && echo "herdr: $lb/herdr locked to $pinned (D-019)"
  fi
fi

# The Claude hook runs python3 -I (isolated), see herdr/patch-claude-hook.sh (audit run-7, run-8).
sh "${ZSH:-$HOME/.dotfiles}/herdr/patch-claude-hook.sh" || true  # it warns; never abort dot

if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
  echo "herdr: config already current"
  exit 0
fi
if [ -f "$dst" ] && [ ! -L "$dst" ]; then
  mv "$dst" "$dst.pre-dotfiles"
  echo "herdr: kept the old config as $dst.pre-dotfiles"
fi
rm -f "$dst"
tmp="$(mktemp "$dst.XXXXXX")"
cp "$src" "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$dst"
echo "herdr: copied $src to $dst"
