#!/usr/bin/env bash
# dev-icloud-backup edge exits (the main behaviour is test/dev-icloud-backup.sh): no iCloud
# Drive exits 1 and writes nothing; -n writes neither archive nor LAST_RUN.json; nothing
# secret to archive is status 4 (the previous archive kept); a repo whose history cannot be
# bundled is status 5 while the other repos and the mirror are still done.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home" ZSH="$here" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$t/bin"; printf '#!/bin/sh\necho testhost\n' > "$t/bin/scutil"; chmod +x "$t/bin/scutil"
export PATH="$t/bin:$PATH"
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"; root="$icloud/Backups/testhost"
keys="$HOME/.config/sops/age/keys.txt"
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
run() { out=$("$here/bin/dev-icloud-backup" "$@" 2>&1) && rc=0 || rc=$?; }

# No iCloud Drive (signed out): exit 1, nothing created.
mkdir -p "$HOME/dev/notes"; echo x > "$HOME/dev/notes/a.txt"
run; ok [ "$rc" = 1 ]; ok grep -q 'iCloud Drive not found' <<<"$out"; ok [ ! -e "$HOME/Library/Mobile Documents" ]

# Nothing secret-shaped and no repos: status 4, mirror still made.
mkdir -p "$icloud" "$(dirname "$keys")"; age-keygen -o "$keys" 2>/dev/null
run; ok [ "$rc" = 4 ]; ok grep -q 'no secret files found' <<<"$out"
ok [ -f "$root/dev/notes/a.txt" ]; ok grep -q '"exit":4' "$root/LAST_RUN.json"

# -n: rsync dry run only; no archive, no LAST_RUN.json change, no new mirror file.
echo y > "$HOME/dev/notes/b.txt"; printf 'S=1\n' > "$HOME/dev/notes/.env"; cp "$root/LAST_RUN.json" "$t/last.before"
run -n; ok [ "$rc" = 0 ]
ok [ ! -e "$root/dev-secrets.tar.age" ]; ok [ ! -e "$root/dev/notes/b.txt" ]
ok cmp -s "$t/last.before" "$root/LAST_RUN.json"

# A repo with a ref to a missing object cannot be bundled: status 5; the good repo's bundle,
# the archive and the mirror are still made.
for r in good bad; do
  git init -q "$HOME/dev/$r"; echo r > "$HOME/dev/$r/README"; git -C "$HOME/dev/$r" add README; git -C "$HOME/dev/$r" commit -qm init
done
echo 1111111111111111111111111111111111111111 > "$HOME/dev/bad/.git/refs/heads/broken"
run; ok [ "$rc" = 5 ]; ok grep -q 'git bundle failed for bad' <<<"$out"
ok [ -s "$root/git/good.bundle.age" ]; ok [ ! -e "$root/git/bad.bundle.age" ]; ok [ ! -e "$root/git/.bad.tmp" ]
ok [ -s "$root/dev-secrets.tar.age" ]; ok [ -f "$root/dev/notes/b.txt" ]; ok [ ! -e "$root/dev/notes/.env" ]
ok grep -q '"exit":5' "$root/LAST_RUN.json"

(( fail == 0 )) && echo "ok dev-icloud-backup-edges"
exit "$fail"
