#!/bin/bash
# scripts/check.sh — doctor-style prerequisite + post-install verifier.
#   default mode : environment readiness with an explicit severity map.
#   --post mode  : verify managed artifacts landed under the resolved config dir.
# Aggregate exit: 0 PASS / 1 WARN / 2 FAIL (design v4 §2). Reads no stdin, never
# prompts. Human-readable lines on stdout. BSD-safe idioms only.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

MANIFEST="$SCRIPT_DIR/manifest.txt"
CLAUDE_MD_MARKER='<!-- BEGIN claude-code-setup workflow-rules v'
HOOK_FILES=(protect-branches.sh protect-secrets.sh orchestrator-delegate-guard.sh design-scope-guard.sh syntax-check.sh)

# Version floors (leading-semver comparison). 2.1.53 is the CVE-2026-33068
# security floor; the two higher tiers gate feature completeness.
VER_FLOOR_SECURITY="2.1.53"
VER_FLOOR_SENTINEL="2.1.132"
VER_FLOOR_FULL="2.1.198"

WORST=0

pass() { printf 'PASS: %s\n' "$*"; }
info() { printf 'INFO: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*"; if [ "$WORST" -lt 1 ]; then WORST=1; fi; }
fail() { printf 'FAIL: %s\n' "$*"; WORST=2; }

# --- version helpers ---------------------------------------------------------

# ccs_semver <text> — echo the first leading x.y.z found (tolerates prefixes,
# suffixes, and line wrapping in `claude --version` output).
ccs_semver() {
  printf '%s\n' "$1" | tr -c '0-9.\n' ' ' | tr ' ' '\n' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 \
    | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+'
}

# ccs_ver_lt <a> <b> — true when semver a < b.
ccs_ver_lt() {
  local a="$1" b="$2" arest brest amaj amin apat bmaj bmin bpat
  amaj="${a%%.*}"; arest="${a#*.}"; amin="${arest%%.*}"; apat="${arest#*.}"; apat="${apat%%[!0-9]*}"
  bmaj="${b%%.*}"; brest="${b#*.}"; bmin="${brest%%.*}"; bpat="${brest#*.}"; bpat="${bpat%%[!0-9]*}"
  [ "$amaj" -ne "$bmaj" ] && { [ "$amaj" -lt "$bmaj" ]; return; }
  [ "$amin" -ne "$bmin" ] && { [ "$amin" -lt "$bmin" ]; return; }
  [ "$apat" -lt "$bpat" ]
}

# run_guarded <cmd...> — run with a timeout when available (gh auth can hang).
run_guarded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 "$@"
  else
    "$@"
  fi
}

# --- default-mode checks -----------------------------------------------------

check_jq() {
  if command -v jq >/dev/null 2>&1; then
    pass "jq found"
  else
    fail "jq not found — hooks fail closed without it (install jq)"
  fi
}

check_version_tiers() {
  local ver="$1"
  if ccs_ver_lt "$ver" "$VER_FLOOR_SECURITY"; then
    fail "claude $ver is below the $VER_FLOOR_SECURITY security floor (CVE-2026-33068) — upgrade now"
  else
    pass "claude $ver meets the $VER_FLOOR_SECURITY security floor"
  fi
  if ccs_ver_lt "$ver" "$VER_FLOOR_SENTINEL"; then
    warn "claude $ver < $VER_FLOOR_SENTINEL — /build sentinel session isolation degraded (skills/build/SKILL.md)"
  fi
  if ccs_ver_lt "$ver" "$VER_FLOOR_FULL"; then
    warn "claude $ver < $VER_FLOOR_FULL — Explore agent model override unavailable (agents/Explore.md)"
  fi
}

check_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    fail "claude CLI not found — install Claude Code (>= $VER_FLOOR_FULL recommended)"
    return 0
  fi
  local raw ver
  raw="$( claude --version 2>/dev/null || true )"
  ver="$( ccs_semver "$raw" 2>/dev/null || true )"
  if [ -z "$ver" ]; then
    warn "could not parse 'claude --version' output: '$raw'"
  else
    check_version_tiers "$ver"
  fi
  info "claude present — run 'claude doctor' for deeper diagnostics"
}

check_writable() {
  local dir="$1" probe
  probe="$dir/.ccs-write-test.$$"
  if ( : > "$probe" ) 2>/dev/null; then
    rm -f "$probe"
    pass "config dir writable: $dir"
  else
    fail "config dir not writable: $dir"
  fi
}

check_config_dir() {
  if ccs_claude_dir_is_regular_file; then
    fail "config dir '$CLAUDE_DIR' exists but is not a directory"
  elif ccs_is_source_eq_dest; then
    fail "config dir resolves to the repo root ($REPO_ROOT) — refusing (installing the repo onto itself)"
  elif [ -d "$CLAUDE_DIR" ]; then
    check_writable "$CLAUDE_DIR"
  else
    local parent
    parent="$( dirname "$CLAUDE_DIR" )"
    if [ -d "$parent" ] && [ -w "$parent" ]; then
      pass "config dir '$CLAUDE_DIR' will be created under writable parent"
    else
      fail "config dir '$CLAUDE_DIR' does not exist and parent '$parent' is not writable"
    fi
  fi
}

