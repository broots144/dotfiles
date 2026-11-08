#!/bin/sh
#
# herdr's Claude hook runs `python3 -`, which puts the session's working directory first on
# sys.path: a json.py or socket.py at the root of a repo Claude starts in would run on every
# SessionStart (security audit run-7). Isolated mode (-I) drops the cwd. herdr rewrites the hook
# on every integration install (CLI, TUI or API), so herdr/install.sh, the zsh `herdr` wrapper
# and the com.broots.herdr-hook-patch LaunchAgent run this; the gate checks it on n0. Idempotent.
# A failed rewrite or a hook whose python line no longer matches either form fails loudly
# (exit 1) instead of passing as done (code review 2026-11-08).

set -eu
HOOK="${HERDR_CLAUDE_HOOK:-$HOME/.claude/hooks/herdr-agent-state.sh}"
[ -f "$HOOK" ] || exit 0
if grep -q '^HERDR_ACTION=.* python3 -I - <<' "$HOOK"; then
  exit 0
fi
if ! grep -q '^HERDR_ACTION=.* python3 - <<' "$HOOK"; then
  echo "herdr: WARNING: $HOOK has no python3 line this patch knows; check it by hand (D-014)" >&2
  exit 1
fi
tmp="$(mktemp "$HOOK.XXXXXX")"
if sed 's/^\(HERDR_ACTION=.* python3\) - <</\1 -I - <</' "$HOOK" > "$tmp" && chmod 755 "$tmp" \
   && grep -q '^HERDR_ACTION=.* python3 -I - <<' "$tmp" && mv "$tmp" "$HOOK"; then
  echo "herdr: Claude hook runs python3 -I (isolated)"
else
  rm -f "$tmp"
  echo "herdr: WARNING: could not patch $HOOK to python3 -I (D-014)" >&2
  exit 1
fi
