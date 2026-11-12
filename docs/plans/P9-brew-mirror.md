# P9: the Brewfile mirrors both Macs, both ways

Asked 2026-11-11: an install on one Mac should reach the repo and then be installed on the
other Mac, in both directions, without a manual `dot`.

## Before

- n0 to repo: automatic (`brew` wrapper, `brew-reconcile` every 30 min on n0).
- repo to book's checkout: automatic (`dev-sync-from-n0` pulls the dotfiles).
- checkout to installed software: manual. Only `dot` ran `brew bundle`.
- book to repo: only interactive installs (the wrapper). `brew-reconcile` ran on n0 only.
- book lacked 102 of the Brewfile's entries on 2026-11-11.

## Design (D-022)

1. `bin/brew-apply`, hourly on both Macs (`com.broots.brew-apply`): fast-forward the checkout,
   `brew bundle install --no-upgrade` with stdin closed when something is missing. Installs
   only. Master only. A failed attempt waits a day for the same Brewfile.
2. `brew-reconcile` on both Macs. It fast-forwards first, works on master only, and retries a
   Brewfile commit that could not be pushed.
3. `script/brewfile-push`, shared by the wrapper and the reconciler: push only when every
   unpushed commit is a Brewfile commit; when the other Mac pushed first, rebase and push
   again. `.gitattributes` sets `Brewfile merge=union` so two added lines never conflict.
4. Removals do not bounce back: `brew-apply` keeps a snapshot of entries seen in the Brewfile;
   `brew-reconcile` does not add back an entry that is installed, in the snapshot and no longer
   listed. Nothing is uninstalled on the other Mac.
5. n0-only entries carry `if n0` in the Brewfile (plain Ruby, so `brew bundle` in `dot` obeys it
   too): local LLMs, 3D printing, home hardware, the app-building stack, media tools.

## Gate

`just verify-phase-9`: test/brew-apply.sh, test/brewfile-push.sh, test/brew-reconcile.sh,
test/brew-sync-push.sh, test/brew-wrapper.sh, plist lint, and `brew bundle list` reads the
Brewfile.

## Rollout

Merge, then `macos/install-launchd.sh` on n0 and on book (book: after
`git -C ~/.dotfiles pull --ff-only`). The first run on book installs about 85 entries.
Check `~/Library/Logs/brew-apply.log` on both.
