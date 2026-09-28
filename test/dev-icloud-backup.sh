#!/usr/bin/env bash
# Secret-bearing files (any case, any of the known names) must reach only the encrypted
# archive, never the plaintext iCloud mirror; ordinary files must reach the mirror.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home"
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
mkdir -p "$icloud" "$HOME/.config/sops/age" "$HOME/dev/app/credentials"
age-keygen -o "$HOME/.config/sops/age/keys.txt" 2>/dev/null

secret=(prod.tfvars.json .ENV KEY.PEM tfplan app.env .envrc .git-credentials sa-key.json
        .mcp.json kubeconfig.yaml main.tfstate .env.local id_ed25519 credentials/notes.txt)
plain=(README.md main.tf src.py)
for f in "${secret[@]}" "${plain[@]}"; do echo x > "$HOME/dev/app/$f"; done

"$here/bin/dev-icloud-backup" >/dev/null
root="$(echo "$icloud"/Backups/*)"
listed="$(age -d -i "$HOME/.config/sops/age/keys.txt" "$root/dev-secrets.tar.age" | tar -tf -)"

fail=0
for f in "${secret[@]}"; do
  [[ -e "$root/dev/app/$f" ]] && { echo "FAIL: $f mirrored in plaintext"; fail=1; }
  grep -qxF "app/$f" <<<"$listed" || { echo "FAIL: $f missing from encrypted archive"; fail=1; }
done
for f in "${plain[@]}"; do
  [[ -e "$root/dev/app/$f" ]] || { echo "FAIL: $f not mirrored"; fail=1; }
done
(( fail == 0 )) && echo "ok dev-icloud-backup"
exit "$fail"
