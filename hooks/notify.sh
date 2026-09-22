#!/bin/bash
# Notification|Stop|StopFailure — session-labelled desktop notifier. Pings
# only when a human is needed: the four immediate Notification types, plus
# the built-in idle_prompt gated on the background-task count that Stop
# records. Opt-in via ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cw-notify.json
# (absent -> silent). Always exits 0: exit 2 on Stop would block the turn.
# No output unless CW_NOTIFY_DRY_RUN=1.

# shellcheck disable=SC2317,SC2329 # invoked indirectly via `trap ... EXIT` below; older shellcheck reports SC2317, newer SC2329
finish() {
  exit 0
}
trap finish EXIT

INPUT=$(cat 2>/dev/null)

command -v jq >/dev/null 2>&1 || exit 0
[ "$CW_NOTIFY" = "0" ] && exit 0

printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
NOTIF_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD_IN=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
# shellcheck disable=SC2034 # parsed for parity with the spec's field list; not yet branched on
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active == true' 2>/dev/null)
BG_COUNT=$(printf '%s' "$INPUT" | jq '(.background_tasks // []) | if type == "array" then length else 0 end' 2>/dev/null)
case "$BG_COUNT" in ''|*[!0-9]*) BG_COUNT=0 ;; esac

# --- config: the file's presence is the opt-in ------------------------------
HOME_DIR="${HOME:-/root}"
CONFIG_FILE="${CW_NOTIFY_CONFIG:-${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}/cw-notify.json}"
[ -f "$CONFIG_FILE" ] || exit 0

ENABLED=true
PRESENCE=false
IDLE_SECONDS=300
STALE_SECONDS=1800
IDLE_MESSAGE="Waiting for your input"
ENTRYPOINTS="cli"

CFG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null)
if printf '%s' "$CFG_CONTENT" | jq -e . >/dev/null 2>&1; then
  # jq's `//` treats an explicit `false` as falsy too, so an explicit
  # `"enabled": false` must be read with `has`, not `// true`.
  v=$(printf '%s' "$CFG_CONTENT" | jq -r 'if has("enabled") then .enabled else true end' 2>/dev/null) && [ -n "$v" ] && ENABLED="$v"
  v=$(printf '%s' "$CFG_CONTENT" | jq -r '.presence // false' 2>/dev/null) && [ -n "$v" ] && PRESENCE="$v"
  v=$(printf '%s' "$CFG_CONTENT" | jq -r '.idle_seconds // 300' 2>/dev/null) && [ -n "$v" ] && IDLE_SECONDS="$v"
  v=$(printf '%s' "$CFG_CONTENT" | jq -r '.stale_seconds // 1800' 2>/dev/null) && [ -n "$v" ] && STALE_SECONDS="$v"
  v=$(printf '%s' "$CFG_CONTENT" | jq -r '.idle_message // "Waiting for your input"' 2>/dev/null) && [ -n "$v" ] && IDLE_MESSAGE="$v"
  v=$(printf '%s' "$CFG_CONTENT" | jq -r '(.entrypoints // ["cli"]) | join(" ")' 2>/dev/null) && ENTRYPOINTS="$v"
fi
case "$IDLE_SECONDS" in ''|*[!0-9]*) IDLE_SECONDS=300 ;; esac
case "$STALE_SECONDS" in ''|*[!0-9]*) STALE_SECONDS=1800 ;; esac

[ "$ENABLED" = "false" ] && exit 0

# --- headless guard -----------------------------------------------------
if [ -n "$CLAUDE_CODE_ENTRYPOINT" ]; then
  match=0
  for ep in $ENTRYPOINTS; do
    [ "$ep" = "$CLAUDE_CODE_ENTRYPOINT" ] && match=1 && break
  done
  [ "$match" -eq 1 ] || exit 0
fi

STATE_DIR="${CW_NOTIFY_STATE_DIR:-${TMPDIR:-/tmp}/cw-notify}"
# Sanitise session_id before it reaches a path: keep only a safe charset, and
# treat an empty/"."/".." result as no session state at all (fail open on
# idle_prompt, skip the write on Stop/StopFailure) rather than let a hostile
# or empty id traverse out of STATE_DIR or collide across sessions.
SESSION_ID_SAFE=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
case "$SESSION_ID_SAFE" in
  ""|"."|"..") SESSION_ID_SAFE="" ;;
esac
if [ -n "$SESSION_ID_SAFE" ]; then
  STATE_FILE="$STATE_DIR/${SESSION_ID_SAFE}.bg"
else
  STATE_FILE=""
fi

case "$HOOK_EVENT" in
  Stop)
    if [ -n "$STATE_FILE" ]; then
      mkdir -p "$STATE_DIR" 2>/dev/null
      { printf '%s %s\n' "$BG_COUNT" "$(date +%s)" > "$STATE_FILE"; } 2>/dev/null
    fi
    exit 0
    ;;
  StopFailure)
    if [ -n "$STATE_FILE" ]; then
      mkdir -p "$STATE_DIR" 2>/dev/null
      { printf '0 %s\n' "$(date +%s)" > "$STATE_FILE"; } 2>/dev/null
    fi
    exit 0
    ;;
  Notification)
    ;;
  *)
    exit 0
    ;;
esac

# defensive re-check: only the seven matcher types are handled here
case "$NOTIF_TYPE" in
  permission_prompt|worker_permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|push_notification|idle_prompt) ;;
  *) exit 0 ;;
esac

