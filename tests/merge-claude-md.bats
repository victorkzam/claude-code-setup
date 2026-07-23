#!/usr/bin/env bats
# tests/merge-claude-md.bats — coverage for scripts/merge-claude-md.sh: fresh copy,
# version-agnostic in-place replace, append, malformed/symlink refusals, dry-run
# purity, and idempotency. Task-local fixtures only (test_helper is frozen).

load test_helper

MERGE="$REPO_ROOT/scripts/merge-claude-md.sh"

setup() {
  ccs_setup_sandbox
  mkdir -p "$CLAUDE_CONFIG_DIR"
  TARGET="$CLAUDE_CONFIG_DIR/CLAUDE.md"
  EXPECTED="$BATS_TEST_TMPDIR/expected-block"
  _expected_block > "$EXPECTED"
}

# _expected_block — the repo's managed block, inclusive of its markers.
_expected_block() {
  awk '/^<!-- BEGIN claude-code-setup workflow-rules v/{f=1}
       f{print}
       /^<!-- END claude-code-setup workflow-rules v/{f=0}' "$REPO_ROOT/CLAUDE.md"
}

# --- fresh -------------------------------------------------------------------

@test "fresh: no target yields a file equal to the managed block only" {
  run bash "$MERGE" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:merged:$TARGET"* ]]
  [ -f "$TARGET" ]
  diff "$EXPECTED" "$TARGET"
  # Personal sections that live OUTSIDE the block must never be copied.
  ! grep -q "Identity" "$TARGET"
  ! grep -q "Stack Preferences" "$TARGET"
}

# --- replace (same version) --------------------------------------------------

@test "replace: v1 block with stale content is replaced, surroundings intact" {
  cat > "$TARGET" <<'EOF'
# My Personal Header
keep me above

<!-- BEGIN claude-code-setup workflow-rules v1 -->
STALE OLD RULES
<!-- END claude-code-setup workflow-rules v1 -->

keep me below
EOF
  run bash "$MERGE" --apply
  [ "$status" -eq 0 ]
  grep -q "keep me above" "$TARGET"
  grep -q "keep me below" "$TARGET"
  ! grep -q "STALE OLD RULES" "$TARGET"
  grep -q "Never push directly to main" "$TARGET"
  [ "$( grep -c '^<!-- BEGIN claude-code-setup workflow-rules' "$TARGET" )" -eq 1 ]
  [ "$( grep -c '^<!-- END claude-code-setup workflow-rules' "$TARGET" )" -eq 1 ]
}

# --- upgrade (different version) ---------------------------------------------

@test "upgrade: a v0 block is replaced by the current v1 block, not duplicated" {
  cat > "$TARGET" <<'EOF'
<!-- BEGIN claude-code-setup workflow-rules v0 -->
ancient rules
<!-- END claude-code-setup workflow-rules v0 -->
EOF
  run bash "$MERGE" --apply
  [ "$status" -eq 0 ]
  ! grep -q "workflow-rules v0" "$TARGET"
  ! grep -q "ancient rules" "$TARGET"
  [ "$( grep -c '^<!-- BEGIN claude-code-setup workflow-rules v1 -->$' "$TARGET" )" -eq 1 ]
  [ "$( grep -c '^<!-- END claude-code-setup workflow-rules v1 -->$' "$TARGET" )" -eq 1 ]
  diff "$EXPECTED" "$TARGET"
}

# --- append (no markers) -----------------------------------------------------

@test "append: an unmanaged target keeps its content and gains the block" {
  printf '# Existing config\nsome personal notes\n' > "$TARGET"
  run bash "$MERGE" --apply
  [ "$status" -eq 0 ]
  grep -q "some personal notes" "$TARGET"
  grep -q "Never push directly to main" "$TARGET"
  [ "$( grep -c '^<!-- BEGIN claude-code-setup workflow-rules v1 -->$' "$TARGET" )" -eq 1 ]
  # A blank line must separate the original tail from the appended block.
  grep -q '^$' "$TARGET"
}

# --- refusals ----------------------------------------------------------------

@test "malformed: a lone BEGIN marker is refused and the target is untouched" {
  cat > "$TARGET" <<'EOF'
# Header
<!-- BEGIN claude-code-setup workflow-rules v1 -->
orphaned
EOF
  local before
  before="$( cat "$TARGET" )"
  run bash "$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
  [[ "$output" == *"Repair manually"* ]]
  [ "$( cat "$TARGET" )" = "$before" ]
}

@test "malformed: an END marker before BEGIN is refused, target untouched, no backup dir created" {
  cat > "$TARGET" <<'EOF'
# Header
<!-- END claude-code-setup workflow-rules v1 -->
orphaned tail
<!-- BEGIN claude-code-setup workflow-rules v1 -->
EOF
  local before
  before="$( cat "$TARGET" )"
  run bash "$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
  [[ "$output" == *"found 1 BEGIN / 1 END marker(s)"* ]]
  [[ "$output" == *"Repair manually"* ]]
  [ "$( cat "$TARGET" )" = "$before" ]
  [ ! -d "$CLAUDE_CONFIG_DIR/backups" ]
}

@test "malformed: duplicate BEGIN/END pairs are refused, target untouched, no backup dir created" {
  cat > "$TARGET" <<'EOF'
<!-- BEGIN claude-code-setup workflow-rules v1 -->
first block
<!-- END claude-code-setup workflow-rules v1 -->

<!-- BEGIN claude-code-setup workflow-rules v1 -->
second block
<!-- END claude-code-setup workflow-rules v1 -->
EOF
  local before
  before="$( cat "$TARGET" )"
  run bash "$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
  [[ "$output" == *"found 2 BEGIN / 2 END marker(s)"* ]]
  [[ "$output" == *"Repair manually"* ]]
  [ "$( cat "$TARGET" )" = "$before" ]
  [ ! -d "$CLAUDE_CONFIG_DIR/backups" ]
}

@test "symlinked target is refused (exit 1)" {
  printf 'real\n' > "$SANDBOX/real-claude.md"
  ln -s "$SANDBOX/real-claude.md" "$TARGET"
  run bash "$MERGE" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink"* ]]
}

# --- dry-run purity ----------------------------------------------------------

@test "dry-run: emits a diff and mutates nothing" {
  cat > "$TARGET" <<'EOF'
<!-- BEGIN claude-code-setup workflow-rules v1 -->
STALE
<!-- END claude-code-setup workflow-rules v1 -->
EOF
  local before
  before="$( cat "$TARGET" )"
  run bash "$MERGE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"@@"* ]]
  [[ "$output" == *"CCS-STATUS:merged:$TARGET"* ]]
  [ "$( cat "$TARGET" )" = "$before" ]
}

# --- idempotency -------------------------------------------------------------

@test "idempotent: a second apply reports unchanged and is byte-identical" {
  run bash "$MERGE" --apply
  [ "$status" -eq 0 ]
  local after_first
  after_first="$( cat "$TARGET" )"
  run bash "$MERGE" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:unchanged:$TARGET"* ]]
  [ "$( cat "$TARGET" )" = "$after_first" ]
}

# --- usage -------------------------------------------------------------------

@test "usage: no mode flag exits 2" {
  run bash "$MERGE"
  [ "$status" -eq 2 ]
}

@test "usage: both mode flags exit 2" {
  run bash "$MERGE" --apply --dry-run
  [ "$status" -eq 2 ]
}
