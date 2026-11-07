#!/usr/bin/env bash
#
# Shared classification of ~/dev for the two jobs that copy it somewhere:
#   bin/dev-icloud-backup   (n0 -> iCloud Drive, nightly)
#   bin/dev-sync-from-n0    (MacBook <- n0, every 20 minutes)
# One list of what is rebuildable, what is secret-bearing and what is gitignored, so the two
# copies never drift apart in what they carry. Source this file; it defines no side effects
# beyond the arrays and functions below. Portable to macOS bash 3.2 (no associative arrays).
#
# Folders to skip entirely (re-acquirable, tens of GB). '/x/' = top level only, 'x/' = anywhere.
DEV_TREE_EXCLUDES=(
  /bulk-youtube-download/
  /local-image-llm/
  node_modules/ .venv/ venv/ .terraform/ dist/ .astro/ .next/ .cache/ .aws-sam/ .build/
  __pycache__/ .pytest_cache/ .ruff_cache/ .mypy_cache/
  '*.iso' .DS_Store
)
# Secret-bearing names: never in a plaintext mirror, always in the encrypted/private copy.
# Matched case-insensitively (.ENV, KEY.PEM). A name that turns out to be a directory goes
# into the copy whole, so nothing it holds is dropped from both copies.
DEV_TREE_SECRET_NAMES=(
  '*.tfstate' '*.tfstate.*' '*.tfvars' '*.tfvars.json' '*.tfplan' tfplan plan.out
  '.env*' '*.env' values.env '*.dev.vars' .dev.vars '*.envrc'
  '*.pem' '*.key' '*.p12' '*.pfx' '*.p8' '*.ppk' '*.jks' '*.keystore'
  'id_rsa*' 'id_dsa*' 'id_ecdsa*' 'id_ed25519*'
  '*keys.txt' '*.kubeconfig' 'kubeconfig*' '*-k3s.yaml' '*-k3s.yml' '*k8s-config*'
  '*-key.json' '*_key.json' '*serviceaccount*.json' '*service-account*.json'
  '*service_account*.json' sa.json
  'token*.json' 'token*.pickle' 'client_secret*.json' 'credentials*' '*secrets*'
  .git-credentials .netrc .npmrc .pypirc .pgpass .htpasswd '.vault_pass*' '*vault-pass*'
  '*.local.zsh' '*.local.symlink' 'gitconfig.local*'
  settings.local.json .mcp.json '*.age' '*.gpg' '*.asc' '*.token'
)
# Gitignored directories that are rebuildable output: kept out of the plaintext mirror like
# every gitignored directory, but not copied into the encrypted archive (tens of thousands of
# files). Only consulted for directories git reports as ignored.
DEV_TREE_REBUILDABLE=(
  target build .build .wrangler .pio .swiftpm cdk.out '*.egg-info' test-results .hypothesis
  .func .husky lambda_build .gradle .tox .nox .turbo .svelte-kit .parcel-cache .nuxt coverage
)

# dev_tree_skip_re <name>...: the names (DEV_TREE_EXCLUDES syntax) as one ERE over relative
# paths: '/x/' at the start only, 'x/' and plain names as any path component.
dev_tree_skip_re() {
  local e re=""
  for e in "$@"; do
    case "$e" in /*) e="${e#/}"; e="${e%/}"; e="^${e//./\\.}" ;; *) e="${e%/}"; e="(^|/)${e//./\\.}" ;; esac
    re+="${re:+|}${e//\*/[^/]*}(/|$)"
  done
  printf %s "$re"
}

