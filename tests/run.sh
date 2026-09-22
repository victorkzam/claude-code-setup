#!/bin/bash
# tests/run.sh — single test runner, one subcommand per invocation.
# Subcommands: hooks, size, dedupe, scan, trailers, all.
# Must work on macOS system bash 3.2 and bash 5, BSD and GNU coreutils: no
# mapfile/readarray, no ${var,,}, no associative arrays, no sed -i without a
# suffix, no grep -P. Deliberately no `set -u`: bash < 4.4 raises "unbound
# variable" on `"${empty_array[@]}"` under nounset, and this script is run
# under bash 3.2 in CI.
#
# Usage errors exit 2; check failures exit 1; a skipped trailers check
# returns exit 3; success exits 0.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASELINE_BYTES=73738
BASH_BIN="${BASH:-bash}"
HOOKS_DIR="${CW_HOOKS_DIR:-$ROOT/hooks}"

usage() {
  echo "usage: tests/run.sh {hooks|size|dedupe|scan|trailers|all} [options]" >&2
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

push_case() {
  # $1: expected code, $2: description, $3: cwd, $4: command
  local expected desc cwd cmd payload code
  expected="$1"
  desc="$2"
  cwd="$3"
  cmd="$4"
  payload=$(jq -nc --arg c "$cmd" --arg d "$cwd" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
  printf '%s' "$payload" | HOME="$SCRATCH/base" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" >/dev/null 2>&1
  code=$?
  check_code "$code" "$expected" "$desc"
}

push_case_repo() {
  # Same as push_case, but skipped (outside the pass/fail count) when the
  # scratch git repositories could not be created.
  if [ "$REPOS_OK" -ne 1 ]; then
    printf 'hooks: skipped (no scratch repo): %s\n' "$2"
    return
  fi
  push_case "$@"
}

speed_case() {
  # $1: expected code, $2: description, $3: cwd, $4: command
  local expected desc cwd cmd payload code secs
  expected="$1"
  desc="$2"
  cwd="$3"
  cmd="$4"
  payload=$(jq -nc --arg c "$cmd" --arg d "$cwd" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
  SECONDS=0
  printf '%s' "$payload" | HOME="$SCRATCH/base" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" >/dev/null 2>&1
  code=$?
  secs=$SECONDS
  if [ "$code" -eq "$expected" ] && [ "$secs" -le 1 ]; then
    report 1 "$desc"
  else
    report 0 "$desc" "exit=$code want=$expected secs=$secs"
  fi
}

REPOS_OK=0

setup_scratch_repos() {
  # Four scratch repositories for the state/resolution cases: rm (main, one
  # commit), rf (cloned, HEAD feat/x, no upstream), rc (like rf plus an
  # upstream on main, push.default unset), ru (like rc plus
  # push.default=upstream). Each git invocation inherits the real HOME's
  # gitconfig, so identity and signing are pinned with -c. If `git init -b
  # main` fails, REPOS_OK stays 0 and every case naming a scratch repo is
  # skipped through push_case_repo.
  local gc
  gc="-c user.name=cw-test -c user.email=cw-test@example.com -c commit.gpgsign=false"
  # shellcheck disable=SC2086 # $gc is a fixed, space-separated list of -c flags, deliberately unquoted
  if ! git $gc init -q -b main "$SCRATCH/rm" >/dev/null 2>&1; then
    REPOS_OK=0
    return
  fi
  printf 'x\n' > "$SCRATCH/rm/README.md"
  # shellcheck disable=SC2086
  git -C "$SCRATCH/rm" $gc add README.md >/dev/null 2>&1
  # shellcheck disable=SC2086
  git -C "$SCRATCH/rm" $gc commit -q -m init >/dev/null 2>&1

  # shellcheck disable=SC2086
  git $gc clone -q "$SCRATCH/rm" "$SCRATCH/rf" >/dev/null 2>&1
  # shellcheck disable=SC2086
  git -C "$SCRATCH/rf" $gc checkout -q -b feat/x >/dev/null 2>&1

  # shellcheck disable=SC2086
  git $gc clone -q "$SCRATCH/rm" "$SCRATCH/rc" >/dev/null 2>&1
  # shellcheck disable=SC2086
  git -C "$SCRATCH/rc" $gc checkout -q -b feat/x >/dev/null 2>&1
  git -C "$SCRATCH/rc" branch --set-upstream-to=origin/main >/dev/null 2>&1

  # shellcheck disable=SC2086
  git $gc clone -q "$SCRATCH/rm" "$SCRATCH/ru" >/dev/null 2>&1
  # shellcheck disable=SC2086
  git -C "$SCRATCH/ru" $gc checkout -q -b feat/x >/dev/null 2>&1
  git -C "$SCRATCH/ru" branch --set-upstream-to=origin/main >/dev/null 2>&1
  git -C "$SCRATCH/ru" config push.default upstream >/dev/null 2>&1

  REPOS_OK=1
}

hooks_push_cases() {
  local home_dir out code
  home_dir="$SCRATCH/base"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "push origin main -> blocked"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat/x"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 0 "push -u origin feat/x -> allowed"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force origin feat/x"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "push --force -> blocked"

  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && git push origin main"},"cwd":"/tmp"}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "chained cd && push main -> blocked"
}

hooks_secrets_cases() {
  local home_dir out code
  home_dir="$SCRATCH/base"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.env"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write .env -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.env.example"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 0 "write .env.example -> allowed"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/secrets/.env.example"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write secrets/.env.example -> blocked"

  out=$(printf '%s' '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/tmp/x/secrets.ipynb"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
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
    | PATH="$nojq_bin" HOME="$SCRATCH/base" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" \
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
    | HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
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
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" '.systemMessage | test("wrong profile")'; then
    report 1 "profile wrong -> systemMessage wrong profile"
  else
    report 0 "profile wrong -> systemMessage wrong profile" "exit=$code out=$out"
  fi

  out=$(printf '%s' '{"cwd":"/somewhere/else","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
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
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
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
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
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
    | HOME="$h" CLAUDE_CONFIG_DIR="$h" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" '.systemMessage | test("wrong profile")'; then
    report 1 "commented/malformed lines ignored -> wrong profile"
  else
    report 0 "commented/malformed lines ignored -> wrong profile" "exit=$code out=$out"
  fi
}

hooks_nested_cases() {
  push_case 2 "nested sh -c push main -> blocked" "/tmp" 'sh -c "git push origin main"'
  push_case 2 "nested bash -c cd && push main -> blocked" "/tmp" "bash -c 'cd /tmp && git push origin main'"
  push_case 2 "eval push main -> blocked" "/tmp" 'eval "git push origin main"'
  # shellcheck disable=SC2016 # payload literal for the hook, not a shell expansion here
  push_case 2 "backtick-wrapped push main -> blocked" "/tmp" 'echo `git push origin main`'
  push_case_repo 2 "nested sh -c cd \$SCRATCH/rm && push -> blocked" "/tmp" "sh -c \"cd $SCRATCH/rm && git push\""
}

hooks_backslash_cases() {
  push_case 2 "backslash-escaped \\git push main -> blocked" "/tmp" '\git push origin main'
  push_case 0 "backslash-escaped \\git push -u origin feat/x -> allowed" "/tmp" '\git push -u origin feat/x'
}

hooks_options_cases() {
  push_case 2 "push --all origin -> blocked" "/tmp" 'git push --all origin'
  push_case 2 "push --mirror origin -> blocked" "/tmp" 'git push --mirror origin'
  push_case 2 "push origin --all -> blocked" "/tmp" 'git push origin --all'
  push_case 0 "push --force-with-lease origin feat/x -> allowed" "/tmp" 'git push --force-with-lease origin feat/x'
  push_case 0 "push --force-with-lease=feat/x origin feat/x -> allowed" "/tmp" 'git push --force-with-lease=feat/x origin feat/x'
  push_case 0 "push --force-if-includes origin feat/x -> allowed" "/tmp" 'git push --force-if-includes origin feat/x'
  push_case 2 "push --force-with-lease origin main -> blocked" "/tmp" 'git push --force-with-lease origin main'
  push_case 2 "push -fu origin feat/x -> blocked" "/tmp" 'git push -fu origin feat/x'
  push_case 2 "push origin +feat/x -> blocked" "/tmp" 'git push origin +feat/x'
  push_case 2 "push origin HEAD:main -> blocked" "/tmp" 'git push origin HEAD:main'
  push_case 2 "push origin --delete main -> blocked" "/tmp" 'git push origin --delete main'
  push_case 2 "push origin :main -> blocked" "/tmp" 'git push origin :main'
  push_case 0 "push origin --dry-run feat/x -> allowed" "/tmp" 'git push origin --dry-run feat/x'
}

hooks_names_cases() {
  push_case 0 "push -u origin feat/main-nav -> allowed" "/tmp" 'git push -u origin feat/main-nav'
  push_case 0 "commit message mentioning push to main -> allowed" "/tmp" 'git commit -m "docs: pushing to main is blocked"'
  push_case 2 "env-assignment FOO=bar git push origin main -> blocked" "/tmp" 'FOO=bar git push origin main'
  push_case 2 "git -c core.x=1 push origin main -> blocked" "/tmp" 'git -c core.x=1 push origin main'
  push_case 2 "case-insensitive GIT push origin main -> blocked" "/tmp" 'GIT push origin main'
}

hooks_state_cases() {
  push_case 2 "switch main && push -> blocked" "/tmp" 'git switch main && git push'
  push_case 2 "checkout main && push origin -> blocked" "/tmp" 'git checkout main && git push origin'
  push_case_repo 2 "cd \$SCRATCH/rm && push -> blocked" "/tmp" "cd $SCRATCH/rm && git push"
  # shellcheck disable=SC2016 # payload literal for the hook: $DIR must stay unexpanded
  push_case 2 "cd \"\$DIR\" && push -> blocked (unknown dir)" "/tmp" 'cd "$DIR" && git push'
  push_case 0 "checkout -b feat/y && push -u origin HEAD -> allowed" "/tmp" 'git checkout -b feat/y && git push -u origin HEAD'
  push_case 0 "checkout -- README.md && push -u origin feat/x -> allowed" "/tmp" 'git checkout -- README.md && git push -u origin feat/x'
  push_case_repo 2 "checkout -b feat/y && cd \$SCRATCH/rm && push -> blocked (cd clears branch)" "/tmp" "git checkout -b feat/y && cd $SCRATCH/rm && git push"
  push_case 2 "status & push origin main (bare & separator) -> blocked" "/tmp" 'git status & git push origin main'
  push_case 2 "pushd /tmp && popd && push -> blocked (popd anywhere clears state)" "/tmp" 'pushd /tmp && popd && git push'
  push_case 2 "checkout feat/x -- README.md && push -> blocked (path checkout, not a branch change)" "/tmp" 'git checkout feat/x -- README.md && git push'
  push_case_repo 2 "cd -P \$SCRATCH/rm && push -> blocked (-P is an option, not the dir)" "/tmp" "cd -P $SCRATCH/rm && git push"
  push_case_repo 2 "cd -- \$SCRATCH/rm && push -> blocked (-- is an option, not the dir)" "/tmp" "cd -- $SCRATCH/rm && git push"
}

hooks_resolution_cases() {
  push_case_repo 2 "cwd rm: push -> blocked (current branch main)" "$SCRATCH/rm" 'git push'
  push_case_repo 2 "cwd rm: push origin -> blocked (current branch main)" "$SCRATCH/rm" 'git push origin'
  push_case_repo 2 "cwd rm: push -u origin HEAD -> blocked (current branch main)" "$SCRATCH/rm" 'git push -u origin HEAD'
  push_case_repo 2 "cwd rm: checkout -- README.md && push -> blocked (unknown branch)" "$SCRATCH/rm" 'git checkout -- README.md && git push'
  push_case_repo 0 "cwd rf: push -> allowed (feat/x, no upstream)" "$SCRATCH/rf" 'git push'
  push_case_repo 0 "cwd rf: push -u origin HEAD -> allowed (feat/x, no upstream)" "$SCRATCH/rf" 'git push -u origin HEAD'
  push_case_repo 2 "cwd rf: git -C \$SCRATCH/rm push -> blocked (-C wins)" "$SCRATCH/rf" "git -C $SCRATCH/rm push"
  push_case_repo 2 "cwd ru: push -> blocked (upstream main, push.default upstream)" "$SCRATCH/ru" 'git push'
  push_case_repo 0 "cwd rc: push -> allowed (upstream main, push.default unset)" "$SCRATCH/rc" 'git push'
  push_case_repo 0 "cwd rm: push feat/x -> allowed (explicit slash destination)" "$SCRATCH/rm" 'git push feat/x'
  push_case_repo 2 "cwd /tmp: checkout -b feat/y && git -C \$SCRATCH/rm push -> blocked (-C wins over tracked branch)" "/tmp" "git checkout -b feat/y && git -C $SCRATCH/rm push"
  push_case_repo 0 "cwd /tmp: checkout -b feat/y && git -C \$SCRATCH/rf push -> allowed" "/tmp" "git checkout -b feat/y && git -C $SCRATCH/rf push"
}

hooks_speed_cases() {
  local big seg2 i seg3 letters seg4
  big=$(printf '%*s' 100000 '' | tr ' ' 'a')
  speed_case 2 "100k-char token + push main -> blocked, under 1s" "/tmp" "$big && git push origin main"

  seg2=""
  i=1
  while [ "$i" -le 5000 ]; do
    if [ -z "$seg2" ]; then
      seg2="echo abcd-$i"
    else
      seg2="$seg2 && echo abcd-$i"
    fi
    i=$((i + 1))
  done
  speed_case 2 "5000 && segments + push main -> blocked, under 1s" "/tmp" "$seg2 && git push origin main"

  letters="abcdefghijklmnopqrstuvwxyz0123456789ABCD"
  seg3=""
  i=1
  while [ "$i" -le 2000 ]; do
    if [ -z "$seg3" ]; then
      seg3="echo line-$i-$letters"
    else
      seg3="$seg3
echo line-$i-$letters"
    fi
    i=$((i + 1))
  done
  speed_case 0 "2000-line heredoc-shaped input, no push -> allowed, under 1s" "/tmp" "$seg3"

  seg4=""
  i=1
  while [ "$i" -le 12000 ]; do
    if [ -z "$seg4" ]; then
      seg4="abcd-$i"
    else
      seg4="$seg4 abcd-$i"
    fi
    i=$((i + 1))
  done
  speed_case 2 "one ~100k-char segment (many short cd-containing tokens) + push main -> blocked, under 1s" "/tmp" "$seg4 && git push origin main"
}

hooks_input_cases() {
  local errfile out code errtxt
  errfile="$SCRATCH/input1.err"
  out=$(printf '%s' 'not json' | HOME="$SCRATCH/base" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" 2>"$errfile")
  code=$?
  errtxt=$(cat "$errfile" 2>/dev/null)
  if [ "$code" -eq 0 ] && [ -z "$errtxt" ]; then
    report 1 "malformed json input -> exit 0, stderr empty"
  else
    report 0 "malformed json input -> exit 0, stderr empty" "exit=$code err=$errtxt"
  fi

  out=$(printf '%s' '{}' | HOME="$SCRATCH/base" "$BASH_BIN" "$HOOKS_DIR/protect-branches.sh" 2>/dev/null)
  code=$?
  check_code "$code" 0 "empty json object -> exit 0"
}

hooks_secrets_new_cases() {
  local home_dir out code
  home_dir="$SCRATCH/base"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/certs/client.p12"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write client.p12 -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.netrc"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write .netrc -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/id_dsa"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write id_dsa -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/id_ecdsa"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write id_ecdsa -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/terraform.tfstate"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write terraform.tfstate -> blocked"

  out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/terraform.tfstate.backup"}}' \
    | HOME="$home_dir" "$BASH_BIN" "$HOOKS_DIR/protect-secrets.sh" 2>/dev/null)
  code=$?
  check_code "$code" 2 "write terraform.tfstate.backup -> blocked"
}

hooks_profile_error_case() {
  local shimbin u p out code
  shimbin="$SCRATCH/jqshim"
  mkdir -p "$shimbin"
  for u in cat sed basename dirname printf head cut tr grep; do
    p=$(command -v "$u" 2>/dev/null) || continue
    ln -sf "$p" "$shimbin/$u"
  done
  printf '#!/bin/sh\nexit 5\n' > "$shimbin/jq"
  chmod +x "$shimbin/jq"

  out=$(printf '%s' '{"cwd":"/tmp","hook_event_name":"SessionStart"}' \
    | PATH="$shimbin" HOME="$SCRATCH/base2" CLAUDE_CONFIG_DIR="$SCRATCH/base2/.claude" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && [ "$out" = "{}" ]; then
    report 1 "jq present but every call fails -> stdout {}, exit 0"
  else
    report 0 "jq present but every call fails -> stdout {}, exit 0" "exit=$code out=$out"
  fi
}

hooks_profile_crlf_case() {
  local h out code
  h="$SCRATCH/c16"
  mkdir -p "$h/.claude"
  printf '/tmp|%s/.claude\r\n' "$h" > "$h/.claude-profiles"
  out=$(printf '%s' '{"cwd":"/tmp","hook_event_name":"SessionStart"}' \
    | HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" "$BASH_BIN" "$HOOKS_DIR/profile-check.sh" 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ] && jqtest "$out" 'has("systemMessage") | not'; then
    report 1 "CRLF .claude-profiles line, mapping matches active -> no systemMessage"
  else
    report 0 "CRLF .claude-profiles line, mapping matches active -> no systemMessage" "exit=$code out=$out"
  fi
}

cmd_hooks() {
  [ $# -eq 0 ] || usage
  CASE_NUM=0
  HPASS=0
  HFAIL=0
  REPOS_OK=0
  SCRATCH=$(mktemp -d)
  mkdir -p "$SCRATCH/base"
  setup_scratch_repos

  hooks_push_cases
  hooks_nested_cases
  hooks_backslash_cases
  hooks_options_cases
  hooks_names_cases
  hooks_state_cases
  hooks_resolution_cases
  hooks_speed_cases
  hooks_input_cases
  hooks_secrets_cases
  hooks_secrets_new_cases
  hooks_jq_absent_case
  hooks_profile_cases_a
  hooks_profile_cases_b
  hooks_profile_error_case
  hooks_profile_crlf_case

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
# trailers
# ---------------------------------------------------------------------------

cmd_trailers() {
  [ $# -eq 0 ] || usage
  local expected shallow base n fail c body trailer_count co_count short subject

  expected=$(sed -n 's/^  \(Co-Authored-By: .*\)$/\1/p' "$ROOT/rules/workflow.md" | head -n 1)
  if [ -z "$expected" ]; then
    echo "trailers: cannot read the expected trailer from rules/workflow.md" >&2
    return 1
  fi

  shallow=$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)
  base=""
  if [ "$shallow" != "true" ]; then
    if git -C "$ROOT" rev-parse --verify -q main >/dev/null 2>&1; then
      base="main"
    elif git -C "$ROOT" rev-parse --verify -q origin/main >/dev/null 2>&1; then
      base="origin/main"
    fi
  fi

  if [ "$shallow" = "true" ] || [ -z "$base" ]; then
    echo "trailers: skipped (shallow repository or no main/origin/main ref)"
    return 3
  fi

  n=0
  fail=0
  while read -r c; do
    [ -z "$c" ] && continue
    n=$((n + 1))
    body=$(git -C "$ROOT" log -1 --format=%B "$c")
    trailer_count=$(printf '%s\n' "$body" | grep -c -F -x -- "$expected")
    co_count=$(printf '%s\n' "$body" | grep -ci '^Co-Authored-By:')
    if [ "$trailer_count" -eq 1 ] && [ "$co_count" -eq 1 ] && ! printf '%s\n' "$body" | grep -q '^Claude-Session:'; then
      continue
    fi
    short=$(git -C "$ROOT" rev-parse --short "$c")
    subject=$(git -C "$ROOT" log -1 --format=%s "$c")
    echo "trailers: VIOLATION $short $subject: expected exactly one trailer line \"$expected\" and no session line"
    fail=1
  done < <(git -C "$ROOT" rev-list --no-merges "$base..HEAD")

  if [ "$fail" -eq 0 ]; then
    echo "trailers: OK ($base..HEAD, $n commits)"
    return 0
  fi
  return 1
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
  local fail summary trailers_rc
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

  cmd_trailers
  trailers_rc=$?
  case "$trailers_rc" in
    0)
      summary="$summary
all: trailers: PASS"
      ;;
    3)
      summary="$summary
all: trailers: SKIPPED"
      ;;
    *)
      summary="$summary
all: trailers: FAIL"
      fail=1
      ;;
  esac

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
    trailers)
      shift
      cmd_trailers "$@"
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
