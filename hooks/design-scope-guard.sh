#!/bin/bash
# PreToolUse(Write|Edit) scope guard. While /design is active for THIS session (its
# short post-approval write window), edits are confined to design artifact paths.
# Session-scoped + self-healing sentinel, structurally mirroring
# hooks/orchestrator-delegate-guard.sh. Honest strength claim: the sentinel is
# model-removable in principle — same trust class as the delegate guard.
#
# TTL_MINUTES: a sentinel older than this is treated as stale (a crashed/killed
# /design) and reaped, then the edit is allowed. /design's write window is short,
# so this is a generous ceiling rather than an expected duration.
TTL_MINUTES=120

INPUT=$(cat)

# Fast path (no jq needed): if no sentinel file of any kind exists, /design is not
# active anywhere on the machine, so there is nothing to guard — exit before we
# need to parse anything. This is the common case for every edit outside a /design run.
if ! ls /tmp/claude-design-active* >/dev/null 2>&1; then
  exit 0
fi

# Past this point a sentinel might be active, so we need jq to read session_id /
# agent_type / file_path from stdin. Fail closed rather than silently allowing
# an edit the guard can no longer evaluate.
command -v jq >/dev/null 2>&1 || { echo "jq required for this hook — install jq or remove it from settings.json" >&2; exit 2; }

SID=$(echo "$INPUT" | jq -r '.session_id // empty')
SENTINEL="/tmp/claude-design-active${SID:+.$SID}"
LEGACY="/tmp/claude-design-active"

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
# A delegated subagent is allowed to edit (accepted residual exemption).
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
if [ -n "$AGENT_TYPE" ] && [ "$AGENT_TYPE" != "main" ]; then
  exit 0
fi

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

# /design may write plan and research artifacts, and .gitattributes (used to mark
# generated files). When CLAUDE_CONFIG_DIR is set (adopters using a non-default
# config location), its plans/ dir is editable too, alongside the default
# $HOME/.claude/plans/.
case "$FILE" in
  */docs/plans/*|*/docs/research/*|*/.gitattributes|"$HOME"/.claude/plans/*|/tmp/*|"") exit 0 ;;
esac
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
  case "$FILE" in
    "$CLAUDE_CONFIG_DIR"/plans/*) exit 0 ;;
  esac
fi

echo "/design is active — writes are confined to the design artifact paths (docs/plans/, docs/research/, plans dir)" >&2
exit 2
