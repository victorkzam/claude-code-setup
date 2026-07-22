#!/usr/bin/env bash
# tests/test_helper.bash — shared bats plumbing for the installer test suite.
# Sandbox setup ONLY; no task-specific fixtures. This file is frozen after Task 7
# (design M9) — later tasks add their own fixtures to their own .bats files.

# Absolute path to the repo under test.
REPO_ROOT="$( cd "$BATS_TEST_DIRNAME/.." && pwd -P )"
export REPO_ROOT

# ccs_setup_sandbox — isolated HOME + config dir under the per-test tmpdir.
# Ambient CLAUDE_CONFIG_DIR must never leak into tests (M5): unset it, then set it
# explicitly to a sandbox path. A stub bin dir is prepended to PATH so fake
# executables can override real ones while real tools stay reachable.
ccs_setup_sandbox() {
  SANDBOX="$BATS_TEST_TMPDIR/sandbox"
  CCS_STUB_BIN="$SANDBOX/bin"
  mkdir -p "$SANDBOX/home" "$CCS_STUB_BIN"
  unset CLAUDE_CONFIG_DIR
  HOME="$SANDBOX/home"
  CLAUDE_CONFIG_DIR="$HOME/.claude"
  PATH="$CCS_STUB_BIN:$PATH"
  export HOME CLAUDE_CONFIG_DIR PATH
}

# ccs_isolate_path — restrict PATH to the stub bin plus symlinks of the base
# utilities the scripts need, so a test can simulate a tool being ABSENT simply by
# not stubbing it. Call after ccs_setup_sandbox.
ccs_isolate_path() {
  local orig="$PATH" util src
  for util in bash sh env dirname basename grep head tr cat cp mv rm mkdir \
              chmod ln sort uniq mktemp date sed awk find git timeout; do
    src="$( PATH="$orig" command -v "$util" 2>/dev/null || true )"
    [ -n "$src" ] && ln -sf "$src" "$CCS_STUB_BIN/$util"
  done
  PATH="$CCS_STUB_BIN"
  export PATH
}

# ccs_make_stub <name> <exit_code> [output_line...] — create a fake executable on
# the stub PATH that prints the given lines (verbatim, for any args) and exits
# with <exit_code>.
ccs_make_stub() {
  local name="$1" code="$2"
  shift 2
  local file="$CCS_STUB_BIN/$name" line
  {
    printf '#!/usr/bin/env bash\n'
    for line in "$@"; do
      printf 'printf "%%s\\n" %q\n' "$line"
    done
    printf 'exit %s\n' "$code"
  } > "$file"
  chmod +x "$file"
}
