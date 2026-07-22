#!/usr/bin/env bats
# tests/merge-settings.bats — coverage for scripts/merge-settings.sh, the sole
# writer of settings.json. Verifies the fresh-verbatim path, the basename-keyed
# hook reconciliation (incl. cross-version old-form upgrade), the narrowed
# two-area merge, byte-stable idempotency, and every refusal path.

load test_helper

MERGE="scripts/merge-settings.sh"

setup() {
  ccs_setup_sandbox
  mkdir -p "$CLAUDE_CONFIG_DIR"
}

# --- local fixtures ----------------------------------------------------------

# _write_adopter — an adopter settings.json with a FOREIGN hook, personal keys,
# an old-form managed hook reference, and custom permissions.allow entries.
_write_adopter() {
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{
  "model": "sonnet",
  "customKey": "keep-me",
  "permissions": {
    "allow": [ "Bash(ls)", "Bash(git status)" ],
    "defaultMode": "plan"
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash ~/.claude/hooks/protect-branches.sh", "timeout": 5 } ] },
      { "matcher": "Custom", "hooks": [
        { "type": "command", "command": "bash /foreign/my-hook.sh" } ] }
    ]
  }
}
EOF
}

# _managed_cmds <file> — commands referencing a managed hook filename, one per line.
_managed_cmds() {
  jq -r '[.. | .command? // empty | select(test("hooks/(protect-branches|protect-secrets|orchestrator-delegate-guard|syntax-check)\\.sh"))] | .[]' "$1"
}

_receipt() { find "$CLAUDE_CONFIG_DIR/backups" -name receipt.txt | head -n 1; }

# --- fresh install (M3 verbatim) --------------------------------------------

@test "fresh: --apply writes the template verbatim (byte-identical)" {
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:merged:$CLAUDE_CONFIG_DIR/settings.json"* ]]
  cmp "$CLAUDE_CONFIG_DIR/settings.json" "$REPO_ROOT/settings.example.json"
}

@test "fresh: --apply records a merged receipt line" {
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  run grep merged "$( _receipt )"
  [ "$status" -eq 0 ]
}

@test "fresh: --backup-dir threads the shared run dir" {
  local run_dir="$SANDBOX/run"
  mkdir -p "$run_dir"
  run bash "$REPO_ROOT/$MERGE" --apply --backup-dir "$run_dir"
  [ "$status" -eq 0 ]
  [ -f "$run_dir/receipt.txt" ]
}

# --- foreign preservation + narrowed merge ----------------------------------

@test "foreign-preserved: keeps foreign hook, personal keys, and dedups allow" {
  _write_adopter
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  # personal keys untouched
  [ "$( jq -r '.model' "$s" )" = "sonnet" ]
  [ "$( jq -r '.customKey' "$s" )" = "keep-me" ]
  [ "$( jq -r '.permissions.defaultMode' "$s" )" = "plan" ]
  # foreign hook preserved
  [ "$( jq '[.. | .command? // empty | select(contains("/foreign/my-hook.sh"))] | length' "$s" )" -eq 1 ]
  # all four managed hooks present
  [ "$( _managed_cmds "$s" | sort -u | wc -l | tr -d ' ' )" -eq 4 ]
  # allow: adopter entries survive, template entries added, deduped (no dup git status)
  [ "$( jq '.permissions.allow | length' "$s" )" -eq 12 ]
  [ "$( jq '[.permissions.allow[] | select(. == "Bash(git status)")] | length' "$s" )" -eq 1 ]
  [ "$( jq '[.permissions.allow[] | select(. == "Bash(ls)")] | length' "$s" )" -eq 1 ]
}

