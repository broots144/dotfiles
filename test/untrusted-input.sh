#!/usr/bin/env bash
# Repo contents and REPL values are data: the prompt, git-wtf, irbrc and `dot -p` must not
# execute them or publish files nobody chose to track.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
fail=0; no() { [[ ! -e "$1" ]] || { echo "FAIL: $2"; fail=1; }; }

# Prompt: a checked-out bare-repo-shaped directory whose config names an fsmonitor hook.
mkdir -p "$t/clone"; git init -q --bare "$t/clone/evil.git"
git -C "$t/clone/evil.git" config core.bare false
git -C "$t/clone/evil.git" config core.worktree ..
git -C "$t/clone/evil.git" config core.fsmonitor "touch $t/pwned-prompt; false"
(cd "$t/clone/evil.git" && zsh -fc "source $here/zsh/prompt.zsh; git_dirty; need_push" >/dev/null 2>&1) || true
no "$t/pwned-prompt" "prompt ran core.fsmonitor from an untrusted repo"

# Prompt: a repo-local filter driver must not run when the prompt checks for changes.
G() { git -c user.email=t@example.invalid -c user.name=t -c core.hooksPath=/dev/null "$@"; }
G init -q "$t/filt"; echo a > "$t/filt/f"; echo '* filter=x.y' > "$t/filt/.gitattributes"
G -C "$t/filt" add .; G -C "$t/filt" commit -qm i
git -C "$t/filt" config filter.x.y.clean "touch $t/pwned-filter; cat"
git -C "$t/filt" config filter.x.y.required true
touch -t 200001010000 "$t/filt/f"
out="$(cd "$t/filt" && zsh -fc "source $here/zsh/prompt.zsh; git_dirty" 2>/dev/null)" || true
no "$t/pwned-filter" "prompt ran a repo-local filter driver"
[[ "$out" == *main* || "$out" == *master* ]] || { echo "FAIL: prompt lost the branch in a filtered repo"; fail=1; }
# ... including a driver whose name holds '=' (a `-c filter.x=y.clean=` override would split).
G init -q "$t/filt2"; echo a > "$t/filt2/f"; echo '* filter=x=y' > "$t/filt2/.gitattributes"
G -C "$t/filt2" add .; G -C "$t/filt2" commit -qm i
git -C "$t/filt2" config 'filter.x=y.clean' "touch $t/pwned-filter2; cat"
touch -t 200001010000 "$t/filt2/f"
(cd "$t/filt2" && zsh -fc "source $here/zsh/prompt.zsh; git_dirty" >/dev/null 2>&1) || true
no "$t/pwned-filter2" "prompt ran a repo-local filter driver named with '='"

# Prompt (need_push too): no repo-local textconv, external diff, fsmonitor, hook or lazy-fetch
# transport command may run. The promisor remote points origin/main at a missing object.
G init -q -b main "$t/np"; echo a > "$t/np/f"; echo '* diff=tc' > "$t/np/.gitattributes"
G -C "$t/np" add .; G -C "$t/np" commit -qm i; echo b >> "$t/np/f"; G -C "$t/np" commit -qam two
git -C "$t/np" config core.repositoryformatversion 1
git -C "$t/np" config extensions.partialClone origin
git -C "$t/np" config remote.origin.url ssh://example.invalid/x
git -C "$t/np" config remote.origin.promisor true
git -C "$t/np" config core.sshCommand "touch $t/pwned-np-ssh; false"
git -C "$t/np" config diff.tc.textconv "touch $t/pwned-np-tc; cat"
git -C "$t/np" config diff.external "touch $t/pwned-np-ext; true"
git -C "$t/np" config core.fsmonitor "touch $t/pwned-np-fsm; false"
mkdir -p "$t/np/.git/refs/remotes/origin"
echo 1111111111111111111111111111111111111111 > "$t/np/.git/refs/remotes/origin/main"
out="$(cd "$t/np" && zsh -fc "source $here/zsh/prompt.zsh; git_dirty; need_push" 2>/dev/null)" || true
for w in ssh tc ext fsm; do no "$t/pwned-np-$w" "prompt ran repo-local $w command"; done
[[ "$out" == *main* ]] || { echo "FAIL: prompt lost the branch in the need_push fixture"; fail=1; }

