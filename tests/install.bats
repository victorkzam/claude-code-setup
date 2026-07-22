#!/usr/bin/env bats
# tests/install.bats — coverage for scripts/install.sh (manifest-driven
# install/unchanged/skip/overwrite policy, backups, receipts, dry-run safety).

load test_helper

setup() {
  ccs_setup_sandbox
}

# --- local fixtures ----------------------------------------------------------

_install() { run bash "$REPO_ROOT/scripts/install.sh" "$@"; }

_expected_sha() { git -C "$REPO_ROOT" rev-parse HEAD; }

# _agent_rel / _hook_rel — first manifest entries per category, resolved
# dynamically so these tests stay valid if the manifest contents change.
_agent_rel() { grep '^agents/' "$REPO_ROOT/scripts/manifest.txt" | head -n 1; }
_hook_rel()  { grep '^hooks/'  "$REPO_ROOT/scripts/manifest.txt" | head -n 1; }

# _tree_digest <dir> — content-sensitive digest of an entire directory tree
# (paths + file contents), used to prove --dry-run performs zero mutations.
_tree_digest() {
  ( cd "$1" 2>/dev/null && find . -type f -print0 | LC_ALL=C sort -z \
      | while IFS= read -r -d '' f; do printf '%s\n' "$f"; cat "$f"; done ) \
    | shasum -a 256 | awk '{print $1}'
}

_receipt_files() {
  find "$CLAUDE_CONFIG_DIR/backups/claude-code-setup" -name receipt.txt 2>/dev/null
}

# --- fresh install -----------------------------------------------------------

@test "fresh install into a nonexistent CLAUDE_DIR creates it and installs everything" {
  [ ! -e "$CLAUDE_CONFIG_DIR" ]
  _install
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:backup-dir:"* ]]
  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    [ -e "$CLAUDE_CONFIG_DIR/$rel" ]
    [[ "$output" == *"CCS-STATUS:installed:$rel"* ]]
  done < "$REPO_ROOT/scripts/manifest.txt"
  [ -d "$CLAUDE_CONFIG_DIR/plans" ]
}

