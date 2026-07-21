#!/bin/bash
# PreToolUse(Write|Edit) delegation guard. While /build is active for THIS session, the
# main-thread orchestrator must delegate source edits to the implementer subagent.
# Session-scoped + self-healing — replaces the prior machine-global, never-expiring
# sentinel that could permanently lock every project/session if /build was killed.
# Mitigates anthropics/claude-code#51609.
#
# TTL_MINUTES: a sentinel older than this is treated as stale (a crashed/killed /build)
# and reaped, then the edit is allowed. /build re-touches its sentinel at the start of
# every task, so only a stalled/killed run trips this. Heuristic for tuning:
# max(expected_task_count * 10, 45), capped at 120. This is the single adjustment point.
TTL_MINUTES=90

INPUT=$(cat)

# Fast path (no jq needed): if no sentinel file of any kind exists, /build is not
# active anywhere on the machine, so there is nothing to guard — exit before we
# need to parse anything. This is the common case for every edit outside a /build run.
if ! ls /tmp/claude-orchestrator-active* >/dev/null 2>&1; then
  exit 0
fi

# Past this point a sentinel might be active, so we need jq to read session_id /
# agent_type / file_path from stdin. Fail closed rather than silently allowing
# an edit the guard can no longer evaluate.
command -v jq >/dev/null 2>&1 || { echo "jq required for this hook — install jq or remove it from settings.json" >&2; exit 2; }

SID=$(echo "$INPUT" | jq -r '.session_id // empty')
SENTINEL="/tmp/claude-orchestrator-active${SID:+.$SID}"
LEGACY="/tmp/claude-orchestrator-active"

# Find an active, non-stale sentinel: prefer the session-scoped one, fall back to the
# legacy global path for backward compatibility. Reap stale ones (self-heal).
ACTIVE=""
for S in "$SENTINEL" "$LEGACY"; do
  [ -f "$S" ] || continue
  if [ -n "$(find "$S" -mmin +"$TTL_MINUTES" 2>/dev/null)" ]; then
    rm -f "$S"
    continue
  fi
  ACTIVE="$S"; break
done
[ -n "$ACTIVE" ] || exit 0

# agent_type is present in hook stdin only inside a subagent (per Claude Code hooks
# docs; for custom agents it is the frontmatter `name`), absent on the main thread.
# A delegated subagent (implementer/reviewer/...) is allowed to edit.
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
if [ -n "$AGENT_TYPE" ] && [ "$AGENT_TYPE" != "main" ]; then
  exit 0
fi

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

# The orchestrator may still touch its own plan/design drafts and scratch space.
case "$FILE" in
  "$HOME"/.claude/plans/*|/tmp/*|"") exit 0 ;;
esac

echo "Blocked: /build is active (session ${SID:-global}); the orchestrator must not edit source files directly. Spawn an implementer subagent for this change. Plan files under ~/.claude/plans/ remain editable." >&2
exit 2