@test "foreign-preserved: a hook naming a managed file only in echo text is kept" {
  # Token-anchored classification: the managed filename appears solely inside log
  # text; the invoked script is custom-guard.sh. The entry must NOT be treated as
  # managed (stripped), and the template hooks must be added alongside it.
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "echo 'migrated away from protect-branches.sh, now using custom-guard.sh' && bash /totally/different/custom-guard.sh" } ] }
    ]
  }
}
EOF
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  # the adopter's real custom hook survives intact (command byte-preserved)
  [ "$( jq '[.. | .command? // empty | select(contains("custom-guard.sh"))] | length' "$s" )" -eq 1 ]
  [ "$( jq -r '[.. | .command? // empty | select(contains("custom-guard.sh"))][0]' "$s" )" = "echo 'migrated away from protect-branches.sh, now using custom-guard.sh' && bash /totally/different/custom-guard.sh" ]
  # template managed hooks are added alongside (real protect-branches.sh invocation)
  [ "$( jq '[.. | .command? // empty | select(contains("hooks/protect-branches.sh"))] | length' "$s" )" -eq 1 ]
  [ "$( _managed_cmds "$s" | sort -u | wc -l | tr -d ' ' )" -eq 4 ]
}

@test "narrowed merge: template-only key defaultMode is NOT added to permissions" {
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{ "hooks": {} }
EOF
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  # permissions.allow created; defaultMode (present in template) not copied over
  [ "$( jq 'has("permissions")' "$CLAUDE_CONFIG_DIR/settings.json" )" = "true" ]
  [ "$( jq '.permissions | has("defaultMode")' "$CLAUDE_CONFIG_DIR/settings.json" )" = "false" ]
  # model/statusLine from template are NOT introduced
  [ "$( jq 'has("model")' "$CLAUDE_CONFIG_DIR/settings.json" )" = "false" ]
  [ "$( jq 'has("statusLine")' "$CLAUDE_CONFIG_DIR/settings.json" )" = "false" ]
}

# --- cross-version old-form upgrade (iter-4) --------------------------------

@test "old-form upgrade: a manual-cp-era hook ref becomes the new form, not doubled" {
  _write_adopter
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  # exactly ONE protect-branches entry, in the config-dir-aware form
  [ "$( jq '[.. | .command? // empty | select(contains("protect-branches.sh"))] | length' "$s" )" -eq 1 ]
  local cmd
  cmd="$( jq -r '[.. | .command? // empty | select(contains("protect-branches.sh"))][0]' "$s" )"
  [[ "$cmd" == *'${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/protect-branches.sh'* ]]
  [[ "$cmd" != *"~/.claude"* ]]
}

# --- permissions creation (iter-3) ------------------------------------------

@test "iter-3: config without a permissions key gains permissions.allow" {
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{ "model": "opus" }
EOF
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  [ "$( jq '.permissions.allow | length' "$CLAUDE_CONFIG_DIR/settings.json" )" -eq 11 ]
}

@test "iter-3: config with permissions but no allow gains allow, keeps siblings" {
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{ "permissions": { "defaultMode": "plan" } }
EOF
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  [ "$( jq '.permissions.allow | length' "$s" )" -eq 11 ]
  [ "$( jq -r '.permissions.defaultMode' "$s" )" = "plan" ]
}

# --- byte-stable idempotency (M7) -------------------------------------------

@test "fixed-point: fresh --apply then a SECOND --apply is a byte-identical no-op" {
  # The e2e-critical sequence: a fresh verbatim write must be a fixed point, so a
  # repeat run reports unchanged and never rewrites (no phantom diff to the user).
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:merged:"* ]]
  local sum1 sum2
  sum1="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:unchanged:"* ]]
  sum2="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  [ "$sum1" = "$sum2" ]
}

@test "round-trip: second apply is a byte-identical no-op" {
  _write_adopter
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  local sum1 sum2
  sum1="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:unchanged:"* ]]
  sum2="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  [ "$sum1" = "$sum2" ]
}

