# herdr on n0

herdr is the agent multiplexer: one server on n0 owns every pane and agent (Claude Code
sessions included), and any number of clients attach to it. Decisions: docs/DECISIONS.md
D-010 (install, pin, Claude integration) and D-011 (the server under launchd).

## What runs where

| Piece | Where | Notes |
|---|---|---|
| `herdr` binary | Homebrew, pinned (`brew pin herdr`), version in `herdr/VERSION` | herdr's own updater is off |
| Server, default session | LaunchAgent `com.broots.herdr-server` on n0 | log `~/Library/Logs/herdr-server.log` |
| Config | `herdr/config.toml`, linked to `~/.config/herdr/config.toml` by `herdr/install.sh` | |
| Sockets | `~/.config/herdr/herdr.sock` (API) and `herdr-client.sock` | 0600, in a 0700 dir |
| Claude hook | `~/.claude/hooks/herdr-agent-state.sh`, one `SessionStart` entry in `~/.claude/settings.json` | `herdr integration status` |

The sockets are a full control API: anything that can connect can type into every pane. Only
your user can, by file mode. Never loosen `~/.config/herdr` or point another account at it.

## Local, on n0 in Ghostty

```sh
herdr                 # attach to the default session (the LaunchAgent keeps it running)
```

- `ctrl+b` is the prefix. `ctrl+b ?` lists keys and settings; the UI is mouse-first.
- The sidebar shows each agent's state: working, blocked (needs you, red), idle/done.
- A background agent that finishes or blocks raises a macOS notification through Ghostty
  (`[ui.toast] delivery = "terminal"`, OSC 9/777; Ghostty's `desktop-notifications` is on by
  default) and a sound.
- The theme follows Ghostty's light/dark appearance (catppuccin and catppuccin-latte).
- New panes start a login zsh, like a new Ghostty tab, so PATH and the ssh-agent are the usual
  ones.

## Detach and reattach

- Detach: `ctrl+b q`. Panes and agents keep running in the server.
- Reattach: `herdr` again, from any terminal.
- Stop everything (ends every pane): `herdr server stop`. The LaunchAgent does not restart a
  clean stop; start it again with `launchctl kickstart gui/$(id -u)/com.broots.herdr-server`
  (not a bare `herdr`, which would start a server outside the LaunchAgent's fixed environment and
  without its D-012 cache purge). Restart in one step: `launchctl kickstart -k gui/$(id -u)/com.broots.herdr-server`.
- After a server restart herdr restores the layout and resumes Claude sessions into their
  conversations (`resume_agents_on_restore`). Screen history is not saved to disk
  (`pane_history = false`), on purpose.

## Named sessions

Independent servers with their own panes and sockets; they share this config.

```sh
herdr --session work          # create or attach
herdr session list
herdr session stop work
herdr session delete work
```

The LaunchAgent manages only the default session; a named one runs until you stop it or n0
reboots. The Atlas agent view (workshop144/atlas) reads the default session only.

## From the MacBook (`book`)

```sh
herdr --remote n0                     # the remote server owns the panes; local herdr draws the UI
herdr --remote n0 --session work      # a named session
```

`n0` resolves at home (`n0.lab`) and over NetBird (`n0.sl.mesh`); herdr uses your normal SSH
config and keys, so `ssh n0` must work first. The local UI uses the MacBook's keybindings and
can paste images from the Mac clipboard into a remote agent. Detach with `ctrl+b q`.

## From the Galaxy tablet (plain SSH)

```sh
ssh n0
herdr                 # same server, same panes, drawn in the tablet's terminal
```

- Use a terminal with a real `ctrl` key and 256 colours or better (Termux, JuiceSSH).
- On a narrow screen, collapse the sidebar with the `«` at its bottom edge.
- Detach with `ctrl+b q` before closing the app; a dropped connection only detaches too.
- If the tablet's passphrase-protected key cannot prompt, load it into its agent first.

## tmux

No shell file auto-attaches tmux today. If one ever does, it must skip herdr panes, or herdr
sees `tmux` instead of the agent and the terminal shrinks recursively:

```sh
if [[ -z ${TMUX:-} && ${HERDR_ENV:-} != 1 ]]; then
  tmux new-session -A -s main
fi
```

`test/herdr.sh` fails on a tracked shell file that starts tmux without `HERDR_ENV`.

## Upgrading herdr

The pin is deliberate (D-010). To move it: read the release notes for new defaults and new
network behaviour, then

```sh
brew unpin herdr && brew upgrade herdr && brew pin herdr
herdr --version > /dev/null && herdr integration install claude   # refresh the hook if it changed
```

update `herdr/VERSION`, run `just verify-phase-8`, and restart the server when no agent is
mid-task: `launchctl kickstart -k gui/$(id -u)/com.broots.herdr-server`. Do the same on the
MacBook (`herdr/install.sh` pins herdr there too), so `herdr --remote n0` never meets a newer
client.
