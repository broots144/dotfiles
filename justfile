# Maintained shell scripts (bash/sh). Legacy holman scripts are syntax-checked only.
maintained := "bin/brew-nightly bin/brew-apply script/brewfile-push script/self-update bin/herdr-server herdr/install.sh herdr/patch-claude-hook.sh script/verify-herdr bin/dev-icloud-backup bin/dev-pull bin/dev-push-to-n0 bin/dev-sync-from-n0 lib/dev-tree.sh macos/install-launchd.sh script/test script/check-state script/coverage test/*.sh test/lib/fake-n0.sh"

default: check

# validate + lint + test
check: syntax lint plists test

# zsh -n on zsh sources, bash -n / sh -n on shell scripts
syntax:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in */*.zsh zsh/*.symlink functions/* bin/brew-reconcile; do zsh -n "$f"; done
    for f in bin/* lib/* script/* test/*.sh test/lib/* macos/*.sh herdr/*.sh; do
      [[ -L "$f" ]] && continue
      case "$(head -1 "$f")" in *bash*) bash -n "$f" ;; */sh*) sh -n "$f" ;; esac
    done
    echo "syntax ok"

lint:
    shellcheck -S warning {{maintained}}
    @echo "shellcheck ok"

plists:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in macos/*.plist; do plutil -lint -s "$f"; done
    echo "plists ok"

test:
    script/test

# approximate line coverage of the maintained bash scripts (bash >= 4.1)
coverage:
    script/coverage

# P0 topic layout: every zsh topic file parses
verify-phase-0: syntax

# P1 Brewfile sync: wrapper pushes only its own lone Brewfile commit
verify-phase-1:
    test/brew-sync-push.sh

# P2 security hardening: repo data is data
verify-phase-2:
    test/untrusted-input.sh

# P3 encrypted iCloud backup
verify-phase-3:
    test/dev-icloud-backup.sh

# P4 two-machine ~/dev sync
verify-phase-4:
    test/dev-pull.sh

# P5 nightly brew upgrade on the laptop
verify-phase-5:
    bash -n bin/brew-nightly
    shellcheck -S warning bin/brew-nightly
    plutil -lint -s macos/com.broots.brew-nightly.plist
    @echo "verify-phase-5 ok"

# P6 repo-state pattern: state files present, guard behaves
verify-phase-6:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in STATE.md ROADMAP.md LESSONS.md docs/DECISIONS.md CLAUDE.md; do test -s "$f"; done
    grep -q 'read STATE.md, ROADMAP.md, LESSONS.md' CLAUDE.md
    if grep -n $'\xe2\x80\x94\|\xe2\x80\x93' STATE.md ROADMAP.md LESSONS.md docs/DECISIONS.md CLAUDE.md docs/plans/*.md; then echo "dash found"; exit 1; fi
    script/check-state --self-test
    echo "verify-phase-6 ok"

# P8 herdr on n0: pin, Claude integration, server under launchd, socket answering, modes (run on n0)
verify-phase-8:
    test/herdr.sh
    script/verify-herdr

# P9 Brewfile mirror both ways (D-022)
verify-phase-9:
    test/brew-apply.sh
    test/brewfile-push.sh
    test/brew-reconcile.sh
    test/brew-sync-push.sh
    test/brew-wrapper.sh
    plutil -lint -s macos/com.broots.brew-apply.plist macos/com.broots.brew-reconcile.plist
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --all --file=Brewfile >/dev/null
    @echo "verify-phase-9 ok"

# alias of verify-phase-8 (the task brief called it "phase 1")
verify-herdr: verify-phase-8

# Re-run the security-audit skill's validators on this repo's newest audit run and show its
# counts. Audit output lives outside the repo and is never committed:
# ${SECURITY_AUDIT_ROOT:-~/security-audit-skill}/dotfiles/run-N.
verify-security:
    #!/usr/bin/env bash
    set -euo pipefail
    skill="${SECURITY_AUDIT_SKILL:-$HOME/.claude/skills/security-audit}"
    root="${SECURITY_AUDIT_ROOT:-$HOME/security-audit-skill}/dotfiles"
    n=$(ls -d "$root"/run-*/findings.json 2>/dev/null | sed 's|.*/run-\([0-9]*\)/findings.json|\1|' | sort -n | tail -1)
    [ -n "$n" ] || { echo "no finished audit run for dotfiles"; exit 1; }
    d="$root/run-$n"
    echo "dotfiles run-$n: $(jq -r .run_status "$d/run-metadata.json")"
    node "$skill/validate-findings.cjs" "$d/findings.json"
    node "$skill/validate-coverage-ledger.cjs" "$d/coverage-ledger.json"
    jq -r 'def v(x): map(select(.verdict == x)); (v("confirmed") | map(.severity.overall_severity) | group_by(.) | map("\(.[0]) \(length)") | join(", ")) as $s
      | "confirmed: \(v("confirmed") | length)\(if $s == "" then "" else " (\($s))" end)",
        "needs_validation: \(v("needs_validation") | length)",
        "rejected: \(v("rejected") | length)"' "$d/findings.json"
