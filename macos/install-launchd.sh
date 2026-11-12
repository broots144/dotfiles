#!/usr/bin/env bash
#
# Install/refresh the dotfiles LaunchAgents.
#
# Renders each macos/*.plist (rewriting __HOME__ to the real $HOME, since
# launchd does not expand ~), drops it into ~/Library/LaunchAgents, and
# (re)bootstraps it into the current GUI session when the rendered file changed or the job is
# not loaded. Idempotent, safe to re-run. An agent that
# will not load is reported and the rest still load; the run then exits 1.
#
# A plist that carries `<!-- dotfiles-hosts: a b -->` (or `a,b`) is installed only on those hosts
# (and unloaded/removed elsewhere). The host is HostName, else LocalHostName: Bonjour renames
# LocalHostName on a name conflict (n0 became n0-2 on 2026-10-28), HostName stays put.
# A plist without the marker is installed everywhere. The iCloud backup belongs to n0; the dev
# sync and the nightly brew upgrade to the laptop; the Brewfile reconciler and brew-apply run on
# both (D-022).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
agents_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"

mkdir -p "$agents_dir" "$HOME/Library/Logs"
err="$(mktemp)"; trap 'rm -f "$err"' EXIT
failed=0

# Reload cleanly: boot it out if loaded, then boot it back in. bootout returns before the job
# is gone, and a bootstrap of the same label meanwhile fails with "Bootstrap failed: 5", which
# under set -e stopped the script and left the later agents unrefreshed (review r3, N4). So
# wait (up to 5 s) until `launchctl print` no longer finds it, then try the bootstrap 3 times.
reload() {  # <label> <plist>
  local i
  launchctl bootout "gui/$uid/$1" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "gui/$uid/$1" >/dev/null 2>&1 || break
    sleep 0.5
  done
  for i in 1 2 3; do
    launchctl bootstrap "gui/$uid" "$2" 2>"$err" && return 0
    (( i < 3 )) && sleep 1
  done
  cat "$err" >&2
  return 1
}
me="$(scutil --get HostName 2>/dev/null || scutil --get LocalHostName 2>/dev/null || hostname -s)"

shopt -s nullglob
for src in "$here"/com.broots.*.plist; do
  label="$(basename "$src" .plist)"
  dst="$agents_dir/$label.plist"

  hosts="$(sed -n 's/.*dotfiles-hosts: *\(.*[^ ]\) *-->.*/\1/p' "$src")"
  # Whole names only: `grep -w n0` also matched a marker naming n0-2 ('-' is not a word char).
  # Names are separated by spaces, tabs or commas (`n0,book` works too).
  if [[ -n "$hosts" && " ${hosts//[,$'\t']/ } " != *" $me "* ]]; then
    if [[ -e "$dst" ]]; then
      launchctl bootout "gui/$uid/$label" 2>/dev/null || true
      rm -f "$dst"
      echo "removed $label (hosts: $hosts; this is $me)"
    else
      echo "skipped $label (hosts: $hosts; this is $me)"
    fi
    continue
  fi

  # Reload only what changed or is not loaded: a bootout stops the job, and for the herdr
  # server that ends every pane and agent on n0 (code review 2026-11-08). An unchanged,
  # loaded job is left running.
  new="$(sed "s|__HOME__|$HOME|g" "$src")"
  if [[ -f "$dst" && "$(cat "$dst")" == "$new" ]] && launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
    echo "unchanged $label"
    continue
  fi
  printf '%s\n' "$new" > "$dst"

  if ! reload "$label" "$dst"; then
    echo "failed to load $label" >&2; failed=1; continue
  fi
  launchctl enable "gui/$uid/$label"

  echo "loaded $label"
done

if (( failed )); then echo "LaunchAgents installed, with failures (see above)." >&2; exit 1; fi
echo "LaunchAgents installed."
