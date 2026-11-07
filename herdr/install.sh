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
