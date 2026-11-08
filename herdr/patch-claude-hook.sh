#!/bin/sh
#
# herdr's Claude hook runs `python3 -`, which puts the session's working directory first on
# sys.path: a json.py or socket.py at the root of a repo Claude starts in would run on every
# SessionStart (security audit run-7). Isolated mode (-I) drops the cwd. herdr rewrites the hook
# on every `herdr integration install`, so herdr/install.sh and the zsh `herdr` wrapper both run
# this (audit run-8); the gate checks it on n0. Idempotent.

set -eu
HOOK="${HERDR_CLAUDE_HOOK:-$HOME/.claude/hooks/herdr-agent-state.sh}"
if [ -f "$HOOK" ] && grep -q '^HERDR_ACTION=.* python3 - <<' "$HOOK"; then
  tmp="$(mktemp "$HOOK.XXXXXX")"
  sed 's/^\(HERDR_ACTION=.* python3\) - <</\1 -I - <</' "$HOOK" > "$tmp" && chmod 755 "$tmp" && mv "$tmp" "$HOOK"
  echo "herdr: Claude hook runs python3 -I (isolated)"
fi