# git-wtf: branch names from a clone are argv words, not shell text.
G init -q -b 'main;touch${IFS}pwned-wtf' "$t/wtfsrc"; G -C "$t/wtfsrc" commit -q --allow-empty -m i
git clone -q "$t/wtfsrc" "$t/wtf" 2>/dev/null; G -C "$t/wtf" commit -q --allow-empty -m two
(cd "$t/wtf" && /usr/bin/ruby "$here/bin/git-wtf" >/dev/null 2>&1) || true
no "$t/wtf/pwned-wtf" "git-wtf ran a branch name through the shell"

# ge: untracked file names reach the editor as single path arguments, never as options.
G init -q "$t/ge"; touch "$t/ge/--command=x" "$t/ge/a b"
printf '#!/bin/sh\nfor a; do printf "%%s\\n" "$a"; done\n' > "$t/ed"; chmod +x "$t/ed"
args="$(cd "$t/ge" && EDITOR="$t/ed" "$here/bin/git-edit-new")"
[[ "$args" == $'./--command=x\n./a b' ]] || { echo "FAIL: ge passed file names as options or split them"; fail=1; }

# git-wtf: a .git-wtfrc must not instantiate arbitrary Ruby objects.
printf -- "--- !ruby/object:Gem::Requirement\nrequirements: []\n" > "$t/rc"
/usr/bin/ruby -ryaml -e "$(sed -n 's/.*(h = \(YAML[^)]*([^)]*)\)).*/x = \1/p' "$here/bin/git-wtf" | sed 's/fn/ARGV[0]/')" "$t/rc" 2>/dev/null \
  && { echo "FAIL: git-wtf config loads Ruby objects"; fail=1; }

# irbrc cop: the copied value is data for pbcopy, not shell text.
mkdir "$t/bin"; printf '#!/bin/sh\ncat >/dev/null\n' > "$t/bin/pbcopy"; chmod +x "$t/bin/pbcopy"
PATH="$t/bin:$PATH" /usr/bin/ruby -e '
  module IRB; def self.CurrentContext; Struct.new(:last_value).new(ARGV[0]); end; end
  eval(File.read(ARGV[1])[/^def cop.*?^end/m]); cop' "x'; touch $t/pwned-irb; echo '" "$here/ruby/irbrc.symlink" >/dev/null 2>&1 || true
no "$t/pwned-irb" "irbrc cop ran shell text from the last value"

# dot -p: an untracked file must not be committed.
git init -q --bare "$t/up.git"; git clone -q "$t/up.git" "$t/dots" 2>/dev/null
mkdir "$t/dots/bin"; touch "$t/dots/Brewfile"; cp "$here/bin/dot" "$t/dots/bin/dot"
( cd "$t/dots"; git config user.email t@example.invalid; git config user.name t
  git checkout -q -b master; git add -A; git commit -qm init >/dev/null 2>&1; git push -q -u origin master >/dev/null 2>&1
  echo secret > .env.new; echo changed >> bin/dot
  printf '#!/bin/sh\nfor a; do case "$a" in --file=*) touch "${a#--file=}";; esac; done\nexit 0\n' > "$t/bin/brew"; chmod +x "$t/bin/brew"
  PATH="$t/bin:$PATH" sh bin/dot -p >/dev/null 2>&1 || true )
git -C "$t/up.git" ls-tree -r --name-only master | grep -qx .env.new && { echo "FAIL: dot -p pushed an untracked file"; fail=1; }
git -C "$t/up.git" log -1 --format=%s master | grep -qx "Auto sync and push" || { echo "FAIL: dot -p did not push tracked changes"; fail=1; }

# dot -p: a live *.symlink config change (what `git config --global` writes) is not published
# unattended, and credential-shaped additions stop the run.
( cd "$t/dots"; git pull -q 2>/dev/null; printf '[user]\n' > gitconfig.symlink; git add gitconfig.symlink
  git commit -qm cfg >/dev/null 2>&1; git push -q >/dev/null 2>&1
  printf '[http]\n  extraheader = X\n' >> gitconfig.symlink; echo more >> bin/dot
  PATH="$t/bin:$PATH" sh bin/dot -p >/dev/null 2>&1 </dev/null || true )
