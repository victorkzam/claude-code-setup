#!/bin/bash
# tests/run.sh — single test runner, one subcommand per invocation.
# Subcommands: hooks, size, dedupe, scan, all.
# Must work on macOS system bash 3.2 and bash 5, BSD and GNU coreutils: no
# mapfile/readarray, no ${var,,}, no associative arrays, no sed -i without a
# suffix, no grep -P. Deliberately no `set -u`: bash < 4.4 raises "unbound
# variable" on `"${empty_array[@]}"` under nounset, and this script is run
# under bash 3.2 in CI.
#
# Usage errors exit 2; check failures exit 1; success exits 0.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASELINE_BYTES=73738
BASH_BIN="${BASH:-bash}"

usage() {
  echo "usage: tests/run.sh {hooks|size|dedupe|scan|all} [options]" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# hooks
# ---------------------------------------------------------------------------

CASE_NUM=0
HPASS=0
HFAIL=0

report() {
  # $1: 1=pass 0=fail, $2: description, $3: detail (fail only)
  CASE_NUM=$((CASE_NUM + 1))
  if [ "$1" -eq 1 ]; then
    HPASS=$((HPASS + 1))
    printf 'hooks: case %02d [PASS] %s\n' "$CASE_NUM" "$2"
  else
    HFAIL=$((HFAIL + 1))
    printf 'hooks: case %02d [FAIL] %s (%s)\n' "$CASE_NUM" "$2" "$3"
  fi
}

jqtest() {
  printf '%s' "$1" | jq -e "$2" >/dev/null 2>&1
}

check_code() {
  # $1: actual code, $2: expected code, $3: description
  if [ "$1" -eq "$2" ]; then
    report 1 "$3"
  else
    report 0 "$3" "exit=$1 want=$2"
  fi
}

hooks_push_cases() {
  local home_dir out code
  home_dir="$SCRATCH/base"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "push origin main -> blocked"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat/x"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 0 "push -u origin feat/x -> allowed"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force origin feat/x"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "push --force -> blocked"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && git push origin main"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "chained cd && push main -> blocked"
}

hooks_secrets_cases() {
  local home_dir out code
  home_dir="$SCRATCH/base"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.env"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write .env -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.env.example"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 0 "write .env.example -> allowed"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/secrets/.env.example"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write secrets/.env.example -> blocked"

  out=$(printf '%s' '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/tmp/x/secrets.ipynb"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$ROOT/hooks/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "notebookedit secrets.ipynb -> blocked"
}

hooks_jq_absent_case() {
  local nojq_bin errfile code errtxt u p
  nojq_bin="$SCRATCH/c9bin"
  mkdir -p "$nojq_bin"
  for u in bash sh cat tr sed grep basename dirname printf readlink realpath cut head; do
    p=$(command -v "$u" 2>/dev/null) || continue
    ln -sf "$p" "$nojq_bin/$u"
  done

  errfile="$SCRATCH/c9.err"
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":"/tmp"}' \
    | PATH="$nojq_bin" HOME="$SCRATCH/base" "$BASH_BIN" "$ROOT/hooks/protect-branches.sh" \
    >/dev/null 2>"$errfile"
  code=$?
  errtxt=$(cat "$errfile")

  case "$errtxt" in
    *"jq not found"*)
      if [ "$code" -eq 0 ]; then
        report 1 "jq absent -> skip, exit 0"
      else
        report 0 "jq absent -> skip, exit 0" "exit=$code"
      fi
      ;;
    *)
      report 0 "jq absent -> skip, exit 0" "no 'jq not found' on stderr: $errtxt"
      ;;
  esac
}

