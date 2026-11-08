# herdr on n0 (D-011): the default server belongs to the LaunchAgent, which gives it a fixed
# environment and purges unpinned agent-detection rules first (D-012). A bare `herdr` with no
# server running would start one itself from this shell, with this shell's environment
# (security audit run-7). So when the LaunchAgent is installed and its server is down, start it
# through launchd and wait for its socket before attaching; if that fails, say so and stop.
#
# Two more guards (security audit run-8):
# - `herdr --remote <host>` only with the pinned version here: when client and server protocol
#   generations differ, herdr offers to install its own unpinned binary on the remote host
#   (default yes). Same pin on both ends (D-010) means the offer never comes.
# - `herdr integration install` rewrites the Claude hook without the python3 -I patch; put it
#   back right after, instead of waiting for the next `dot`.
# - A plain `herdr server stop` is refused while the LaunchAgent is installed (D-016): the job
#   restarts only after a crash, so a clean stop left the default server down for the next SSH
#   attach to start outside the LaunchAgent. Use launchctl to restart it or keep it stopped.
herdr() {
  local label=com.broots.herdr-server dot="${ZSH:-$HOME/.dotfiles}" a
  for a in "$@"; do
    if [[ "$a" == --remote || "$a" == --remote=* ]]; then
      local have pin
      have="$(command herdr --version 2>/dev/null | awk '{print $2}')"
      pin="$(cat "$dot/herdr/VERSION" 2>/dev/null)"
      if [[ -z "$pin" || "$have" != "$pin" ]]; then
        print -u2 "herdr: this herdr is '${have:-missing}' but herdr/VERSION pins '${pin:-?}'; fix the pin here (dot) before --remote, or herdr may install an unpinned binary on the host"
        return 1
      fi
      break
    fi
  done
  if [[ "$1" == server && "$2" == stop && -f "$HOME/Library/LaunchAgents/$label.plist" && " $* " != *" --session"* ]]; then
    print -u2 "herdr: the default server belongs to the LaunchAgent (D-016). Restart it: launchctl kickstart -k gui/$(id -u)/$label; keep it stopped: launchctl bootout gui/$(id -u)/$label"
    return 1
  fi
  # A bare attach to the default session, however it is spelled (upstream session.rs).
  local bare=0 i
  case "$*" in ""|"--session default"|"--session=default"|"session attach default") bare=1 ;; esac
  if (( bare )) && [[ -f "$HOME/Library/LaunchAgents/$label.plist" ]] \
     && ! command herdr status server 2>/dev/null | grep -q 'status: running'; then
    # Never fall through to a server started from this shell (code review 2026-11-08): say why
    # and stop instead.
    if ! launchctl kickstart "gui/$(id -u)/$label" 2>/dev/null; then
      print -u2 "herdr: launchctl kickstart of $label failed (not loaded? run macos/install-launchd.sh); not starting a server from this shell (D-011)"
      return 1
    fi
    for i in {1..${HERDR_ATTACH_WAIT_TICKS:-100}}; do
      command herdr status server 2>/dev/null | grep -q 'status: running' && break
      sleep 0.1
    done
    if ! command herdr status server 2>/dev/null | grep -q 'status: running'; then
      print -u2 "herdr: the LaunchAgent's server is not up yet (waiting behind another server? see ~/Library/Logs/herdr-server.log); not starting one from this shell (D-011)"
      return 1
    fi
  fi
  command herdr "$@"
  local rc=$?
  if [[ "$1" == integration && "$2" == install ]]; then
    sh "$dot/herdr/patch-claude-hook.sh"
  fi
  return $rc
}
