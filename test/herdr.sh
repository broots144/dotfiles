#!/usr/bin/env bash
# herdr (D-010, D-011): the tracked config is valid and keeps the safe settings, herdr/install.sh
# links it into an owner-only ~/.config/herdr, bin/herdr-server tightens that directory and
# waits for a hand-started server, the LaunchAgent restarts it after a crash, and no shell file
# auto-attaches tmux inside a herdr pane (herdr docs: agents.mdx, guard with HERDR_ENV).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
fail() { local m="FAIL herdr: $*"; m="${m//$HOME/~}"; echo "${m//$(id -un)/<user>}" >&2; exit 1; }
mode() { stat -f %Lp "$1"; }

cfg="$here/herdr/config.toml"

# 1. The config parses with the installed herdr, when there is one (CI installs it).
if command -v herdr >/dev/null 2>&1; then
  HERDR_CONFIG_PATH="$cfg" herdr config check >/dev/null || fail "herdr config check rejects herdr/config.toml"
  printf 'onboarding = [\n' > "$t/bad.toml"
  if HERDR_CONFIG_PATH="$t/bad.toml" herdr config check >/dev/null 2>&1; then
    fail "herdr config check passed a broken file, so check 1 proves nothing"
  fi
fi

# 2. Settings that keep secrets off disk and the binary on its pin.
want() { grep -Eq "^$1 *= *$2\$" "$cfg" || fail "config.toml must set $1 = $2"; }
want pane_history false
want allow_nested false
want version_check false
want manifest_check false
want delivery '"terminal"'

# 3. install.sh: owner-only dir, link to the tracked file, an old file kept, idempotent. No real
#    brew or hook: the test must not re-pin or patch the host (code review 2026-11-08).
home="$t/home"; mkdir -p "$home/.config/herdr"; chmod 755 "$home/.config/herdr"
echo "old = 1" > "$home/.config/herdr/config.toml"
out="$(HOME="$home" ZSH="$here" HERDR_BREW=/nonexistent HERDR_CLAUDE_HOOK=/nonexistent sh "$here/herdr/install.sh")"
[[ "$(mode "$home/.config/herdr")" == 700 ]] || fail "install.sh left ~/.config/herdr at $(mode "$home/.config/herdr")"
[[ -L "$home/.config/herdr/config.toml" ]] || fail "install.sh did not link config.toml"
[[ "$(readlink "$home/.config/herdr/config.toml")" == "$here/herdr/config.toml" ]] || fail "config.toml links elsewhere"
grep -q "old = 1" "$home/.config/herdr/config.toml.pre-dotfiles" || fail "the old config was not kept"
[[ "$out" == *linked* ]] || fail "install.sh said: $out"
out="$(HOME="$home" ZSH="$here" HERDR_BREW=/nonexistent HERDR_CLAUDE_HOOK=/nonexistent sh "$here/herdr/install.sh")"
[[ "$out" == *"already linked"* ]] || fail "second install.sh run was not a no-op: $out"

# 4. bin/herdr-server: 0700 dirs, waits while another server runs, then execs `herdr server`.
cat > "$t/herdr" <<S
#!/bin/sh
echo "\$*" >> "$t/calls"
case "\$*" in
  "status server") n=\$(cat "$t/n" 2>/dev/null || echo 0); echo \$((n + 1)) > "$t/n"
    [ "\$n" -lt 2 ] && echo "status: running" || echo "status: not running" ;;
  --version) echo "herdr 0.0.0" ;;
  server) echo "served" ;;
esac
S
chmod +x "$t/herdr"
mkdir -p "$t/h2/.config/herdr/sessions"; chmod 755 "$t/h2/.config/herdr" "$t/h2/.config/herdr/sessions"
out="$(HOME="$t/h2" HERDR_BIN="$t/herdr" HERDR_SERVER_WAIT_S=0 /bin/bash "$here/bin/herdr-server")"
[[ "$(mode "$t/h2/.config/herdr")" == 700 ]] || fail "herdr-server left the dir at $(mode "$t/h2/.config/herdr")"
[[ "$(mode "$t/h2/.config/herdr/sessions")" == 700 ]] || fail "herdr-server left sessions/ open"
[[ "$(grep -c '^status server$' "$t/calls")" == 3 ]] || fail "herdr-server did not wait for the running server"
[[ "$(tail -1 "$t/calls")" == server ]] || fail "herdr-server did not exec herdr server last"
[[ "$out" == *served* ]] || fail "herdr-server output: $out"

