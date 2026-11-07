#!/usr/bin/env bash
# Supply chain (security review 2026-11-07 r2, L3): every action a workflow uses is pinned to a
# full commit SHA (the repo setting sha_pinning_required enforces it on GitHub too), and
# Dependabot keeps those pins current, with the deps: prefix state-guard exempts.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
uses=$(grep -hE '^[[:space:]]*-?[[:space:]]*uses:' "$here"/.github/workflows/*.yml | sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//' || true)
[[ -n "$uses" ]] || { echo "FAIL: no uses: lines found"; fail=1; }
while IFS= read -r u; do
  [[ -z "$u" || "$u" == ./* ]] && continue
  [[ "$u" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+@[0-9a-f]{40}$ ]] || { echo "FAIL: action not pinned to a full SHA: $u"; fail=1; }
done <<< "$uses"
grep -hE 'uses:.*@[0-9a-f]{40}' "$here"/.github/workflows/*.yml | grep -vqE '# v[0-9]' && { echo "FAIL: a SHA pin lacks its '# vX' comment"; fail=1; }
dep="$here/.github/dependabot.yml"
[[ -f "$dep" ]] || { echo "FAIL: no .github/dependabot.yml"; fail=1; }
grep -qE '^[[:space:]]*-[[:space:]]*package-ecosystem:[[:space:]]*"?github-actions"?' "$dep" 2>/dev/null || { echo "FAIL: dependabot does not watch github-actions"; fail=1; }
grep -qE '^[[:space:]]*prefix:[[:space:]]*"?deps"?' "$dep" 2>/dev/null || { echo "FAIL: dependabot commits lack the deps prefix state-guard exempts"; fail=1; }
(( fail == 0 )) && echo "ok workflow-pinning"
exit "$fail"
