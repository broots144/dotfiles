# P8: herdr on n0

Goal: herdr is the agent multiplexer on n0, used locally in Ghostty, from the MacBook with
`herdr --remote n0`, and from the Galaxy tablet over plain SSH. The Atlas agent view
(workshop144/atlas) reads the same server, so its socket must stay private to this user.
The task brief called this "phase 1"; P1 already exists here, so it is P8.

1. Install with Homebrew (0.9.5 is the latest release and Homebrew has it), `brew pin herdr`,
   record the version in `herdr/VERSION`. herdr's own updater and remote manifest fetch off.
2. Claude Code integration: read `src/integration/claude_settings.rs` and the hook asset at
   the v0.9.5 tag, back up `~/.claude/settings.json`, run `herdr integration install claude`,
   diff, record exactly what it wrote (D-010). Verify with two Claude sessions in herdr panes:
   working, blocked (a Write permission prompt and the folder-trust prompt), idle; check the
   sidebar rendering, not only the API.
3. Shell: look for tmux auto-attach in every rc file; none exists. Add a test that fails on a
   tracked shell file that starts tmux without the `HERDR_ENV` guard (herdr docs, agents.mdx).
4. Ghostty: theme follows Ghostty's appearance, notifications through the outer terminal
   (OSC 9/777), login shells in panes.
5. Socket: herdr makes both sockets 0600 (src/server/socket_paths.rs:12) but leaves
   `~/.config/herdr` 0755 with a 0644 session.json and logs. `herdr/install.sh` and
   `bin/herdr-server` set the directory to 0700. No umask change (panes inherit it).
6. Server under launchd: `com.broots.herdr-server`, n0 only, KeepAlive on crash only, fixed
   environment, log in ~/Library/Logs (D-011).
7. Config `herdr/config.toml` linked into `~/.config/herdr`; doc `docs/herdr.md` (local,
   MacBook, tablet, named sessions, detach and reattach, upgrades).
8. Gate: `just verify-phase-8` (alias `verify-herdr`): test/herdr.sh, then live checks of the
   pin, integration, launchd state, socket answering, socket and directory modes. Output in
   STATE.md.
