## §T Task breakdown — cw-plugin rev 2

Commits land on `feat/cw-plugin`, created by the live `/build` from `main` after P0. Trailer
per CLAUDE.md on every commit (`Co-Authored-By: Claude <noreply@anthropic.com>`). Tasks run
sequentially in id order (each depends on the previous; `files_owned` disjoint). Zero-count
checks use `! grep -q`. `$CW_SCAN_PATTERNS` (exported at P0) names the private pattern file;
`bash tests/run.sh scan` reads it by default. `$ROOT` is `git rev-parse --show-toplevel`. The
bytes baseline is 73,738 (§R1.1). A verification clause marked "(after the commit)" depends
on the index: the implementer runs it after its commit and the orchestrator's gate re-runs
it; every other clause must pass before the commit. A clause written `cmd; test $? -eq N`
expects that exit code. Interruption and fix-ups per D2.10.

## P0 (the maintainer, plain shell, not a task)
1. Merge PR #2 on GitHub; `R=<path to the checkout>`; `git -C "$R" switch main && git -C "$R"
   pull`.
2. In `$R`: remove the stale private mirror directory under `docs/plans/` (the only entry
   besides `cw-plugin`; untracked and ignored, byte-identical to its private archive —
   confirm with `git ls-files docs/plans | wc -l` = 0 first), `git checkout .gitignore`,
   `rm -f src.txt`.
3. Write the private pattern file outside the repo (a directory of mode 700, the file mode
   600), one extended regex per line: the home path, employer and client names, organisation
   ids, private profile-dir names — not the public display name or handle; `export
   CW_SCAN_PATTERNS=<pattern file>` in `.zshrc` and the current shell.
4. Pre-approve the verification commands for the build session: in `$R/.claude/settings.local.json`
   (ignored) set `permissions.allow` to `Bash(bash:*)`, `Bash(jq:*)`, `Bash(shellcheck:*)`,
   `Bash(claude plugin:*)`, `Bash(env:*)`, `Bash(comm:*)`, `Bash(mktemp:*)`, `Bash(mkdir:*)`,
   `Bash(ln:*)`, `Bash(cat:*)`, `Bash(echo:*)`, `Bash(printf:*)`, `Bash(ls:*)`, `Bash(wc:*)`,
   `Bash(tr:*)`, `Bash(awk:*)`, `Bash(grep:*)`, `Bash(test:*)`, `Bash(sed:*)`, `Bash(find:*)`,
   `Bash(git:*)` (a compound clause the permission parser cannot split may still prompt;
   accepted).
5. Probe (two minutes): `P=$(mktemp -d); mkdir -p $P/.claude-plugin $P/skills/dt $P/hooks`;
   `plugin.json` `{"name":"probe"}`; `skills/dt/SKILL.md` with frontmatter `name: dt`,
   `disallowed-tools: Write, Edit` and the body "First try to create /tmp/dt-probe.txt
   containing hello with the Write tool; then spawn a general-purpose subagent and ask it to
   create /tmp/dt-probe-sub.txt containing hello with the Write tool"; `hooks/hooks.json`
   with a SessionStart `startup` command `echo
   '{"systemMessage":"probe-ok","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"probe-ok"}}'`;
   from a scratch folder `claude --plugin-dir $P`: note whether `probe-ok` is shown at start;
   run `/probe:dt`: note whether the orchestrator's Write is refused AND whether the
   subagent's write succeeds (`test -f /tmp/dt-probe-sub.txt`). Record all three answers in
   D0 (they fix the wording of D2.4 and D2.5; a subagent that cannot write means the field
   propagates and the boundary falls back to prose plus the review gate).
6. `claude --version` (≥ 2.1.269); `command -v jq shellcheck`.
Verify: `git -C "$R" branch --show-current` = main; `git -C "$R" status --short | grep -v
'docs/plans/cw-plugin' | wc -l` = 0 (the artifact set written by `/design` Step 6 is the only
untracked path); `ls "$R/docs/plans" | tr '\n' ' '` = `cw-plugin `; `test ! -f "$R/src.txt"`;
`test -s "$CW_SCAN_PATTERNS"`; `test "$(grep -cEf "$CW_SCAN_PATTERNS" <a local file known to
contain private strings, e.g. the live profile's Google Workspace rule>)" -ge 1` (the pattern
file bites); `test "$(grep -cEf "$CW_SCAN_PATTERNS" "$R/LICENSE")" -eq 0`; `cd "$R" && ! git
grep --untracked -qniEf "$CW_SCAN_PATTERNS" -- . ':!LICENSE'` (covers the untracked artifact
set); `ls "$R/docs/plans/cw-plugin" | wc -l` = 5 (the five files written by `/design` Step 6);
`jq -e '.permissions.allow|length>=15' "$R/.claude/settings.local.json"`; the three probe
answers recorded.