# 4a. ...as a session leader (herdr --remote would offer to restart it otherwise), from a launchd
#     job that stays the parent, forwards TERM and exits with the server's status (D-017).
cat > "$t/herdr-sess" <<'S'
#!/bin/sh
case "$*" in
  "status server") echo "status: not running" ;;
  --version) echo "herdr 0.0.0" ;;
  server) # python runs as a child of this shell: its parent must be the session leader
    python3 -c 'import os; print("leader", os.getsid(0) == os.getppid())'
    [ -n "$WAIT_TERM" ] && { trap 'echo got TERM >> "$WAIT_TERM"; exit 0' TERM; : > "$WAIT_TERM.up"; while :; do sleep 0.1; done; }
    exit 3 ;;
esac
S
chmod +x "$t/herdr-sess"
set +e; out="$(HOME="$t/h2" HERDR_BIN="$t/herdr-sess" HERDR_SERVER_WAIT_S=0 HERDR_STATE_DIR="$t/st0" /bin/bash "$here/bin/herdr-server")"; rc=$?; set -e
[[ "$out" == *"leader True"* ]] || fail "the server is not a session leader: $out"
[[ $rc == 3 ]] || fail "herdr-server did not exit with the server's status ($rc)"
HOME="$t/h2" HERDR_BIN="$t/herdr-sess" HERDR_SERVER_WAIT_S=0 HERDR_STATE_DIR="$t/st0" WAIT_TERM="$t/term" /bin/bash "$here/bin/herdr-server" >/dev/null & sp=$!
for _ in $(seq 50); do [[ -e "$t/term.up" ]] && break; sleep 0.1; done
kill -TERM "$sp"; set +e; wait "$sp"; rc=$?; set -e
grep -q "got TERM" "$t/term" || fail "herdr-server did not forward TERM to the server"
[[ $rc == 0 ]] || fail "a clean stop after TERM exited $rc"

# 4b. ...and drops a remote agent-detection cache before starting (D-012), leaving the rest.
mkdir -p "$t/st/agent-detection/remote" "$t/st/agent-detection/local"
touch "$t/st/agent-detection/remote/claude.toml" "$t/st/agent-detection/status.toml"
: > "$t/calls"; echo 2 > "$t/n"
HOME="$t/h2" HERDR_BIN="$t/herdr" HERDR_SERVER_WAIT_S=0 HERDR_STATE_DIR="$t/st" /bin/bash "$here/bin/herdr-server" >/dev/null
[[ ! -e "$t/st/agent-detection/remote" && ! -e "$t/st/agent-detection/status.toml" ]] || fail "remote rule cache left in place"
[[ -d "$t/st/agent-detection/local" ]] || fail "herdr-server removed more than the remote cache"

# 4c. ...even when the cache is refilled while it waits for a hand-started server (audit run-6).
: > "$t/calls"; echo 0 > "$t/n"; rm -rf "$t/st"; mkdir -p "$t/st/agent-detection"
cat > "$t/herdr-refill" <<S
#!/bin/sh
case "\$*" in
  "status server") n=\$(cat "$t/n"); echo \$((n + 1)) > "$t/n"
    mkdir -p "$t/st/agent-detection/remote"; touch "$t/st/agent-detection/remote/claude.toml"
    [ "\$n" -lt 2 ] && echo "status: running" || echo "status: not running" ;;
  --version) echo "herdr 0.0.0" ;;
  server) [ -e "$t/st/agent-detection/remote" ] && echo "CACHE PRESENT AT EXEC" || echo "clean at exec" ;;
esac
S
chmod +x "$t/herdr-refill"
out="$(HOME="$t/h2" HERDR_BIN="$t/herdr-refill" HERDR_SERVER_WAIT_S=0 HERDR_STATE_DIR="$t/st" /bin/bash "$here/bin/herdr-server")"
[[ "$out" == *"clean at exec"* ]] || fail "a cache refilled during the wait reached the server: $out"

# 4d. herdr/install.sh pins herdr in Homebrew on every Mac (D-010), and fails loudly when the
#     installed version is not herdr/VERSION (audit run-7), without aborting `dot` (code review). The version is the binary's own, not
#     the keg name, which carries Homebrew revisions (0.9.5_1; code review 2026-11-08).
cat > "$t/brew" <<S
#!/bin/sh
echo "\$*" >> "$t/brew-calls"
case "\$*" in "list --versions herdr") echo "herdr \${FAKE_HERDR_VERSION}_1" ;; --prefix) echo "$t/bp" ;; esac
exit 0
S
mkdir -p "$t/bp/opt/herdr/bin"; printf '#!/bin/sh\necho "herdr $FAKE_HERDR_VERSION"\n' > "$t/bp/opt/herdr/bin/herdr"
chmod +x "$t/brew" "$t/bp/opt/herdr/bin/herdr"
FAKE_HERDR_VERSION="$(cat "$here/herdr/VERSION")" HOME="$t/h3" ZSH="$here" HERDR_BREW="$t/brew" HERDR_CLAUDE_HOOK=/nonexistent sh "$here/herdr/install.sh" >/dev/null \
  || fail "install.sh failed with the pinned version installed"