check_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh not found — needed by /ship (not for install); install the GitHub CLI"
    return 0
  fi
  if run_guarded gh auth status >/dev/null 2>&1; then
    pass "gh authenticated"
  else
    warn "gh present but not authenticated — run 'gh auth login' before /ship"
  fi
}

check_git_identity() {
  local name email
  name="$( git config --global user.name 2>/dev/null || true )"
  email="$( git config --global user.email 2>/dev/null || true )"
  if [ -n "$name" ] && [ -n "$email" ]; then
    pass "git identity configured"
  else
    warn "git user.name/user.email not set — /build commits would be unattributed"
  fi
}

check_mcp_one() {
  case "$1" in
    *"$2"*) pass "optional MCP server present: $2" ;;
    *)      warn "optional MCP server absent: $2 (install for research/docs; not required)" ;;
  esac
}

check_mcp() {
  command -v claude >/dev/null 2>&1 || return 0
  local list
  list="$( claude mcp list 2>/dev/null || true )"
  check_mcp_one "$list" context7
  check_mcp_one "$list" exa
}

run_default() {
  check_jq
  check_claude
  check_config_dir
  check_gh
  check_git_identity
  check_mcp
}

# --- post-install checks -----------------------------------------------------

post_manifest_files() {
  local rel target
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    target="$CLAUDE_DIR/$rel"
    if [ ! -e "$target" ]; then
      fail "missing managed artifact: $rel"
      continue
    fi
    case "$rel" in
      hooks/*.sh)
        if [ -x "$target" ]; then
          pass "installed + executable: $rel"
        else
          fail "hook not executable: $rel"
        fi
        ;;
      *)
        pass "installed: $rel"
        ;;
    esac
  done < "$MANIFEST"
}

post_settings_hooks() {
  local sfile="$1" cmds fname missing present
  cmds="$( jq -r '[.. | .command? // empty] | .[]' "$sfile" 2>/dev/null || true )"
  missing=""
  present=0
  for fname in "${HOOK_FILES[@]}"; do
    case "$cmds" in
      *"$fname"*) present=$((present + 1)) ;;
      *)          missing="$missing $fname" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass "settings.json references all managed hooks (by filename)"
  elif [ "$present" -eq 0 ]; then
    warn "settings.json has no managed hook entries — ignore if you declined this merge"
  else
    fail "settings.json is missing managed hook(s):$missing"
  fi
}

post_settings() {
  local sfile="$CLAUDE_DIR/settings.json"
  if [ ! -e "$sfile" ]; then
    warn "settings.json not found — ignore if you declined this merge"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    fail "jq not found — cannot verify settings.json"
    return 0
  fi
  if ! jq empty "$sfile" >/dev/null 2>&1; then
    fail "settings.json is present but not valid JSON"
    return 0
  fi
  post_settings_hooks "$sfile"
}

post_claude_md() {
  local cfile="$CLAUDE_DIR/CLAUDE.md"
  if [ ! -e "$cfile" ]; then
    warn "managed CLAUDE.md not found — ignore if you declined this merge"
    return 0
  fi
  if grep -qF "$CLAUDE_MD_MARKER" "$cfile" 2>/dev/null; then
    pass "managed CLAUDE.md marker block present"
  else
    warn "CLAUDE.md present but managed marker block absent — ignore if you declined this merge"
  fi
}

post_setup_skill_absent() {
  if [ -e "$CLAUDE_DIR/skills/setup" ]; then
    fail "setup skill is installed under $CLAUDE_DIR/skills/setup — it must never be installed"
  else
    pass "setup skill correctly absent from config dir"
  fi
}

run_post() {
  if [ ! -e "$MANIFEST" ]; then
    fail "manifest not found: $MANIFEST"
    return 0
  fi
  post_manifest_files
  post_settings
  post_claude_md
  post_setup_skill_absent
}

# --- entrypoint --------------------------------------------------------------

main() {
  local mode="default"
  case "${1:-}" in
    --post)    mode="post" ;;
    "")        mode="default" ;;
    -h|--help) printf 'usage: check.sh [--post]\n'; exit 0 ;;
    *)         printf 'usage: check.sh [--post]\n' >&2; exit 2 ;;
  esac

  if [ "$mode" = "post" ]; then
    printf '== claude-code-setup post-install check (%s) ==\n' "$CLAUDE_DIR"
    run_post
  else
    printf '== claude-code-setup prerequisite check (%s) ==\n' "$CLAUDE_DIR"
    run_default
  fi

  case "$WORST" in
    0) printf 'RESULT: PASS\n'; exit 0 ;;
    1) printf 'RESULT: WARN\n'; exit 1 ;;
    *) printf 'RESULT: FAIL\n'; exit 2 ;;
  esac
}

main "$@"