git -C "$t/up.git" show master:gitconfig.symlink | grep -q extraheader && { echo "FAIL: dot -p published a live config change"; fail=1; }
( cd "$t/dots"; git checkout -q -- gitconfig.symlink; echo 'url = https://u:tok@example.invalid' >> bin/dot
  PATH="$t/bin:$PATH" sh bin/dot -p >/dev/null 2>&1 </dev/null || true )
git -C "$t/up.git" show master:bin/dot | grep -q 'u:tok@' && { echo "FAIL: dot -p published a credential-shaped line"; fail=1; }

# dev-pull (launchd, every 20 min, every checkout under ~/dev): repo-local config must not run
# a command through the transport (uploadpack on a local upstream, ext::), hooks on the merge,
# a filter driver on the checkout, or a worktree outside the repo. Local upstreams need
# DEV_PULL_ALLOW_FILE=1 (the tests' hook), so the hook and filter cases use it; the transport
# cases are checked both ways.
dp() { HOME="$t/dp" ZSH="$here" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t" \
  DEV_PULL_GH=/usr/bin/false "$here/bin/dev-pull" 2>&1 || true; }
dpup() {  # <name>: upstream $t/dpup/<name> one commit ahead of the clone $t/dp/dev/<name>
  G init -q -b main "$t/dpup/$1"; echo a > "$t/dpup/$1/f"; G -C "$t/dpup/$1" add f; G -C "$t/dpup/$1" commit -qm i
  git clone -q "$t/dpup/$1" "$t/dp/dev/$1"; echo b >> "$t/dpup/$1/f"; G -C "$t/dpup/$1" commit -qam two
}
mkdir -p "$t/dp/dev" "$t/dpup"
dpup upl; git -C "$t/dp/dev/upl" config remote.origin.uploadpack "touch $t/pwned-dp-upl; git-upload-pack"
dpup ext; git -C "$t/dp/dev/ext" remote set-url origin "ext::sh -c touch% $t/pwned-dp-ext"
dpup hook; mkdir "$t/hooks"
printf '#!/bin/sh\ntouch %s/pwned-dp-hook\n' "$t" | tee "$t/hooks/post-merge" > "$t/dp/dev/hook/.git/hooks/post-merge"
chmod +x "$t/hooks/post-merge" "$t/dp/dev/hook/.git/hooks/post-merge"
dpup hook2; git -C "$t/dp/dev/hook2" config core.hooksPath "$t/hooks"
dpup filt; git -C "$t/dp/dev/filt" config filter.x.smudge "touch $t/pwned-dp-filt; cat"
echo '* filter=x' > "$t/dpup/filt/.gitattributes"; echo c > "$t/dpup/filt/g"; G -C "$t/dpup/filt" add .; G -C "$t/dpup/filt" commit -qm attrs
dpup wt; mkdir "$t/elsewhere"; git -C "$t/dp/dev/wt" config core.worktree "$t/elsewhere"
dpup push; git -C "$t/dp/dev/push" config remote.origin.pushurl "$t/elsewhere.git"
dpup insteadof; git -C "$t/dp/dev/insteadof" config url."ext::sh -c touch% $t/pwned-dp-url% #".insteadOf "$t/dpup/"
out=$(dp)
for w in upl ext hook filt url; do no "$t/pwned-dp-$w" "dev-pull ran repo-local $w command (no file transport)"; done
grep -q "origin not on GitHub or trusted-origins, skipped: hook" <<<"$out" || { echo "FAIL: dev-pull fetched a local-path origin"; fail=1; }
out=$(DEV_PULL_ALLOW_FILE=1 dp)
for w in upl ext hook filt url; do no "$t/pwned-dp-$w" "dev-pull ran repo-local $w command"; done
[[ "$(git -C "$t/dp/dev/hook" log -1 --format=%s)" == two && "$(git -C "$t/dp/dev/hook2" log -1 --format=%s)" == two ]] \
  || { echo "FAIL: dev-pull did not fast-forward the hook fixtures"; fail=1; }
for c in "upl (remote.origin.uploadpack)" "filt (filter.x.smudge)" "wt (core.worktree)" "push (remote.origin.pushurl)"; do
  grep -qF "repo-local git config can run commands (${c#* (}" <<<"$(grep -F ": ${c%% *}" <<<"$out")" \
    || { echo "FAIL: dev-pull did not skip ${c%% *}"; fail=1; }
done
[[ -z "$(ls -A "$t/elsewhere")" ]] || { echo "FAIL: dev-pull checked out into core.worktree"; fail=1; }
grep -q "skipped: ext" <<<"$out" || { echo "FAIL: dev-pull fetched an ext:: origin"; fail=1; }
grep -q "skipped: insteadof" <<<"$out" || { echo "FAIL: dev-pull followed a repo-local url.insteadOf"; fail=1; }
grep -q ', 6 skipped' <<<"$out" || { echo "FAIL: dev-pull skip count ($out)"; fail=1; }

# dev-pull and submodules (review r2 N1): status and fetch must not run anything from a
# submodule's own config. Absorbed submodule (.git/modules/<name>/config): the repo is skipped
# as unsafe. Non-absorbed one (sub/.git/config, not scanned): status must not descend into it
# (a clean filter would run) and fetch must not recurse into it (credential helper, transport).
dps() { HOME="$t/dps" ZSH="$here" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t" \
  DEV_PULL_GH=/usr/bin/false DEV_PULL_ALLOW_FILE=1 "$here/bin/dev-pull" 2>&1 || true; }
Gf() { G -c protocol.file.allow=always "$@"; }
mkdir -p "$t/dps/dev" "$t/dpsup"
G init -q -b main "$t/dpsup/sub"; echo a > "$t/dpsup/sub/f"; echo '* filter=x' > "$t/dpsup/sub/.gitattributes"
G -C "$t/dpsup/sub" add .; G -C "$t/dpsup/sub" commit -qm i
for s in abs nab; do
  G init -q -b main "$t/dpsup/$s"; echo a > "$t/dpsup/$s/f"; G -C "$t/dpsup/$s" add f
  Gf -C "$t/dpsup/$s" submodule -q add "$t/dpsup/sub" sub 2>/dev/null; G -C "$t/dpsup/$s" commit -qm i
done
Gf clone -q --recurse-submodules "$t/dpsup/abs" "$t/dps/dev/abs" 2>/dev/null
Gf clone -q --recurse-submodules "$t/dpsup/abs" "$t/dps/dev/absok" 2>/dev/null   # git's own core.worktree only
git -C "$t/dps/dev/abs/sub" config filter.x.clean "touch $t/pwned-dps-abs; cat"
git clone -q "$t/dpsup/nab" "$t/dps/dev/nab"; G -C "$t/dps/dev/nab" submodule -q init
rmdir "$t/dps/dev/nab/sub"; git clone -q "$t/dpsup/sub" "$t/dps/dev/nab/sub"
git -C "$t/dps/dev/nab/sub" config filter.x.clean "touch $t/pwned-dps-nab; cat"
touch -t 200001010000 "$t/dps/dev/abs/sub/f" "$t/dps/dev/nab/sub/f"
echo b >> "$t/dpsup/sub/f"; G -C "$t/dpsup/sub" commit -qam two; new_sub=$(git -C "$t/dpsup/sub" rev-parse HEAD)
Gf -C "$t/dpsup/nab" submodule -q update --remote sub 2>/dev/null; G -C "$t/dpsup/nab" commit -qam bump
out=$(dps)
no "$t/pwned-dps-abs" "dev-pull ran a filter from an absorbed submodule's config"
no "$t/pwned-dps-nab" "dev-pull ran a filter from a submodule's config (status descended)"
grep -q "repo-local git config can run commands (filter.x.clean in submodule sub), skipped: abs" <<<"$out" \
  || { echo "FAIL: dev-pull did not skip a repo whose submodule config names a filter ($out)"; fail=1; }
grep -q "skipped: absok" <<<"$out" && { echo "FAIL: dev-pull skipped a plain absorbed submodule ($out)"; fail=1; }
grep -q ", 1 skipped" <<<"$out" || { echo "FAIL: dev-pull submodule skip count ($out)"; fail=1; }
git -C "$t/dps/dev/nab/sub" cat-file -e "$new_sub" 2>/dev/null && { echo "FAIL: dev-pull fetch recursed into a submodule"; fail=1; }
[[ "$(git -C "$t/dps/dev/nab" log -1 --format=%s)" == bump ]] || { echo "FAIL: dev-pull did not fast-forward the submodule superproject ($out)"; fail=1; }

# dev-pull and the origin remote (review 2026-11-07 r3, N1). `git push origin` pushes to every
# remote.origin.url when no pushurl is set, so a planted second url would get the WIP snapshot:
# the repo is unsafe and skipped. A planted remote.origin.fetch mapping onto refs/heads must
# not force-update or (with --prune) delete local branches: dev-pull fetches with its own
# refspecs and --refmap= , never the configured ones.
dpn() { HOME="$t/dpn" ZSH="$here" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$t" \
  DEV_PULL_GH="$t/gh-private" DEV_PULL_GITLEAKS="$t/leaks-ok" DEV_PULL_OWN_RE='/dpnup/' DEV_PULL_ALLOW_FILE=1 \
  "$here/bin/dev-pull" 2>&1 || true; }
printf '#!/bin/sh\necho true\n' > "$t/gh-private"; printf '#!/bin/sh\nexit 0\n' > "$t/leaks-ok"; chmod +x "$t/gh-private" "$t/leaks-ok"
mkdir -p "$t/dpn/dev" "$t/dpnup"
for s in two fmap; do
  G init -q -b main "$t/dpnup/$s"; echo a > "$t/dpnup/$s/f"; G -C "$t/dpnup/$s" add f; G -C "$t/dpnup/$s" commit -qm i
  git clone -q "$t/dpnup/$s" "$t/dpn/dev/$s"; echo b >> "$t/dpnup/$s/f"; G -C "$t/dpnup/$s" commit -qam two
done
G -C "$t/dpnup/fmap" branch other   # a single-branch clone stays narrow (only safe configured refspecs kept)
git clone -q --single-branch "$t/dpnup/fmap" "$t/dpn/dev/narrow"
G init -q --bare "$t/stolen.git"
git -C "$t/dpn/dev/two" config --add remote.origin.url "$t/stolen.git"; echo dirty >> "$t/dpn/dev/two/f"
keep0=$(git -C "$t/dpn/dev/fmap" rev-parse HEAD)
G -C "$t/dpnup/fmap" update-ref refs/wip/book HEAD   # the other host's snapshot still arrives
git -C "$t/dpn/dev/fmap" branch keep; git -C "$t/dpn/dev/fmap" branch mine/work
git -C "$t/dpn/dev/fmap" config --add remote.origin.fetch '+refs/heads/main:refs/heads/keep'
git -C "$t/dpn/dev/fmap" config --add remote.origin.fetch '+refs/heads/gone/*:refs/heads/mine/*'
out=$(dpn)
[[ -z "$(git -C "$t/stolen.git" for-each-ref)" ]] || { echo "FAIL: dev-pull pushed a WIP snapshot to a second remote.origin.url"; fail=1; }
grep -q "repo-local git config can run commands (remote.origin.url, 2 urls), skipped: two" <<<"$out" \
  || { echo "FAIL: dev-pull did not skip a repo with two origin urls ($out)"; fail=1; }
[[ "$(git -C "$t/dpn/dev/fmap" rev-parse keep)" == "$keep0" ]] || { echo "FAIL: dev-pull fetch force-updated a local branch through a planted refspec"; fail=1; }
git -C "$t/dpn/dev/fmap" rev-parse -q --verify refs/heads/mine/work >/dev/null || { echo "FAIL: dev-pull fetch --prune deleted a local branch through a planted refspec"; fail=1; }
git -C "$t/dpn/dev/fmap" rev-parse -q --verify refs/wip/book >/dev/null || { echo "FAIL: dev-pull did not fetch refs/wip/* of an own repo"; fail=1; }
git -C "$t/dpn/dev/narrow" rev-parse -q --verify refs/remotes/origin/other >/dev/null && { echo "FAIL: dev-pull widened a single-branch clone's fetch"; fail=1; }
[[ "$(git -C "$t/dpn/dev/fmap" log -1 --format=%s)" == two ]] || { echo "FAIL: dev-pull did not fast-forward fmap ($out)"; fail=1; }

(( fail == 0 )) && echo "ok untrusted-input"
exit "$fail"