grep -qx "pin herdr" "$t/brew-calls" || fail "install.sh did not brew pin herdr"
set +e; err="$(FAKE_HERDR_VERSION=9.9.9 HOME="$t/h3" ZSH="$here" HERDR_BREW="$t/brew" HERDR_CLAUDE_HOOK=/nonexistent sh "$here/herdr/install.sh" 2>&1 >/dev/null)"; rc=$?; set -e
[[ $rc -eq 0 && "$err" == *"WARNING: installed 9.9.9, but herdr/VERSION pins"* ]] || fail "install.sh must warn about a herdr that is not the pin, and not abort dot ($rc)"

# 4e. install.sh puts herdr's Claude hook in isolated mode, so a json.py in the session's cwd
#     is not imported (audit run-7); idempotent.
cp "$here/test/fixtures/herdr-agent-state.sh" "$t/hook.sh"
mkdir -p "$t/hk/mod"; echo 'import sys; open(sys.argv[0] if False else "'"$t"'/hk/PWNED","w").write("x")' > "$t/hk/mod/json.py"
HOME="$t/h4" ZSH="$here" HERDR_BREW=/nonexistent HERDR_CLAUDE_HOOK="$t/hook.sh" sh "$here/herdr/install.sh" >/dev/null
HOME="$t/h4" ZSH="$here" HERDR_BREW=/nonexistent HERDR_CLAUDE_HOOK="$t/hook.sh" sh "$here/herdr/install.sh" >/dev/null
[[ "$(grep -c 'python3 -I - <<' "$t/hook.sh")" == 1 ]] || fail "hook not patched to python3 -I exactly once"
(cd "$t/hk/mod" && echo '{}' | HERDR_ENV=1 HERDR_SOCKET_PATH=/nonexistent HERDR_PANE_ID=w1:p1 bash "$t/hook.sh" session) || true
[[ ! -e "$t/hk/PWNED" ]] || fail "the patched hook still imported json.py from the session cwd"

# 4e2. The patch fails loudly, and leaves no temp file, when it cannot rewrite the hook or the
#      hook's python line matches neither form (code review 2026-11-08).
printf '#!/bin/sh\nHERDR_ACTION=x python3 -u - <<PY\nPY\n' > "$t/odd-hook.sh"
set +e; err="$(HERDR_CLAUDE_HOOK="$t/odd-hook.sh" sh "$here/herdr/patch-claude-hook.sh" 2>&1)"; rc=$?; set -e
[[ $rc == 1 && "$err" == *"WARNING"* ]] || fail "an unknown hook shape passed silently ($rc)"
mkdir -p "$t/ro"; cp "$here/test/fixtures/herdr-agent-state.sh" "$t/ro/hook.sh"; chmod 555 "$t/ro"
set +e; err="$(HERDR_CLAUDE_HOOK="$t/ro/hook.sh" sh "$here/herdr/patch-claude-hook.sh" 2>&1)"; rc=$?; set -e
chmod 755 "$t/ro"
[[ $rc == 1 ]] || fail "a failed rewrite exited $rc"
[[ "$(ls "$t/ro")" == hook.sh ]] || fail "a failed rewrite left a temp file"
HERDR_CLAUDE_HOOK=/nonexistent sh "$here/herdr/patch-claude-hook.sh" || fail "a missing hook is not an error"

