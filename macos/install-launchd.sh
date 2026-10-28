#!/usr/bin/env bash
#
# Install/refresh the dotfiles LaunchAgents.
#
# Renders each macos/*.plist (rewriting __HOME__ to the real $HOME, since
# launchd does not expand ~), drops it into ~/Library/LaunchAgents, and
# (re)bootstraps it into the current GUI session. Idempotent — safe to re-run.
#
# A plist that carries `<!-- dotfiles-hosts: a b -->` is installed only on those hosts
# (and unloaded/removed elsewhere). The host is HostName, else LocalHostName: Bonjour renames
# LocalHostName on a name conflict (n0 became n0-2 on 2026-10-28), HostName stays put.
# A plist without the marker is installed everywhere. The iCloud backup and the Brewfile
# reconciler belong to n0; the dev sync to the laptop.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
agents_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"

mkdir -p "$agents_dir" "$HOME/Library/Logs"
me="$(scutil --get HostName 2>/dev/null || scutil --get LocalHostName 2>/dev/null || hostname -s)"

shopt -s nullglob
for src in "$here"/com.broots.*.plist; do
  label="$(basename "$src" .plist)"
  dst="$agents_dir/$label.plist"

  hosts="$(sed -n 's/.*dotfiles-hosts: *\(.*[^ ]\) *-->.*/\1/p' "$src")"
  if [[ -n "$hosts" ]] && ! grep -qw -- "$me" <<<"$hosts"; then
    if [[ -e "$dst" ]]; then
      launchctl bootout "gui/$uid/$label" 2>/dev/null || true
      rm -f "$dst"
      echo "removed $label (hosts: $hosts; this is $me)"
    else
      echo "skipped $label (hosts: $hosts; this is $me)"
    fi
    continue
  fi

  sed "s|__HOME__|$HOME|g" "$src" > "$dst"

  # Reload cleanly: boot it out if already loaded, then boot it back in.
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$uid" "$dst"
  launchctl enable "gui/$uid/$label"

  echo "loaded $label"
done

echo "LaunchAgents installed."
