#!/usr/bin/env bash
# herdr (D-010, D-011): the tracked config is valid and keeps the safe settings, herdr/install.sh
# links it into an owner-only ~/.config/herdr, bin/herdr-server tightens that directory and
# waits for a hand-started server, the LaunchAgent restarts only on a crash, and no shell file
# auto-attaches tmux inside a herdr pane (herdr docs: agents.mdx, guard with HERDR_ENV).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL herdr: $*" >&2; exit 1; }
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

# 3. install.sh: owner-only dir, link to the tracked file, an old file kept, idempotent.
home="$t/home"; mkdir -p "$home/.config/herdr"; chmod 755 "$home/.config/herdr"
echo "old = 1" > "$home/.config/herdr/config.toml"
out="$(HOME="$home" ZSH="$here" sh "$here/herdr/install.sh")"
[[ "$(mode "$home/.config/herdr")" == 700 ]] || fail "install.sh left ~/.config/herdr at $(mode "$home/.config/herdr")"
[[ -L "$home/.config/herdr/config.toml" ]] || fail "install.sh did not link config.toml"
[[ "$(readlink "$home/.config/herdr/config.toml")" == "$here/herdr/config.toml" ]] || fail "config.toml links elsewhere"
grep -q "old = 1" "$home/.config/herdr/config.toml.pre-dotfiles" || fail "the old config was not kept"
[[ "$out" == *linked* ]] || fail "install.sh said: $out"
out="$(HOME="$home" ZSH="$here" sh "$here/herdr/install.sh")"
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

# 5. The LaunchAgent: n0 only, restart on crash only, logs in ~/Library/Logs.
p="$here/macos/com.broots.herdr-server.plist"
plutil -lint -s "$p"
grep -q '<!-- dotfiles-hosts: n0 -->' "$p" || fail "plist is not gated to n0"
[[ "$(plutil -extract KeepAlive.SuccessfulExit raw "$p")" == false ]] || fail "KeepAlive must be SuccessfulExit=false"
[[ "$(plutil -extract StandardOutPath raw "$p")" == "__HOME__/Library/Logs/herdr-server.log" ]] || fail "log path"
[[ "$(plutil -extract ProgramArguments.1 raw "$p")" == "__HOME__/.dotfiles/bin/herdr-server" ]] || fail "program"

# 6. No tmux auto-attach without the HERDR_ENV guard in any shell file this repo ships.
while IFS= read -r f; do
  if grep -Eq 'tmux +(new-session|new|attach|attach-session|a)( |$)' "$f" && ! grep -q 'HERDR_ENV' "$f"; then
    fail "$f starts tmux without the HERDR_ENV guard"
  fi
done < <(cd "$here" && git ls-files '*.zsh' '*.symlink' '*.sh' 'functions/*' | sed "s|^|$here/|")

echo "ok herdr"