# 4f. On n0 a bare `herdr` starts the LaunchAgent's server first instead of its own (audit run-7).
mkdir -p "$t/z/bin" "$t/z/home/Library/LaunchAgents"; touch "$t/z/home/Library/LaunchAgents/com.broots.herdr-server.plist"
cat > "$t/z/bin/herdr" <<S
#!/bin/sh
echo "herdr \$*" >> "$t/z/calls"
case "\$*" in "status server") [ -e "$t/z/up" ] && echo "status: running" || echo "status: not running" ;; esac
S
cat > "$t/z/bin/launchctl" <<S
#!/bin/sh
echo "launchctl \$*" >> "$t/z/calls"; touch "$t/z/up"
S
chmod +x "$t/z/bin/herdr" "$t/z/bin/launchctl"
HOME="$t/z/home" PATH="$t/z/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr"
grep -q "^launchctl kickstart gui/.*/com.broots.herdr-server" "$t/z/calls" || fail "bare herdr did not start the LaunchAgent"
[[ "$(tail -1 "$t/z/calls")" == "herdr " ]] || fail "bare herdr did not attach after the LaunchAgent started"
: > "$t/z/calls"; HOME="$t/z/home" PATH="$t/z/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr pane list"
! grep -q launchctl "$t/z/calls" || fail "herdr with arguments touched launchd"
: > "$t/z/calls"; set +e
err="$(HOME="$t/z/home" PATH="$t/z/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr server stop" 2>&1)"; rc=$?; set -e
[[ $rc == 1 && "$err" == *"launchctl kickstart -k"* ]] || fail "a plain herdr server stop was not refused (D-016)"
! grep -q "herdr server stop" "$t/z/calls" || fail "the refused stop reached herdr"
HOME="$t/z/home" PATH="$t/z/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr server stop --session work"
grep -q "herdr server stop --session work" "$t/z/calls" || fail "a named session's stop was refused"

# 4g. `herdr --remote` refuses an unpinned local herdr (the host would be offered an unpinned
#     install), and `herdr integration install` re-applies the hook's python3 -I (audit run-8).
mkdir -p "$t/r/bin" "$t/r/dot/herdr"; echo 0.9.5 > "$t/r/dot/herdr/VERSION"; cp "$here/herdr/patch-claude-hook.sh" "$t/r/dot/herdr/"
cat > "$t/r/bin/herdr" <<S
#!/bin/sh
echo "herdr \$*" >> "$t/r/calls"
case "\$*" in --version) echo "herdr \$(cat "$t/r/have")" ;; "integration install claude") cp "$here/test/fixtures/herdr-agent-state.sh" "$t/r/hook.sh" ;; esac
S
chmod +x "$t/r/bin/herdr"; echo 0.9.6 > "$t/r/have"
set +e; HOME="$t/r" ZSH="$t/r/dot" PATH="$t/r/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr --remote n0" 2>"$t/r/err"; rc=$?; set -e
[[ $rc -ne 0 ]] && grep -q "pins '0.9.5'" "$t/r/err" || fail "herdr --remote ran with an unpinned local herdr"
! grep -q "herdr --remote" "$t/r/calls" || fail "the unpinned herdr reached the remote attach"
echo 0.9.5 > "$t/r/have"; : > "$t/r/calls"
HOME="$t/r" ZSH="$t/r/dot" PATH="$t/r/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr --remote=n0"
grep -q "^herdr --remote=n0" "$t/r/calls" || fail "the pinned herdr did not attach"
HOME="$t/r" ZSH="$t/r/dot" HERDR_CLAUDE_HOOK="$t/r/hook.sh" PATH="$t/r/bin:$PATH" zsh -fc "source '$here/herdr/herdr.zsh'; herdr integration install claude" >/dev/null
[[ "$(grep -c 'python3 -I - <<' "$t/r/hook.sh")" == 1 ]] || fail "integration install left the hook without python3 -I"

# 5. The LaunchAgent: n0 only, restarted only after a crash (D-016), logs in ~/Library/Logs.
p="$here/macos/com.broots.herdr-server.plist"
plutil -lint -s "$p"
grep -q '<!-- dotfiles-hosts: n0 -->' "$p" || fail "plist is not gated to n0"
[[ "$(plutil -extract KeepAlive.SuccessfulExit raw "$p")" == false ]] || fail "KeepAlive must be SuccessfulExit=false (D-016: no respawn at shutdown)"
[[ "$(plutil -extract StandardOutPath raw "$p")" == "__HOME__/Library/Logs/herdr-server.log" ]] || fail "log path"
[[ "$(plutil -extract ProgramArguments.1 raw "$p")" == "__HOME__/.dotfiles/bin/herdr-server" ]] || fail "program"

# 5a. Every Mac re-patches the hook whenever it changes, whatever rewrote it (code review).
p="$here/macos/com.broots.herdr-hook-patch.plist"
plutil -lint -s "$p"
! grep -q 'dotfiles-hosts' "$p" || fail "the hook-patch agent must run on every Mac"
[[ "$(plutil -extract WatchPaths.0 raw "$p")" == "__HOME__/.claude/hooks/herdr-agent-state.sh" ]] || fail "hook-patch watches the wrong path"
[[ "$(plutil -extract ProgramArguments.1 raw "$p")" == "__HOME__/.dotfiles/herdr/patch-claude-hook.sh" ]] || fail "hook-patch runs the wrong program"

