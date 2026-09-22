#!/bin/bash
# PreToolUse(Bash) — block pushes whose DESTINATION is main/master, force
# pushes, and pushes of every branch (--all/--mirror). Blocks by destination,
# never by a branch-name substring, so a feature branch whose name merely
# contains "main"/"master" (e.g. `git push -u origin feat/main-nav`) is
# allowed, and a lease-style force option (--force-with-lease,
# --force-if-includes) to a destination other than main/master passes. The
# command text is normalised once (backslash-newline continuations joined,
# quote characters and backslashes stripped, tabs flattened) so a
# nested-shell body such as `sh -c "git push origin main"` is scanned the
# same as a top-level command, at any nesting depth: quote removal turns it
# into the flat tokens `sh -c git push origin main`, which the scanner below
# reads the same way it reads a top-level invocation.
# `cd`/`pushd` and `git switch`/`git checkout` are tracked across segments,
# in order, the last change wins, so a refspec-less push after a directory
# or branch change resolves against the tracked state instead of the hook's
# own cwd; state the text cannot resolve (an interpolated `$VAR`, `-`,
# `popd`, a detached checkout) blocks with a hint rather than silently
# falling through.
#
# Rule S (subshell scoping): a `(...)`, `$(...)`, or backtick-quoted body is
# its own scope — a `cd` or checkout inside it is restored when it closes,
# so it cannot leak into a bare push that follows outside; a plain checkout
# inside the scope (one the text cannot attribute to a directory of its
# own) leaves the branch unknown on close instead of silently reverting,
# since it did change on-disk state the outer command never asked for. Both
# effects propagate outward through nested scopes, so an outer close also
# lands on unknown instead of restoring past an inner scope that saw one.
# When the whole command's parens/backticks don't balance (a stray `)` in
# prose, e.g. inside a commit message, closes a scope early), a `cd` inside
# the closing scope leaves the directory unknown too, rather than trusting a
# restore the text cannot actually attribute to that close.
# Rule C (cd, second positional): a `cd` followed by a second directory-
# shaped positional in the same segment (the shell itself would reject two
# directory arguments; the real-world source is a quoted path with a space
# whose quotes were already stripped) marks the destination unknown rather
# than guessing which one wins. A redirection — operand attached
# (`2>/dev/null`) or a bare operator followed by its operand as a separate
# token (`> /dev/null`) — is exempt, as is a trailing `#` comment.
# Rule G (checkout via `-C`): `git -C <dir> switch`/`checkout` changes
# another repository's on-disk branch without touching the cd/branch state
# tracked for the command's own directory; a later push whose own `-C` (or
# tracked directory) names that same repository resolves against that
# checkout instead of a stale `rev-parse`.
#
# Scope: a guardrail against the agent's own accidental pushes, not a
# sandbox. Out of scope: a command held in a variable and `eval`ed
# indirectly, an xargs-fed refspec, a shell wrapper or alias not named
# `git`, `git -c k="v w"` before push (the embedded space defeats the word
# split), and a `gh api` call. A `cd` or branch change the hook cannot
# resolve blocks with a hint instead of guessing. Quoted prose that spells a
# push to main — inside `echo "…"`, a heredoc line, a `--body "…"` — is
# blocked as if it were the command; a heredoc line was already blocked
# before this change, and the remedy is the same: keep such text in a file.

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

# Rule G state: the directory and branch of the most recent `-C <dir>
# switch/checkout`, a single slot a later `-C` checkout overwrites. This is
# on-disk state for another repository, not the command's own tracked
# directory, so rule S never saves or restores it across a subshell.
C_DIR=""
C_BRANCH=""

# Normalise a path used for a same-repository comparison (C_DIR, GITDIR,
# TRACK_DIR are each passed through this at the point they are set): strip a
# leading "./" from a relative path, collapse any "/./" segment to "/", and
# strip trailing slashes (never the root "/"). Otherwise-equivalent spellings
# of one directory (`rf`, `rf/`, `./rf`) then compare equal by plain string
# comparison. Sets NORM_PATH; no subshell, no process — path text only,
# O(length of the path), the same technique as walk_switch_branch's
# RESOLVED_BRANCH.
norm_path() {
  NORM_PATH="$1"
  case "$NORM_PATH" in
    ./?*) NORM_PATH="${NORM_PATH#./}" ;;
  esac
  while :; do
    case "$NORM_PATH" in
      */./*) NORM_PATH="${NORM_PATH%%/./*}/${NORM_PATH#*/./}" ;;
      *) break ;;
    esac
  done
  while :; do
    case "$NORM_PATH" in
      */) NORM_PATH="${NORM_PATH%/}" ;;
      *) break ;;
    esac
  done
  [ -z "$NORM_PATH" ] && NORM_PATH="/"
}

