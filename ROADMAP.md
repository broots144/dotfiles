# Roadmap

Status detail lives in STATE.md. Each phase's gate is `just verify-phase-N`.

| Phase | Title | Status | Gate / blocker |
|---|---|---|---|
| P0 | Topic layout and bootstrap (holman fork) | ✅ | `verify-phase-0`: zsh syntax of all topic files |
| P1 | Brewfile stays true: `brew` wrapper and `brew-reconcile` | ✅ | `verify-phase-1`: test/brew-sync-push.sh |
| P2 | Security hardening, audit runs 1 to 3 | ✅ | `verify-phase-2`: test/untrusted-input.sh |
| P3 | Encrypted nightly iCloud backup of ~/dev | ✅ | `verify-phase-3`: test/dev-icloud-backup.sh (open: EDEADLK on n0, see STATE.md) |
| P4 | Two-machine ~/dev sync, GitHub as hub | ✅ | `verify-phase-4`: test/dev-pull.sh |
| P5 | Nightly Homebrew upgrade on the laptop | ✅ | `verify-phase-5`: bash syntax, shellcheck, plist lint |
| P6 | Repo-state pattern and PR state guard | 🟡 | `verify-phase-6`: guard self-test; merge of the retrofit PR |
| P8 | herdr agent multiplexer on n0 | 🟡 | `verify-phase-8`: test/herdr.sh + script/verify-herdr (live, n0) |
| P7 | README rewritten for this setup; legacy scripts linted or removed | ⏸ | not started |