# 5b. script/verify-herdr never prints the home path or the account name, even when every
#     check fails (its output goes into STATE.md of this public repo; audit run-6 finding).
mkdir -p "$t/vh/bin" "$t/vh/herdr"; chmod 755 "$t/vh/herdr"; echo x > "$t/vh/herdr/herdr.sock"
for c in herdr brew launchctl; do printf '#!/bin/sh\necho "error at %s/x for %s" >&2\nexit 1\n' "$HOME" "$(id -un)" > "$t/vh/bin/$c"; chmod +x "$t/vh/bin/$c"; done
set +e; out="$(PATH="$t/vh/bin:$PATH" HERDR_BIN="$t/vh/bin/herdr" HERDR_DIR="$t/vh/herdr" bash "$here/script/verify-herdr" 2>&1)"; rc=$?; set -e
[[ $rc -ne 0 ]] || fail "verify-herdr passed against a broken setup"
[[ "$out" == *"FAIL"* ]] || fail "verify-herdr printed no FAIL line"
[[ "$out" != *"$HOME"* ]] || fail "verify-herdr printed the home path"
[[ "$out" != *"$(id -un)"* ]] || fail "verify-herdr printed the account name"
[[ "$out" == *"owner me"* ]] || fail "verify-herdr did not say whose the files are"

# 5c. The gate fails when the running server is not the pinned version, even with the right
#     binary on disk (audit run-7).
cat > "$t/vh/bin/herdr" <<S
#!/bin/sh
case "\$*" in
  --version) echo "herdr \$(cat "$here/herdr/VERSION")" ;;
  "status server") printf 'status: running\nversion: 0.0.1\n' ;;
  *) exit 1 ;;
esac
S
chmod +x "$t/vh/bin/herdr"
set +e; out="$(PATH="$t/vh/bin:$PATH" HERDR_BIN="$t/vh/bin/herdr" HERDR_DIR="$t/vh/herdr" bash "$here/script/verify-herdr" 2>&1)"; set -e
[[ "$out" == *"running server is '0.0.1', not the pin"* ]] || fail "gate did not catch a server older than the pin"
[[ "$out" == *"at the LaunchAgent's path"* ]] || fail "gate did not check the LaunchAgent's binary"

# 5d. The gate fails when launchd's job is not itself the server holding the socket, e.g. the
#     wrapper still waiting behind a hand- or SSH-started server (audit run-8).
sleep 30 & wpid=$!
cat > "$t/vh/bin/herdr" <<S
#!/bin/sh
case "\$*" in
  --version) echo "herdr \$(cat "$here/herdr/VERSION")" ;;
  "status server") printf 'status: running\nversion: %s\n' "\$(cat "$here/herdr/VERSION")" ;;
  *) exit 1 ;;
esac
S
printf '#!/bin/sh\nprintf "\\tstate = running\\n\\tpid = %s\\n"\n' "$wpid" > "$t/vh/bin/launchctl"
chmod +x "$t/vh/bin/herdr" "$t/vh/bin/launchctl"
set +e; out="$(PATH="$t/vh/bin:$PATH" HERDR_BIN="$t/vh/bin/herdr" HERDR_DIR="$t/vh/herdr" bash "$here/script/verify-herdr" 2>&1)"; set -e
kill "$wpid" 2>/dev/null || true
[[ "$out" == *"launchd com.broots.herdr-server: running"* ]] || fail "5d: fake launchd not seen as running"
[[ "$out" == *"FAIL the job has no '$t/vh/bin/herdr server' child"* ]] || fail "gate accepted a job with no server child"
[[ "$out" == *"FAIL server is not a session leader"* ]] || fail "gate did not check detached_server_daemon"
[[ "$out" == *"FAIL herdr.sock is held by"* ]] || fail "gate accepted a socket the job does not hold"

# 6. No tmux auto-attach without the HERDR_ENV guard in any shell file this repo ships.
while IFS= read -r f; do
  if grep -Eq 'tmux +(new-session|new|attach|attach-session|a)( |$)' "$f" && ! grep -q 'HERDR_ENV' "$f"; then
    fail "$f starts tmux without the HERDR_ENV guard"
  fi
done < <(cd "$here" && git ls-files '*.zsh' '*.symlink' '*.sh' 'functions/*' | sed "s|^|$here/|")

echo "ok herdr"
