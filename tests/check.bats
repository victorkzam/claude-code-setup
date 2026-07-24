#!/usr/bin/env bats
# tests/check.bats — coverage for scripts/check.sh (default severity map, version
# floor tiers, --post verification) and the enforced manifest (C3).

load test_helper

setup() {
  ccs_setup_sandbox
  mkdir -p "$CLAUDE_CONFIG_DIR"
}

# --- local fixtures ----------------------------------------------------------

# _stub_claude <version> [mcp_server...] — fake `claude` that answers --version
# and `mcp list`. Any listed servers appear in the mcp output.
_stub_claude() {
  local ver="$1"
  shift
  local file="$CCS_STUB_BIN/claude" m
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  --version) printf "%%s\\n" %q ;;\n' "$ver (Claude Code)"
    printf '  mcp) '
    for m in "$@"; do printf 'printf "%%s\\n" %q; ' "$m"; done
    printf ':;;\n'
    printf '  *) : ;;\n'
    printf 'esac\n'
  } > "$file"
  chmod +x "$file"
}

_set_git_identity() {
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
}

# Everything present, healthy version, authed gh, identity set, MCP present.
_stub_clean_default() {
  ccs_make_stub jq 0
  _stub_claude "2.1.200" context7 exa
  ccs_make_stub gh 0
  _set_git_identity
}

