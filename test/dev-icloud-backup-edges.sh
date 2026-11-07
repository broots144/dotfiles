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

# Worktrees and submodules have a .git file, not a .git dir: their gitignored files must stay
# out of the plaintext mirror too (a worktree's private/pairing.txt was copied, 2026-11-07),
# go into the archive, and stay out of the MacBook sync manifest. A worktree git cannot read
# (its main repo moved) is left out of the mirror whole.
rm -rf "$HOME/dev/bad"
m="$HOME/dev/main"; git init -q -b main "$m"; printf 'private/\n*.log\n' > "$m/.gitignore"; echo r > "$m/README"
git -C "$m" add .; git -C "$m" commit -qm init
mkdir -p "$m/private"; echo pin > "$m/private/pairing.txt"
git -C "$m" worktree add -q -b br "$HOME/dev/_wt/main/br"
w="$HOME/dev/_wt/main/br"; mkdir -p "$w/private" "$w/cdk.out"; echo pin2 > "$w/private/pairing.txt"; echo l > "$w/run.log"
printf 'cdk.out/\n' >> "$w/.gitignore"; echo c > "$w/cdk.out/tpl.json"; echo ok > "$w/plain.txt"
git init -q -b main "$t/subsrc"; printf 'cache/\nlocal.txt\n' > "$t/subsrc/.gitignore"; git -C "$t/subsrc" add .; git -C "$t/subsrc" commit -qm s
git init -q -b main "$HOME/dev/sup"; git -C "$HOME/dev/sup" -c protocol.file.allow=always submodule -q add "$t/subsrc" sub
git -C "$HOME/dev/sup" commit -qm sub; mkdir -p "$HOME/dev/sup/sub/cache"
echo k > "$HOME/dev/sup/sub/cache/k.txt"; echo k2 > "$HOME/dev/sup/sub/local.txt"
git -C "$m" worktree add -q -b gone "$HOME/dev/_wt/main/gone"; echo g > "$HOME/dev/_wt/main/gone/notes.txt"
printf 'gitdir: %s/nowhere\n' "$t" > "$HOME/dev/_wt/main/gone/.git"
run; ok [ "$rc" = 0 ]
for f in main/private _wt/main/br/private/pairing.txt _wt/main/br/run.log _wt/main/br/cdk.out sup/sub/cache sup/sub/local.txt _wt/main/gone; do
  ok [ ! -e "$root/dev/$f" ]
done
ok [ -f "$root/dev/_wt/main/br/plain.txt" ]; ok [ -f "$root/dev/sup/sub/.gitignore" ]
listed=$(age -d -i "$keys" "$root/dev-secrets.tar.age" | tar -tzf -)
for f in main/private/pairing.txt _wt/main/br/private/pairing.txt _wt/main/br/run.log sup/sub/cache/k.txt sup/sub/local.txt _wt/main/gone/notes.txt; do
  ok grep -qxF "$f" <<<"$listed"
done
ok bash -c '! grep -q "cdk.out" <<<"$1"' _ "$listed"
. "$here/lib/dev-tree.sh"; mkdir "$t/w"; dev_tree_lists "$HOME/dev/" "$t/w"
man=$(dev_tree_private_files "$HOME/dev/" "$t/w" | tr '\0' '\n')
ok bash -c '! grep -q "^_wt/\|^sup/sub/" <<<"$1"' _ "$man"
rm -rf "$HOME/dev/_wt/main/gone"; git -C "$m" worktree prune

# iCloud refusals (2026-11-07): openrsync cannot delete an excluded package directory in iCloud
# ("unlinkat: Directory not empty") and gives up on an evicted mirror file (EDEADLK). Those
# mirror paths are removed and rsync runs again (at most three runs, and only while there is
# something to remove); a path that leaves the mirror is ignored; a failure that stays is the
# exit status. .build/ is never mirrored.
mkdir -p "$HOME/dev/notes/.build/App.app" "$root/dev/notes/.build/App.app/Contents"
echo b > "$HOME/dev/notes/.build/App.app/x"; echo b > "$root/dev/notes/.build/App.app/Contents/Info.plist"
echo canary > "$root/escape-canary"
# An evicted package directory in the mirror fails stat itself (2026-11-07 17:34Z, exit 23:
# "ClaudeGlance.xcodeproj/xcshareddata: fstatat: Resource deadlock avoided").
mkdir -p "$root/dev/notes/App.xcodeproj/xcshareddata"
# Under launchd the children of an evicted (dataless) mirror directory cannot even be stat'ed,
# so the reported path does not "exist": the nearest evicted ancestor inside the mirror goes.
mkdir -p "$root/dev/notes/Evicted.xcodeproj"; chflags hidden "$root/dev/notes/Evicted.xcodeproj"
cat > "$t/rsync-once" <<EOF
#!/bin/sh
n=\$(cat "$t/rsync.n" 2>/dev/null || echo 0); echo \$((n + 1)) > "$t/rsync.n"
if [ "\$n" -lt "\${FAILS:-1}" ]; then
  echo "rsync(1): error: notes/.build/App.app: unlinkat: Directory not empty" >&2
  echo "rsync(1): error: notes/a.txt: mmap: Resource deadlock avoided" >&2
  echo "rsync(1): error: notes/App.xcodeproj/xcshareddata: fstatat: Resource deadlock avoided" >&2
  echo "rsync(1): error: notes/Evicted.xcodeproj/sub/gone.txt: fstatat: Resource deadlock avoided" >&2
  echo "rsync(1): error: notes/plain-missing/x: fstatat: Resource deadlock avoided" >&2
  echo "rsync(1): error: ../escape-canary: unlinkat: Directory not empty" >&2
  echo "rsync(0): error: unexpected end of file" >&2; exit 1
