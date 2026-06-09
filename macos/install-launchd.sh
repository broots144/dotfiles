#!/usr/bin/env bash
#
# Install/refresh the dotfiles LaunchAgents.
#
# Renders each macos/*.plist (rewriting __HOME__ to the real $HOME, since
# launchd does not expand ~), drops it into ~/Library/LaunchAgents, and
# (re)bootstraps it into the current GUI session. Idempotent — safe to re-run.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
agents_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"

mkdir -p "$agents_dir" "$HOME/Library/Logs"

shopt -s nullglob
for src in "$here"/com.broots.*.plist; do
  label="$(basename "$src" .plist)"
  dst="$agents_dir/$label.plist"

  sed "s|__HOME__|$HOME|g" "$src" > "$dst"

  # Reload cleanly: boot it out if already loaded, then boot it back in.
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$uid" "$dst"
  launchctl enable "gui/$uid/$label"

  echo "loaded $label"
done

echo "LaunchAgents installed."
