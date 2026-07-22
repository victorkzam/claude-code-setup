#!/usr/bin/env bats
# Tests for hooks/orchestrator-delegate-guard.sh's plan-file allowlist across both
# the default ($HOME/.claude) and CLAUDE_CONFIG_DIR-based config layouts.
#
# Self-contained on purpose: does NOT source tests/test_helper.bash (owned by a
# different, concurrently-running task) and never touches any real
# /tmp/claude-orchestrator-active* sentinel -- only one fabricated per-test
# session id, created in setup() and removed in teardown().

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/orchestrator-delegate-guard.sh"

  # Unique, throwaway session id/sentinel per test -- never the real global sentinel.
  SID="bats-guard-$$-${RANDOM}${RANDOM}"
  SENTINEL="/tmp/claude-orchestrator-active.${SID}"
  touch "$SENTINEL"

  # Fake HOME/CLAUDE_CONFIG_DIR sandboxes MUST NOT live under /tmp: the hook's
  # own "/tmp/*" allowlist rule (line ~59) would then match any file path
  # inside them and exit 0 before the CLAUDE_CONFIG_DIR branch under test is
  # ever evaluated, making the assertion vacuously true (it stays green even
  # if that branch is deleted). Root the sandbox under the real $HOME instead
  # -- guaranteed writable in CI and outside /tmp on both macOS and Linux.
  REAL_HOME="$HOME"
  SANDBOX_ROOT="$(mktemp -d "${REAL_HOME}/.ccs-hooks-test.XXXXXX")"
  case "$SANDBOX_ROOT" in
    /tmp/*)
      echo "FATAL: sandbox root resolved under /tmp ($SANDBOX_ROOT) -- would make the CLAUDE_CONFIG_DIR allowlist test vacuous. Aborting." >&2
      return 1
      ;;
  esac

  TEST_HOME="${SANDBOX_ROOT}/home"
  TEST_CONFIG_DIR="${SANDBOX_ROOT}/config"
  mkdir -p "$TEST_HOME/.claude/plans" "$TEST_CONFIG_DIR/plans"

  export HOME="$TEST_HOME"
  unset CLAUDE_CONFIG_DIR
}

teardown() {
  rm -f "$SENTINEL"
  # Guard against an empty/unset SANDBOX_ROOT (e.g. setup aborted before it was
  # set) turning `rm -rf` into a no-op-on-cwd footgun.
  [ -n "${SANDBOX_ROOT:-}" ] && rm -rf "$SANDBOX_ROOT"
}

# Builds the PreToolUse(Write|Edit) stdin JSON shape the hook reads: session_id
# (sentinel lookup) and tool_input.file_path (allowlist check). agent_type is
# intentionally omitted -- absent means "main thread" per the hook's own comment.
json_for() {
  printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$SID" "$1"
}

@test "plan-file edit under \$HOME/.claude/plans is allowed (default layout)" {
  run bash "$HOOK" <<< "$(json_for "$TEST_HOME/.claude/plans/adopter-setup-tasks.md")"
  [ "$status" -eq 0 ]
}

@test "plan-file edit under \$CLAUDE_CONFIG_DIR/plans is allowed when set" {
  export CLAUDE_CONFIG_DIR="$TEST_CONFIG_DIR"
  run bash "$HOOK" <<< "$(json_for "$TEST_CONFIG_DIR/plans/adopter-setup-tasks.md")"
  [ "$status" -eq 0 ]
}

@test "source-file edit is blocked while sentinel is active (default layout)" {
  run bash "$HOOK" <<< "$(json_for "/opt/some-project/src/main.py")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Blocked"* ]]
}

@test "source-file edit is blocked while sentinel is active (CLAUDE_CONFIG_DIR layout)" {
  export CLAUDE_CONFIG_DIR="$TEST_CONFIG_DIR"
  run bash "$HOOK" <<< "$(json_for "/opt/some-project/src/main.py")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Blocked"* ]]
}