MSG=""
if [ -n "$AGENT_ID" ]; then
  case "$NOTIF_TYPE" in
    permission_prompt|worker_permission_prompt) MSG="Permission needed (agent: $AGENT_TYPE)" ;;
    *) exit 0 ;;
  esac
else
  case "$NOTIF_TYPE" in
    permission_prompt)
      MSG="Permission needed"
      ;;
    worker_permission_prompt)
      MSG="Permission needed (worker)"
      ;;
    elicitation_dialog|elicitation_url_dialog)
      MSG="Input needed"
      ;;
    agent_needs_input|push_notification)
      if [ -n "$MESSAGE" ]; then
        MSG="$MESSAGE"
      else
        MSG="Attention needed"
      fi
      ;;
    idle_prompt)
      DO_PING=1
      if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        record=""
        { IFS= read -r record < "$STATE_FILE"; } 2>/dev/null
        bg_count=""
        bg_epoch=""
        # Require exactly "<digits> <digits>" before any arithmetic: a
        # malformed record (e.g. a leading zero bash would read as octal)
        # must fail open rather than error out mid-expression.
        case "$record" in
          *[!0-9\ ]*|"") ;;
          *' '*)
            bg_count="${record%% *}"
            bg_epoch="${record#* }"
            case "$bg_count" in ''|*[!0-9]*) bg_count="" ;; esac
            case "$bg_epoch" in ''|*[!0-9]*|*' '*) bg_epoch="" ;; esac
            ;;
        esac
        if [ -n "$bg_count" ] && [ -n "$bg_epoch" ]; then
          now=$(date +%s)
          age=$((now - 10#$bg_epoch))
          if [ "$((10#$bg_count))" -gt 0 ] && [ "$age" -lt "$STALE_SECONDS" ]; then
            DO_PING=0
          fi
        fi
      fi
      if [ "$DO_PING" -eq 1 ]; then
        MSG="$IDLE_MESSAGE"
      else
        exit 0
      fi
      ;;
  esac
fi

# --- title: <folder> [· <session name or its <folder>- suffix>] -----------
FOLDER=$(basename "${CWD_IN:-$PWD}")
REG_FILE="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}/sessions/${CLAUDE_PID}.json"
NAME=""
if [ -n "$CLAUDE_PID" ] && [ -f "$REG_FILE" ]; then
  NAME=$(jq -r '.name // empty' "$REG_FILE" 2>/dev/null)
fi
if [ -z "$NAME" ]; then
  TITLE="$FOLDER"
else
  case "$NAME" in
    "$FOLDER"-*)
      rest="${NAME#"$FOLDER"-}"
      TITLE="$FOLDER · $rest"
      ;;
    *)
      TITLE="$FOLDER · $NAME"
      ;;
  esac
fi

# --- sanitise title and message: control chars -> space, squeeze, truncate -
# Byte-wise and locale-independent: LC_ALL=C keeps tr from reinterpreting
# multibyte UTF-8 sequences. Only C0 controls and DEL (0x00-0x1F, 0x7F) map
# to space; every byte >= 0x80 (all UTF-8 continuation/lead bytes) passes
# through untouched. Truncation uses bash substring expansion so it is
# character-based (not byte-based) whenever the hook runs in a UTF-8 locale.
TITLE=$(printf '%s' "$TITLE" | LC_ALL=C tr '\000-\037\177' ' ' | LC_ALL=C tr -s ' ')
TITLE="${TITLE# }"
TITLE="${TITLE% }"
TITLE="${TITLE:0:100}"
MSG=$(printf '%s' "$MSG" | LC_ALL=C tr '\000-\037\177' ' ' | LC_ALL=C tr -s ' ')
MSG="${MSG# }"
MSG="${MSG% }"
MSG="${MSG:0:200}"

# --- presence (routing only; off by default) -------------------------------
if [ "$PRESENCE" = "true" ]; then
  PSTATE="$CW_NOTIFY_PRESENCE"
  if [ "$PSTATE" != "at" ] && [ "$PSTATE" != "away" ]; then
    PSTATE="at"
    if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
      IDLE_NS=$(ioreg -c IOHIDSystem 2>/dev/null | grep -o '"HIDIdleTime" = [0-9]*' | head -1 | sed 's/.* = //')
      case "$IDLE_NS" in ''|*[!0-9]*) IDLE_NS=0 ;; esac
      IDLE_S=$((IDLE_NS / 1000000000))
      LOCKED=$(ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw - 2>/dev/null)
      is_locked=0
      case "$LOCKED" in true|1) is_locked=1 ;; esac
      if [ "$IDLE_S" -ge "$IDLE_SECONDS" ] || [ "$is_locked" -eq 1 ]; then
        PSTATE="away"
      fi
    fi
  fi
  if [ "$PSTATE" = "away" ]; then
    BRIDGE=""
    if [ -n "$CLAUDE_PID" ] && [ -f "$REG_FILE" ]; then
      BRIDGE=$(jq -r '.bridgeSessionId // empty' "$REG_FILE" 2>/dev/null)
    fi
    [ -n "$BRIDGE" ] && exit 0
  fi
fi

# --- delivery ---------------------------------------------------------------
if [ "$CW_NOTIFY_DRY_RUN" = "1" ]; then
  printf 'notify: %s | %s\n' "$TITLE" "$MSG"
  exit 0
fi

if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' -- "$TITLE" "$MSG" >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "$TITLE" "$MSG" >/dev/null 2>&1
fi

exit 0
