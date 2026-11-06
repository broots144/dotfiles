# P6: Repo-state pattern

Goal: the repo carries its own memory so any session can pick up without prior context.

1. Add STATE.md, ROADMAP.md, LESSONS.md, docs/DECISIONS.md, CLAUDE.md, seeded from git history and PRs #1 to #7, and from what is actually running on n0.
2. Add a justfile: `check` (syntax, shellcheck of maintained scripts, plist lint, tests) and `verify-phase-0` to `verify-phase-6` mapped onto the existing tests.
3. Add `script/check-state` and a pull-request-only workflow running it. Escape hatch: every commit subject starts with `chore:`, `deps:` or `brew:`. It must not touch the unattended `brew:` pushes to `master`.
4. Gate: `just verify-phase-6` passes and its output is pasted into STATE.md.