fi
exec /usr/bin/rsync "\$@"
EOF
chmod +x "$t/rsync-once"
rm -f "$t/rsync.n"; mkdir -p "$root/dev/notes/plain-missing"; DEV_BACKUP_EVICTED_FLAG=hidden DEV_BACKUP_RSYNC="$t/rsync-once" run
ok grep -q 'removed notes/Evicted.xcodeproj from the mirror' <<<"$out"
ok bash -c '! grep -q "removed notes/plain-missing from the mirror" <<<"$1"' _ "$out"   # not evicted: left alone
ok [ "$rc" = 0 ]; ok [ "$(cat "$t/rsync.n")" = 2 ]
ok grep -q 'removed notes/.build/App.app from the mirror' <<<"$out"; ok grep -q 'removed notes/App.xcodeproj/xcshareddata from the mirror' <<<"$out"; ok grep -q 'retrying the mirror (attempt 2 of 3)' <<<"$out"
ok [ ! -e "$root/dev/notes/.build" ]; ok [ -f "$root/dev/notes/a.txt" ]; ok [ -f "$root/escape-canary" ]
ok grep -q '"exit":0' "$root/LAST_RUN.json"
mkdir -p "$root/dev/notes/.build/App.app"; rm -f "$t/rsync.n"
FAILS=9 DEV_BACKUP_RSYNC="$t/rsync-once" run
ok [ "$rc" = 1 ]; ok [ "$(cat "$t/rsync.n")" = 2 ]   # nothing left to fix: no third run; ok grep -q '"exit":1' "$root/LAST_RUN.json"
printf '#!/bin/sh\necho "rsync: error: something else" >&2; exit 23\n' > "$t/rsync-other"; chmod +x "$t/rsync-other"
DEV_BACKUP_RSYNC="$t/rsync-other" run; ok [ "$rc" = 23 ]; ok bash -c '! grep -q retrying <<<"$1"' _ "$out"

# Evicted mirror files (dataless; the tests use the user-settable `hidden` flag instead) that
# changed in ~/dev, or are gone from it, are removed before rsync, which cannot read them back
# under launchd (EDEADLK, one file per run); an unchanged evicted file is left as it is.
echo same > "$HOME/dev/notes/same.txt"; echo v1 > "$HOME/dev/notes/changed.txt"; echo old > "$HOME/dev/notes/gone.txt"
run; ok [ "$rc" = 0 ]
chflags hidden "$root/dev/notes/same.txt" "$root/dev/notes/changed.txt" "$root/dev/notes/gone.txt"
echo v2-longer > "$HOME/dev/notes/changed.txt"; rm "$HOME/dev/notes/gone.txt"
DEV_BACKUP_EVICTED_FLAG=hidden run; ok [ "$rc" = 0 ]
ok grep -q 'removed 2 evicted mirror file(s)' <<<"$out"
ok [ "$(cat "$root/dev/notes/changed.txt")" = v2-longer ]; ok [ ! -e "$root/dev/notes/gone.txt" ]
ok bash -c '/bin/ls -lO "$1" | grep -q hidden' _ "$root/dev/notes/same.txt"   # untouched
# Every evicted file gone from ~/dev (nothing to compare against): all removed.
chflags hidden "$root/dev/notes/changed.txt"; rm -rf "$HOME/dev/notes/changed.txt" "$HOME/dev/notes/same.txt"
DEV_BACKUP_EVICTED_FLAG=hidden run; ok [ "$rc" = 0 ]; ok grep -q 'removed 2 evicted mirror file(s)' <<<"$out"

# A listed file that is gone by the time tar runs (Night Shift writes under ~/dev during the
# run) is left out of the archive, not fatal (review r3, N2): bsdtar exits 1 with "Cannot
# stat", the archive is still written. Any other tar error still fails the archive (status 4)
# and keeps the previous one.
printf 'S=1\n' > "$HOME/dev/notes/.env"; printf 'S=2\n' > "$HOME/dev/notes/vanish.env"
cat > "$t/tar-vanish" <<EOF
#!/bin/sh
rm -f "$HOME/dev/notes/vanish.env"; exec tar "\$@"
EOF
printf '#!/bin/sh\necho "tar: notes/.env: Cannot open: Permission denied" >&2; echo "tar: Error exit delayed from previous errors." >&2; exit 1\n' > "$t/tar-denied"
chmod +x "$t/tar-vanish" "$t/tar-denied"
rm -f "$root/dev-secrets.tar.age"
DEV_BACKUP_TAR="$t/tar-vanish" run; ok [ "$rc" = 0 ]; ok grep -q 'secret files (encrypted), 1 gone since the scan' <<<"$out"
ok grep -q '"exit":0' "$root/LAST_RUN.json"
ok bash -c 'age -d -i "$1" "$2" | tar -tzf - | grep -qx notes/.env' _ "$keys" "$root/dev-secrets.tar.age"
cp "$root/dev-secrets.tar.age" "$t/archive.before"; printf 'S=3\n' > "$HOME/dev/notes/vanish.env"
DEV_BACKUP_TAR="$t/tar-denied" run; ok [ "$rc" = 4 ]; ok grep -q 'secret archive failed' <<<"$out"
ok grep -q 'Permission denied' <<<"$out"; ok cmp -s "$t/archive.before" "$root/dev-secrets.tar.age"
ok [ ! -e "$root/.dev-secrets.tar.age.tmp" ]

(( fail == 0 )) && echo "ok dev-icloud-backup-edges"
exit "$fail"