# Rule S state: a subshell/command-substitution/backtick nesting depth, with
# a pair of arrays (indexed by depth, which stays tiny — the O(i) indexed-
# array cost noted below does not apply here) saving TRACK_DIR/TRACK_BRANCH
# on open, and a per-depth flag recording whether a plain (no `-C`)
# switch/checkout ran inside that scope. CD_SEEN is the same shape for a
# `cd`/`pushd`/`popd` inside that scope, read by close_subshell together
# with BALANCED (below) to decide whether TRACK_DIR can be restored on an
# unbalanced close. Both flags propagate to the parent scope's slot on
# close, so an enclosing close also lands on unknown/unrestorable instead of
# silently reverting past a nested scope that saw one. BT_OPEN tracks
# whether the next backtick in reading order opens or closes a scope.
SUBSHELL_DEPTH=0
SAVE_DIR=()
SAVE_BRANCH=()
CHK_SEEN=()
CD_SEEN=()
BT_OPEN=0

open_subshell() {
  SAVE_DIR[SUBSHELL_DEPTH]="$TRACK_DIR"
  SAVE_BRANCH[SUBSHELL_DEPTH]="$TRACK_BRANCH"
  CHK_SEEN[SUBSHELL_DEPTH]=0
  CD_SEEN[SUBSHELL_DEPTH]=0
  SUBSHELL_DEPTH=$((SUBSHELL_DEPTH + 1))
}

close_subshell() {
  # An unbalanced close (quote-stripping can leave one) at depth zero is a
  # no-op. TRACK_DIR is restored from the saved value unless the whole
  # command's parens/backticks are unbalanced (BALANCED=0, set once below)
  # and a cd/pushd/popd ran inside this scope, in which case the text
  # cannot say where the shell is after the close and TRACK_DIR becomes
  # unknown instead. TRACK_BRANCH is restored only when no plain
  # switch/checkout ran inside this scope, otherwise it becomes unknown —
  # the scope changed on-disk state the text cannot attribute back to a
  # directory outside it. Either flag, once set for this depth, propagates
  # to the parent scope's slot so a further enclosing close inherits it too.
  [ "$SUBSHELL_DEPTH" -eq 0 ] && return 0
  SUBSHELL_DEPTH=$((SUBSHELL_DEPTH - 1))
  if [ "$BALANCED" = 1 ] || [ "${CD_SEEN[$SUBSHELL_DEPTH]}" != 1 ]; then
    TRACK_DIR="${SAVE_DIR[$SUBSHELL_DEPTH]}"
  else
    TRACK_DIR=unknown
  fi
  if [ "${CHK_SEEN[$SUBSHELL_DEPTH]}" = 1 ]; then
    TRACK_BRANCH=unknown
  else
    TRACK_BRANCH="${SAVE_BRANCH[$SUBSHELL_DEPTH]}"
  fi
  if [ "$SUBSHELL_DEPTH" -gt 0 ]; then
    [ "${CHK_SEEN[$SUBSHELL_DEPTH]}" = 1 ] && CHK_SEEN[SUBSHELL_DEPTH - 1]=1
    [ "${CD_SEEN[$SUBSHELL_DEPTH]}" = 1 ] && CD_SEEN[SUBSHELL_DEPTH - 1]=1
  fi
}

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
# change that never happened. Sets RESOLVED_BRANCH; shared by the plain
# path (resolve_switch_branch, below) and rule G's `-C` path in locate_git,
# which read RESOLVED_BRANCH into TRACK_BRANCH or C_BRANCH respectively.
walk_switch_branch() {
  branch=""
  found_positional=0
  while [ $# -gt 0 ]; do
    sa="$1"
    shift
    case "$sa" in
      -b | -B | -c | -C)
        if [ $# -eq 0 ]; then
          RESOLVED_BRANCH=unknown
        else
          RESOLVED_BRANCH="$1"
        fi
        return ;;
      -- | -p | --patch | HEAD | -)
        RESOLVED_BRANCH=unknown
        return ;;
      *'$'*)
        RESOLVED_BRANCH=unknown
        return ;;
      -*)
        continue ;;
      *)
        if [ "$found_positional" = 1 ]; then
          RESOLVED_BRANCH=unknown
          return
        fi
        branch="$sa"
        found_positional=1
        continue ;;
    esac
  done
  if [ "$found_positional" = 1 ]; then
    RESOLVED_BRANCH="$branch"
  else
    RESOLVED_BRANCH=unknown
  fi
}

resolve_switch_branch() {
  walk_switch_branch "$@"
  TRACK_BRANCH="$RESOLVED_BRANCH"
}

