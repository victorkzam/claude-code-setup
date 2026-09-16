#!/bin/bash
# PreToolUse(Bash) — block pushes whose DESTINATION is main/master, and force
# pushes. Blocks by destination, never by a branch-name substring, so a feature
# branch whose name merely contains "main"/"master" (e.g. `git push -u origin
# feat/main-nav`) is allowed. Backslash-newline continuations are joined, then
# the command is split into segments on &&, ||, ;, |, (, ), and newlines, and
# each segment is tokenized independently (with one layer of surrounding
# quotes stripped from each token) so chained/grouped commands like
# `(cd /tmp && git push origin main)` are still caught. Each segment's tokens
# are scanned for a `git` invocation, tolerating leading env assignments
# (FOO=bar) and global options (-C <dir>, -c k=v, ...) before the subcommand.

if ! command -v jq >/dev/null 2>&1; then
  echo "cw: jq not found, hook skipped" >&2
  exit 0
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

TAB="$(printf '\t')"

block() { echo "Blocked: $1" >&2; exit 2; }

# Splits $1 on whitespace into the global array TOK. A single- or double-
# quoted span is treated as part of the current word and that one layer of
# quoting is stripped (e.g. "main" -> main). Not a full shell parser: nested
# shells (bash -c "..."), escaped quotes, and multi-quote-region words are
# out of scope.
tokenize() {
  s="$1"
  i=0
  n=${#s}
  q=""
  buf=""
  started=0
  TOK=()
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        q=""
      else
        buf="$buf$c"
      fi
    elif [ "$c" = '"' ] || [ "$c" = "'" ]; then
      q="$c"
      started=1
    elif [ "$c" = " " ] || [ "$c" = "$TAB" ]; then
      if [ "$started" = 1 ]; then
        TOK+=( "$buf" )
        buf=""
        started=0
      fi
    else
      buf="$buf$c"
      started=1
    fi
    i=$((i+1))
  done
  [ "$started" = 1 ] && TOK+=( "$buf" )
}

check_segment() {
  seg="$1"
  tokenize "$seg"
  n=${#TOK[@]}

  is_push=0
  GITDIR=""
  i=0
  while [ "$i" -lt "$n" ]; do
    t="${TOK[$i]}"
    case "$t" in
      *=*) i=$((i+1)); continue ;;            # leading env assignment
    esac
    if [ "$t" = "git" ] || [ "${t##*/}" = "git" ]; then
      j=$((i+1))
      while [ "$j" -lt "$n" ]; do
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
  [ "$is_push" = 1 ] || return 0

  # Collect positional (non-option) args after `push`; flag force options and
  # `+`-prefixed (forced) refspecs.
  pos=()
  k=0; m=${#REF[@]}
  while [ "$k" -lt "$m" ]; do
    a="${REF[$k]}"
    case "$a" in
      --force|--force-if-includes|--force-with-lease|--force-with-lease=*)
        block "force push is not allowed." ;;
      -o|--push-option|--repo)
        k=$((k+2)); continue ;;               # option that consumes a separate-word arg
      -[A-Za-z]*)
        case "$a" in *f*) block "force push is not allowed." ;; esac
        k=$((k+1)); continue ;;               # short-option cluster without -f
      --*)
        k=$((k+1)); continue ;;               # other long option (incl. --opt=val)
      -*)
        k=$((k+1)); continue ;;               # any other dash token
      +*)
        block "force push (+ refspec) is not allowed." ;;
      *)
        pos+=( "$a" ); k=$((k+1)) ;;
    esac
  done

  # Destination checks over positional tokens (remote, refspecs, bare refs).
  has_explicit_ref=0
  for p in "${pos[@]}"; do
    case "$p" in
      *:*)                                   # src:dst (or :dst)
        dst="${p##*:}"; dst="${dst#refs/heads/}"
        has_explicit_ref=1
        { [ "$dst" = main ] || [ "$dst" = master ]; } && block "push destination is main/master. Use a feature branch." ;;
      *)
        base="${p#refs/heads/}"
        if [ "$base" = main ] || [ "$base" = master ]; then
          block "pushing to main/master is not allowed. Use a feature branch."
        fi
        # A bare branch-name ref (contains a slash) counts as an explicit
        # destination. A bare `HEAD` does not: it still resolves against the
        # current branch of the repo at cwd, same as a refspec-less push.
        case "$p" in */*) has_explicit_ref=1 ;; esac ;;
    esac
  done

  # Refspec-less push (`git push`, `git push origin`, `git push -u origin
  # HEAD`): resolve the current branch and block if it is main/master. If git
  # resolution fails (not a repo), do NOT block — /ship is the backstop.
  npos=${#pos[@]}
  if [ "$has_explicit_ref" = 0 ] && { [ "$npos" -le 1 ] || [ "${pos[*]: -1}" = "HEAD" ]; }; then
    BR=$(git -C "${GITDIR:-${CWD:-.}}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
      block "current branch is $BR; push from a feature branch."
    fi
  fi
  return 0
}

# Join backslash-newline continuations into a single space. Done with a plain
# bash read loop, not `sed N`, because BSD sed's N silently drops the final
# line when the input has no trailing newline (as $CMD does not).
CMD_JOINED=""
while IFS= read -r jline || [ -n "$jline" ]; do
  if [ -z "$CMD_JOINED" ]; then
    CMD_JOINED="$jline"
  else
    case "$CMD_JOINED" in
      *\\) CMD_JOINED="${CMD_JOINED%\\} $jline" ;;
      *) CMD_JOINED="$CMD_JOINED
$jline" ;;
    esac
  fi
done <<EOF
$CMD
EOF

# Split the command into segments on &&, ||, ;, |, (, ), and newlines,
# tab-flatten each segment, then check every segment independently.
CMD_SEGMENTED=$(printf '%s' "$CMD_JOINED" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g' -e 's/(/\n/g' -e 's/)/\n/g')
while IFS= read -r line; do
  seg_flat=$(printf '%s' "$line" | tr '\t' ' ')
  [ -z "${seg_flat// /}" ] && continue
  check_segment "$seg_flat"
done <<EOF
$CMD_SEGMENTED
EOF

exit 0
