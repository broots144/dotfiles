# test fixtures

- `herdr-agent-state.sh`: herdr v0.9.5's Claude Code hook asset (src/integration/assets/claude/herdr-agent-state.sh at tag v0.9.5, commit 2ecf19a, Apache-2.0, https://github.com/ogulcancelik/herdr), unmodified. test/herdr.sh checks that herdr/install.sh patches it to `python3 -I` and that the patched copy no longer imports modules from the session cwd.
