# shellcheck shell=bash
# Sourced by the tests (bash). fake_n0_stubs <dir>: writes stand-ins for scutil and ssh into
# <dir> (put it first in PATH). Nothing leaves the machine:
#   scutil  prints $FAKE_HOST (default book): the host the script under test thinks it is on.
#   ssh     host n0 runs the remote command locally, in $FAKE_N0_HOME with HOME set to it (so
#           rsync and git over ssh reach a fake n0 tree); any other host (github.com) is
#           unreachable. FAKE_N0_DOWN=1: n0 is unreachable too. FAKE_N0_RSYNC_FAIL=1: n0 answers,
#           but a remote rsync fails (exit 12, a protocol error).
fake_n0_stubs() {
  local d="$1"
  mkdir -p "$d"
  printf '#!/bin/sh\necho "${FAKE_HOST:-book}"\n' > "$d/scutil"
  cat > "$d/ssh" <<'SSH'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in -o|-l|-p|-i|-F) shift 2 ;; -*) shift ;; *) break ;; esac
done
host=$1; shift
[ "$host" = n0 ] && [ -z "${FAKE_N0_DOWN:-}" ] || { echo "ssh: connect to host $host: unreachable (stub)" >&2; exit 255; }
case "$*" in rsync*) [ -n "${FAKE_N0_RSYNC_FAIL:-}" ] && { echo "rsync: protocol error (stub)" >&2; exit 12; } ;; esac
cd "$FAKE_N0_HOME" || exit 255
HOME="$FAKE_N0_HOME" ZSH='' exec /bin/sh -c "$*"
SSH
  chmod +x "$d/scutil" "$d/ssh"
}
