#!/bin/bash
# scripts/merge-claude-md.sh — merge the repo's managed CLAUDE.md "workflow-rules"
# block into the adopter's $CLAUDE_DIR/CLAUDE.md. Non-destructive by construction:
#   fresh target   -> new file containing exactly the managed block (markers only,
#                     never Victor's personal sections, which live outside the block)
#   marker'd target-> REPLACE the block in place (version-agnostic; upgrade-safe)
#   plain target   -> APPEND the block after a blank-line separator
#   malformed target (one marker, END-before-BEGIN, or duplicates) -> REFUSE, untouched
# See lib.sh for the global script contract (exit codes, machine lines, atomics).

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

SOURCE_MD="$REPO_ROOT/CLAUDE.md"
TARGET_MD="$CLAUDE_DIR/CLAUDE.md"

# Version-agnostic marker patterns: BEGIN/END lines of ANY version match, so an
# older installed block (v0, v2, ...) is upgraded in place rather than duplicated.
BEGIN_RE='^<!-- BEGIN claude-code-setup workflow-rules v.* -->$'
END_RE='^<!-- END claude-code-setup workflow-rules v.* -->$'

usage() {
  printf 'usage: merge-claude-md.sh (--dry-run|--apply) [--backup-dir <dir>]\n' >&2
  exit "${1:-2}"
}

# analyze_markers <file> — set MK_BEGIN_COUNT / MK_END_COUNT and the first
# BEGIN/END line numbers (empty when none). BSD grep/cut/head only.
analyze_markers() {
  local file="$1" bl el
  bl="$( grep -nE "$BEGIN_RE" "$file" 2>/dev/null || true )"
  el="$( grep -nE "$END_RE" "$file" 2>/dev/null || true )"
  MK_BEGIN_COUNT="$( printf '%s' "$bl" | grep -c . || true )"
  MK_END_COUNT="$( printf '%s' "$el" | grep -c . || true )"
  MK_BEGIN_LINE="$( printf '%s\n' "$bl" | head -n 1 | cut -d: -f1 )"
  MK_END_LINE="$( printf '%s\n' "$el" | head -n 1 | cut -d: -f1 )"
}

# extract_source_block — write the repo's managed block (inclusive of markers)
# into $BLOCK_FILE. A malformed source is a packaging bug -> internal error.
extract_source_block() {
  analyze_markers "$SOURCE_MD"
  if [ "$MK_BEGIN_COUNT" != "1" ] || [ "$MK_END_COUNT" != "1" ] \
     || [ "$MK_BEGIN_LINE" -ge "$MK_END_LINE" ]; then
    ccs_die 2 "packaging error: $SOURCE_MD has no single managed workflow-rules block"
  fi
  awk -v b="$MK_BEGIN_LINE" -v e="$MK_END_LINE" 'NR>=b && NR<=e' "$SOURCE_MD" > "$BLOCK_FILE"
}

refuse_malformed() {
  ccs_die 1 "malformed managed block in $TARGET_MD (found $MK_BEGIN_COUNT BEGIN / $MK_END_COUNT END marker(s)). Repair manually: keep exactly one matching '<!-- BEGIN claude-code-setup workflow-rules vN -->' ... '<!-- END claude-code-setup workflow-rules vN -->' pair with BEGIN before END, OR delete both marker lines to re-append a fresh block, then re-run."
}

build_append() {
  ACTION=merged
  cp "$TARGET_MD" "$RESULT_FILE"
  # Ensure a trailing newline, then exactly one blank-line separator.
  if [ -s "$RESULT_FILE" ] && [ -n "$( tail -c 1 "$RESULT_FILE" )" ]; then
    printf '\n' >> "$RESULT_FILE"
  fi
  printf '\n' >> "$RESULT_FILE"
  cat "$BLOCK_FILE" >> "$RESULT_FILE"
}

build_replace() {
  ACTION=merged
  awk -v b="$MK_BEGIN_LINE" 'NR<b' "$TARGET_MD" > "$RESULT_FILE"
  cat "$BLOCK_FILE" >> "$RESULT_FILE"
  awk -v e="$MK_END_LINE" 'NR>e' "$TARGET_MD" >> "$RESULT_FILE"
}

# build_result — decide the action and materialize $RESULT_FILE from $TARGET_MD.
build_result() {
  refuse_symlink "$TARGET_MD"
  if [ ! -e "$TARGET_MD" ]; then
    ACTION=merged
    cp "$BLOCK_FILE" "$RESULT_FILE"
    return 0
  fi
  analyze_markers "$TARGET_MD"
  if [ "$MK_BEGIN_COUNT" = "0" ] && [ "$MK_END_COUNT" = "0" ]; then
    build_append
  elif [ "$MK_BEGIN_COUNT" = "1" ] && [ "$MK_END_COUNT" = "1" ] \
       && [ "$MK_BEGIN_LINE" -lt "$MK_END_LINE" ]; then
    build_replace
  else
    refuse_malformed
  fi
}

do_dry_run() {
  if [ -e "$TARGET_MD" ] && cmp -s "$TARGET_MD" "$RESULT_FILE"; then
    ccs_status unchanged "$TARGET_MD"
    return 0
  fi
  ccs_status "$ACTION" "$TARGET_MD"
  local cur="/dev/null"
  [ -e "$TARGET_MD" ] && cur="$TARGET_MD"
  diff -u -L "a/CLAUDE.md" -L "b/CLAUDE.md" "$cur" "$RESULT_FILE" || true
}

do_apply() {
  if [ -e "$TARGET_MD" ] && cmp -s "$TARGET_MD" "$RESULT_FILE"; then
    ccs_status unchanged "$TARGET_MD"
    return 0
  fi
  local run_dir backup=""
  if [ -n "$BACKUP_DIR" ]; then
    run_dir="$( ccs_backup_run_dir --backup-dir "$BACKUP_DIR" )"
  else
    run_dir="$( ccs_backup_run_dir )"
  fi
  if [ -e "$TARGET_MD" ]; then
    backup="$run_dir/CLAUDE.md"
    cp "$TARGET_MD" "$backup"
  fi
  ccs_atomic_install "$RESULT_FILE" "$TARGET_MD"
  ccs_receipt_append "$run_dir" "$ACTION" "$TARGET_MD" "$backup"
  ccs_status "$ACTION" "$TARGET_MD"
}

main() {
  local mode=""
  BACKUP_DIR=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) if [ -n "$mode" ]; then usage 2; fi; mode="dry-run" ;;
      --apply)   if [ -n "$mode" ]; then usage 2; fi; mode="apply" ;;
      --backup-dir)
        shift
        if [ $# -eq 0 ]; then usage 2; fi
        BACKUP_DIR="$1" ;;
      -h|--help)
        printf 'usage: merge-claude-md.sh (--dry-run|--apply) [--backup-dir <dir>]\n'
        exit 0 ;;
      *) usage 2 ;;
    esac
    shift
  done
  [ -n "$mode" ] || usage 2

  WORK="$( mktemp -d "${TMPDIR:-/tmp}/ccs-claudemd.XXXXXX" )"
  trap 'rm -rf "$WORK"' EXIT
  BLOCK_FILE="$WORK/block"
  RESULT_FILE="$WORK/result"

  extract_source_block
  build_result

  if [ "$mode" = "apply" ]; then
    do_apply
  else
    do_dry_run
  fi
}

main "$@"