# 'ab' -> '[aA][bB]': rsync patterns are case-sensitive.
dev_tree_nocase() {
  local p="$1" out="" c lo up i
  for (( i = 0; i < ${#p}; i++ )); do
    c="${p:i:1}"
    lo=$(printf %s "$c" | tr '[:upper:]' '[:lower:]'); up=$(printf %s "$c" | tr '[:lower:]' '[:upper:]')
    if [[ "$lo" != "$up" ]]; then out+="[$lo$up]"; else out+="$c"; fi
  done
  printf %s "$out"
}

# Every git call isolated from repo-local executable config.
DEV_TREE_GIT=(git -c safe.bareRepository=explicit -c core.fsmonitor=false)

# dev_tree_repos <src/> <outfile> [all]: NUL-separated list of every .git directory under <src>
# (nested ones too), relative to <src>, bulk folders pruned. With `all`, also every .git file:
# git worktrees (~/dev/_wt) and submodules, which have a working tree but no object store. The repo half of dev_tree_lists,
# on its own because bin/dev-pull needs only this and the ignored-file scan is slow.
# Rebuildable output (DEV_TREE_REBUILDABLE: .pio, .build, target, ...) is pruned too, unless the
# directory is itself a checkout: the third-party clones a build tool leaves there
# (.pio/libdeps/*, .build/checkouts/*) are not ours to fetch, merge, bundle or sync.
dev_tree_repos() {
  local src="$1" out="$2" e bulk=() rb=() kind=(-type d)
  [[ "${3:-}" == all ]] && kind=(\( -type d -o -type f \))
  for e in "${DEV_TREE_EXCLUDES[@]}"; do
    case "$e" in
      /*/) bulk+=(-o -path "./${e:1:${#e}-2}") ;;
      */)  bulk+=(-o -name "${e%/}") ;;
    esac
  done
  for e in "${DEV_TREE_REBUILDABLE[@]}"; do rb+=(-o -name "$e"); done
  # find exits 1 on one unreadable or vanished entry; keep what it listed (pipefail callers).
  { (cd "$src" && find . -name .git "${kind[@]}" -prune -print0 -o \( -false "${bulk[@]}" \) -prune \
      -o -type d \( -false "${rb[@]}" \) -exec sh -c '! test -e "$1/.git"' _ {} \; -prune) || true; } | dev_tree_strip > "$out"
}

# dev_tree_private_files <src/> <workdir>: NUL-separated paths of what git does not carry:
# the named + gitignored set from dev_tree_lists minus every file tracked in the checkout or on
# an origin branch (directories in the named set expand to their files). Needs dev_tree_lists output in <workdir>. Used by the
# MacBook sync in both directions (bin/dev-sync-from-n0 --manifest on n0, bin/dev-push-to-n0
# on the laptop), so the two directions carry the same set.
dev_tree_private_files() {
  local src="$1" work="$2" g r p skip
  # The bulk/junk names of DEV_TREE_EXCLUDES as one regex: git lists a cache directory's own
  # .gitignore and the odd .DS_Store as ignored files, and neither is worth carrying.
  skip=$(dev_tree_skip_re "${DEV_TREE_EXCLUDES[@]}")
  (cd "$src" && cat "$work/named" "$work/ignored" | sort -zu | while IFS= read -r -d '' p; do
    if [[ -d "$p" && ! -L "$p" ]]; then find "$p" -name .git -prune -o -type f -print; else printf '%s\n' "$p"; fi
  done) | grep -vE "$skip" | sort -u > "$work/all"
  # Tracked means tracked here or on any origin branch: a file committed on a feature branch
  # (or already merged on GitHub) is git's to carry, and a copy rsynced ahead of the merge
  # lands untracked on the other machine.
  local ref
  while IFS= read -r -d '' g; do
    r="${g%/.git}"
    {
      "${DEV_TREE_GIT[@]}" -C "$src$r" ls-files 2>/dev/null
      "${DEV_TREE_GIT[@]}" -C "$src$r" for-each-ref --format='%(refname)' refs/remotes/origin 2>/dev/null | grep -v '/HEAD$' |
        while IFS= read -r ref; do "${DEV_TREE_GIT[@]}" -C "$src$r" ls-tree -r --name-only "$ref" 2>/dev/null; done
    } | sed "s|^|$r/|"
  done < "$work/repos" | sort -u > "$work/tracked"
  if [[ -s "$work/tracked" ]]; then grep -vxF -f "$work/tracked" "$work/all"; else cat "$work/all"; fi | tr '\n' '\0'
}

# dev_tree_lists <src/> <workdir>: writes NUL-separated lists, relative to <src>, into <workdir>:
#   repos    every .git directory (nested ones too), bulk folders pruned
#   checkouts every .git directory and .git file (worktrees, submodules): the ignored-file scan
#            and the exclude rules cover each working tree, not only those with a .git dir
#   named    files and directories with a secret-bearing name (bulk folders and .git pruned)
#   ignored  gitignored regular files up to 1 MiB that sit outside a gitignored directory
#   ignoredd regular files up to 1 MiB inside gitignored directories (rebuildable ones in
#            DEV_TREE_REBUILDABLE and bulk folders left out), the gitignored files of worktrees
#            and submodules, and the files of a checkout git cannot read. Archive only: the MacBook sync
#            (dev_tree_private_files) does not read it, so scratch/, logs/, cache/ and private/
#            dirs stay on the machine that made them and are not copied both ways every 20 min.
#   gitcfg   each repo's .git/config
#   rules    rsync exclude rules ('- /path') for every gitignored file and directory, of any
#            size: default-deny, nothing gitignored reaches the plaintext mirror. A checkout
#            whose ignored files git cannot list (a worktree whose main repo moved) is
#            excluded whole.
# Also fills DEV_TREE_RSYNC_EXCLUDES with --exclude args for .git, the bulk folders and the
# secret names (case-insensitive).
# Returns non-zero when a list could not be written (the callers refuse to mirror on that);
# find and git errors on single entries are tolerated, the scan keeps what it could list.
dev_tree_lists() {
  local src="$1" work="$2" e g r f p q sz bulk_re rebuild_re prune=()
  DEV_TREE_RSYNC_EXCLUDES=(--exclude .git/)
  for e in "${DEV_TREE_EXCLUDES[@]}"; do DEV_TREE_RSYNC_EXCLUDES+=(--exclude "$e"); done
  for e in "${DEV_TREE_SECRET_NAMES[@]}"; do DEV_TREE_RSYNC_EXCLUDES+=(--exclude "$(dev_tree_nocase "$e")"); done

  # The same bulk folders as find(1) prune rules, and the secret names as -iname tests.
  local bulk=() named=()
  for e in "${DEV_TREE_EXCLUDES[@]}"; do
    case "$e" in
      /*/) bulk+=(-o -path "./${e:1:${#e}-2}") ;;
      */)  bulk+=(-o -name "${e%/}") ;;
    esac
  done
  for e in "${DEV_TREE_SECRET_NAMES[@]}"; do named+=(-o -iname "$e"); done
  named=( \( "${named[@]:1}" \) )

  # Lists are NUL-separated so any legal file name survives.
  { (cd "$src" && find . \( -name .git "${bulk[@]}" \) -prune -o "${named[@]}" -prune -print0) || true; } | dev_tree_strip > "$work/named" || return 1
  dev_tree_repos "$src" "$work/repos" || return 1
  dev_tree_repos "$src" "$work/checkouts" all || return 1

  # Inside an ignored directory: skip .git, bulk folders and rebuildable output.
  bulk_re=$(dev_tree_skip_re "${DEV_TREE_EXCLUDES[@]}")
  rebuild_re=$(dev_tree_skip_re "${DEV_TREE_REBUILDABLE[@]}")
  for e in .git "${DEV_TREE_EXCLUDES[@]}" "${DEV_TREE_REBUILDABLE[@]}"; do
    case "$e" in /*|'*.iso'|.DS_Store) ;; *) prune+=(-o -name "${e%/}") ;; esac
  done
  prune=( \( "${prune[@]:1}" \) )

  : > "$work/ignored" && : > "$work/ignoredd" && : > "$work/gitcfg" && : > "$work/rules" || return 1
  local small
  while IFS= read -r -d '' g; do
    r="${g%/.git}"
    # A worktree's or submodule's ignored files are archived only (like ignoredd): the MacBook
    # sync covers the main checkouts, not n0's worktrees.
    small="$work/ignored"; [[ -d "$src$g" ]] || small="$work/ignoredd"
    if [[ -d "$src$g" && -f "$src$g/config" ]]; then printf '%s\0' "$g/config" >> "$work/gitcfg" || return 1; fi
    if ! "${DEV_TREE_GIT[@]}" -C "$src$r" ls-files -z --others --ignored --exclude-standard --directory > "$work/ls" 2>/dev/null; then
      # Git cannot read this checkout: nothing in it can be told apart, so none of it is mirrored.
      [[ -n "$r" && "$r" != .git && -d "$src$r" ]] || continue
      q="${r//\*/\\*}"; q="${q//\?/\\?}"; q="${q//\[/\\[}"
      printf -- '- /%s/\0' "$q" >> "$work/rules" || return 1
      { (cd "$src" && find "$r" "${prune[@]}" -prune -o -type f ! -name .DS_Store ! -name '*.iso' -size -1025k -print0) || true; } >> "$work/ignoredd" || return 1
      continue
    fi
    while IFS= read -r -d '' f; do
      p="$r/${f%/}"
      [[ -e "$src$p" && ! -L "$src$p" ]] || continue
      # Bulk folders are excluded by DEV_TREE_RSYNC_EXCLUDES already; a secret-named path or
      # one under a secret-named directory is archived whole through `named`.
      [[ "$p" =~ $bulk_re ]] && continue
      dev_tree_in_named "$p" "$work/named" && continue
      q="${p//\*/\\*}"; q="${q//\?/\\?}"; q="${q//\[/\\[}"
      if [[ "$f" == */ ]]; then
        printf -- '- /%s/\0' "$q" >> "$work/rules" || return 1
        [[ "${f%/}" =~ $rebuild_re ]] && continue
        { (cd "$src" && find "$p" "${prune[@]}" -prune -o -type f ! -name .DS_Store ! -name '*.iso' -size -1025k -print0) || true; } >> "$work/ignoredd" || return 1
        continue
      fi
      printf -- '- /%s\0' "$q" >> "$work/rules" || return 1
      [[ -f "$src$p" ]] || continue
      sz=$(stat -f %z "$src$p" 2>/dev/null) || continue
      if (( sz <= 1048576 )); then printf '%s\0' "$p" >> "$small" || return 1; fi
    done < "$work/ls"
  done < "$work/checkouts"
  return 0
}

# dev_tree_in_named <path> <named-list>: true if <path> or a directory above it is listed.
dev_tree_in_named() {
  local x="$1"
  while :; do
    grep -qzxF -- "$x" "$2" && return 0
    [[ "$x" == */* ]] || return 1
    x="${x%/*}"
  done
}

dev_tree_strip() { local p; while IFS= read -r -d '' p; do printf '%s\0' "${p#./}"; done; }
