#!/bin/bash
# PreToolUse(Bash) — block pushes whose DESTINATION is main/master, force
# pushes, and pushes of every branch (--all/--mirror). Blocks by destination,
# never by a branch-name substring, so a feature branch whose name merely
# contains "main"/"master" (e.g. `git push -u origin feat/main-nav`) is
# allowed. The command text is normalised once (backslash-newline
# continuations joined, quote characters and backslashes stripped, tabs
# flattened) so a nested-shell body such as `sh -c "git push origin main"`
# is scanned the same as a top-level command, at any nesting depth: quote
# removal turns it into the flat tokens `sh -c git push origin main`, which
# the scanner below reads the same way it reads a top-level invocation.
# `cd`/`pushd` and `git switch`/`git checkout` are tracked across segments,
# in order, the last change wins, so a refspec-less push after a directory
# or branch change resolves against the tracked state instead of the hook's
# own cwd; state the text cannot resolve (an interpolated `$VAR`, `-`,
# `popd`, a detached checkout) blocks with a hint rather than silently
# falling through.
#
# Scope: a guardrail against the agent's own accidental pushes, not a
# sandbox. Out of scope: a command held in a variable and `eval`ed
# indirectly, an xargs-fed refspec, a shell wrapper or alias not named
# `git`, and `git -c k="v w"` before push (the embedded space defeats the
# word split). A `cd` or branch change the hook cannot resolve blocks with a
# hint instead of guessing. Quoted prose that spells a push to main — inside
# `echo "…"`, a heredoc line, a `--body "…"` — is blocked as if it were the
# command; a heredoc line was already blocked before this change, and the
# remedy is the same: keep such text in a file.

if ! command -v jq >/dev/null 2>&1; then
  echo "cw: jq not found, hook skipped" >&2
  exit 0
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

[ -z "$CMD" ] && exit 0

block() { echo "Blocked: $1" >&2; exit 2; }

TRACK_DIR=""
TRACK_BRANCH=""

# Refspec-less push resolution, shared by the -C path and the tracked/cwd
# path: only when push.default is upstream/tracking, and only when no
# positional token is HEAD and there are at most one, does an upstream
# ending in main/master block.
check_upstream() {
  dir="$1"
  [ "$npos" -gt 1 ] && return 0
  headfound=0
  for p in "${pos[@]}"; do
    [ "$p" = "HEAD" ] && headfound=1
  done
  [ "$headfound" = 1 ] && return 0
  pd=$(git -C "$dir" config --get push.default 2>/dev/null)
  case "$pd" in
    upstream | tracking) : ;;
    *) return 0 ;;
  esac
  up=$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  case "$up" in
    */main | */master)
      block "current branch tracks $up and push.default is upstream; push to a feature branch explicitly." ;;
  esac
  return 0
}

# `git switch`/`git checkout` branch resolution: walk the tokens after the
# subcommand with positional parameters (shift), never an indexed array.
# `-b`/`-B`/`-c`/`-C` name the branch in the next token and stop immediately.
# `--`, `-p`, `--patch`, `HEAD`, `-`, or a token containing `$` make the
# branch unknown and stop. Any other `-` option is skipped. The walk does
# NOT stop at the first positional: it is remembered as a tentative branch
# and scanning continues, so a later `--` or a second positional (a path
# checkout such as `git checkout feat/x -- README.md`) still makes the
# branch unknown instead of leaving the first token recorded as a branch
# change that never happened.
resolve_switch_branch() {
  branch=""
  found_positional=0
  while [ $# -gt 0 ]; do
    sa="$1"
    shift
    case "$sa" in
      -b | -B | -c | -C)
        if [ $# -eq 0 ]; then
          TRACK_BRANCH=unknown
        else
          TRACK_BRANCH="$1"
        fi
        return ;;
      -- | -p | --patch | HEAD | -)
        TRACK_BRANCH=unknown
        return ;;
      *'$'*)
        TRACK_BRANCH=unknown
        return ;;
      -*)
        continue ;;
      *)
        if [ "$found_positional" = 1 ]; then
          TRACK_BRANCH=unknown
          return
        fi
        branch="$sa"
        found_positional=1
        continue ;;
    esac
  done
  if [ "$found_positional" = 1 ]; then
    TRACK_BRANCH="$branch"
  else
    TRACK_BRANCH=unknown
  fi
}

