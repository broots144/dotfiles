# herdr on n0 (D-011): the default server belongs to the LaunchAgent, which gives it a fixed
# environment and purges unpinned agent-detection rules first (D-012). A bare `herdr` with no
# server running would start one itself from this shell, with this shell's environment
# (security audit run-7). So when the LaunchAgent is installed and its server is down, start it
# through launchd and wait for its socket before attaching. Anything else passes straight through.
herdr() {
  local label=com.broots.herdr-server
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
}