@test "round-trip: unchanged no-op writes no new backup/receipt" {
  _write_adopter
  bash "$REPO_ROOT/$MERGE" --apply
  local before after
  before="$( find "$CLAUDE_CONFIG_DIR/backups" -type f | wc -l | tr -d ' ' )"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 0 ]
  after="$( find "$CLAUDE_CONFIG_DIR/backups" -type f | wc -l | tr -d ' ' )"
  [ "$before" = "$after" ]
}

# --- dry-run safety (M6) -----------------------------------------------------

@test "dry-run: mutates nothing and emits a unified diff" {
  _write_adopter
  local sum1 sum2
  sum1="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"@@"* ]]
  sum2="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  [ "$sum1" = "$sum2" ]
}

@test "dry-run: fresh target previews the full template without creating it" {
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"protect-branches.sh"* ]]
  [ ! -e "$CLAUDE_CONFIG_DIR/settings.json" ]
}

# --- refusals (all exit 1, target untouched) --------------------------------

@test "refusal: symlinked target is refused (exit 1)" {
  ln -s "$SANDBOX/elsewhere.json" "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink"* ]]
}

@test "refusal: missing jq (exit 1)" {
  ccs_isolate_path
  _write_adopter
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq"* ]]
}

@test "refusal: unparseable JSON target (exit 1)" {
  printf 'not json {' > "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "refusal: valid JSON that is not an object (exit 1)" {
  printf '[1,2,3]' > "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an object"* ]]
}

@test "refusal: object with a non-object .hooks (exit 1, CCS message not jq crash)" {
  printf '{"hooks": "nope"}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"CCS:"* ]]
  [[ "$output" == *".hooks must be a JSON object"* ]]
  # dry-run refuses identically
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *".hooks must be a JSON object"* ]]
}

@test "refusal: object with a non-array .permissions.allow (exit 1, CCS message)" {
  printf '{"permissions":{"allow":"not-an-array"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"CCS:"* ]]
  [[ "$output" == *".permissions.allow must be a JSON array"* ]]
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *".permissions.allow must be a JSON array"* ]]
}

# --- malformed NESTED hook shapes (regression: must refuse, never raw jq exit-5) --

@test "refusal: event value is a string, not an array (exit 1, CCS message, untouched)" {
  printf '{"hooks": {"PreToolUse": "not-an-array"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  local sum1 sum2
  sum1="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"CCS:"* ]]
  [[ "$output" == *".hooks.PreToolUse must be a JSON array"* ]]
  sum2="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"
  [ "$sum1" = "$sum2" ]
  # dry-run refuses identically, never a raw jq crash
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *".hooks.PreToolUse must be a JSON array"* ]]
}

@test "refusal: hook entry .command is a number, not a string (exit 1, CCS message)" {
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": 12345 } ] }
    ]
  }
}
EOF
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"CCS:"* ]]
  [[ "$output" == *".hooks.PreToolUse[].hooks[].command must be a JSON string"* ]]
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *".hooks.PreToolUse[].hooks[].command must be a JSON string"* ]]
}

@test "refusal: inner .hooks value is an object, not an array (exit 1, CCS message)" {
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": { "type": "command", "command": "bash foo.sh" } }
    ]
  }
}
EOF
  run bash "$REPO_ROOT/$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"CCS:"* ]]
  [[ "$output" == *".hooks.PreToolUse[].hooks must be a JSON array"* ]]
  run bash "$REPO_ROOT/$MERGE" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *".hooks.PreToolUse[].hooks must be a JSON array"* ]]
}

# --- usage errors (exit 2) ---------------------------------------------------

@test "usage: no mode is a usage error (exit 2)" {
  run bash "$REPO_ROOT/$MERGE"
  [ "$status" -eq 2 ]
}

@test "usage: both --dry-run and --apply is a usage error (exit 2)" {
  run bash "$REPO_ROOT/$MERGE" --dry-run --apply
  [ "$status" -eq 2 ]
}

@test "usage: unknown flag is a usage error (exit 2)" {
  run bash "$REPO_ROOT/$MERGE" --frobnicate
  [ "$status" -eq 2 ]
}