# cd/pushd/popd tracking over one segment's tokens: a linear scan with
# positional parameters (shift), never an indexed array, so it stays O(n)
# under bash 3.2 (indexed-array element access there is O(i), which turns an
# indexed loop into O(n^2) — the measured cost of the old TOK[$i] walk). A
# `cd`/`pushd` token (first occurrence, any position) records the following
# non-option token as the directory, skipping over option tokens longer than
# one character (`-P`, `-L`, `--`, `-e`, ...); a bare `-`, no argument, or an
# argument containing `$` records the directory as unknown. A `popd` token
# anywhere in the segment also records the directory as unknown and clears
# the branch, regardless of whether `cd`/`pushd` appears too. Either trigger
# clears the recorded branch, because it belonged to the directory or branch
# that came before.
scan_cd_popd() {
  found_cd=0
  awaiting_arg=0
  has_popd=0
  while [ $# -gt 0 ]; do
    t="$1"
    shift
    [ "$t" = popd ] && has_popd=1
    if [ "$awaiting_arg" = 1 ]; then
      case "$t" in
        -)
          TRACK_DIR=unknown
          awaiting_arg=0 ;;
        -?*)
          continue ;;                                     # option token (-P, -L, --, -e...): skip, keep waiting
        *'$'*)
          TRACK_DIR=unknown
          awaiting_arg=0 ;;
        /*)
          TRACK_DIR="$t"
          awaiting_arg=0 ;;
        *)
          if [ -n "$CWD" ]; then
            TRACK_DIR="$CWD/$t"
          else
            TRACK_DIR="$t"
          fi
          awaiting_arg=0 ;;
      esac
    elif [ "$found_cd" = 0 ] && { [ "$t" = cd ] || [ "$t" = pushd ]; }; then
      found_cd=1
      awaiting_arg=1
    fi
  done
  [ "$awaiting_arg" = 1 ] && TRACK_DIR=unknown
  { [ "$found_cd" = 1 ] || [ "$has_popd" = 1 ]; } && TRACK_BRANCH=""
  [ "$has_popd" = 1 ] && TRACK_DIR=unknown
}

# Push-arguments processing: `$@` is exactly the tokens after `push`, handed
# over from locate_git without a copy. `pos` collects the positional
# (non-option) tokens with a shift loop, then the destination checks walk
# `pos` with a plain `for`, which bash already iterates in one pass (no
# computed index).
handle_push() {
  pos=()
  while [ $# -gt 0 ]; do
    a="$1"
    shift
    case "$a" in
      --force)
        block "force push is not allowed." ;;
      --all | --mirror)
        block "pushing every branch (--all/--mirror) is not allowed." ;;
      -o | --push-option | --repo)
        shift ;;                                          # option that consumes a separate-word arg
      -[A-Za-z]*)
        case "$a" in *f*) block "force push is not allowed." ;; esac ;;
      --*)
        : ;;                                               # other long option (incl. --opt=val)
      -*)
        : ;;                                               # any other dash token
      +*)
        block "force push (+ refspec) is not allowed." ;;
      *)
        pos+=("$a") ;;
    esac
  done

  # Destination checks over positional tokens (remote, refspecs, bare refs).
  has_explicit_ref=0
  for p in "${pos[@]}"; do
    case "$p" in
      *:*)                                                 # src:dst (or :dst)
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
        # current branch, same as a refspec-less push.
        case "$p" in */*) has_explicit_ref=1 ;; esac ;;
    esac
  done

  # Refspec-less push (`git push`, `git push origin`, `git push -u origin
  # HEAD`): resolve the destination from tracked state, a push segment's own
  # `-C`, or the hook's cwd, in that order, and block if it lands on
  # main/master. State the text cannot resolve blocks with a hint instead of
  # silently falling through. Resolution failure (not a repo) allows, as
  # today.
  npos=${#pos[@]}
  if [ "$has_explicit_ref" = 0 ] && { [ "$npos" -le 1 ] || [ "${pos[*]: -1}" = "HEAD" ]; }; then
    if [ -n "$GITDIR" ]; then
      BR=$(git -C "$GITDIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
        block "current branch is $BR; push from a feature branch."
      fi
      check_upstream "$GITDIR"
    elif [ -n "$TRACK_BRANCH" ] && [ "$TRACK_BRANCH" != "unknown" ]; then
      if [ "$TRACK_BRANCH" = "main" ] || [ "$TRACK_BRANCH" = "master" ]; then
        block "current branch is $TRACK_BRANCH; push from a feature branch."
      fi
    elif [ "$TRACK_BRANCH" = "unknown" ] || [ "$TRACK_DIR" = "unknown" ]; then
      block "cannot determine the destination after a cd or branch change; use an explicit refspec such as git push origin <branch>."
    else
      rdir="${TRACK_DIR:-${CWD:-.}}"
      BR=$(git -C "$rdir" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
        block "current branch is $BR; push from a feature branch."
      fi
      check_upstream "$rdir"
    fi
  fi
}

# Locate a git invocation: first git-spelled token (case-insensitive,
# tolerating a leading path), env assignments and other tokens skipped while
# searching — a linear scan with positional parameters (shift), matching
# scan_cd_popd's technique, so it stays O(n) under bash 3.2. Once found,
# walks git's own options (skipping a separate-word argument for
# -C/-c/--git-dir/etc, recording -C's argument as GITDIR) until it reaches
# `push`, `switch`, or `checkout`, at which point the remaining tokens
# (still `$@`, no copy) are handed straight to the matching handler.
locate_git() {
  git_found=0
  expect_val=""
  GITDIR=""
  while [ $# -gt 0 ]; do
    t="$1"
    shift

    if [ "$git_found" = 0 ]; then
      case "$t" in
        *=*) ;;
        git | [Gg][Ii][Tt] | */git | */[Gg][Ii][Tt]) git_found=1 ;;
      esac
      continue
    fi

    if [ -n "$expect_val" ]; then
      if [ "$expect_val" = gitdir ]; then
        case "$t" in
          /*) GITDIR="$t" ;;
          *)
            if [ -n "$CWD" ]; then
              GITDIR="$CWD/$t"
            else
              GITDIR="$t"
            fi ;;
        esac
      fi
      expect_val=""
      continue
    fi

    case "$t" in
      -C)
        expect_val=gitdir ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path | -o | --push-option | --repo)
        expect_val=skip ;;                                # option that consumes a separate-word arg
      --*=* | -*)
        : ;;                                               # single-token option (incl. --opt=val)
      push)
        handle_push "$@"
        return ;;
      switch | checkout)
        resolve_switch_branch "$@"
        return ;;
      *)
        return ;;                                          # a different subcommand (log/commit/...)
    esac
  done
}

check_segment() {
  seg="$1"
  [ -z "$seg" ] && return 0
  # Skip cheaply unless the segment could possibly hold a git/cd/pushd/popd
  # invocation, before paying for the word split.
  case "$seg" in
    *[Gg][Ii][Tt]* | *cd* | *pushd* | *popd*) : ;;
    *) return 0 ;;
  esac

  set -f
  # shellcheck disable=SC2086 # deliberate word splitting with globbing off, no here-string, no process
  set -- $seg
  set +f
  [ $# -eq 0 ] && return 0

  scan_cd_popd "$@"
  locate_git "$@"
  return 0
}

# Join backslash-newline continuations (one process), strip quote characters
# and backslashes (one process), flatten tabs to spaces (one process). Linear
# in C throughout; no per-character loop.
CMD_JOINED=$(printf '%s\n' "$CMD" | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }')
CMD_NORM=$(printf '%s' "$CMD_JOINED" | tr -d $'"\'\\' | tr '\t' ' ')

# Fast path: a command whose normalised text contains no "push" substring
# exits 0 before any further parsing.
case "$CMD_NORM" in
  *push*) ;;
  *) exit 0 ;;
esac

# Split into segments on &&, ||, ;, |, (, ), backticks, and a bare & (added
# after the && rule, so `2>&1` splits into harmless pieces, not the operator
# itself), then newlines. One process; no further process per segment.
CMD_SPLIT=$(printf '%s' "$CMD_NORM" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g' -e 's/(/\n/g' -e 's/)/\n/g' -e 's/`/\n/g' -e 's/&/\n/g')
while IFS= read -r line; do
  # Blank-or-all-spaces check via a case glob, not "${line// /}": bash 3.2's
  # global pattern substitution rebuilds the string per match, which is
  # O(n^2) for a line with many spaces (measured: tens of seconds on a
  # ~17KB line) — the same class of bug as an indexed-array walk.
  case "$line" in
    *[^\ ]*) : ;;
    *) continue ;;
  esac
  check_segment "$line"
done <<EOF
$CMD_SPLIT
EOF

exit 0