hooks_profile_cases_a() {
  local h out code

  h="$SCRATCH/c10"
  mkdir -p "$h"
  out=$(printf '%s' '{"cwd":"/tmp","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" "$BASH_BIN" "$ROOT/hooks/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" '.hookSpecificOutput.additionalContext | startswith("profile ")'; then
    report 1 "profile right, no .claude-profiles -> additionalContext"
  else
    report 0 "profile right, no .claude-profiles -> additionalContext" "exit=$code out=$out"
  fi

  h="$SCRATCH/c11"
  mkdir -p "$h/other"
  printf '/tmp/proj|%s/other\n' "$h" > "$h/.claude-profiles"
  out=$(printf '%s' '{"cwd":"/tmp/proj/sub","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$ROOT/hooks/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" '.systemMessage | test("wrong profile")'; then
    report 1 "profile wrong -> systemMessage wrong profile"
  else
    report 0 "profile wrong -> systemMessage wrong profile" "exit=$code out=$out"
  fi

  out=$(printf '%s' '{"cwd":"/somewhere/else","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$ROOT/hooks/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" 'has("systemMessage") | not'; then
    report 1 "unmapped cwd, .claude-profiles present -> no systemMessage"
  else
    report 0 "unmapped cwd, .claude-profiles present -> no systemMessage" "exit=$code out=$out"
  fi
}

hooks_profile_cases_b() {
  local h out code

  h="$SCRATCH/c13"
  mkdir -p "$h"
  printf '@/nonexistent/x.md\n' > "$h/CLAUDE.md"
  out=$(printf '%s' '{"cwd":"/tmp","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$ROOT/hooks/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" '.systemMessage | test("missing import")' \
    && jqtest "$out" '.hookSpecificOutput.additionalContext | test("missing import")'; then
    report 1 "missing absolute import -> both fields"
  else
    report 0 "missing absolute import -> both fields" "exit=$code out=$out"
  fi

  h="$SCRATCH/c14"
  mkdir -p "$h/rules"
  printf 'x' > "$h/rules/x.md"
  printf '@rules/x.md\n' > "$h/CLAUDE.md"
  out=$(printf '%s' '{"cwd":"/tmp","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$ROOT/hooks/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" 'has("systemMessage") | not'; then
    report 1 "relative import exists -> no systemMessage"
  else
    report 0 "relative import exists -> no systemMessage" "exit=$code out=$out"
  fi

  h="$SCRATCH/c15"
  mkdir -p "$h/other"
  printf '# comment\nmalformed line\n/tmp/proj|%s/other\n' "$h" > "$h/.claude-profiles"
  out=$(printf '%s' '{"cwd":"/tmp/proj/sub","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$ROOT/hooks/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" '.systemMessage | test("wrong profile")'; then
    report 1 "commented/malformed lines ignored -> wrong profile"
  else
    report 0 "commented/malformed lines ignored -> wrong profile" "exit=$code out=$out"
  fi
}

cmd_hooks() {
  [ $# -eq 0 ] || usage
  CASE_NUM=0
  HPASS=0
  HFAIL=0
  SCRATCH=$(mktemp -d)
  mkdir -p "$SCRATCH/base"

  hooks_push_cases
  hooks_secrets_cases
  hooks_jq_absent_case
  hooks_profile_cases_a
  hooks_profile_cases_b

  printf 'hooks: %d passed, %d failed\n' "$HPASS" "$HFAIL"
  rm -rf "$SCRATCH"
  [ "$HFAIL" -eq 0 ]
}

# ---------------------------------------------------------------------------
# size
# ---------------------------------------------------------------------------

SCOPE_FILES=""

files_in_scope() {
  # $1: comma-separated dir list (skills,agents,rules), or "" for all three.
  local dirs want_skills want_agents want_rules
  dirs="$1"
  want_skills=0
  want_agents=0
  want_rules=0
  if [ -z "$dirs" ]; then
    want_skills=1
    want_agents=1
    want_rules=1
  else
    case ",$dirs," in *,skills,*) want_skills=1 ;; esac
    case ",$dirs," in *,agents,*) want_agents=1 ;; esac
    case ",$dirs," in *,rules,*) want_rules=1 ;; esac
  fi

  SCOPE_FILES=""
  if [ "$want_skills" -eq 1 ]; then
    SCOPE_FILES="$SCOPE_FILES
$(find "$ROOT/skills" -name 'SKILL.md' 2>/dev/null)"
  fi
  if [ "$want_agents" -eq 1 ]; then
    SCOPE_FILES="$SCOPE_FILES
$(find "$ROOT/agents" -maxdepth 1 -name '*.md' 2>/dev/null)"
  fi
  if [ "$want_rules" -eq 1 ]; then
    SCOPE_FILES="$SCOPE_FILES
$(find "$ROOT/rules" -maxdepth 1 -name '*.md' 2>/dev/null)"
  fi
}

validate_only_scope() {
  # $1: comma-separated --only value (non-empty); exits 2 on any bad entry.
  local scope d rest
  scope="$1"
  while [ -n "$scope" ]; do
    case "$scope" in
      *,*)
        d="${scope%%,*}"
        rest="${scope#*,}"
        ;;
      *)
        d="$scope"
        rest=""
        ;;
    esac
    case "$d" in
      skills | agents | rules) : ;;
      *)
        echo "usage: --only accepts a comma-separated list of skills,agents,rules (bad scope: '$d')" >&2
        exit 2
        ;;
    esac
    scope="$rest"
  done
}

