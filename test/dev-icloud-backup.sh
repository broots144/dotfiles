#!/usr/bin/env bash
# Secret-bearing files (any case, any of the known names, any gitignored small file, any
# git object store) must reach only encrypted copies, never the plaintext iCloud mirror;
# ordinary files must reach the mirror; odd file names must not break the archive; an
# emptied ~/dev must not wipe the backup.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home"
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
keys="$HOME/.config/sops/age/keys.txt"
mkdir -p "$icloud" "$HOME/.config/sops/age" "$HOME/dev/app/credentials" "$HOME/dev/other"
age-keygen -o "$keys" 2>/dev/null
g() { git -c user.email=t@example.invalid -c user.name=t -C "$HOME/dev/app" "$@"; }

secret=(prod.tfvars.json .ENV KEY.PEM tfplan app.env .envrc .git-credentials sa-key.json
        .mcp.json kubeconfig.yaml main.tfstate .env.local id_ed25519 credentials/notes.txt
        lab-k3s.yaml my.local.zsh secrets.yaml service-account.json .pgpass .vault_pass
        $'nl\nname.pem' 'café.env' 'star*[x].key'
        private-notes.txt)          # unlisted name, but gitignored: default-deny
plain=(README.md main.tf src.py .gitignore)
for f in "${secret[@]}" "${plain[@]}"; do printf 'x\n' > "$HOME/dev/app/$f"; done
echo x > "$HOME/dev/other/keep.txt"
printf 'private-notes.txt\n' > "$HOME/dev/app/.gitignore"
g init -q
printf 'MARKER_IN_HISTORY\n' > "$HOME/dev/app/leaked.txt"
g add README.md .gitignore leaked.txt; g commit -qm init; g rm -q leaked.txt; g commit -qm rm

"$here/bin/dev-icloud-backup" >/dev/null
root="$(echo "$icloud"/Backups/*)"
listed="$(age -d -i "$keys" "$root/dev-secrets.tar.age" | tar -tf -)"

fail=0
mkdir "$t/x"; age -d -i "$keys" "$root/dev-secrets.tar.age" | tar -xf - -C "$t/x"
for f in "${secret[@]}"; do
  [[ -e "$root/dev/app/$f" ]] && { echo "FAIL: $f mirrored in plaintext"; fail=1; }
  [[ -f "$t/x/app/$f" ]] || { echo "FAIL: $f missing from encrypted archive"; fail=1; }
done
for f in "${plain[@]}"; do
  [[ -e "$root/dev/app/$f" ]] || { echo "FAIL: $f not mirrored"; fail=1; }
done
[[ -e "$root/dev/app/.git" ]] && { echo "FAIL: .git mirrored in plaintext"; fail=1; }
grep -rq MARKER_IN_HISTORY "$root" 2>/dev/null && { echo "FAIL: git history readable in plaintext"; fail=1; }
grep -qxF app/.git/config <<<"$listed" || { echo "FAIL: .git/config not archived"; fail=1; }
age -d -i "$keys" "$root/git/app.bundle.age" > "$t/app.bundle"
git clone -q "$t/app.bundle" "$t/restored" 2>/dev/null && git -C "$t/restored" show HEAD~1:leaked.txt | grep -q MARKER_IN_HISTORY \
  || { echo "FAIL: git history not restorable from the encrypted bundle"; fail=1; }
ls "$root"/secrets-history/dev-secrets-*.tar.age >/dev/null 2>&1 || { echo "FAIL: no archive generation kept"; fail=1; }

# An emptied ~/dev must not wipe the mirror or replace the archive.
before="$(shasum "$root/dev-secrets.tar.age")"
mv "$HOME/dev" "$t/dev.away"; mkdir "$HOME/dev"
"$here/bin/dev-icloud-backup" >/dev/null 2>&1 && { echo "FAIL: empty source accepted"; fail=1; }
[[ -e "$root/dev/app/README.md" ]] || { echo "FAIL: empty source wiped the mirror"; fail=1; }
[[ "$(shasum "$root/dev-secrets.tar.age")" == "$before" ]] || { echo "FAIL: empty source replaced the archive"; fail=1; }

(( fail == 0 )) && echo "ok dev-icloud-backup"
exit "$fail"
