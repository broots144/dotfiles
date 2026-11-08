# herdr on n0 (D-011): the default server belongs to the LaunchAgent, which gives it a fixed
# environment and purges unpinned agent-detection rules first (D-012). A bare `herdr` with no
# server running would start one itself from this shell, with this shell's environment
# (security audit run-7). So when the LaunchAgent is installed and its server is down, start it
# through launchd and wait for its socket before attaching.
#
# Two more guards (security audit run-8):
# - `herdr --remote <host>` only with the pinned version here: when client and server protocol
#   generations differ, herdr offers to install its own unpinned binary on the remote host
#   (default yes). Same pin on both ends (D-010) means the offer never comes.
# - `herdr integration install` rewrites the Claude hook without the python3 -I patch; put it
#   back right after, instead of waiting for the next `dot`.
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
  if (( $# == 0 )) && [[ -f "$HOME/Library/LaunchAgents/$label.plist" ]] \
     && ! command herdr status server 2>/dev/null | grep -q 'status: running'; then
    launchctl kickstart "gui/$(id -u)/$label" 2>/dev/null
    local i
    for i in {1..50}; do
      command herdr status server 2>/dev/null | grep -q 'status: running' && break
      sleep 0.1
    done
  fi
  command herdr "$@"
  local rc=$?
  if [[ "$1" == integration && "$2" == install ]]; then
    sh "$dot/herdr/patch-claude-hook.sh"
  fi
  return $rc
}