write_frontmatter_awk() {
  cat > "$1" <<'AWKEOF'
BEGIN { infm = 0; capture = 0; val = "" }
NR == 1 { if ($0 == "---") { infm = 1 }; next }
infm == 1 {
  if ($0 == "---") { infm = 0; next }
  if (capture == 1) {
    if ($0 ~ /^[ \t]/ || length($0) == 0) {
      line = $0
      sub(/^[ \t]+/, "", line)
      val = val line "\n"
      next
    } else {
      capture = 0
    }
  }
  if ($0 ~ "^" field ":") {
    rest = $0
    sub("^" field ":[ \t]*", "", rest)
    if (rest == "|" || rest == ">" || rest == "|-" || rest == ">-") {
      capture = 1
      val = ""
    } else {
      n = length(rest)
      if (n >= 2) {
        c1 = substr(rest, 1, 1)
        c2 = substr(rest, n, 1)
        if ((c1 == "\"" && c2 == "\"") || (c1 == "'" && c2 == "'")) {
          rest = substr(rest, 2, n - 2)
        }
      }
      val = rest
    }
  }
}
END { printf "%s", val }
AWKEOF
}

size_check_line_caps() {
  # $1: --only dir scope (same string passed to files_in_scope)
  local f lines cap viol
  files_in_scope "$1"
  viol=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    lines=$(wc -l < "$f" | tr -d ' ')
    cap=150
    case "$f" in
      */skills/design/SKILL.md | */skills/build/SKILL.md) cap=200 ;;
    esac
    if [ "$lines" -gt "$cap" ]; then
      echo "size: VIOLATION $f: $lines lines (cap $cap)"
      viol=1
    fi
  done <<SCOPE
$SCOPE_FILES
SCOPE
  [ "$viol" -eq 0 ]
}

size_check_full_extras() {
  local wf lines tmpawk f d w total viol
  viol=0

  wf="$ROOT/WORKFLOW.md"
  if [ -f "$wf" ]; then
    lines=$(wc -l < "$wf" | tr -d ' ')
    if [ "$lines" -gt 200 ]; then
      echo "size: VIOLATION $wf: $lines lines (cap 200)"
      viol=1
    fi
  fi

  tmpawk=$(mktemp)
  write_frontmatter_awk "$tmpawk"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    d=$(awk -v field="description" -f "$tmpawk" "$f")
    w=$(awk -v field="when_to_use" -f "$tmpawk" "$f")
    total=$((${#d} + ${#w}))
    if [ "$total" -gt 1536 ]; then
      echo "size: VIOLATION $f: description+when_to_use = $total chars (cap 1536)"
      viol=1
    fi
  done <<SCOPE
$(find "$ROOT/skills" -name 'SKILL.md' 2>/dev/null)
SCOPE
  rm -f "$tmpawk"

  [ "$viol" -eq 0 ]
}

cmd_size() {
  local baseline only only_given fail total f sz

  baseline="$BASELINE_BYTES"
  only=""
  only_given=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --only)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          echo "usage: tests/run.sh size [<baseline-bytes>] [--only <dir,dir>]" >&2
          exit 2
        fi
        validate_only_scope "$2"
        only="$2"
        only_given=1
        shift 2
        ;;
      [0-9]*)
        baseline="$1"
        shift
        ;;
      *)
        echo "usage: tests/run.sh size [<baseline-bytes>] [--only <dir,dir>]" >&2
        exit 2
        ;;
    esac
  done

  files_in_scope "$only"
  total=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    sz=$(wc -c < "$f" | tr -d ' ')
    total=$((total + sz))
  done <<SCOPE
$SCOPE_FILES
SCOPE

  awk -v t="$total" -v b="$baseline" \
    'BEGIN { pct = (b > 0) ? (t / b) * 100 : 0; printf "size: %d bytes, %.1f%% of baseline %d\n", t, pct, b }'

  fail=0
  [ "$total" -gt "$baseline" ] && fail=1

  size_check_line_caps "$only" || fail=1
  if [ "$only_given" -eq 0 ]; then
    size_check_full_extras || fail=1
  fi

  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# dedupe
# ---------------------------------------------------------------------------

cmd_dedupe() {
  local only phrases_file targets phrase tf n hitfiles fail

  only=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --only)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          echo "usage: tests/run.sh dedupe [--only <dir>]" >&2
          exit 2
        fi
        validate_only_scope "$2"
        only="$2"
        shift 2
        ;;
      *)
        echo "usage: tests/run.sh dedupe [--only <dir>]" >&2
        exit 2
        ;;
    esac
  done

  phrases_file="$ROOT/tests/dedupe-phrases.txt"
  if [ ! -f "$phrases_file" ]; then
    echo "dedupe: missing $phrases_file" >&2
    return 1
  fi

  files_in_scope "$only"
  targets="$SCOPE_FILES"
  fail=0

  while IFS= read -r phrase || [ -n "$phrase" ]; do
    [ -z "$phrase" ] && continue
    n=0
    hitfiles=""
    while IFS= read -r tf; do
      [ -z "$tf" ] && continue
      if grep -qriF -- "$phrase" "$tf" 2>/dev/null; then
        n=$((n + 1))
        if [ -z "$hitfiles" ]; then
          hitfiles="$tf"
        else
          hitfiles="$hitfiles, $tf"
        fi
      fi
    done <<SCOPE
