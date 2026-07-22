#!/usr/bin/env bats
# tests/e2e.bats — M4 end-to-end integration: the full adopter journey
# (check -> install -> merge-settings -> merge-claude-md -> check --post),
# run TWICE to prove the whole pipeline is byte-stable on repeat runs.
#
# CI reality: the `claude` binary is ABSENT on both CI runners (no real Claude
# Code install). Rather than depend on that being true of whatever machine runs
# this suite, `_hide_claude` (below) strips any real `claude` from PATH so
# `check.sh` (default mode) deterministically fails for that one reason (exit 2,
# "claude CLI not found") everywhere it runs — the point of this suite is to
# exercise the REAL install/merge pipeline end to end, not to fabricate a
# healthy doctor report by stubbing every tool.

load test_helper

# _hide_claude — strip any PATH entry that resolves a real `claude` binary, so
# "claude is absent" is asserted deterministically on every machine (CI runners
# and a contributor's laptop alike), rather than depending on the runner
# happening to lack a Claude Code install. Every other real tool (jq, git,
# bash...) stays reachable — this is NOT ccs_isolate_path's full sandboxing.
_hide_claude() {
  local newpath="" dir oldifs
  oldifs="$IFS"
  IFS=':'
  for dir in $PATH; do
    [ -x "$dir/claude" ] && continue
    newpath="${newpath:+$newpath:}$dir"
  done
  IFS="$oldifs"
  PATH="$newpath"
  export PATH
}

setup() {
  ccs_setup_sandbox
  _hide_claude
  # Sandbox git identity for hygiene: install/merge scripts shell out to git for
  # provenance (ccs_repo_sha uses -C "$SCRIPT_DIR", which resolves inside the
  # repo clone itself, so this is not strictly required for that call) but a
  # scoped identity keeps any incidental git usage inside the sandbox honest and
  # avoids ever touching the invoking user's real ~/.gitconfig.
  git config --global user.name "CCS E2E"
  git config --global user.email "ccs-e2e@example.com"
}

# _run_pipeline — one full adopter journey. Sets BACKUP_DIR as a side effect
# (parsed from install's CCS-STATUS:backup-dir: line) so the caller can thread
# it into the merge scripts, exactly as the /setup skill does.
_run_pipeline() {
  # 1. pre-install check: claude is absent in CI -> exit 2, specific reason.
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"claude CLI not found"* ]]

  # 2. real install.
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  local backup_line
  backup_line="$( printf '%s\n' "$output" | grep -m1 'CCS-STATUS:backup-dir:' )"
  [ -n "$backup_line" ]
  BACKUP_DIR="${backup_line#CCS-STATUS:backup-dir:}"
  [ -d "$BACKUP_DIR" ]

  # 3. merge-settings, threaded into the same run dir.
  run bash "$REPO_ROOT/scripts/merge-settings.sh" --apply --backup-dir "$BACKUP_DIR"
  [ "$status" -eq 0 ]

  # 4. merge-claude-md, threaded into the same run dir.
  run bash "$REPO_ROOT/scripts/merge-claude-md.sh" --apply --backup-dir "$BACKUP_DIR"
  [ "$status" -eq 0 ]

  # 5. post-install check must pass now that every managed artifact landed.
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "full happy path: check -> install -> merge-settings -> merge-claude-md -> check --post (exit 0)" {
  _run_pipeline

  # Receipt exists in the run dir with plausible action lines from every step.
  [ -f "$BACKUP_DIR/receipt.txt" ]
  grep -qE $'^installed\t' "$BACKUP_DIR/receipt.txt"
  grep -qE $'^merged\t' "$BACKUP_DIR/receipt.txt"
}

@test "repeat run: every step is a byte-stable no-op and --post still passes" {
  _run_pipeline
  local claude_md_sum settings_sum
  claude_md_sum="$( cksum < "$CLAUDE_CONFIG_DIR/CLAUDE.md" )"
  settings_sum="$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )"

  # 1. repeat check (still no claude binary -> same specific failure).
  run bash "$REPO_ROOT/scripts/check.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"claude CLI not found"* ]]

  # 2. repeat install: no installs/overwrites, every manifest entry unchanged.
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CCS-STATUS:installed:"* ]]
  [[ "$output" != *"CCS-STATUS:overwritten:"* ]]
  local rel
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    [[ "$output" == *"CCS-STATUS:unchanged:$rel"* ]]
  done < "$REPO_ROOT/scripts/manifest.txt"
  local repeat_backup_line repeat_backup_dir
  repeat_backup_line="$( printf '%s\n' "$output" | grep -m1 'CCS-STATUS:backup-dir:' )"
  repeat_backup_dir="${repeat_backup_line#CCS-STATUS:backup-dir:}"

  # 3. repeat merge-settings: byte-stable unchanged no-op.
  run bash "$REPO_ROOT/scripts/merge-settings.sh" --apply --backup-dir "$repeat_backup_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:unchanged:"* ]]
  [ "$( cksum < "$CLAUDE_CONFIG_DIR/settings.json" )" = "$settings_sum" ]

  # 4. repeat merge-claude-md: byte-stable unchanged no-op.
  run bash "$REPO_ROOT/scripts/merge-claude-md.sh" --apply --backup-dir "$repeat_backup_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CCS-STATUS:unchanged:"* ]]
  [ "$( cksum < "$CLAUDE_CONFIG_DIR/CLAUDE.md" )" = "$claude_md_sum" ]

  # 5. --post is still green.
  run bash "$REPO_ROOT/scripts/check.sh" --post
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}
