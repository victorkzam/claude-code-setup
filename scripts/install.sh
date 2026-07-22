#!/bin/bash
# scripts/install.sh — manifest-driven installer for claude-code-setup managed
# artifacts (agents/hooks/rules/skills) into the adopter's Claude config dir.
# Idempotent: missing -> install, identical -> unchanged, differs -> skip
# unless --force[=<category>]. Every overwrite backs up the adopter's file
# first. See scripts/lib.sh for the shared contract this script builds on.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

MANIFEST="$SCRIPT_DIR/manifest.txt"
CATEGORIES=" agents hooks rules skills "

DRY_RUN=0
DIFF=0
FORCE_ALL=0
FORCE_CATEGORY=""
BACKUP_DIR_ARG=""
FAILED=0
BACKUP_RUN_DIR=""

usage() {
  printf 'usage: install.sh [--dry-run [--diff]] [--force | --force=<category>] [--backup-dir <path>]\n' >&2
}

# --- arg parsing --------------------------------------------------------------

# parse_args <argv...> — --dry-run, when present, must be the very first flag
# (fixed order so a permission prefix of "bash scripts/install.sh --dry-run"
# covers both the plain and --diff forms). --diff requires --dry-run.
parse_args() {
  local first="${1:-}" a has_dry=0
  for a in "$@"; do
    [ "$a" = "--dry-run" ] && has_dry=1
  done
  if [ "$has_dry" -eq 1 ] && [ "$first" != "--dry-run" ]; then
    usage
    exit 2
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --diff) DIFF=1; shift ;;
      --force) FORCE_ALL=1; shift ;;
      --force=*) FORCE_CATEGORY="${1#--force=}"; shift ;;
      --backup-dir)
        [ "$#" -ge 2 ] || { usage; exit 2; }
        BACKUP_DIR_ARG="$2"
        shift 2
        ;;
      *) usage; exit 2 ;;
    esac
  done

  if [ "$DIFF" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf 'CCS: --diff requires --dry-run\n' >&2
    usage
    exit 2
  fi

  if [ -n "$FORCE_CATEGORY" ]; then
    case "$CATEGORIES" in
      *" $FORCE_CATEGORY "*) : ;;
      *) printf 'CCS: unknown --force category: %s\n' "$FORCE_CATEGORY" >&2; exit 2 ;;
    esac
  fi
}

# --- guards --------------------------------------------------------------

# validate_manifest_rel <rel> — shared guard for every manifest-reading loop.
# Delegates the path-escape check to lib.sh (shared with any future consumer),
# then enforces the closed category allowlist, which is install.sh-local since
# CATEGORIES lives here.
validate_manifest_rel() {
  local rel="$1"
  ccs_validate_manifest_rel "$rel"
  case "$CATEGORIES" in
    *" ${rel%%/*} "*) : ;;
    *) ccs_die 1 "manifest path has an unmanaged category: $rel" ;;
  esac
}

# validate_manifest — validate every relative path in the manifest BEFORE any
# writes happen (mkdir, backup dir, copy), so a single malformed/malicious line
# fails the whole run instead of leaving partial side effects from lines read
# ahead of it.
validate_manifest() {
  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    validate_manifest_rel "$rel"
  done < "$MANIFEST"
}

main_guards() {
  if ccs_claude_dir_is_regular_file; then
    ccs_die 2 "config dir '$CLAUDE_DIR' exists but is not a directory"
  fi
  if ccs_is_source_eq_dest; then
    ccs_die 2 "config dir resolves to the repo root ($REPO_ROOT) — refusing to install onto itself"
  fi
  [ -e "$MANIFEST" ] || ccs_die 2 "manifest not found: $MANIFEST"
  validate_manifest
}

# --- directory provisioning ------------------------------------------------

# ensure_dirs — mkdir -p every manifest parent dir plus plans/ (created even
# though no manifest file lives there). Only called for real (non-dry) runs.
ensure_dirs() {
  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    mkdir -p "$CLAUDE_DIR/$( dirname "$rel" )"
  done < "$MANIFEST"
  mkdir -p "$CLAUDE_DIR/plans"
}

