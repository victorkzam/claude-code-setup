#!/bin/bash
# SessionStart(startup|resume|clear|fork) — surface profile-config mismatches
# and missing CLAUDE.md imports as a SessionStart notice. Always exits 0
# (exit 2 would block session initialization) and always prints exactly one
# JSON line to stdout, even on an internal error.

if ! command -v jq >/dev/null 2>&1; then
  echo "cw: jq not found, hook skipped" >&2
  printf '%s\n' '{}'
  exit 0
fi

OUT='{}'
# shellcheck disable=SC2329 # invoked indirectly via `trap ... EXIT` below
finish() {
  printf '%s\n' "$OUT"
  exit 0
}
trap finish EXIT

INPUT=$(cat 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

HOME_DIR="${HOME:-/root}"
ACTIVE="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}"

expand_tilde() {
  # shellcheck disable=SC2088 # intentional literal-~ pattern match, not expansion
  case "$1" in
    "~") printf '%s' "$HOME_DIR" ;;
    "~/"*) rest=${1#??}; printf '%s/%s' "$HOME_DIR" "$rest" ;;
    *) printf '%s' "$1" ;;
  esac
}

# realpath-style resolution; fall back to the raw string if it doesn't exist.
resolve_dir() {
  if [ -d "$1" ]; then
    ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

NOTICES=()

PROFILES_FILE="$HOME_DIR/.claude-profiles"
if [ -f "$PROFILES_FILE" ]; then
  BEST_PREFIX=""
  BEST_DIR=""
  while IFS= read -r pline || [ -n "$pline" ]; do
    case "$pline" in
      \#*) continue ;;
    esac
    case "$pline" in
      *'|'*) ;;
      *) continue ;;
    esac
    prefix="${pline%%|*}"
    dir="${pline#*|}"
    prefix=$(expand_tilde "$prefix")
    dir=$(expand_tilde "$dir")
    case "$CWD" in
      "$prefix"|"$prefix"/*)
        if [ ${#prefix} -gt ${#BEST_PREFIX} ]; then
          BEST_PREFIX="$prefix"
          BEST_DIR="$dir"
        fi
        ;;
    esac
  done < "$PROFILES_FILE"

  if [ -n "$BEST_PREFIX" ]; then
    RES_BEST=$(resolve_dir "$BEST_DIR")
    RES_ACTIVE=$(resolve_dir "$ACTIVE")
    if [ "$RES_BEST" != "$RES_ACTIVE" ]; then
      NOTICES+=( "wrong profile: $CWD maps to $BEST_DIR" )
    fi
  fi
fi

CLAUDE_MD="$ACTIVE/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  while IFS= read -r cline || [ -n "$cline" ]; do
    case "$cline" in
      @*)
        tgt="${cline#@}"
        tgt=$(printf '%s' "$tgt" | sed -e 's/[[:space:]]*$//')
        tgt=$(expand_tilde "$tgt")
        case "$tgt" in
          /*) : ;;
          *) tgt="$ACTIVE/$tgt" ;;
        esac
        [ -e "$tgt" ] || NOTICES+=( "missing import: $tgt" )
        ;;
    esac
  done < "$CLAUDE_MD"
fi

if [ ${#NOTICES[@]} -gt 0 ]; then
  MSG=""
  for n in "${NOTICES[@]}"; do
    if [ -z "$MSG" ]; then
      MSG="$n"
    else
      MSG="$MSG; $n"
    fi
  done
  OUT=$(jq -nc --arg msg "$MSG" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}')
else
  BASE=$(basename "$ACTIVE")
  OUT=$(jq -nc --arg ctx "profile $BASE · plugin cw" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}')
fi

exit 0