# cd/pushd/popd tracking over one segment's tokens: a linear scan with
# positional parameters (shift), never an indexed array, so it stays O(n)
# under bash 3.2 (indexed-array element access there is O(i), which turns an
# indexed loop into O(n^2) — the measured cost of the old TOK[$i] walk). A
# `cd`/`pushd` token (first occurrence, any position) records the following
# non-option token as the directory (passed through norm_path, rule G/S/C's
# shared path spelling), skipping over option tokens longer than one
# character (`-P`, `-L`, `--`, `-e`, ...); a bare `-`, no argument, or an
# argument containing `$` records the directory as unknown. A token starting
# with `#` stops the scan outright — a trailing comment's words are not
# further tokens of the command. Rule C: once the directory argument is
# recorded, any further token that isn't an option (`-*`) or a redirection
# also marks the directory unknown — the shell would reject a second
# directory argument, so text shaped like one is almost always a quoted path
# with a space whose quotes were already stripped. A redirection is either a
# token with the operand attached (contains `>`/`<` plus other characters,
# e.g. `2>/dev/null`) or a bare operator token (optional leading digits then
# only `>`/`<` characters, e.g. `>`, `2>>`) — a bare operator also consumes
# the following token as its operand, so a space before the operand (`>
# /dev/null`) is not mistaken for a second directory argument. A `popd`
# token anywhere in the segment also records the directory as unknown and
# clears the branch, regardless of whether `cd`/`pushd` appears too. Either
# trigger clears the recorded branch, because it belonged to the directory
# or branch that came before, and, inside a subshell scope, marks that
# depth's CD_SEEN so rule S's close_subshell can tell an unbalanced close
# had a directory change inside it.
scan_cd_popd() {
  found_cd=0
  awaiting_arg=0
  has_popd=0
  arg_taken=0
  skip_redir_arg=0
  while [ $# -gt 0 ]; do
    t="$1"
    shift
    case "$t" in '#'*) break ;; esac
    [ "$t" = popd ] && has_popd=1
    if [ "$awaiting_arg" = 1 ]; then
      case "$t" in
        -)
          TRACK_DIR=unknown
          awaiting_arg=0
          arg_taken=1 ;;
        -?*)
          continue ;;                                     # option token (-P, -L, --, -e...): skip, keep waiting
        *'$'*)
          TRACK_DIR=unknown
          awaiting_arg=0
          arg_taken=1 ;;
        /*)
          norm_path "$t"
          TRACK_DIR="$NORM_PATH"
          awaiting_arg=0
          arg_taken=1 ;;
        *)
          if [ -n "$CWD" ]; then
            norm_path "$CWD/$t"
          else
            norm_path "$t"
          fi
          TRACK_DIR="$NORM_PATH"
          awaiting_arg=0
          arg_taken=1 ;;
      esac
    elif [ "$arg_taken" = 1 ]; then
      if [ "$skip_redir_arg" = 1 ]; then
        skip_redir_arg=0                                  # bare operator's operand token: consume, not a 2nd dir arg
        continue
      fi
      case "$t" in
        -*) : ;;                                          # option token
        *[!0-9\<\>]*)
          case "$t" in
            *'>'* | *'<'*) : ;;                            # redirection with the operand attached
            *) TRACK_DIR=unknown ;;                        # rule C: second positional
          esac ;;
        *[\<\>]*)
          skip_redir_arg=1 ;;                              # bare redirection operator: its operand is next
        *)
          TRACK_DIR=unknown ;;                              # rule C: second positional
      esac
    elif [ "$found_cd" = 0 ] && { [ "$t" = cd ] || [ "$t" = pushd ]; }; then
      found_cd=1
      awaiting_arg=1
    fi
  done
  [ "$awaiting_arg" = 1 ] && TRACK_DIR=unknown
  { [ "$found_cd" = 1 ] || [ "$has_popd" = 1 ]; } && TRACK_BRANCH=""
  [ "$has_popd" = 1 ] && TRACK_DIR=unknown
  if { [ "$found_cd" = 1 ] || [ "$has_popd" = 1 ]; } && [ "$SUBSHELL_DEPTH" -gt 0 ]; then
    CD_SEEN[SUBSHELL_DEPTH - 1]=1
  fi
}

# Rule G: resolve a refspec-less push's destination for directory $1. When
# $1 is the target of an earlier `-C <dir> switch/checkout` (C_DIR) with a
# known result (C_BRANCH), that checkout decides the outcome directly and
# the upstream check is skipped; otherwise falls back to `rev-parse` plus
# check_upstream, as before rule G.
resolve_push_dest() {
  dir="$1"
  if [ "$dir" = "$C_DIR" ] && [ -n "$C_BRANCH" ]; then
    if [ "$C_BRANCH" = "main" ] || [ "$C_BRANCH" = "master" ]; then
      block "current branch is $C_BRANCH; push from a feature branch."
    elif [ "$C_BRANCH" = "unknown" ]; then
      block "cannot determine the destination after a cd or branch change; use an explicit refspec such as git push origin <branch>."
    fi
    return 0
  fi
  BR=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
    block "current branch is $BR; push from a feature branch."
  fi
  check_upstream "$dir"
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
      resolve_push_dest "$GITDIR"
    elif [ -n "$TRACK_BRANCH" ] && [ "$TRACK_BRANCH" != "unknown" ]; then
      if [ "$TRACK_BRANCH" = "main" ] || [ "$TRACK_BRANCH" = "master" ]; then
        block "current branch is $TRACK_BRANCH; push from a feature branch."
      fi
    elif [ "$TRACK_BRANCH" = "unknown" ] || [ "$TRACK_DIR" = "unknown" ]; then
      block "cannot determine the destination after a cd or branch change; use an explicit refspec such as git push origin <branch>."
    else
      rdir="${TRACK_DIR:-${CWD:-.}}"
      resolve_push_dest "$rdir"
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
# (still `$@`, no copy) are handed straight to the matching handler. Rule G:
# a `switch`/`checkout` reached with a non-empty GITDIR (a `-C` was given)
# never touches TRACK_BRANCH — it names another repository — and records
# its result in C_DIR/C_BRANCH instead; a plain switch/checkout (no `-C`)
# still updates TRACK_BRANCH and, inside a subshell scope, marks that
# depth's CHK_SEEN so rule S can leave the branch unknown on close.
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
          /*) norm_path "$t" ;;
          *)
            if [ -n "$CWD" ]; then
              norm_path "$CWD/$t"
            else
              norm_path "$t"
            fi ;;
        esac
        GITDIR="$NORM_PATH"
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
        if [ -n "$GITDIR" ]; then
          walk_switch_branch "$@"
          C_DIR="$GITDIR"
          C_BRANCH="$RESOLVED_BRANCH"
        else
          resolve_switch_branch "$@"
          [ "$SUBSHELL_DEPTH" -gt 0 ] && CHK_SEEN[SUBSHELL_DEPTH - 1]=1
        fi
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

# Rule S, unbalanced-close guard: whether the whole command's parens and
# backticks are balanced, counted once over CMD_NORM (three linear passes,
# no per-character loop, no bash pattern substitution on the whole string —
# see the O(n^2) note above). A stray ")" in prose (inside an echo/commit
# message) inside a real subshell closes that scope early and can restore a
# directory change that never actually left the shell; when the counts don't
# balance, close_subshell (rule S) treats a scope that saw a cd/pushd/popd as
# unresolvable instead of trusting the saved value.
CMD_OPENS=$(printf '%s' "$CMD_NORM" | tr -cd '(' | wc -c | tr -d ' ')
CMD_CLOSES=$(printf '%s' "$CMD_NORM" | tr -cd ')' | wc -c | tr -d ' ')
CMD_BT=$(printf '%s' "$CMD_NORM" | tr -cd '`' | wc -c | tr -d ' ')
BALANCED=0
[ "$CMD_OPENS" -eq "$CMD_CLOSES" ] && [ $((CMD_BT % 2)) -eq 0 ] && BALANCED=1

# Split into segments on &&, ||, ;, |, (, ), backticks, and a bare & (added
# after the && rule, so `2>&1` splits into harmless pieces, not the operator
# itself), then newlines. `(`, `)` and a backtick become their own one-
# character lines instead of being deleted, so the read loop below can open
# and close a rule S subshell scope at each one. One process; no further
# process per segment.
# shellcheck disable=SC2016 # the backtick pair in the sed program is a literal marker for sed, not a command substitution
CMD_SPLIT=$(printf '%s' "$CMD_NORM" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g' -e 's/(/\n(\n/g' -e 's/)/\n)\n/g' -e 's/`/\n`\n/g' -e 's/&/\n/g')
while IFS= read -r line; do
  # Blank-or-all-spaces check via a case glob, not "${line// /}": bash 3.2's
  # global pattern substitution rebuilds the string per match, which is
  # O(n^2) for a line with many spaces (measured: tens of seconds on a
  # ~17KB line) — the same class of bug as an indexed-array walk.
  case "$line" in
    *[^\ ]*) : ;;
    *) continue ;;
  esac
  # Rule S: a marker line opens or closes a subshell scope instead of being
  # scanned as a segment. A backtick toggles between open and close.
  case "$line" in
    '(')
      open_subshell
      continue ;;
    ')')
      close_subshell
      continue ;;
    '`')
      if [ "$BT_OPEN" = 1 ]; then
        BT_OPEN=0
        close_subshell
      else
        BT_OPEN=1
        open_subshell
      fi
      continue ;;
  esac
  check_segment "$line"
done <<EOF
$CMD_SPLIT
EOF

exit 0
