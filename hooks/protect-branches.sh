#!/bin/bash
# PreToolUse(Bash, git *) — block pushes whose DESTINATION is main/master, and force
# pushes. Blocks by destination, never by a branch-name substring, so a feature branch
# whose name merely contains "main"/"master" (e.g. `git push -u origin feat/main-nav`)
# is allowed. Tokenizes the command so `git -C <dir> push`, `git -c k=v push`,
# `git --git-dir=... push`, `env X=Y git push`, `/usr/bin/git push` are all recognized.
# `/ship`'s "refuse if on main" is the backstop for the refspec-less heuristic.

# Fail closed: this hook parses tool input with jq. Without jq we cannot safely
# decide, so block rather than silently letting an unchecked push through.
command -v jq >/dev/null 2>&1 || { echo "jq required for this hook — install jq or remove it from settings.json" >&2; exit 2; }

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Flatten newlines so a one-line `read -a` tokenization sees the whole command.
CMD_FLAT=$(printf '%s' "$CMD" | tr '\n\t' '  ')
read -r -a TOK <<< "$CMD_FLAT"
n=${#TOK[@]}

# Locate a `git` invocation and its subcommand, tolerating leading env assignments
# (FOO=bar), an absolute path to git, and global options before the subcommand.
is_push=0
i=0
while [ $i -lt $n ]; do
  t="${TOK[$i]}"
  case "$t" in
    *=*) i=$((i+1)); continue ;;            # leading env assignment
  esac
  if [ "$t" = "git" ] || [ "${t##*/}" = "git" ]; then
    j=$((i+1))
    while [ $j -lt $n ]; do
      a="${TOK[$j]}"
      case "$a" in
        -C) GITDIR="${TOK[$((j+1))]}"; j=$((j+2)); continue ;;   # capture repo dir
        -c|--git-dir|--work-tree|--namespace|--exec-path|-o|--push-option|--repo)
          j=$((j+2)); continue ;;           # option that consumes a separate-word arg
        --*=*|-*) j=$((j+1)); continue ;;   # single-token option (incl. --opt=val)
        push) is_push=1; REF=( "${TOK[@]:$((j+1))}" ); break ;;
        *) break ;;                          # a different subcommand (log/commit/...)
      esac
    done
    break
  fi
  i=$((i+1))
done
[ "$is_push" = 1 ] || exit 0

block() { echo "Blocked: $1" >&2; exit 2; }

# Collect positional (non-option) args after `push`; flag force options.
pos=()
k=0; m=${#REF[@]}
while [ $k -lt $m ]; do
  a="${REF[$k]}"
  case "$a" in
    --force|--force-with-lease|--force-with-lease=*|--force-if-includes|-f)
      block "force push is not allowed." ;;
    -o|--push-option|--repo) k=$((k+2)); continue ;;   # option + its arg
    --*=*|-*) k=$((k+1)); continue ;;                  # other option
    *) pos+=( "$a" ); k=$((k+1)) ;;
  esac
done

# Destination checks over positional tokens (remote, refspecs, bare refs).
has_explicit_ref=0
for p in "${pos[@]}"; do
  case "$p" in
    *:*)                                   # src:dst (or +src:dst, :dst)
      dst="${p##*:}"; dst="${dst#refs/heads/}"
      has_explicit_ref=1
      { [ "$dst" = main ] || [ "$dst" = master ]; } && block "push destination is main/master. Use a feature branch." ;;
    *)
      base="${p#refs/heads/}"
      if [ "$base" = main ] || [ "$base" = master ]; then
        block "pushing to main/master is not allowed. Use a feature branch."
      fi
      # A bare ref like HEAD or a branch name counts as explicit (not refspec-less),
      # except a lone remote name. We treat anything that is not clearly the remote
      # conservatively: HEAD or a slash/feature ref => explicit.
      case "$p" in HEAD|*/*) has_explicit_ref=1 ;; esac ;;
  esac
done

# Refspec-less push (`git push`, `git push origin`, `git push -u origin HEAD`):
# resolve the current branch and block if it is main/master. If git resolution
# fails (not a repo), do NOT block — /ship is the backstop.
npos=${#pos[@]}
if [ "$has_explicit_ref" = 0 ] && { [ "$npos" -le 1 ] || [ "${pos[*]: -1}" = "HEAD" ]; }; then
  BR=$(git -C "${GITDIR:-${CWD:-.}}" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
    block "current branch is $BR; push from a feature branch."
  fi
fi

exit 0
