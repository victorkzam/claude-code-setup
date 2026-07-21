#!/bin/bash
# PostToolUse(Write|Edit) — informational syntax check. ALWAYS exits 0 (never blocks);
# surfaces the real first lines of any error so they are visible in the tool output
# (the old version hid Python errors behind 2>/dev/null and a vague message).
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

show_fail() { echo "Syntax error in $FILE:"; echo "$1" | head -5; }

case "$FILE" in
  *.py)
    OUT=$(python3 -m py_compile "$FILE" 2>&1) && echo "Syntax OK: $FILE" || show_fail "$OUT"
    ;;
  *.js|*.mjs|*.cjs)
    if command -v node >/dev/null 2>&1; then
      OUT=$(node --check "$FILE" 2>&1) && echo "Syntax OK: $FILE" || show_fail "$OUT"
    fi
    ;;
  *.ts|*.tsx|*.jsx)
    echo "Note: $FILE — tsc not available without project config; skipped TS syntax check."
    ;;
  *.sh|*.bash)
    OUT=$(bash -n "$FILE" 2>&1) && echo "Syntax OK: $FILE" || show_fail "$OUT"
    ;;
  *.json)
    if command -v jq >/dev/null 2>&1; then
      OUT=$(jq empty "$FILE" 2>&1) && echo "Syntax OK: $FILE" || show_fail "$OUT"
    fi
    ;;
  *.swift)
    if command -v swiftc >/dev/null 2>&1; then
      OUT=$(swiftc -parse "$FILE" 2>&1) && echo "Syntax OK: $FILE" || show_fail "$OUT"
    fi
    ;;
esac
exit 0
