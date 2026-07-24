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
  DESIGN_HOOK="${BATS_TEST_DIRNAME}/../hooks/design-scope-guard.sh"

  # Unique, throwaway session id/sentinel per test -- never the real global sentinel.
  SID="bats-guard-$$-${RANDOM}${RANDOM}"
  SENTINEL="/tmp/claude-orchestrator-active.${SID}"
  touch "$SENTINEL"

  # design-scope-guard.sh sentinel -- distinct filename prefix from $SENTINEL above,
  # so the two guards' sentinels never collide. NOT touched by default: tests that
  # need /design "active" call design_sentinel_on() explicitly; tests that need it
  # absent (the fast-path case) simply never call it. Always removed in teardown.
  DESIGN_SENTINEL="/tmp/claude-design-active.${SID}"

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
  rm -f "$SENTINEL" "$DESIGN_SENTINEL"
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

# Turns the design-scope-guard sentinel "on" for the current test's session id.
design_sentinel_on() {
  touch "$DESIGN_SENTINEL"
}

# Same stdin shape as json_for(), plus tool_name -- design-scope-guard.sh does not
# read tool_name at all (it only inspects tool_input.file_path), so a Write vs Edit
# probe on the same file_path must produce identical exit codes. That parity is
# what the "source-path probes" test below asserts.
json_for_design() {
  printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$SID" "$2" "$1"
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

@test "delegate-guard: docs/plans/ write is allowed while sentinel is active" {
  run bash "$HOOK" <<< "$(json_for "$TEST_HOME/proj/docs/plans/some-slug/draft.md")"
  [ "$status" -eq 0 ]
}

@test "delegate-guard: .gitattributes write is allowed while sentinel is active" {
  run bash "$HOOK" <<< "$(json_for "$TEST_HOME/proj/.gitattributes")"
  [ "$status" -eq 0 ]
}

@test "delegate-guard: near-miss docs/plansX/ (not docs/plans/) is still blocked" {
  run bash "$HOOK" <<< "$(json_for "$TEST_HOME/proj/docs/plansX/evil.md")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Blocked"* ]]
}

# --- hooks/design-scope-guard.sh ---------------------------------------------
# Same sandbox/sentinel-isolation conventions as above, applied to the sibling
# guard: a per-test session id, a scratch sentinel file, and (per this file's
# own note at setup()'s SANDBOX_ROOT check) fixture paths rooted outside /tmp
# so the hook's own "/tmp/*" allowlist branch can't make an assertion vacuous.

@test "design-scope-guard: docs/plans/ write under a project fixture is allowed while sentinel is active" {
  design_sentinel_on
  FIXTURE="$SANDBOX_ROOT/proj/docs/plans/some-slug/draft.md"
  run bash "$DESIGN_HOOK" <<< "$(json_for_design "$FIXTURE" "Write")"
  [ "$status" -eq 0 ]
}

@test "design-scope-guard: source-path probe is blocked identically for Write and Edit tool shapes" {
  design_sentinel_on
  FIXTURE="$SANDBOX_ROOT/proj/src/main.py"

  run bash "$DESIGN_HOOK" <<< "$(json_for_design "$FIXTURE" "Write")"
  [ "$status" -eq 2 ]
  write_output="$output"

  run bash "$DESIGN_HOOK" <<< "$(json_for_design "$FIXTURE" "Edit")"
  [ "$status" -eq 2 ]

  # Note: issue #37210 documents a harness-side runtime caveat around how the
  # test harness replays Write vs Edit shapes -- it is not a defect in this
  # hook. The hook itself never reads tool_name, so both shapes must agree.
  [ "$output" = "$write_output" ]
}

@test "design-scope-guard: fast path allows any write when no design sentinel exists" {
  # Deliberately do NOT call design_sentinel_on() -- exercises the jq-free
  # `ls /tmp/claude-design-active*` fast path taken when /design isn't active.
  FIXTURE="$SANDBOX_ROOT/proj/src/main.py"
  run bash "$DESIGN_HOOK" <<< "$(json_for_design "$FIXTURE" "Write")"
  [ "$status" -eq 0 ]
}

# --- hardening matrix: fail-closed on unparseable input, .. traversal, ------
# relative/empty paths -- for BOTH guards. Existing allow-cases above must
# still pass unchanged.

# Builds the same stdin shape as json_for(), but with an explicit agent_type,
# for the one subagent-exemption pin below. json_for()/json_for_design()
# intentionally omit agent_type (absent == main thread).
json_for_with_agent() {
  printf '{"session_id":"%s","agent_type":"%s","tool_input":{"file_path":"%s"}}' "$SID" "$1" "$2"
}

@test "delegate-guard: .. traversal via an allowlisted prefix is blocked" {
  FIXTURE="$SANDBOX_ROOT/proj/docs/plans/../../../etc/evil"
  run bash "$HOOK" <<< "$(json_for "$FIXTURE")"
  [ "$status" -eq 2 ]
}

@test "delegate-guard: relative file_path is blocked" {
  run bash "$HOOK" <<< "$(json_for "docs/plans/x.md")"
  [ "$status" -eq 2 ]
}

@test "delegate-guard: empty file_path is blocked" {
  run bash "$HOOK" <<< "$(json_for "")"
  [ "$status" -eq 2 ]
}

@test "delegate-guard: malformed JSON on stdin is blocked (parse gate)" {
  run bash "$HOOK" <<< "$(printf 'not-json{{{')"
  [ "$status" -eq 2 ]
}

@test "delegate-guard: /tmp/../etc/passwd is blocked (.. check precedes /tmp/* allow arm)" {
  run bash "$HOOK" <<< "$(json_for "/tmp/../etc/passwd")"
  [ "$status" -eq 2 ]
}

@test "delegate-guard: subagent with a .. path is exempt (main-thread-only scope)" {
  FIXTURE="$SANDBOX_ROOT/proj/docs/plans/../../../etc/evil"
  run bash "$HOOK" <<< "$(json_for_with_agent "implementer" "$FIXTURE")"
  [ "$status" -eq 0 ]
}

@test "design-scope-guard: .. traversal via an allowlisted prefix is blocked" {
  design_sentinel_on
  FIXTURE="$SANDBOX_ROOT/proj/docs/plans/../../../etc/evil"
  run bash "$DESIGN_HOOK" <<< "$(json_for_design "$FIXTURE" "Write")"
  [ "$status" -eq 2 ]
}

@test "design-scope-guard: relative file_path is blocked" {
  design_sentinel_on
  run bash "$DESIGN_HOOK" <<< "$(json_for_design "docs/plans/x.md" "Write")"
  [ "$status" -eq 2 ]
}

@test "design-scope-guard: empty file_path is blocked" {
  design_sentinel_on
  run bash "$DESIGN_HOOK" <<< "$(json_for_design "" "Write")"
  [ "$status" -eq 2 ]
}

@test "design-scope-guard: malformed JSON on stdin is blocked (parse gate)" {
  design_sentinel_on
  run bash "$DESIGN_HOOK" <<< "$(printf 'not-json{{{')"
  [ "$status" -eq 2 ]
}

@test "design-scope-guard: /tmp/../etc/passwd is blocked (.. check precedes /tmp/* allow arm)" {
  design_sentinel_on
  run bash "$DESIGN_HOOK" <<< "$(json_for_design "/tmp/../etc/passwd" "Write")"
  [ "$status" -eq 2 ]
}