$targets
SCOPE
    if [ "$n" -ge 2 ]; then
      echo "dedupe: VIOLATION \"$phrase\" appears in: $hitfiles"
      fail=1
    fi
  done < "$phrases_file"

  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------

SCAN_PATHSPECS=()

scan_git_mode() {
  # $1: pattern file, $2: report flag (0/1)
  local pf report_flag out err gcode
  pf="$1"
  report_flag="$2"
  out=$(mktemp)
  err=$(mktemp)

  ( cd "$ROOT" && git grep --untracked -niEf "$pf" -- "${SCAN_PATHSPECS[@]}" ) > "$out" 2>"$err"
  gcode=$?

  if [ "$gcode" -gt 1 ]; then
    echo "scan: git grep error:" >&2
    cat "$err" >&2
    rm -f "$out" "$err"
    return 2
  fi

  rm -f "$err"
  if [ "$gcode" -eq 0 ]; then
    if [ "$report_flag" -eq 1 ]; then
      cut -d: -f1,2 "$out"
      rm -f "$out"
      return 0
    fi
    rm -f "$out"
    echo "scan: hit(s) found" >&2
    return 1
  fi
  rm -f "$out"
  return 0
}

scan_path_mode() {
  # $1: pattern file, $2: directory, $3: report flag (0/1)
  local pf dir report_flag out gcode
  pf="$1"
  dir="$2"
  report_flag="$3"
  out=$(mktemp)

  grep -rIniEf "$pf" "$dir" > "$out" 2>/dev/null
  gcode=$?

  if [ "$gcode" -gt 1 ]; then
    echo "scan: grep error scanning $dir" >&2
    rm -f "$out"
    return 2
  fi
  if [ "$gcode" -eq 0 ]; then
    if [ "$report_flag" -eq 1 ]; then
      cut -d: -f1,2 "$out"
      rm -f "$out"
      return 0
    fi
    rm -f "$out"
    echo "scan: hit(s) found" >&2
    return 1
  fi
  rm -f "$out"
  return 0
}

scan_history() {
  # $1: pattern file, $2: range, $3: report flag (0/1)
  local pf range report_flag tmplog logerr gcode count firstline
  pf="$1"
  range="$2"
  report_flag="$3"
  tmplog=$(mktemp)
  logerr=$(mktemp)

  git -C "$ROOT" log -p "$range" > "$tmplog" 2>"$logerr"
  gcode=$?

  if [ "$gcode" -ne 0 ]; then
    firstline=$(head -n 1 "$logerr")
    echo "scan: git log failed for range $range: $firstline" >&2
    rm -f "$tmplog" "$logerr"
    return 2
  fi
  rm -f "$logerr"

  count=$(grep -ciEf "$pf" "$tmplog" 2>/dev/null)
  count=${count:-0}
  rm -f "$tmplog"

  if [ "$count" -gt 0 ]; then
    if [ "$report_flag" -eq 1 ]; then
      echo "scan: history hits: $count (range $range)"
      return 0
    fi
    echo "scan: history hit(s) found" >&2
    return 1
  fi
  return 0
}