## Task T1
- scope: Plugin skeleton and hooks: `.gitignore` allowlist gains `!.claude-plugin/` and `!.claude-plugin/**`, replaces the `docs/plans/**` and `docs/research/**` lines by `!docs/`, `!docs/plans/`, `!docs/plans/*.md`, `!docs/plans/cw-plugin/`, `!docs/plans/cw-plugin/**`, drops the `scripts/` and the four `.claude/` allowlist lines (keep `!CLAUDE.md` and the `.claude/settings.json` rail); `.claude-plugin/plugin.json` (name cw, version 1.0.0, description, author name only, repository URL, license MIT, keywords); `.claude-plugin/marketplace.json` (name `claude-code-setup`, owner name, one entry `cw`, source `./` — or `.` if `claude plugin validate .` rejects `./`); `hooks/hooks.json` per D2.4 (no `if` fields; SessionStart matcher `startup|resume|clear|fork`); `hooks/profile-check.sh` (new, per D2.4: always exit 0, always the JSON context line, notices in `systemMessage` and `additionalContext`, `~`/relative import targets, comments and malformed profile lines skipped); `hooks/protect-branches.sh` rewritten from the LIVE copy (`~/.claude/hooks/`) with segment splitting on `&&`/`||`/`;`/`|`/newline, no opt-out, and every `EXEMPT` line removed (the block and its four later branch points); `hooks/protect-secrets.sh` from the LIVE copy with the `notebook_path` fallback, the template allowlist moved after the directory checks, and without the personal comment — write this file with a Bash heredoc, never with Write or Edit (the live secrets hook blocks any `*secret*` path); every script's jq check warns on stderr and exits 0 when jq is missing; all three scripts shellcheck-clean at the default severity (fix the findings the live copies carry); delete the three dead hook scripts.
- files_owned: [.gitignore, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, hooks/hooks.json, hooks/profile-check.sh, hooks/protect-branches.sh, hooks/protect-secrets.sh, hooks/orchestrator-delegate-guard.sh, hooks/design-scope-guard.sh, hooks/syntax-check.sh]
- files_forbidden: [skills/**, agents/**, rules/**, tests/**, scripts/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, .github/**]
- depends_on: none
- agent: implementer
- model: sonnet
- risk: high
- verification: `ROOT=$(git rev-parse --show-toplevel); ! git -C "$ROOT" check-ignore -q .claude-plugin/plugin.json && ! git -C "$ROOT" check-ignore -q docs/plans/cw-plugin/probe && ! git -C "$ROOT" check-ignore -q docs/plans/other.md && git -C "$ROOT" check-ignore -q docs/plans/other/probe`; after the commit `git ls-files --error-unmatch .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json hooks/profile-check.sh`; `jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json`; `jq -e '.name=="cw" and .version=="1.0.0"' .claude-plugin/plugin.json`; `jq -e '.name=="claude-code-setup" and .plugins[0].name=="cw" and .plugins[0].source=="./"' .claude-plugin/marketplace.json`; `jq -e '(.hooks.PreToolUse|length)==2 and (.hooks.SessionStart|length)==1' hooks/hooks.json`; `jq -r '..|objects|.command? // empty' hooks/hooks.json | grep -c CLAUDE_PLUGIN_ROOT` = 3; `test "$(jq '[..|objects|select(has("if"))]|length' hooks/hooks.json)" = 0`; `jq -r '.hooks.PreToolUse[].matcher' hooks/hooks.json | grep -q NotebookEdit`; `ls hooks | tr '\n' ' '` = `hooks.json profile-check.sh protect-branches.sh protect-secrets.sh `; `shellcheck -x hooks/*.sh`; `printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":"/tmp"}' | bash hooks/protect-branches.sh; test $? -eq 2`; `printf '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && git push origin main"},"cwd":"/tmp"}' | bash hooks/protect-branches.sh; test $? -eq 2`; `printf '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat/x"},"cwd":"/tmp"}' | bash hooks/protect-branches.sh`; `printf '{"tool_name":"Bash","tool_input":{"command":"git push --force origin feat/x"},"cwd":"/tmp"}' | bash hooks/protect-branches.sh; test $? -eq 2`; `printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.env"}}' | bash hooks/protect-secrets.sh; test $? -eq 2`; `printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/.env.example"}}' | bash hooks/protect-secrets.sh`; `printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/secrets/.env.example"}}' | bash hooks/protect-secrets.sh; test $? -eq 2`; `printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/tmp/x/secrets.ipynb"}}' | bash hooks/protect-secrets.sh; test $? -eq 2`; `! grep -q EXEMPT hooks/protect-branches.sh`; `jq -r '.hooks.SessionStart[].matcher' hooks/hooks.json | grep -q fork`; `B=$(mktemp -d); for u in bash sh cat tr sed grep basename dirname printf readlink realpath cut head; do p=$(command -v $u) && ln -s "$p" "$B/$u"; done; printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | PATH=$B bash hooks/protect-branches.sh 2>&1 >/dev/null | grep -q 'jq not found'` (the scratch bin lacks jq; the hook must exit 0 and warn); `H=$(mktemp -d); printf '{"cwd":"/tmp","hook_event_name":"SessionStart"}' | HOME=$H CLAUDE_CONFIG_DIR=$H bash hooks/profile-check.sh | jq -e '.hookSpecificOutput.additionalContext|startswith("profile ")'`; `H=$(mktemp -d); mkdir -p $H/other; printf '# comment\nmalformed line\n/tmp/proj|%s/other\n' "$H" > $H/.claude-profiles; printf '{"cwd":"/tmp/proj/sub","hook_event_name":"SessionStart"}' | HOME=$H CLAUDE_CONFIG_DIR=$H bash hooks/profile-check.sh | jq -e '.systemMessage|test("wrong profile")'`; `H=$(mktemp -d); printf '@rules/x.md\n' > $H/CLAUDE.md; printf '{"cwd":"/tmp","hook_event_name":"SessionStart"}' | HOME=$H CLAUDE_CONFIG_DIR=$H bash hooks/profile-check.sh | jq -e '.systemMessage|test("missing import")'` (each hook exits 0); `! grep -rqnE '/(Users|home)/' hooks`; `! grep -rqniEf "$CW_SCAN_PATTERNS" hooks .claude-plugin .gitignore`; `claude plugin validate .` exits 0; `CFG=$(mktemp -d); mkdir -p "$CFG/skills"; ln -s "$PWD" "$CFG/skills/cw"; env CLAUDE_CONFIG_DIR="$CFG" claude plugin list | grep -q 'cw@skills-dir'`
- commit: feat(plugin): cw manifest, hooks.json, profile check, lean protect hooks

## Task T2
- scope: `tests/run.sh` per D2.6 (`hooks` with the fifteen cases under a scratch HOME and CLAUDE_CONFIG_DIR, asserting exit codes and JSON fields with `jq -e`; `size` with the `BASELINE_BYTES=73738` constant, per-file caps (150; 200 for design and build), the WORKFLOW cap and the description cap in full mode; `dedupe`; `scan` with the `$CW_SCAN_PATTERNS` default, `--history`, `--report`, `-p`, pathspec pass-through; `all`); `tests/dedupe-phrases.txt` (the 15 clusters of D2.2, one fixed string each); delete the six bats suites, the helper, the checklist, `scripts/`, `.claude/skills/setup/`; rewrite `.github/workflows/ci.yml` per D2.6 (jobs `ubuntu` incl. the unauthenticated `claude plugin validate .` step, and `macos`).
- files_owned: [tests/run.sh, tests/dedupe-phrases.txt, tests/check.bats, tests/hooks.bats, tests/install.bats, tests/merge-settings.bats, tests/merge-claude-md.bats, tests/e2e.bats, tests/test_helper.bash, tests/manual-setup-checklist.md, scripts/**, .claude/skills/setup/**, .github/workflows/ci.yml]
- files_forbidden: [hooks/**, skills/**, agents/**, rules/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, tests/settings-keys.txt, .gitignore, .claude-plugin/**]
- depends_on: [T1]
- agent: implementer
- model: sonnet
- risk: normal
- verification: `bash tests/run.sh hooks` exits 0 and prints 15 passes; `bash tests/run.sh size 1 --only rules; test $? -eq 1` (expected exit 1: the ratio exceeds 100%); `bash tests/run.sh size 99999999 --only rules` exits 0 (rules/orchestration.md is 47 lines; the not-yet-rewritten skills are excluded on purpose); `bash tests/run.sh dedupe; test $? -le 1` (runs; exits 0 only after T5); `P=$(mktemp); echo 'zzz-no-such-string' > $P; bash tests/run.sh scan $P` exits 0; `echo 'shellcheck' > $P; ! bash tests/run.sh scan $P`; `echo 'shellcheck' > $P; bash tests/run.sh scan $P --report` exits 0 and prints a hit; `echo 'zzz-no-such-string' > $P; bash tests/run.sh scan $P --history main..HEAD` exits 0; `D=$(mktemp -d); echo shellcheck > $D/f; echo 'shellcheck' > $P; ! bash tests/run.sh scan $P -p $D`; `bash tests/run.sh scan` exits 0 (uses `$CW_SCAN_PATTERNS`); `bash tests/run.sh all; test $? -le 1` (fails on the old skills' size caps until T5; exits 0 after T6); `wc -l < tests/dedupe-phrases.txt` = 15; `! ls tests | grep -q bats`; `test ! -f tests/test_helper.bash && test ! -d scripts && test ! -d .claude/skills`; `grep -q shellcheck .github/workflows/ci.yml && grep -q 'run.sh all' .github/workflows/ci.yml && grep -q 'macos' .github/workflows/ci.yml && grep -q 'plugin validate' .github/workflows/ci.yml`; `shellcheck -x tests/run.sh`
- commit: test: run.sh hook, size, dedupe and scan checks; retire the installer

## Task T3
- scope: `rules/workflow.md` (≤40 lines; base the LIVE `~/.claude/CLAUDE.md` workflow, research-first and context-hygiene rules plus the design-document convention of D2.5; no identity or stack lines) and `rules/orchestration.md` (≤60 lines; base LIVE; anti-ratchet kept; capitals removed; "the user" instead of a name); `rules/google-workspace.md` is not in the repo (the content moves in T5).
- files_owned: [rules/workflow.md, rules/orchestration.md]
- files_forbidden: [skills/**, agents/**, hooks/**, tests/**, README.md, WORKFLOW.md, CLAUDE.md]
- depends_on: [T2]
- agent: implementer
- model: opus
- risk: high
- verification: `wc -l < rules/workflow.md` ≤ 40; `wc -l < rules/orchestration.md` ≤ 60; `grep -q 'anti-ratchet' rules/orchestration.md && grep -q 'NO_VERDICT' rules/orchestration.md`; `grep -q 'Co-Authored-By' rules/workflow.md && grep -q 'docs/plans' rules/workflow.md && grep -qi 'context7' rules/workflow.md && grep -qi 'checkpoint' rules/workflow.md`; `! grep -rqwE 'NEVER|ALWAYS|MUST|CRITICAL' rules`; `! grep -rqi 'under 50 lines' rules`; `N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1); ! grep -rqi "$N" rules`; `test ! -f rules/google-workspace.md`; `bash tests/run.sh dedupe --only rules` exits 0; `bash tests/run.sh size 99999999 --only rules` exits 0; `bash tests/run.sh scan -- rules` exits 0
- commit: refactor(rules): one home per rule, lean workflow and orchestration files

## Task T4
- scope: Rewrite the five agents per D2.3 from the repo copies (namespaced as `cw:` in prose, verdict JSON schema in `reviewer.md`, "the user" instead of a name, no `permissionMode`, `mcpServers`, `hooks` or `skills` keys); delete `agents/Explore.md`.
- files_owned: [agents/implementer.md, agents/reviewer.md, agents/researcher.md, agents/design-reviewer.md, agents/direction-reviewer.md, agents/Explore.md]
- files_forbidden: [skills/**, hooks/**, rules/**, tests/**]
- depends_on: [T3]
- agent: implementer
- model: sonnet
- risk: normal
- verification: `ls agents | wc -l` = 5; `grep -q '^model: sonnet' agents/implementer.md && grep -q '^model: sonnet' agents/researcher.md && grep -q '^model: opus' agents/reviewer.md && grep -q '^model: opus' agents/design-reviewer.md && grep -q '^model: opus' agents/direction-reviewer.md`; `grep -q '^effort: medium' agents/researcher.md && grep -q '^effort: xhigh' agents/direction-reviewer.md && grep -q '^effort: high' agents/implementer.md && grep -q '^effort: high' agents/reviewer.md && grep -q '^effort: high' agents/design-reviewer.md`; `test $(grep -l '^maxTurns:' agents/*.md | wc -l) -eq 5 && test $(grep -l '^tools:' agents/*.md | wc -l) -eq 5`; `! grep -rqnE '^(disallowedTools|permissionMode|mcpServers|hooks|skills):' agents` (no agent keeps a `skills:` preload, D2.3); `grep -l 'memory: project' agents/*reviewer*.md | wc -l` = 3; `grep -q '"verdict"' agents/reviewer.md`; `wc -l agents/*.md | awk '$2!="total" && $1>150{exit 1}'`; `! grep -rqniE 'do not trust|be decisive|do not invent|double-check|under 50 lines' agents`; `N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1); ! grep -rqi "$N" agents`; `! grep -rqwE 'NEVER|ALWAYS|MUST|CRITICAL' agents`; `bash tests/run.sh dedupe --only agents` exits 0; `bash tests/run.sh scan -- agents` exits 0
- commit: refactor(agents): claude 5 model and effort matrix, lean prompts

## Task T5
- scope: Rewrite design, build, ship, compound and search from the repo copies per D2.2 and D2.5 (`cw:` names; design writes the single plan file and Step 6 moves it to `docs/plans/<slug>.md`, `effort: xhigh`, Explore calls with `model: haiku`, no sentinel, no promotion, no `git clean` grant; build reads `docs/plans/<slug>.md` with the folder-layout fallback, supports `continue [<task-id>]` by skipping tasks whose commit subject is already in `git log main..HEAD`, commits `docs(<slug>): design` through git, no `.gitattributes` write, no sentinel, the one-sentence delegation boundary of D2.5 (no `disallowed-tools`: the P0 probe showed it strips the implementers' tools too), a checkpoint text that asks for `/cw:build <slug> continue`, `allowed-tools` per D2.5 without write tools; ship's gate detection adds `tests/run.sh` → `bash tests/run.sh all`; search `--deep` → bundled `/deep-research`; trigger phrases kept on design and search; `disable-model-invocation: true` kept on build, ship, compound; "the user" instead of a name); `skills/google-workspace/SKILL.md` from `~/.claude/rules/google-workspace.md` minus its four personal lines, model-invocable with trigger phrases; `tests/fixtures/two-task-plan.md` per the D2.6 contract.
- files_owned: [skills/design/SKILL.md, skills/build/SKILL.md, skills/ship/SKILL.md, skills/compound/SKILL.md, skills/search/SKILL.md, skills/google-workspace/SKILL.md, tests/fixtures/two-task-plan.md]
- files_forbidden: [agents/**, hooks/**, rules/**, tests/run.sh, tests/dedupe-phrases.txt, README.md, WORKFLOW.md, CLAUDE.md]
- depends_on: [T4]
- agent: implementer
- model: opus
- risk: high
- verification: `ls skills | tr '\n' ' '` = `build compound design google-workspace search ship `; `grep -q '^effort: xhigh' skills/design/SKILL.md`; `grep -q haiku skills/design/SKILL.md`; `grep -l 'disable-model-invocation: true' skills/*/SKILL.md | wc -l` = 3; `grep -q 'cw:implementer' skills/build/SKILL.md && grep -q 'cw:reviewer' skills/build/SKILL.md`; `grep -q 'docs/plans/<slug>.md' skills/build/SKILL.md && grep -q -- '-tasks.md' skills/build/SKILL.md && grep -q 'continue' skills/build/SKILL.md && grep -q 'main..HEAD' skills/build/SKILL.md`; `grep -q 'docs/plans/<slug>.md' skills/design/SKILL.md`; `! grep -q '^disallowed-tools:' skills/build/SKILL.md && grep -q 'Bash(bash' skills/build/SKILL.md && ! awk '/^allowed-tools:/{f=1;next} f&&(/^[a-z-]+:/||/^---$/){f=0} f' skills/build/SKILL.md | grep -qE '^ *- *(Write|Edit|MultiEdit|NotebookEdit) *$'` (only the `allowed-tools` block is inspected; portable ERE); `grep -q 'tests/run.sh all' skills/ship/SKILL.md && grep -q 'Bash(bash' skills/ship/SKILL.md`; `grep -q 'deep-research' skills/search/SKILL.md`; `! grep -rqniE '~/.claude/plans|claude-design-active|claude-orchestrator-active|design-scope-guard|delegate-guard|gitattributes|linguist|git clean' skills`; `N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1); ! grep -rqi "$N" skills`; `! grep -rqwE 'NEVER|ALWAYS|MUST|CRITICAL' skills`; `! grep -rqi 'under 50 lines' skills`; `wc -l skills/search/SKILL.md skills/compound/SKILL.md skills/google-workspace/SKILL.md | awk '$2!="total" && $1>150{exit 1}'`; `wc -l skills/design/SKILL.md skills/build/SKILL.md | awk '$2!="total" && $1>200{exit 1}'`; `bash tests/run.sh size --only skills,agents,rules` exits 0 (ratio reported, target ≤60%); `bash tests/run.sh dedupe` exits 0; `grep -c '^## Task' tests/fixtures/two-task-plan.md` = 2 && grep -q 'test -f a.txt' tests/fixtures/two-task-plan.md && grep -q 'feat: add b' tests/fixtures/two-task-plan.md`; `bash tests/run.sh scan -- skills tests/fixtures` exits 0
- commit: refactor(skills): lean cw skills, single design document, google-workspace playbook

