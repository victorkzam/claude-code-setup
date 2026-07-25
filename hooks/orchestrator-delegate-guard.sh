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
#
# Residual limits (honest disclosure, not exhaustive):
#  (a) this hook fires on PreToolUse(Write|Edit) only -- it does not intercept
#      Bash, so `cp`/shell redirection/`ln -s` can still write outside the
#      allowlist during the guarded window.
#  (b) the require-absolute-path check below is defense-in-depth best practice,
#      not a schema-guaranteed invariant of tool_input.file_path.
#  (c) the checks below sit after the agent_type != main exemption, so this
#      hardening is main-thread-only by design -- delegated subagent edits
#      remain exempt.
#  (d) matching is lexical (string prefix/glob) only, with no symlink
#      resolution -- a symlink placed inside an allowlisted dir that points
#      outside it defeats the allowlist; out of scope for a Write|Edit hook.
#  (e) the project-relative allowances are anchored to the session project root
#      derived from the payload cwd. cwd follows `cd` within the session, so
#      this binds to the session's *current* project -- a real narrowing (an
#      unrelated repo's docs/plans/ no longer matches), not cryptographic
#      confinement.
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

# Malformed JSON yields an empty session_id below, which collapses the sentinel
# path to the unsuffixed legacy path; if nothing is there the sentinel loop
# finds nothing and the hook would exit 0 at the sentinel stage BEFORE any
# file_path check ever runs. Reject unparseable input here instead (fail closed).
echo "$INPUT" | jq empty 2>/dev/null || { echo "orchestrator-delegate-guard — unparseable hook input, refusing (fail closed)" >&2; exit 2; }

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

[ -z "$FILE" ] && { echo "orchestrator-delegate-guard — empty file_path, refusing (fail closed)" >&2; exit 2; }
case "$FILE" in
  ../*|*/../*|*/..|..) echo "orchestrator-delegate-guard — path traversal (..) refused" >&2; exit 2 ;;
esac
case "$FILE" in
  /*) ;;
  *) echo "orchestrator-delegate-guard — non-absolute path refused" >&2; exit 2 ;;
esac

# Anchor the project-relative allowances to THIS session's project root, so the
# promoted docs/plans/, docs/research/, and .gitattributes shapes cannot match
# an unrelated repo elsewhere on disk. Derive the root from the payload cwd: git
# toplevel when cwd is inside a repo, else cwd itself (bats fixtures aren't
# repos). Sanitize first -- an empty, non-absolute, or ..-containing cwd yields
# an empty ROOT, and the project-relative arm below is skipped entirely (fail
# closed for that branch only) rather than collapsing "$ROOT"/... to a bare
# /... glob.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
ROOT=""
case "$CWD" in
  ""|../*|*/../*|*/..|..) ;;
  /*) ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); [ -n "$ROOT" ] || ROOT="$CWD" ;;
esac

# The orchestrator may still touch its own promoted plan/design drafts and the
# project-root .gitattributes (skills/build writes only "$ROOT/.gitattributes"
# -- the docs/plans/** linguist-generated marker -- so only the root file is
# allowed, never */.gitattributes anywhere). These arms are root-anchored
# literal prefixes, never bare */... globs (which this repo has repeatedly
# regressed into an unanchored allowlist bypass).
if [ -n "$ROOT" ]; then
  case "$FILE" in
    "$ROOT"/docs/plans/*|"$ROOT"/docs/research/*|"$ROOT"/.gitattributes) exit 0 ;;
  esac
fi

# Config-dir and scratch allowances are not project-scoped and stay as-is. When
# CLAUDE_CONFIG_DIR is set (adopters using a non-default config location), its
# plans/ dir is editable too, alongside the default $HOME/.claude/plans/.
case "$FILE" in
  "$HOME"/.claude/plans/*|/tmp/*) exit 0 ;;
esac
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
  case "$FILE" in
    "$CLAUDE_CONFIG_DIR"/plans/*) exit 0 ;;
  esac
fi

echo "Blocked: /build is active (session ${SID:-global}); the orchestrator must not edit source files directly. Spawn an implementer subagent for this change. Plan files under ~/.claude/plans/ (or \$CLAUDE_CONFIG_DIR/plans/ if set) and, within THIS project (${ROOT:-<no project root>}), docs/plans/, docs/research/, and .gitattributes remain editable." >&2
exit 2
