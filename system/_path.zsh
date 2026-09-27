# Absolute, operator-owned directories only. A relative entry such as ./bin would
# let any repository you cd into shadow commands the prompt runs on every redraw.
export PATH="/usr/local/bin:/usr/local/sbin:$ZSH/bin:$PATH"
export MANPATH="/usr/local/man:/usr/local/mysql/man:/usr/local/git/man:$MANPATH"
