autoload colors && colors
# cheers, @ehrenmurdick
# http://github.com/ehrenmurdick/config/blob/master/zsh/prompt.zsh

if (( $+commands[git] ))
then
  git="$commands[git]"
else
  git="/usr/bin/git"
fi
# The prompt runs git in whatever directory you cd into. A checked-out tree can hold a
# repo-shaped directory (a bare repo with core.worktree) whose config sets core.fsmonitor,
# which git would execute. Ignore implicit bare repos and never run an fsmonitor hook here.
git=("$git" -c safe.bareRepository=explicit -c core.fsmonitor=false)

git_branch() {
  echo $($git symbolic-ref HEAD 2>/dev/null | awk -F/ {'print $NF'})
}

# `git status` re-hashes a changed file through the filter driver .gitattributes names, and a
# repo's own .git/config (or a file it includes) can define that driver as any command. Blank
# every repo-local driver for the prompt's status calls; global/system ones (git-lfs) stay.
# The overrides go in through GIT_CONFIG_KEY_n/VALUE_n, which take the key verbatim: a driver
# named 'x=y' would be split at '=' by `-c`. Submodules are not entered (their configs would
# get the same chance).
git_status_safe() {
  local -a kv envs
  local scope name d k
  local -i n=${GIT_CONFIG_COUNT:-0}
  kv=(${(0)"$($git config -z --show-scope --name-only --get-regexp '^filter\.' 2>/dev/null)"})
  while (( ${#kv} >= 2 )); do
    scope=$kv[1] name=$kv[2]
    kv=("${(@)kv[3,-1]}")
    [[ $scope == (local|worktree) && $name == filter.*.* ]] || continue
    d=${${name#filter.}%.*}
    for k in clean smudge process required; do
      envs+=("GIT_CONFIG_KEY_$n=filter.$d.$k" "GIT_CONFIG_VALUE_$n=${${k:#required}:+}${${(M)k:#required}:+false}")
      (( n++ ))
    done
  done
  env "${envs[@]}" GIT_CONFIG_COUNT=$n $git status --ignore-submodules=all "$@"
}

git_dirty() {
  if $(! git_status_safe -s &> /dev/null)
  then
    echo ""
  else
    if [[ $(git_status_safe --porcelain) == "" ]]
    then
      echo "on %{$fg_bold[green]%}$(git_prompt_info)%{$reset_color%}"
    else
      echo "on %{$fg_bold[red]%}$(git_prompt_info)%{$reset_color%}"
    fi
  fi
}

git_prompt_info () {
 ref=$($git symbolic-ref HEAD 2>/dev/null) || return
# echo "(%{\e[0;33m%}${ref#refs/heads/}%{\e[0m%})"
 echo "${ref#refs/heads/}"
}

# This assumes that you always have an origin named `origin`, and that you only
# care about one specific origin. If this is not the case, you might want to use
# `$git cherry -v @{upstream}` instead.
need_push () {
  if [ $($git rev-parse --is-inside-work-tree 2>/dev/null) ]
  then
    number=$($git cherry -v origin/$($git symbolic-ref --short HEAD) 2>/dev/null | wc -l | bc)

    if [[ $number == 0 ]]
    then
      echo " "
    else
      echo " with %{$fg_bold[magenta]%}$number unpushed%{$reset_color%}"
    fi
  fi
}

directory_name() {
  echo "%{$fg_bold[cyan]%}%1/%\/%{$reset_color%}"
}

battery_status() {
  if [[ $(sysctl -n hw.model) == *"Book"* ]]
  then
    $ZSH/bin/battery-status
  fi
}

export PROMPT=$'\n$(battery_status)in $(directory_name) $(git_dirty)$(need_push)\n› '
set_prompt () {
  export RPROMPT="%{$fg_bold[cyan]%}%{$reset_color%}"
}

precmd() {
  title "zsh" "%m" "%55<...<%~"
  set_prompt
}
