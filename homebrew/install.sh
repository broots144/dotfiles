#!/bin/sh
#
# Homebrew
#
# Installs Homebrew when it is missing, with the current installer (the old Ruby one at
# Homebrew/install/master/install is gone). Exits non-zero if brew is still not there, so
# bin/dot stops here with a clear message instead of at `brew update`.

brew_bin() {
  command -v brew 2>/dev/null && return 0
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

if ! brew_bin >/dev/null
then
  echo "  Installing Homebrew for you."
  # One installer for macOS and Linux.
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! brew_bin >/dev/null
then
  echo "  Homebrew is not installed; see https://brew.sh" >&2
  exit 1
fi

exit 0