@test "hooks are installed executable" {
  _install
  [ "$status" -eq 0 ]
  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    case "$rel" in
      hooks/*) [ -x "$CLAUDE_CONFIG_DIR/$rel" ] ;;
    esac
  done < "$REPO_ROOT/scripts/manifest.txt"
}

@test "idempotent second run reports unchanged everywhere and adds no backup content" {
  _install
  [ "$status" -eq 0 ]
  local before_receipts after_receipts
  before_receipts="$( _receipt_files | wc -l | tr -d ' ' )"

  _install
  [ "$status" -eq 0 ]
  [[ "$output" != *"CCS-STATUS:installed:"* ]]
  [[ "$output" != *"CCS-STATUS:overwritten:"* ]]
  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    [[ "$output" == *"CCS-STATUS:unchanged:$rel"* ]]
  done < "$REPO_ROOT/scripts/manifest.txt"

  after_receipts="$( _receipt_files | wc -l | tr -d ' ' )"
  # A run dir/receipt is (re)created each run (same-second timestamps may
  # collide with the fresh install's dir, so only assert non-regression), but
  # no run dir may carry copied adopter-file content beyond receipt.txt itself.
  [ "$after_receipts" -ge "$before_receipts" ]
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$( find "$d" -type f ! -name receipt.txt | wc -l | tr -d ' ' )" -eq 0 ]
  done < <( _receipt_files | xargs -n1 dirname )
}

@test "CLAUDE_CONFIG_DIR override is honored end to end" {
  local custom="$SANDBOX/custom-claude-dir"
  CLAUDE_CONFIG_DIR="$custom"
  export CLAUDE_CONFIG_DIR
  _install
  [ "$status" -eq 0 ]
  [ -e "$custom/$( _agent_rel )" ]
  [ ! -e "$HOME/.claude" ]
}

@test "symlinked CLAUDE_DIR is accepted: install lands through the link" {
  local real="$SANDBOX/real-claude-target"
  mkdir -p "$real"
  ln -s "$real" "$CLAUDE_CONFIG_DIR"
  _install
  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_CONFIG_DIR" ]
  [ -e "$real/$( _agent_rel )" ]
}

# --- differs / force policy ---------------------------------------------------

@test "differing files are skipped per category, then --force=<category> overwrites only that category" {
  _install
  [ "$status" -eq 0 ]
  local agent_rel hook_rel
  agent_rel="$( _agent_rel )"
  hook_rel="$( _hook_rel )"
  printf '\nadopter edit\n' >> "$CLAUDE_CONFIG_DIR/$agent_rel"
  printf '\n# adopter edit\n' >> "$CLAUDE_CONFIG_DIR/$hook_rel"

  _install
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:skipped:$agent_rel"* ]]
  [[ "$output" == *"CCS-STATUS:skipped:$hook_rel"* ]]
  [[ "$( cat "$CLAUDE_CONFIG_DIR/$agent_rel" )" == *"adopter edit"* ]]
  [[ "$( cat "$CLAUDE_CONFIG_DIR/$hook_rel" )" == *"adopter edit"* ]]

  run bash "$REPO_ROOT/scripts/install.sh" --force=agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:overwritten:$agent_rel"* ]]
  [[ "$output" != *"CCS-STATUS:overwritten:$hook_rel"* ]]
  cmp -s "$REPO_ROOT/$agent_rel" "$CLAUDE_CONFIG_DIR/$agent_rel"
  [[ "$( cat "$CLAUDE_CONFIG_DIR/$hook_rel" )" == *"adopter edit"* ]]

  local latest backup_dir
  latest="$( _receipt_files | LC_ALL=C sort | tail -n 1 )"
  backup_dir="$( dirname "$latest" )"
  [ -e "$backup_dir/$agent_rel" ]
  [[ "$( cat "$backup_dir/$agent_rel" )" == *"adopter edit"* ]]
  grep -qE $'^overwritten\t'"$CLAUDE_CONFIG_DIR/$agent_rel"$'\t'"$backup_dir/$agent_rel" "$latest"
}

@test "plain --force overwrites all differing categories" {
  _install
  [ "$status" -eq 0 ]
  local agent_rel hook_rel
  agent_rel="$( _agent_rel )"
  hook_rel="$( _hook_rel )"
  printf '\nadopter edit\n' >> "$CLAUDE_CONFIG_DIR/$agent_rel"
  printf '\n# adopter edit\n' >> "$CLAUDE_CONFIG_DIR/$hook_rel"

  run bash "$REPO_ROOT/scripts/install.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:overwritten:$agent_rel"* ]]
  [[ "$output" == *"CCS-STATUS:overwritten:$hook_rel"* ]]
  cmp -s "$REPO_ROOT/$agent_rel" "$CLAUDE_CONFIG_DIR/$agent_rel"
  cmp -s "$REPO_ROOT/$hook_rel" "$CLAUDE_CONFIG_DIR/$hook_rel"
  [ -x "$CLAUDE_CONFIG_DIR/$hook_rel" ]
}

@test "receipt records installed/overwritten/skipped action types with the repo sha" {
  _install
  [ "$status" -eq 0 ]
  local agent_rel
  agent_rel="$( _agent_rel )"
  printf '\nadopter edit\n' >> "$CLAUDE_CONFIG_DIR/$agent_rel"

  run bash "$REPO_ROOT/scripts/install.sh" --force=agents
  [ "$status" -eq 0 ]

  local sha latest
  sha="$( _expected_sha )"
  latest="$( _receipt_files | LC_ALL=C sort | tail -n 1 )"
  grep -qE $'^overwritten\t' "$latest"
  grep -q "$sha" "$latest"

  local first
  first="$( _receipt_files | LC_ALL=C sort | head -n 1 )"
  grep -qE $'^installed\t' "$first"
  grep -q "$sha" "$first"
}

# --- dry-run safety -----------------------------------------------------------

@test "dry-run performs zero mutations" {
  _install
  [ "$status" -eq 0 ]
  local before after
  before="$( _tree_digest "$CLAUDE_CONFIG_DIR" )"
  run bash "$REPO_ROOT/scripts/install.sh" --dry-run
  [ "$status" -eq 0 ]
  after="$( _tree_digest "$CLAUDE_CONFIG_DIR" )"
  [ "$before" = "$after" ]
}

@test "dry-run --diff previews a unified diff and still mutates nothing" {
  _install
  [ "$status" -eq 0 ]
  local agent_rel
  agent_rel="$( _agent_rel )"
  printf '\nadopter edit\n' >> "$CLAUDE_CONFIG_DIR/$agent_rel"

  local before after
  before="$( _tree_digest "$CLAUDE_CONFIG_DIR" )"
  run bash "$REPO_ROOT/scripts/install.sh" --dry-run --diff
  [ "$status" -eq 0 ]
  after="$( _tree_digest "$CLAUDE_CONFIG_DIR" )"
  [ "$before" = "$after" ]
  [[ "$output" == *"CCS-STATUS:skipped:$agent_rel"* ]]
  [[ "$output" == *"+++ $REPO_ROOT/$agent_rel"* ]]
  [[ "$( cat "$CLAUDE_CONFIG_DIR/$agent_rel" )" == *"adopter edit"* ]]
}

@test "--diff without --dry-run is a usage error (exit 2)" {
  run bash "$REPO_ROOT/scripts/install.sh" --diff
  [ "$status" -eq 2 ]
}

@test "--dry-run must be the first flag (exit 2 otherwise)" {
  run bash "$REPO_ROOT/scripts/install.sh" --force --dry-run
  [ "$status" -eq 2 ]
}

# --- symlinked destination file ------------------------------------------------

@test "a symlinked destination file is refused, reported, and other files still install" {
  local agent_rel hook_rel target
  agent_rel="$( _agent_rel )"
  hook_rel="$( _hook_rel )"
  mkdir -p "$CLAUDE_CONFIG_DIR/$( dirname "$agent_rel" )"
  target="$SANDBOX/elsewhere.md"
  printf 'not managed\n' > "$target"
  ln -s "$target" "$CLAUDE_CONFIG_DIR/$agent_rel"

  _install
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to write through symlink"* ]]
  [[ "$output" == *"CCS-STATUS:installed:$hook_rel"* ]]
  [ -L "$CLAUDE_CONFIG_DIR/$agent_rel" ]
}
