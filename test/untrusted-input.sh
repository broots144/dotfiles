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
  printf '#!/bin/sh\n[ "$1" = bundle ] && touch Brewfile\nexit 0\n' > "$t/bin/brew"; chmod +x "$t/bin/brew"
  PATH="$t/bin:$PATH" sh bin/dot -p >/dev/null 2>&1 || true )
git -C "$t/up.git" ls-tree -r --name-only master | grep -qx .env.new && { echo "FAIL: dot -p pushed an untracked file"; fail=1; }
git -C "$t/up.git" log -1 --format=%s master | grep -qx "Auto sync and push" || { echo "FAIL: dot -p did not push tracked changes"; fail=1; }

(( fail == 0 )) && echo "ok untrusted-input"
exit "$fail"
