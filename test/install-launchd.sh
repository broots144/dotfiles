#!/usr/bin/env bash
# macos/install-launchd.sh renders each plist (__HOME__ -> $HOME) into ~/Library/LaunchAgents
# and reloads it; a `dotfiles-hosts` marker limits a plist to the hosts it names, matched as
# whole names (n0 is not n0-2), on HostName, else LocalHostName; a plist for other hosts is
# booted out and removed. The script runs from a copy beside synthetic plists; scutil and
# launchctl are stubs.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HOME="$t/home" LOG="$t/log"
mkdir -p "$t/bin" "$t/macos" "$HOME"
cp "$here/macos/install-launchd.sh" "$t/macos/"
# scutil stub: FAKE_HOSTNAME empty = HostName unset (scutil fails), as on a fresh Mac.
cat > "$t/bin/scutil" <<'S'
#!/bin/sh
case "$2" in
  HostName) [ -n "${FAKE_HOSTNAME:-}" ] && { echo "$FAKE_HOSTNAME"; exit 0; }; echo "HostName: not set" >&2; exit 1 ;;
  LocalHostName) echo "${FAKE_LOCAL:-mac}" ;;
esac
S
printf '#!/bin/sh\necho "launchctl $*" >> "$LOG"\n' > "$t/bin/launchctl"
chmod +x "$t/bin/scutil" "$t/bin/launchctl"
export PATH="$t/bin:$PATH"
plist() {  # <label> [hosts]
  { echo '<?xml version="1.0" encoding="UTF-8"?>'; [[ -z "${2:-}" ]] || echo "<!-- dotfiles-hosts: $2 -->"
    echo "<plist version=\"1.0\"><dict><key>Label</key><string>com.broots.$1</string>"
    echo "<key>StandardOutPath</key><string>__HOME__/Library/Logs/$1.log</string></dict></plist>"; } > "$t/macos/com.broots.$1.plist"
}
plist mini n0; plist laptop book; plist everywhere; plist both 'n0 book'; plist renamed n0-2
fail=0
ok() { "$@" || { echo "FAIL: line ${BASH_LINENO[0]}: $*"; fail=1; }; }
la="$HOME/Library/LaunchAgents"; uid=$(id -u)
run() { : > "$LOG"; out=$(env "$@" "$t/macos/install-launchd.sh" 2>&1) && rc=0 || rc=$?; }

run FAKE_HOSTNAME=n0
ok [ "$rc" = 0 ]
for l in mini everywhere both; do
  ok grep -qx "loaded com.broots.$l" <<<"$out"; ok [ -f "$la/com.broots.$l.plist" ]
  ok grep -qx "launchctl bootstrap gui/$uid $la/com.broots.$l.plist" "$LOG"
  ok grep -qx "launchctl enable gui/$uid/com.broots.$l" "$LOG"
done
ok grep -q "<string>$HOME/Library/Logs/mini.log</string>" "$la/com.broots.mini.plist"
ok bash -c '! grep -q __HOME__ "$1"' _ "$la/com.broots.mini.plist"
ok grep -qx 'skipped com.broots.laptop (hosts: book; this is n0)' <<<"$out"
ok grep -qx 'skipped com.broots.renamed (hosts: n0-2; this is n0)' <<<"$out"
ok [ ! -e "$la/com.broots.laptop.plist" ]; ok [ ! -e "$la/com.broots.renamed.plist" ]
ok [ -d "$HOME/Library/Logs" ]

# HostName unset: LocalHostName decides. An agent installed for another host is removed.
cp "$la/com.broots.mini.plist" "$la/com.broots.laptop.plist"
run FAKE_HOSTNAME= FAKE_LOCAL=book
ok [ "$rc" = 0 ]
ok grep -qx 'loaded com.broots.laptop' <<<"$out"; ok grep -qx 'loaded com.broots.both' <<<"$out"
ok grep -qx 'removed com.broots.mini (hosts: n0; this is book)' <<<"$out"
ok grep -qx "launchctl bootout gui/$uid/com.broots.mini" "$LOG"
ok [ ! -e "$la/com.broots.mini.plist" ]
ok grep -q '<string>com.broots.laptop</string>' "$la/com.broots.laptop.plist"

(( fail == 0 )) && echo "ok install-launchd"
exit "$fail"