## Task T6
- scope: Rewrite README.md (incl. the changelog section with the `1.0.0` entry) and WORKFLOW.md per D2.7; replace the template `CLAUDE.md` by the project file of D2.1 (≤20 lines incl. `Tests: bash tests/run.sh all`); `settings.example.json` per D2.7; `tests/settings-keys.txt` from the settings reference (§R2.13) plus every key the example uses.
- files_owned: [README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, tests/settings-keys.txt]
- files_forbidden: [skills/**, agents/**, hooks/**, rules/**, tests/run.sh, tests/dedupe-phrases.txt, tests/fixtures/**, .claude-plugin/**]
- depends_on: [T5]
- agent: implementer
- model: sonnet
- risk: normal
- verification: `grep -q skills/cw README.md && grep -q 'marketplace add' README.md && grep -q -- '--plugin-dir' README.md && grep -q .claude-profiles README.md && grep -q plansDirectory README.md && grep -q jq README.md && grep -q 'plugin disable' README.md && grep -q acceptEdits README.md && grep -qi migration README.md`; `! grep -q '<you>' README.md`; `! grep -qE 'install.sh|merge-settings|/setup' README.md WORKFLOW.md`; `wc -l < WORKFLOW.md` ≤ 200; `grep -q 'tests/run.sh all' CLAUDE.md && grep -q 'docs/plans' CLAUDE.md && grep -q 'Co-Authored-By' CLAUDE.md && test $(wc -l < CLAUDE.md) -le 20`; `jq -e '.model=="fable" and .plansDirectory=="docs/plans" and (has("hooks")|not) and (.permissions.deny|length)>=6 and ([keys[]|select(startswith("_"))]|length)==0' settings.example.json`; `comm -23 <(jq -r 'keys[]' settings.example.json | sort) <(sort tests/settings-keys.txt)` empty; `grep -qx model tests/settings-keys.txt && grep -qx plansDirectory tests/settings-keys.txt && grep -qx forceLoginOrgUUID tests/settings-keys.txt`; `grep -q '1.0.0' README.md`; `bash tests/run.sh all` exits 0; `bash tests/run.sh scan -- README.md WORKFLOW.md CLAUDE.md settings.example.json tests/settings-keys.txt` exits 0
- commit: docs: plugin install story, project CLAUDE.md and lean example settings

## Task T7
- scope: Release gate per D2.8, verification only (no file changes; `plugin.json` and the README changelog already carry 1.0.0): `git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*'`; `bash tests/run.sh scan` (tree) and `bash tests/run.sh scan --history main..HEAD` must be clean; `bash tests/run.sh scan --history --all --report` hits listed in the exit report (history not rewritten); `claude plugin validate .`; `shellcheck -x hooks/*.sh tests/run.sh`; `bash tests/run.sh all`; the temp-config-dir inventory check of D6.2; the exit report lists every command's output.
- files_owned: []
- files_forbidden: [everything]
- depends_on: [T6]
- agent: implementer
- model: sonnet
- risk: normal
- verification: D6.1, D6.2, D6.3, D6.4, D6.5 and D6.8 in full; `bash tests/run.sh scan --history main..HEAD` exits 0; `git status --short | wc -l` = 0
- commit: none

## Gate G-load (human)
Criterion D6.6 (a) with `claude --plugin-dir <checkout>` from a scratch git repo under `/tmp`
(copy `tests/fixtures/two-task-plan.md` there as `docs/plans/two-task.md` for the dry
`/cw:build two-task`), then (b) from a temp config dir holding only `skills/cw -> <checkout>`
(one-time login).
Fix-ups: fresh `fix(<scope>):` commits, one per file group. Then the live `/ship`: its gate
comes from the project CLAUDE.md (`bash tests/run.sh all`); its Step 1 flags the staged
`hooks/protect-secrets.sh` as a `*secret*` match — expected, wave it through; accept or decline
the `risk: high` panel; CI green; merge on GitHub; `git switch main && git pull`; the
post-merge install check of D6.7. Plan A starts in a session at the private profile.