# Install every manifest artifact under $1 as an empty file (hooks executable).
_populate_at() {
  local base="$1" rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    mkdir -p "$( dirname "$base/$rel" )"
    : > "$base/$rel"
    case "$rel" in hooks/*.sh) chmod +x "$base/$rel" ;; esac
  done < "$REPO_ROOT/scripts/manifest.txt"
}

_populate_claude_dir() { _populate_at "$CLAUDE_CONFIG_DIR"; }

# _write_settings_with_hooks <path_prefix> — settings.json whose five hook
# commands embed <path_prefix>/<hook>.sh (filename match is what --post checks).
_write_settings_with_hooks() {
  local prefix="$1"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"$prefix/protect-branches.sh\"" } ] },
      { "matcher": "Write|Edit", "hooks": [
        { "type": "command", "command": "bash \"$prefix/protect-secrets.sh\"" },
        { "type": "command", "command": "bash \"$prefix/orchestrator-delegate-guard.sh\"" },
        { "type": "command", "command": "bash \"$prefix/design-scope-guard.sh\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "bash \"$prefix/syntax-check.sh\"" } ] }
    ]
  }
}
EOF
}

_write_managed_claude_md() {
  cat > "$CLAUDE_CONFIG_DIR/CLAUDE.md" <<'EOF'
# Managed
<!-- BEGIN claude-code-setup workflow-rules v1 -->
rules
<!-- END claude-code-setup workflow-rules v1 -->
EOF
}

# --- default mode: severity map ---------------------------------------------

@test "default: clean environment passes (exit 0)" {
  ccs_isolate_path
  _stub_clean_default
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "default: missing jq fails (exit 2)" {
  ccs_isolate_path
  _stub_claude "2.1.200" context7 exa
  ccs_make_stub gh 0
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq not found"* ]]
}

@test "default: missing claude fails (exit 2)" {
  ccs_isolate_path
  ccs_make_stub jq 0
  ccs_make_stub gh 0
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"claude CLI not found"* ]]
}

@test "default: missing gh warns (exit 1)" {
  ccs_isolate_path
  ccs_make_stub jq 0
  _stub_claude "2.1.200" context7 exa
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh not found"* ]]
}

@test "default: unset git identity warns (exit 1)" {
  ccs_isolate_path
  ccs_make_stub jq 0
  _stub_claude "2.1.200" context7 exa
  ccs_make_stub gh 0
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"user.name/user.email not set"* ]]
}

@test "default: absent MCP servers warn (exit 1)" {
  ccs_isolate_path
  ccs_make_stub jq 0
  _stub_claude "2.1.200"
  ccs_make_stub gh 0
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP server absent: context7"* ]]
}

# --- default mode: version floor tiers --------------------------------------

@test "version below 2.1.53 fails and states the CVE" {
  ccs_isolate_path
  ccs_make_stub jq 0
  _stub_claude "2.1.40" context7 exa
  ccs_make_stub gh 0
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CVE-2026-33068"* ]]
}

@test "version below 2.1.132 warns (sentinel session isolation)" {
  ccs_isolate_path
  ccs_make_stub jq 0
  _stub_claude "2.1.100" context7 exa
  ccs_make_stub gh 0
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sentinel session isolation"* ]]
}

@test "version below 2.1.198 warns (Explore model override)" {
  ccs_isolate_path
  ccs_make_stub jq 0
  _stub_claude "2.1.150" context7 exa
  ccs_make_stub gh 0
  _set_git_identity
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Explore agent model override"* ]]
}

@test "version >= 2.1.198 is clean (no warnings)" {
  ccs_isolate_path
  _stub_clean_default
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARN"* ]]
}

# --- default mode: config dir integrity -------------------------------------

@test "regular-file config dir fails (exit 2)" {
  ccs_isolate_path
  _stub_clean_default
  rm -rf "$CLAUDE_CONFIG_DIR"
  printf 'x' > "$CLAUDE_CONFIG_DIR"
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a directory"* ]]
}

@test "source == destination is refused (exit 2)" {
  ccs_isolate_path
  _stub_clean_default
  export CLAUDE_CONFIG_DIR="$REPO_ROOT"
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo root"* ]]
}

@test "relative CLAUDE_CONFIG_DIR is normalized to absolute and honored" {
  ccs_isolate_path
  _stub_clean_default
  mkdir -p "$SANDBOX/relcfg"
  cd "$SANDBOX"
  export CLAUDE_CONFIG_DIR="relcfg"
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/relcfg"* ]]
}

@test "symlinked config dir is accepted (checks pass through the link)" {
  ccs_isolate_path
  _stub_clean_default
  mkdir -p "$SANDBOX/realcfg"
  rm -rf "$CLAUDE_CONFIG_DIR"
  ln -s "$SANDBOX/realcfg" "$CLAUDE_CONFIG_DIR"
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 0 ]
}

# --- --post mode -------------------------------------------------------------

@test "post: fully installed artifacts pass (exit 0)" {
  _populate_claude_dir
  _write_settings_with_hooks "\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/hooks"
  _write_managed_claude_md
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "post: hooks by a different literal path still pass (filename match)" {
  _populate_claude_dir
  _write_settings_with_hooks "/some/totally/different/path"
  _write_managed_claude_md
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 0 ]
  [[ "$output" == *"references all managed hooks"* ]]
}

@test "post: settings missing a managed hook filename fails (exit 2)" {
  _populate_claude_dir
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{ "hooks": { "PreToolUse": [ { "hooks": [
  { "command": "bash x/protect-branches.sh" },
  { "command": "bash x/protect-secrets.sh" },
  { "command": "bash x/syntax-check.sh" } ] } ] } }
EOF
  _write_managed_claude_md
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing managed hook"* ]]
}

@test "post: a missing managed artifact is detected (exit 2)" {
  _populate_claude_dir
  _write_settings_with_hooks "x"
  _write_managed_claude_md
  rm -f "$CLAUDE_CONFIG_DIR/hooks/protect-secrets.sh"
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing managed artifact: hooks/protect-secrets.sh"* ]]
}

@test "post: artifacts installed to the wrong dir are detected (exit 2)" {
  _populate_at "$SANDBOX/other/.claude"
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing managed artifact"* ]]
}

@test "post: absent settings.json warns as a declined merge (exit 1)" {
  _populate_claude_dir
  _write_managed_claude_md
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 1 ]
  [[ "$output" == *"ignore if you declined this merge"* ]]
}

@test "post: valid settings.json with no managed hook entries warns (exit 1)" {
  _populate_claude_dir
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{ "hooks": { "PreToolUse": [ { "hooks": [
  { "command": "bash x/some-other-hook.sh" } ] } ] } }
EOF
  _write_managed_claude_md
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"ignore if you declined this merge"* ]]
}

@test "post: setup skill present under config dir fails the invariant (exit 2)" {
  _populate_claude_dir
  _write_settings_with_hooks "x"
  _write_managed_claude_md
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/setup"
  : > "$CLAUDE_CONFIG_DIR/skills/setup/SKILL.md"
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 2 ]
  [[ "$output" == *"must never be installed"* ]]
}

# --- manifest enforcement (C3) ----------------------------------------------

@test "manifest.txt equals git ls-files agents/ hooks/ rules/ skills/" {
  local expected actual
  expected="$( cd "$REPO_ROOT" && git ls-files agents/ hooks/ rules/ skills/ )"
  actual="$( cat "$REPO_ROOT/scripts/manifest.txt" )"
  [ "$actual" = "$expected" ]
}
