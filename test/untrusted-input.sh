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

(( fail == 0 )) && echo "ok untrusted-input"
exit "$fail"
