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
  node_modules/ .venv/ venv/ .terraform/ dist/ .astro/ .next/ .cache/ .aws-sam/
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
  settings.local.json .mcp.json '*.age' '*.gpg' '*.asc'
)

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

# dev_tree_repos <src/> <outfile>: NUL-separated list of every .git directory under <src>
# (nested ones too), relative to <src>, bulk folders pruned. The repo half of dev_tree_lists,
# on its own because bin/dev-pull needs only this and the ignored-file scan is slow.
dev_tree_repos() {
  local src="$1" out="$2" e bulk=()
  for e in "${DEV_TREE_EXCLUDES[@]}"; do
    case "$e" in
      /*/) bulk+=(-o -path "./${e:1:${#e}-2}") ;;
      */)  bulk+=(-o -name "${e%/}") ;;
    esac
  done
  (cd "$src" && find . -name .git -type d -prune -print0 -o \( -false "${bulk[@]}" \) -prune) | dev_tree_strip > "$out"
}

# dev_tree_private_files <src/> <workdir>: NUL-separated paths of what git does not carry:
# the named + gitignored set from dev_tree_lists minus every file tracked in the checkout or on
# an origin branch (directories in the named set expand to their files). Needs dev_tree_lists output in <workdir>. Used by the
# MacBook sync in both directions (bin/dev-sync-from-n0 --manifest on n0, bin/dev-push-to-n0
# on the laptop), so the two directions carry the same set.
dev_tree_private_files() {
  local src="$1" work="$2" g r p e skip=""
  # The bulk/junk names of DEV_TREE_EXCLUDES as one regex: git lists a cache directory's own
  # .gitignore and the odd .DS_Store as ignored files, and neither is worth carrying.
  for e in "${DEV_TREE_EXCLUDES[@]}"; do
    e="${e#/}"; e="${e%/}"; e="${e//./\\.}"; e="${e//\*/.*}"
    skip+="${skip:+|}(^|/)$e(/|$)"
  done
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
#   named    files and directories with a secret-bearing name (bulk folders and .git pruned)
#   ignored  gitignored regular files outside ignored directories, up to 1 MiB
#   gitcfg   each repo's .git/config
#   rules    rsync exclude rules ('- /path') for everything in `ignored`
# Also fills DEV_TREE_RSYNC_EXCLUDES with --exclude args for .git, the bulk folders and the
# secret names (case-insensitive).
dev_tree_lists() {
  local src="$1" work="$2" e g r f p q
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
  (cd "$src" && find . \( -name .git "${bulk[@]}" \) -prune -o "${named[@]}" -prune -print0) | dev_tree_strip > "$work/named"
  dev_tree_repos "$src" "$work/repos"

  : > "$work/ignored"; : > "$work/gitcfg"; : > "$work/rules"
  while IFS= read -r -d '' g; do
    r="${g%/.git}"
    [[ -f "$src$g/config" ]] && printf '%s\0' "$g/config" >> "$work/gitcfg"
    while IFS= read -r -d '' f; do
      [[ "$f" == */ ]] && continue
      p="$r/$f"
      [[ -f "$src$p" && ! -L "$src$p" ]] || continue
      (( $(stat -f %z "$src$p") <= 1048576 )) || continue
      printf '%s\0' "$p" >> "$work/ignored"
      q="${p//\*/\\*}"; q="${q//\?/\\?}"; q="${q//\[/\\[}"
      printf -- '- /%s\0' "$q" >> "$work/rules"
    done < <("${DEV_TREE_GIT[@]}" -C "$src$r" ls-files -z --others --ignored --exclude-standard --directory 2>/dev/null || true)
  done < "$work/repos"
}

dev_tree_strip() { local p; while IFS= read -r -d '' p; do printf '%s\0' "${p#./}"; done; }