cmd_scan() {
  local pattern_file do_history history_range do_report scan_path got_pattern rc

  pattern_file=""
  do_history=0
  history_range="--all"
  do_report=0
  scan_path=""
  got_pattern=0
  SCAN_PATHSPECS=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --history)
        do_history=1
        shift
        if [ $# -gt 0 ]; then
          case "$1" in
            --report | -p | --history | --) : ;;
            *)
              history_range="$1"
              shift
              ;;
          esac
        fi
        ;;
      --report)
        do_report=1
        shift
        ;;
      -p)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          usage
        fi
        scan_path="$2"
        shift 2
        ;;
      --)
        shift
        while [ $# -gt 0 ]; do
          SCAN_PATHSPECS+=("$1")
          shift
        done
        ;;
      *)
        if [ "$got_pattern" -eq 0 ]; then
          pattern_file="$1"
          got_pattern=1
          shift
        else
          usage
        fi
        ;;
    esac
  done

  [ -z "$pattern_file" ] && pattern_file="${CW_SCAN_PATTERNS:-}"
  if [ -z "$pattern_file" ] || [ ! -r "$pattern_file" ]; then
    echo "scan: no readable pattern file (pass one, or set \$CW_SCAN_PATTERNS)" >&2
    exit 2
  fi

  if [ "$do_history" -eq 1 ]; then
    scan_history "$pattern_file" "$history_range" "$do_report"
    rc=$?
  elif [ -n "$scan_path" ]; then
    scan_path_mode "$pattern_file" "$scan_path" "$do_report"
    rc=$?
  else
    scan_git_mode "$pattern_file" "$do_report"
    rc=$?
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# all
# ---------------------------------------------------------------------------

check_settings_keys() {
  local settings keysfile diff_out
  settings="$ROOT/settings.example.json"
  keysfile="$ROOT/tests/settings-keys.txt"

  if [ ! -f "$keysfile" ]; then
    echo "all: settings-keys: missing tests/settings-keys.txt" >&2
    return 1
  fi
  if [ ! -f "$settings" ]; then
    echo "all: settings-keys: missing settings.example.json" >&2
    return 1
  fi

  diff_out=$(comm -23 <(jq -r 'keys[]' "$settings" | sort) <(sort "$keysfile"))
  if [ -n "$diff_out" ]; then
    echo "all: settings-keys: keys in settings.example.json not documented in tests/settings-keys.txt:" >&2
    echo "$diff_out" >&2
    return 1
  fi
  return 0
}

cmd_all() {
  [ $# -eq 0 ] || usage
  local fail summary
  fail=0
  summary=""

  if cmd_hooks; then
    summary="$summary
all: hooks: PASS"
  else
    summary="$summary
all: hooks: FAIL"
    fail=1
  fi

  if cmd_size; then
    summary="$summary
all: size: PASS"
  else
    summary="$summary
all: size: FAIL"
    fail=1
  fi

  if cmd_dedupe; then
    summary="$summary
all: dedupe: PASS"
  else
    summary="$summary
all: dedupe: FAIL"
    fail=1
  fi

  if check_settings_keys; then
    summary="$summary
all: settings-keys: PASS"
  else
    summary="$summary
all: settings-keys: FAIL"
    fail=1
  fi

  if [ -n "${CW_SCAN_PATTERNS:-}" ]; then
    if [ ! -r "$CW_SCAN_PATTERNS" ]; then
      echo "all: scan: pattern file not readable" >&2
      summary="$summary
all: scan: FAIL"
      fail=1
    elif cmd_scan "$CW_SCAN_PATTERNS"; then
      summary="$summary
all: scan: PASS"
    else
      summary="$summary
all: scan: FAIL"
      fail=1
    fi
  else
    echo "all: scan: skipped (\$CW_SCAN_PATTERNS not set)"
    summary="$summary
all: scan: SKIPPED"
  fi

  printf '%s\n' "$summary"
  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  case "${1:-}" in
    hooks)
      shift
      cmd_hooks "$@"
      ;;
    size)
      shift
      cmd_size "$@"
      ;;
    dedupe)
      shift
      cmd_dedupe "$@"
      ;;
    scan)
      shift
      cmd_scan "$@"
      ;;
    all)
      shift
      cmd_all "$@"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
