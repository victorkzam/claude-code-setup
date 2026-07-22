#!/bin/bash
# scripts/lib.sh — shared helpers for the claude-code-setup installer scripts.
# Sourced by check.sh / install.sh / merge-*.sh. Global contract (design v4):
#   * Bash 3.2 compatible (no associative arrays / mapfile / ${v,,}).
#   * set -euo pipefail (callers inherit it via source).
#   * NEVER read stdin, NEVER prompt.
#   * Machine lines "CCS-STATUS:<action>:<path>" go to stdout; every error and
#     refusal reason goes to stderr.
#   * Atomic file writes: mktemp in the destination dir, then mv.
#   * Exit contract: 0 success (incl. no-op), 1 refusal/partial, 2 usage/internal.
# BSD-safe idioms only (macOS bash 3.2 + BSD userland is a CI target).

set -euo pipefail

# --- stream + exit helpers ---------------------------------------------------

# ccs_status <action> <path> — machine-readable status line on stdout.
ccs_status() {
  printf 'CCS-STATUS:%s:%s\n' "$1" "$2"
}

# ccs_die <exit_code> <message...> — reason on stderr, then exit.
ccs_die() {
  local code="$1"
  shift
  printf 'CCS: %s\n' "$*" >&2
  exit "$code"
}

# --- path normalization ------------------------------------------------------

# ccs_abspath <path> — absolutize a path without requiring it to exist. Expands a
# leading "~" / "~/" to $HOME and prefixes $PWD for relative values. Symlinks are
# NOT resolved here (see ccs_canonical). A trailing slash is trimmed (except "/").
ccs_abspath() {
  local p="$1"
  # A leading literal "~" means the user passed a tilde in the value; expand it to
  # $HOME ourselves (case patterns never tilde-expand). SC2088 is a false positive.
  # shellcheck disable=SC2088
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p:2}" ;;
    /*)    : ;;
    *)     p="$PWD/$p" ;;
  esac
  case "$p" in
    */) p="${p%/}"; [ -n "$p" ] || p="/" ;;
  esac
  printf '%s\n' "$p"
}

# ccs_canonical <path> — fully resolved physical path (symlinks collapsed). Emits
# nothing when the path does not exist as a directory.
ccs_canonical() {
  if [ -d "$1" ]; then
    ( cd "$1" && pwd -P )
  fi
}

# --- config dir resolution ---------------------------------------------------

# SCRIPT_DIR is this scripts/ directory; REPO_ROOT is its parent (works for git
# clones and extracted tarballs alike).
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd -P )"

# Fail closed when there is no way to locate the config dir.
if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -z "${HOME:-}" ]; then
  ccs_die 2 "neither CLAUDE_CONFIG_DIR nor HOME is set; cannot locate the config dir"
fi

# CLAUDE_DIR — the adopter's config dir, always absolute/normalized.
CLAUDE_DIR="$( ccs_abspath "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" )"

# --- config dir integrity checks --------------------------------------------

# ccs_claude_dir_is_regular_file — true when CLAUDE_DIR exists but is NOT a
# directory. A symlink to a directory is allowed (stow/chezmoi); a plain file or
# a symlink to a file is not.
ccs_claude_dir_is_regular_file() {
  [ -e "$CLAUDE_DIR" ] && [ ! -d "$CLAUDE_DIR" ]
}

# ccs_is_source_eq_dest — true when the resolved config dir is the repo itself
# (a clone placed at ~/.claude, or CLAUDE_CONFIG_DIR pointed at the clone).
# Installing a repo onto itself would pollute the working tree.
ccs_is_source_eq_dest() {
  local canon
  canon="$( ccs_canonical "$CLAUDE_DIR" )"
  [ -n "$canon" ] && [ "$canon" = "$REPO_ROOT" ]
}

# refuse_symlink <path> — refuse (exit 1) if the write target is a symlink. Used
# to guard every FILE write destination in the merge/install scripts.
refuse_symlink() {
  if [ -L "$1" ]; then
    ccs_die 1 "refusing to write through symlink: $1"
  fi
}

# --- manifest path safety -----------------------------------------------------

# ccs_validate_manifest_rel <rel> — refuse (exit 1) a manifest-sourced relative
# path that is absolute, or that contains a ".." path component. The ".." check
# matches only a FULL path segment (leading "../", embedded "/../", trailing
# "/..", or exactly ".."), never a bare substring, so legitimate filenames that
# merely contain dots (e.g. "foo..bar.md") stay valid. Every manifest-reading
# loop must call this before the line is used to build a destination path —
# same "refuse before writing" convention as refuse_symlink above.
ccs_validate_manifest_rel() {
  local rel="$1"
  case "$rel" in
    /*)
      ccs_die 1 "manifest path is absolute, refusing: $rel" ;;
    ..|../*|*/../*|*/..)
      ccs_die 1 "manifest path escapes the config dir: $rel" ;;
  esac
}

# --- prerequisites -----------------------------------------------------------

# ccs_require_jq — jq-dependent callers fail closed (exit 2) when jq is absent.
ccs_require_jq() {
  command -v jq >/dev/null 2>&1 || ccs_die 2 "jq is required but was not found on PATH"
}

# ccs_repo_sha — repo commit for provenance; tarball adopters degrade to unknown.
ccs_repo_sha() {
  git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo unknown
}

# --- backups + receipts ------------------------------------------------------

# ccs_backup_run_dir [--backup-dir <path>] — echo the backup run directory,
# creating it if needed. With no argument a fresh timestamped dir is created
# under $CLAUDE_DIR/backups/claude-code-setup/ (durable, inside the config dir,
# never $TMPDIR). With --backup-dir the caller's threaded run dir is reused so a
# single /setup run keeps one receipt. Path is emitted on stdout so the skill can
# thread it across install/merge invocations.
ccs_backup_run_dir() {
  local dir=""
  if [ "${1:-}" = "--backup-dir" ]; then
    dir="${2:-}"
  fi
  if [ -z "$dir" ]; then
    dir="$CLAUDE_DIR/backups/claude-code-setup/$( date +%Y%m%d-%H%M%S )"
  fi
  mkdir -p "$dir" || ccs_die 2 "failed to create backup dir: $dir"
  printf '%s\n' "$dir"
}

# ccs_receipt_append <run_dir> <action> <path> [backup_path] — append one receipt
# line (survives interrupts). action is one of installed|overwritten|merged|skipped.
# Fields are tab-separated: action, path, backup, repo sha, timestamp.
ccs_receipt_append() {
  local run_dir="$1" action="$2" path="$3" backup="${4:-}"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$action" "$path" "$backup" "$( ccs_repo_sha )" "$( date +%Y-%m-%dT%H:%M:%S )" \
    >> "$run_dir/receipt.txt"
}

# --- atomic writes -----------------------------------------------------------

# ccs_atomic_install <src> <dst> — copy src onto dst atomically (mktemp in the
# destination directory, then mv). Refuses symlinked destinations.
ccs_atomic_install() {
  local src="$1" dst="$2" tmp dstdir
  refuse_symlink "$dst"
  dstdir="$( dirname "$dst" )"
  mkdir -p "$dstdir" || ccs_die 2 "failed to create destination dir: $dstdir"
  tmp="$( mktemp "$dstdir/.ccs.XXXXXX" )"
  cp "$src" "$tmp"
  mv -f "$tmp" "$dst"
}