# --- force policy ------------------------------------------------------------

# _force_applies <category> — true when --force or --force=<category> covers it.
_force_applies() {
  local category="$1"
  [ "$FORCE_ALL" -eq 1 ] && return 0
  [ -n "$FORCE_CATEGORY" ] && [ "$FORCE_CATEGORY" = "$category" ] && return 0
  return 1
}

# --- per-file handling -------------------------------------------------------

handle_install() {
  local rel="$1" src="$2" dst="$3" category="$4"
  if [ "$DRY_RUN" -eq 1 ]; then
    ccs_status installed "$rel"
    return 0
  fi
  ccs_atomic_install "$src" "$dst"
  [ "$category" = hooks ] && chmod +x "$dst"
  ccs_status installed "$rel"
  ccs_receipt_append "$BACKUP_RUN_DIR" installed "$dst"
}

handle_unchanged() {
  local rel="$1" dst="$2"
  ccs_status unchanged "$rel"
  [ "$DRY_RUN" -eq 1 ] && return 0
  ccs_receipt_append "$BACKUP_RUN_DIR" unchanged "$dst"
}

# _preview_differs <rel> <src> <dst> <category> — dry-run reporting only.
_preview_differs() {
  local rel="$1" src="$2" dst="$3" category="$4"
  if _force_applies "$category"; then
    ccs_status overwritten "$rel"
  else
    ccs_status skipped "$rel"
  fi
  if [ "$DIFF" -eq 1 ]; then
    diff -u "$dst" "$src" || true
  fi
}

handle_differs() {
  local rel="$1" src="$2" dst="$3" category="$4" backup_path
  if [ "$DRY_RUN" -eq 1 ]; then
    _preview_differs "$rel" "$src" "$dst" "$category"
    return 0
  fi

  if _force_applies "$category"; then
    backup_path="$BACKUP_RUN_DIR/$rel"
    mkdir -p "$( dirname "$backup_path" )"
    cp -p "$dst" "$backup_path"
    ccs_atomic_install "$src" "$dst"
    [ "$category" = hooks ] && chmod +x "$dst"
    ccs_status overwritten "$rel"
    ccs_receipt_append "$BACKUP_RUN_DIR" overwritten "$dst" "$backup_path"
  else
    ccs_status skipped "$rel"
    ccs_receipt_append "$BACKUP_RUN_DIR" skipped "$dst"
  fi
}

# process_file <rel> — dispatch one manifest entry to its action handler.
process_file() {
  local rel="$1" src dst category
  src="$REPO_ROOT/$rel"
  dst="$CLAUDE_DIR/$rel"
  category="${rel%%/*}"

  if [ -L "$dst" ]; then
    printf 'CCS: refusing to write through symlink: %s\n' "$dst" >&2
    FAILED=1
    return 0
  fi

  if [ ! -e "$dst" ]; then
    handle_install "$rel" "$src" "$dst" "$category"
  elif cmp -s "$src" "$dst"; then
    handle_unchanged "$rel" "$dst"
  else
    handle_differs "$rel" "$src" "$dst" "$category"
  fi
}

# --- entrypoint --------------------------------------------------------------

main() {
  parse_args "$@"
  main_guards

  if [ "$DRY_RUN" -eq 0 ]; then
    ensure_dirs
    if [ -n "$BACKUP_DIR_ARG" ]; then
      BACKUP_RUN_DIR="$( ccs_backup_run_dir --backup-dir "$BACKUP_DIR_ARG" )"
    else
      BACKUP_RUN_DIR="$( ccs_backup_run_dir )"
    fi
    ccs_status backup-dir "$BACKUP_RUN_DIR"
  fi

  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    process_file "$rel"
  done < "$MANIFEST"

  [ "$FAILED" -eq 0 ] || exit 1
  exit 0
}

main "$@"
