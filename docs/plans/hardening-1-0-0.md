# hardening-1-0-0 — guard-hook hardening and install-doc fixes before PR #3 merges

Slug `hardening-1-0-0`. Branch `feat/cw-plugin` (14 commits over `main`, pushed, PR #3
open, CI green). Each fix is a fresh commit on that branch; PR #3 updates in place. No
version change: 1.0.0 is unreleased.

## Context

A four-reviewer merge-readiness panel on PR #3 (2026-09-21) found, and the orchestrator
reproduced, that the plugin's branch guard does not deliver what its design and README
promise, and that the README's marketplace install route cannot be followed as written.
The maintainer held the merge on 2026-09-21 and chose, at the Step 0 gate on 2026-09-22: harden
the six reproduced cases and state the guard's scope honestly; allow lease-style force
pushes to non-main destinations (the design as written); carry the trivial one-liners
the panel raised; leave the review-cap wording in `rules/orchestration.md` to
`/cw:compound`.

Reproduced on head `fafca6f` (script: the session scratchpad's `repro-hooks.sh`; every
payload is a JSON file piped into the hook, and the hook's exit code is what counts):

| # | Payload command (cwd `/tmp` unless stated) | Today | Promised |
|---|---|---|---|
| F1 | `sh -c "git push origin main"`, `bash -c '…'`, `eval "…"` | 0 | 2 |
| F2 | `git switch main && git merge feat/x && git push` (cwd on feat/x) | 0 | 2 |
| F2 | `cd <repo on main> && git push` (cwd on a feature repo) | 0 | 2 |
| F3 | `git push --all origin`, `git push --mirror origin`, `git push origin --all` (cwd feat/x, local main exists) | 0 | 2 |
| F4 | `echo <40 000 chars> && git push origin main` | 2 in 7.5 s; >~50k chars times out | 2, fast |
| F5 | `git push --force-with-lease origin feat/x`, `--force-if-includes` | 2 | 0 |
| F6 | `\git push origin main` | 0 | 2 |

The hooks reference states that a timed-out PreToolUse command hook does not block the
tool call (Research §2), so F4 is a fail-open, and every long Bash call pays the
tokenizer's cost today. Minor items reproduced alongside: malformed hook input prints
raw jq errors twice; the harness never reaches the branch-resolution code; the secrets
hook misses `.p12`, `.netrc`, `id_dsa`, `id_ecdsa` and Terraform state next to covered
siblings; `profile-check.sh` prints an empty line instead of `{}` when its final `jq`
fails, and a CRLF `.claude-profiles` file yields a false "wrong profile" notice;
`hooks/hooks.json`'s SessionStart matcher omits `compact`, a documented source. README
route (b): `~/.claude/plugins/cache/claude-code-setup/cw/` lacks the `<version>/`
segment the CLI actually creates, and `claude plugin details` prints no path (both
confirmed on a throwaway install with CLI 2.1.278); `claude plugin list --json` does
carry an `installPath` field (confirmed on the live profile). `WORKFLOW.md` omits
`trailers` from the standalone subcommand list; `rules/workflow.md:18` names a
`## Tasks` section that no plan has; `agents/implementer.md`'s Output section never
mentions the JSON exit report `/cw:build`'s gate parses; CI's `claude plugin validate .`
checks only the marketplace manifest; the linguist attribute is undocumented.

Intended outcome: the guard blocks every reproduced form and the plausible variants
next to them, stays under a second on 100k-character commands, allows lease pushes to
feature branches, and its scope is written down in the design and README; the harness
proves each behaviour; the README install route works as printed; CI green; PR #3
ready to merge.

## Approach

**Rewrite the guard's front end, keep its decision logic.** `protect-branches.sh`
keeps its structure (jq check, segment split, per-segment scan, destination rules,
exit 2 with a one-line reason) and changes five things:

1. **Fast path.** A command whose text contains no `push` substring exits 0 before any
   parsing. That alone removes the latency from nearly every long call (heredocs
   writing files rarely contain the word), and it is a pure pattern match, linear in C.
2. **Linear normalisation instead of a per-character loop.** The whole command is
   normalised once, in four processes total: `awk` joins backslash-newline
   continuations (the existing bash join loop is quadratic as well: 2.0 s under bash 5
   and 5.9 s under bash 3.2 for a 2 000-line, 112k-character command, measured; the
   awk one-liner takes 0.03 s), `tr -d` removes every `"`, `'` and `\`
   character, `tr` flattens tabs to spaces, and the existing `sed` split cuts the
   result into segments on `&&`, `||`, `;`, `|`, `(`, `)`, backticks and newlines
   (macOS `sed` emits a real newline for `\n` in the replacement: verified on this
   machine and by the macOS CI job, see Risks). The `push` fast path runs on the
   normalised text, so a quote-split spelling of the word is still seen. Segments are
   then read with a builtin `while read -r` loop and each is split into words with
   `set -f` array assignment (`TOK=( $seg )`, globbing off), a builtin with no process
   and no temp file per segment. Everything is linear in C or builtin code, and it
   exists in bash 3.2. Per-segment `tr` or here-string calls were
   rejected: a 100k-character heredoc writing code has thousands of lines, and one
   spawn per line is seconds again (Research §3 on `<<<` cost). Quote removal is what
   makes nested shells visible at every depth in one pass: `sh -c "git push origin
   main"` becomes the tokens `sh -c git push origin main`, and the existing scanner,
   which looks for a `git` token anywhere in the segment, then sees `git` followed by
   `push`; the depth-3 nesting that prior-art guards missed (Research §3) is flat
   here. Backslash removal is what fixes `\git` (F6).
   Trade-off, stated in the scope paragraph: a quoted prose fragment that spells a push
   to main inside a command (`echo "git push origin main"`, a heredoc line, a
   `--body "…"`) is blocked as if it were the command. Heredoc lines are blocked
   today already; the remedy is the same as before (keep such text in a file). The
   first-subcommand rule stays, so `git commit -m "… push to main …"` remains allowed.
   Research §3 recommends an index-based state machine with recursive
   interpreter-body extraction instead; this plan takes quote removal because it is
   linear by construction, flattens every nesting depth, and is a fraction of the code
   for a bash-3.2 script, at the cost of the prose over-block accepted at Step 0.
3. **Chained state changes (F2) are tracked, not ignored, and the last change wins.**
   Segments are processed in order. A `cd`/`pushd` segment records the target
   directory (absolute as given, relative joined to the hook's `cwd`) and clears any
   recorded branch, because the branch belongs to the old directory; `-`, no
   argument, `popd`, or a target containing `$` records the directory as unknown. A
   `git switch`/`git checkout` segment records a branch by one rule: `-b`, `-B`, `-c`
   or `-C` name the branch in the next token; `--`, `-p`, `--patch`, `HEAD`, `-`, or a
   token containing `$` make the branch unknown (a path checkout or a detached state
   cannot be resolved from text); any other `-` option is skipped; the first remaining
   token is the branch; nothing left is unknown. When a later segment is a
   refspec-less push: a recorded branch is used directly (`main`/`master` blocks);
   otherwise the branch is resolved with `git -C` at the `-C` dir, else the recorded
   directory, else `cwd`; an unknown branch or directory blocks with the reason
   "cannot determine the destination after a cd or branch change; use an explicit
   refspec such as git push origin <branch>". So `git checkout -b feat/x && git push
   -u origin HEAD` stays allowed, `git switch main && … && git push` blocks,
   `cd <literal path on main> && git push` blocks by resolution, and
   `git checkout -b feat/y && cd <path on main> && git push` blocks because the `cd`
   cleared the branch (Research §4: fail closed on state the text cannot resolve).
4. **Upstream check for the fully bare form, gated on `push.default`.** `git push` and
   `git push <remote>` (no ref, no `HEAD`) also resolve `@{u}`, but only when the
   repository's `push.default` is `upstream` or `tracking`: there a bare push lands on
   the upstream, so an upstream ending in `/main` or `/master` blocks. Under the
   default `simple` git refuses a mismatched upstream itself, and under `current` the
   push goes to the same-named remote branch, so the guard does not block there (the
   direction pass caught that an ungated check would wrongly block a `current` user
   whose feature branch tracks `origin/main`). Unsourced — judgment call, resting on
   git-config(1)'s `push.default` entry.
5. **Option semantics per the design.** `--all` and `--mirror` block ("pushes every
   branch, including main/master"). `--force`, `-f` in any short cluster, and `+ref`
   block everywhere. `--force-with-lease`, `--force-with-lease=<ref>` and
   `--force-if-includes` are ordinary options: the destination rules still apply, so a
   lease push to main blocks and one to `feat/x` passes (the maintainer's Step 0
   decision; Research §5). Malformed input: jq errors are silenced and an empty command exits 0.

**Prove it in the harness, not in prose.** Every behaviour above becomes a numbered
case in `tests/run.sh hooks`, including real-repository resolution cases (scratch
repos created with `git init -b`), a 100k-character timing case measured with bash's
`SECONDS`, regression cases for behaviours that must not change (`feat/main-nav`,
commit messages mentioning main, `git -C <dir> push`), and the secrets and profile
fixes. The harness gains `CW_HOOKS_DIR` (default `$ROOT/hooks`) so a candidate hook
directory can be tested before it is installed. That matters in this build: the
plugin loads from this checkout, so the file at `hooks/protect-branches.sh` is the live
guard of the session that edits it, and a syntax error there blocks every Bash call.

**Say what the guard is.** The design's hook paragraph and a README paragraph state
the scope: a guardrail against the agent's own accidental pushes, reading command
text, not a sandbox against a determined operator (who can disable the plugin). Named
out of scope: commands assembled from variables or `eval "$X"`, `xargs`-fed refspecs,
wrappers not named `git` (aliases, `git-push`, `gh api`), `git -c key="quoted value"`
before `push`, and prose that spells a push to main (blocked as text). Research §6
gives the practitioner grounding for stating this plainly.

**Fix the install docs from observed CLI output.** Route (b) names the real cache
layout with the version segment and replaces the `details` claim with
`claude plugin list --json` filtered on `installPath`, which exists in 2.1.278. The
other doc items are one-liners.

**Dropped or deferred.** `rules/orchestration.md:45` review-cap wording:
`/cw:compound` after the PR (the maintainer's choice). Blocking `xargs … git push` and
non-git pushers: out of scope, stated (no reviewed guard covers `xargs`, `find -exec`
or `ssh` bodies either, Research §3). A permission deny rule as a second layer: the
permissions doc states a `Bash(git push *)` rule does not match `git -C . push`, a
quoted `'push'`, or a command inside `sh -c`, and a plugin manifest has no
permissions field (Research §2), so no second layer is available to ship. Returning
`permissionDecision: "ask"` for the unknown-state case instead of blocking: the JSON
form exists (Research §2), but its behaviour under `-p` with permissions skipped is
undocumented and the harness asserts exit codes; kept as exit 2 with an actionable
reason, the fail-closed choice every reviewed guard converged on (Research §3).

## Files to create/modify

| Path | Change |
|---|---|
| `hooks/protect-branches.sh` | Front end rewritten per Approach 1–5; decision messages and exit codes unchanged in shape. Header comment rewritten to describe the new normalisation and the stated scope. Bash 3.2, jq only, shellcheck 0.9.0 and 0.11.0 clean. |
| `hooks/protect-secrets.sh` | Pattern block gains `*.p12`, `*.netrc`, `*id_dsa*`, `*id_ecdsa*`, `*.tfstate`, `*.tfstate.backup`. Nothing else. |
| `hooks/profile-check.sh` | `NEW=$(jq -nc …) && OUT="$NEW"` in both branches so a failing jq leaves `{}`; `.claude-profiles` lines lose a trailing `\r` before parsing. |
| `hooks/hooks.json` | SessionStart matcher `startup\|resume\|clear\|compact\|fork`. |
| `tests/run.sh` | `HOOKS_DIR="${CW_HOOKS_DIR:-$ROOT/hooks}"` used by every hook case; new cases per T1's table; scratch repos for resolution cases; the timing case. |
| `docs/plans/cw-plugin/cw-plugin-design-draft.md` | D2.4 hook paragraph (lines 218–225) rewritten to the new behaviour and scope; line 230 matcher gains `compact`; D6.3 hook-case count updated to T1's total. |
| `README.md` | Route (b) cache path with `<version>/`; the import step uses `claude plugin list --json`; a "What the branch guard does" paragraph under Kill switch; one line on `.gitattributes`. |
| `WORKFLOW.md` | Line 129: standalone list gains `trailers`. |
| `rules/workflow.md` | Line 18: "reads the `## Task <id>` blocks of that file". |
| `agents/implementer.md` | Output section gains item 5: end with the fenced JSON exit report when the orchestrator's prompt specifies one. |
| `skills/ship/SKILL.md` | Step 5 item 2 gains one sentence: write the PR body to a scratch file and pass `--body-file`, so the guard never parses the body as a command. |
| `.github/workflows/ci.yml` | Validate step also runs `claude plugin validate .claude-plugin/plugin.json`. |
| `docs/plans/hardening-1-0-0.md` | This plan; `/cw:build` commits it as `docs(hardening-1-0-0): design`. |

Untouched on purpose: `rules/orchestration.md` (deferred); `.claude-plugin/*.json`
(no version change; the marketplace description warning is a known nit); every skill
except the one instruction line in `skills/ship/SKILL.md`; `.gitattributes` itself
(documented, not changed).

## Dependencies

None new. git ≥ 2.28 in the harness for `git init -b` (macOS system git and
ubuntu-latest both qualify); jq, as today.

## Risks & mitigations

- **The edited hook is live in the editing session.** The plugin loads from this
  checkout, so `hooks/protect-branches.sh` guards the very session that edits it. A
  syntax error exits 2 (bash's own status) and blocks every Bash call. Mitigation: T1
  develops in a scratch copy and tests it with `CW_HOOKS_DIR=<scratch> bash
  tests/run.sh hooks`, installing into `hooks/` only when green; the Edit tool still
  works if the live file breaks (a different hook guards it), so recovery is an edit,
  not a restart. The orchestrator's task prompt must carry this.
- **Payload strings trip the live guard and the auto-mode classifier.** A Bash command
  line containing a push-to-main string is blocked by the live hook, and an agent brief
  that spells such tests out was denied once as "Create Unsafe Agents". Mitigation:
  payloads live in `tests/run.sh` and in this plan; task prompts reference the task
  block by file and id instead of repeating payloads; implementers test through
  `bash tests/run.sh hooks` and payload files, never inline strings.
- **Over-blocking after quote stripping.** Prose containing a push-to-main line inside
  a command is now blocked even when quoted (`echo "…"`, `gh pr create --body "…"`).
  Heredoc lines were blocked before this change. Mitigation: the block message names
  the remedy (put the text in a file), the README scope paragraph says so, and a
  harness case keeps commit messages mentioning main allowed.
- **Over-blocking on unknown state.** `cd "$DIR" && git push` blocks with advice
  because `$DIR` cannot be resolved. The message names the fix (explicit refspec); the
  common agent pattern `git checkout -b x && git push -u origin HEAD` stays allowed by
  branch tracking.
- **Timing case flakiness in CI.** A 100k-character command must finish within 1 s by
  `SECONDS` (integer seconds; a boundary crossing can read 1). Linear code runs in well
  under 200 ms locally; the assertion is `-le 1`, and the case also asserts exit 2 so a
  fast fail-open cannot pass.
- **Shellcheck version drift.** T1's verification runs the local 0.11.0 and, when
  present at `~/.claude/plans/cw-plugin-gates/shellcheck-0.9.0`, CI's apt version
  0.9.0; the build's Phase 0 note says how to put it there. The SC2317/SC2329 pair is
  the known difference (Research §2). CI remains the authoritative 0.9.0 run.
- **BSD `sed` and `\n` in a replacement (unverified risk).** Reviewers cited BSD
  `sed` builds, and the macOS man page (which documents a backslash-newline rather
  than `\n` for a newline in a replacement), under which the split would emit a
  literal `n`, collapse every command into one segment and defeat the state tracking.
  On this machine (Darwin 25) `sed` emits a real newline for `\n`, checked with `od`.
  The existing macOS CI case does not exercise the split (it blocks by finding a `git`
  token anywhere in the segment), so the new state cases are the first real evidence,
  at CI time; a failure there is a red macOS job, never a silent regression, and the
  remedy is a `tr` split mapping each separator character to a newline (one process,
  no escape interpretation involved).
- **The plan file is committed under `docs/`.** CI's LICENSE-name gate greps `docs`,
  so this plan names no person; the build's Phase 0 note re-checks that before the
  design commit.
- **Design draft amendment scope.** Only D2.4's hook paragraph, the SessionStart
  matcher and D6.3's count change; the rest of the released design stays as written.
- **A rule wording edit rides in a feature PR.** `rules/workflow.md:18` and
  `agents/implementer.md` are shipped product on the release branch, same as the
  previous round's `fix(rules)`; accepted, logged here.

## Success criteria

All from the repo root; each exits 0. Push-to-main strings are never typed into a
Bash command line; the harness and the scratchpad script hold them.

1. Guard behaviour: `bash tests/run.sh hooks` and `/bin/bash tests/run.sh hooks` both
   end with `0 failed` and at least 58 passed (73 when the scratch repos can be
   created; the exact total is not pinned anywhere, so adding coverage later breaks
   nothing).
   The reproduction script (copied by the build's Phase 0 to
   `~/.claude/plans/cw-plugin-gates/repro-hooks.sh`) prints, row by row: rc=2 for the
   push-to-main control, the three F1 rows, the backslash row, the env-prefixed
   control, the three blocking F2 rows (bare push with cwd on main, switch-then-push,
   cd-then-push), the three F3 rows and both F4 rows, 14 in all; rc=0 for the
   feature-branch control, the F2 bare-push-on-feature control and both F5 rows, 4 in
   all; and the 40k-character F4 row reports under 1 s.
2. Gates: `bash tests/run.sh all` (summary all PASS incl. `trailers`), `shellcheck -x
   hooks/*.sh tests/run.sh` on 0.11.0 and, when the binary is present, on 0.9.0 (CI's
   apt version runs it regardless), `claude plugin validate .` and `claude plugin
   validate .claude-plugin/plugin.json` exit 0, `jq empty hooks/hooks.json`, `jq -e
   '.hooks.SessionStart[0].matcher=="startup|resume|clear|compact|fork"'
   hooks/hooks.json`.
3. Docs: `grep -q 'cw/<version>/' README.md && grep -q 'installPath' README.md && !
   grep -q 'print the current cache path' README.md && grep -qi 'not a sandbox'
   README.md && grep -q 'linguist' README.md && grep -q 'trailers' WORKFLOW.md && grep
   -q '## Task <id>' rules/workflow.md && grep -qi 'exit report' agents/implementer.md
   && grep -q 'compact' docs/plans/cw-plugin/cw-plugin-design-draft.md`.
4. Hygiene: the CI greps (`! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills
   agents rules`, banned phrases, LICENSE name), `! grep -rn '</content>' hooks tests
   README.md WORKFLOW.md rules agents`, size and dedupe PASS (README and hooks are
   outside dedupe and size scope; `agents/implementer.md` stays ≤ 150 lines).
5. Series: each task's `commit:` subject appears exactly once in `git log --format=%s
   main..HEAD`; `bash tests/run.sh trailers` OK on the whole series; CI green on the
   pushed head for both the push and pull-request runs.

## Research

### Codebase (Explore, haiku, 2026-09-22) and orchestrator reads

- Harness: `tests/run.sh` `report` (30–40) counts `HPASS`/`HFAIL`; `check_code` (46–53)
  compares exit codes; `hooks_push_cases` (55–78) pipes JSON via `printf '%s' '{…}' |
  HOME="$SCRATCH/base" "$BASH_BIN" "$ROOT/hooks/protect-branches.sh"`; four push cases,
  four secrets cases (Write and NotebookEdit only), one jq-absent case with a
  PATH-restricted bin, six profile cases; `cmd_hooks` (213–230) creates `SCRATCH`,
  prints `hooks: %d passed, %d failed`. No case creates a git repository today, so
  `protect-branches.sh:147` (`git -C … rev-parse`) is never reached.
- Size gate scope is `skills/**/SKILL.md`, `agents/*.md`, `rules/*.md` (files_in_scope
  238–268); hooks and tests carry no cap; `WORKFLOW.md` ≤ 200 lines; agents/rules ≤ 150.
  Dedupe scans the same three sets against `tests/dedupe-phrases.txt` (phrases include
  `push directly to main`, `one atomic commit per task`, `never commits`); README is
  outside both gates. D6.4 forbids `gitattributes|linguist` in `skills/` only.
- Design D2.4 (218–231) promises: split on `&&`, `||`, `;`, `|`, newlines; block any
  segment that is a `git push` to main/master by explicit refspec or by current branch;
  block `--force`/`-f`; everything else exits 0; SessionStart matcher
  `startup|resume|clear|fork`. D6.3 asserts "15 hook cases".
- `protect-secrets.sh` patterns (34–43): `*.env|*.env.*|*.envrc|*credentials*|*secret*|
  *config.swift|*.pem|*.key|*.p8|*.pfx|*.jks|*.keystore|*id_rsa*|*id_ed25519*|
  *.gnupg/*|*service-account*.json|*gcp*key*.json`; directory checks precede the
  template allowlist.
- `protect-branches.sh` today: per-character `tokenize()` (31–63) with one layer of
  quote stripping; scanner (65–94) finds the first `git` token, skips `-C <dir>` and
  other global options, breaks on the first subcommand; option loop (99–120) blocks
  `--force`, `--force-if-includes`, `--force-with-lease*`, `-f` clusters, `+ref`;
  destination loop (123–140); refspec-less resolution (146–151) via `git -C
  "${GITDIR:-${CWD:-.}}" rev-parse --abbrev-ref HEAD`; segment split (175) on `&&`,
  `||`, `;`, `|`, `(`, `)`.
- CLI 2.1.278: `claude plugin list --json` entries carry `enabled, id, installPath,
  installedAt, lastUpdated, scope, version`; `installPath` for a marketplace install of
  another plugin reads `<config>/plugins/cache/<marketplace>/<plugin>/<version>`;
  `claude plugin validate --help`: `<path>` is "a plugin or marketplace manifest, or the
  skills, agents, and commands in a directory", with `--strict` and `--json`.
- README: route (b) at 47–56, the (b) import bullet at 129–132, kill switch at
  177–187, tests at 234–246; no mention of `.gitattributes`. `WORKFLOW.md` 128–129
  lists `hooks, size, dedupe, scan`.
- The continuation-join loop in `protect-branches.sh` (158–171) is quadratic as well:
  measured 2.0 s under bash 5 and 5.9 s under `/bin/bash` 3.2 for a 2 000-line,
  112k-character input, against 0.03 s for the awk one-liner T1 specifies, which also
  joins a backslash-newline continuation correctly (checked with `sed -n l`). `.gitattributes` is one line, `docs/plans/** linguist-generated=true`.
  `.gitignore` tracks `docs/plans/*.md`, so the new plan file is not ignored.

### Docs and API currency (cw:researcher, sonnet, 2026-09-22; context7 down, WebFetch on code.claude.com/docs/en/*.md; CLI 2.1.278)

1. PreToolUse stdin for Bash (hooks.md example payload): `session_id`, `prompt_id`,
   `transcript_path`, `cwd`, `scratchpad_dir`, `permission_mode`, `hook_event_name`,
   `tool_name`, `tool_input{command, description, timeout, run_in_background}`,
   `tool_use_id`. No branch or worktree field exists. `cwd` "changes when Claude
   executes a `cd` command"; whether it reflects a `cd` from an earlier separate Bash
   call is not spelled out (medium confidence).
2. Output: "Exit 2 means a blocking error … exit 2 blocks whether or not you print
   JSON: even a JSON `permissionDecision` of `"allow"` can't override it"; other
   non-zero codes do not block and show a hook-error notice. JSON on exit 0 can
   `allow`/`deny`/`ask` (permissions.md: "The hook output can deny the tool call,
   force a prompt, or skip the prompt"). "A blocking hook also takes precedence over
   allow rules." Whether exit-2 stderr reaches the model's context is not stated
   (the docs say the blocking message is the stderr text; observed in this repo's
   validation rounds: the model sees it).
3. Timeouts: default 600 s for command hooks; this plugin sets 10 s in `hooks.json`.
   "A timed-out `command`, `http`, or `mcp_tool` hook doesn't block the tool call.
   The call continues through the normal permission flow, so don't count on a
   stalled hook to act as a gate." No documented minimum.
4. SessionStart matcher values: `startup`, `resume`, `clear`, `compact`, `fork`;
   syntax `"matcher": "startup|resume"` or omitted for all.
5. Permissions (permissions.md): "`Bash(git push *)` | Stops `git push origin main`
   | Doesn't stop `git -C . push origin main`, `git -c push.default=current push
   origin main`, `git 'push' origin main`"; "A deny rule doesn't match the same
   program by path or inside `sh -c`"; Claude Code splits compound commands on
   `&&`, `||`, `;`, `|`, `|&`, `&`, newlines for rule evaluation; "Hook decisions
   don't bypass permission rules … A hook that exits with code 2 stops the tool call
   before permission rules are evaluated." Plugin manifest schema has no
   `permissions` key; a plugin `settings.json` supports only `agent` and
   `subagentStatusLine`. So a plugin cannot ship permission rules.
6. Install layout (plugins-reference.md): cache under `~/.claude/plugins/cache`;
   "each installed version is a separate directory in the cache, grouped by
   marketplace and plugin and named for the resolved version"; on update the old
   version directory is orphaned and swept about 14 days later. The researcher
   reported the CLI reference as describing a path field on `details --json`; the
   design reviewer could not find `installPath` or a `details --json` form on
   plugins-reference.md, so the field is recorded here as a 2.1.278 observation only:
   `claude plugin list --json` entries carry `installPath` (seen on the maintainer's
   profile), which is what T2's README wording relies on. `${CLAUDE_PLUGIN_ROOT}` is substituted only in skill and
   agent content, hook commands and MCP/LSP configs, not in a user's `CLAUDE.md`.
7. `claude plugin validate`: "A plugin with a manifest: `claude plugin validate
   ./my-plugin`"; behaviour with both manifests in one directory is undocumented
   (observed: the marketplace manifest wins); `--help` accepts a manifest file path.
8. Shellcheck: SC2317 false-positives on trap-invoked functions are a known open
   class (issues #2542, #2660); SC2329 was found as introduced in 0.11.0 (medium
   confidence; conflicts with the "0.10+" wording in `hooks/profile-check.sh:14`). The
   directive pair `disable=SC2317,SC2329` is the working suppression.
9. Changelog since 2.1.269 relevant here: 2.1.271 fixed `cd`+`git`/subshell chains
   skipping a read-guard prompt in bypass/auto mode and wildcard-expansion targets
   being skipped in permission checks; 2.1.274 fixed Bash permission checks for
   special shell variables; 2.1.275 npm-sourced plugins install with
   `--ignore-scripts`; 2.1.277 fixed reinstall corrupting an in-use plugin copy.

### Best practices and prior art (cw:researcher, sonnet, 2026-09-22)

1. Prior art: `Yodaisgaming/claude-code-command-guard` splits on `&&`, `||`, `;`, `|`,
   newlines and "re-scans interpreter bodies" (`bash -c`, `sh -c`, `python -c`, `node
   -e`, `$(…)`, backticks), fail-closed on unparseable input, and documents that it
   does not re-scan `xargs`, `find -exec` or `ssh`. `ArjenSchwarz/agentic-coding`
   `no-push-main.py` blocks `feature:main`, `+main`, `HEAD:refs/heads/main`,
   `--mirror`, `--all`, `--delete origin main`, `origin :main`, resolves the current
   branch with `git rev-parse` for refspec-less pushes, and does not handle `cd`/`git
   -C` chains. `PrimeIntellect-ai/prime-agent` PR #2395 went through four review
   rounds: continuation joining, case-insensitive `GIT`/`SH`, `f=-f; git push $f`,
   nesting at depth 3+ via `eval`/`sh -c`/`env -S`, `CDPATH`, a ReDoS regex replaced
   by linear string logic; end state "refuse on any unresolvable argument". Simple
   guards (Trail of Bits config, aihero.dev) are one regex such as
   `git[[:space:]]+push.*(main|master)`.
2. Tokenising in bash 3.2: `read -ra` does not honour quotes (SC2206, Greg's wiki);
   `xargs` honours quotes but errors on unbalanced ones and differs BSD/GNU; `eval
   set --` executes the untrusted text (rejected); gawk `FPAT` is non-portable; a
   here-string costs a temp file per call (`read -ra <<<` ≈ 0.098 s vs IFS array
   assignment ≈ 0.011 s in one micro-benchmark). The researcher recommends an
   index-based single-pass state machine; this plan's choice (strip quotes once,
   split once, builtin array assignment per segment) is the linear variant that also
   flattens nesting, see Approach 2.
3. Nested shells: consensus is extract-and-recurse with a bounded depth and refuse
   beyond it; `xargs`/`find -exec`/`ssh` bodies are a gap in every reviewed guard;
   no over-blocking complaints were found that stem from nested-shell re-scanning
   itself, they cluster on cwd/branch resolution and blanket pattern catalogues.
4. Chained state: `pmgledhill102/agentic-coding-config` issue #404 documents `cd
   /other/clone && git push -u origin <branch>` defeating cwd resolution, and that a
   deny "rejects the whole Bash call" (a heredoc in the same call is lost too); its
   PR #518 "walks the command's segments in order, following `cd` and `git -C` …
   and skips when a path cannot be resolved statically (variables, globs, quoted
   paths)". `git -C` overrides a preceding `cd` for that invocation. Fail-closed on
   unresolvable state is the convergent principle (dcg, Yodaisgaming, prime-agent).
5. Force semantics: general git practice prefers `--force-with-lease` plus
   `--force-if-includes` over `--force`; agent guards allow lease variants only to
   non-default branches and block them to `main`/`master` like plain force
   (ArjenSchwarz, Dicklesworthstone). `--all`, `--mirror`, `--delete` and `:main`
   are blocked unconditionally in both; `--prune` appears in no push guard.
6. Scope statements: Trail of Bits calls its hooks "guardrails, not walls … not a
   security boundary"; Yodaisgaming targets "honest mistakes … a loud stop, not
   silent cleverness"; agentkit.best: "a useful guardrail, but it is not an
   operating-system sandbox". The one concrete over-blocking cost with evidence is
   issue #404's whole-call rejection; claims that users disable over-blocking guards
   were found only as unsourced aggregates (low confidence).
7. Performance: no third-party benchmark of tokenisers at 10k–100k characters; the
   mechanism behind quadratic bash loops is per-iteration string re-slicing or
   appending (codearcana.com profiling); no dataset of real Claude Code command
   lengths exists (the 40k-character figure is this repo's own measurement).

# Tasks

Five commits plus one verification-only task. T2, T3 and T4 own disjoint files and are
independent of each other and of T1; T1 is the hook rewrite (its own commit); T5 the
design-draft amendment; T6 the release gate. Run order: T1, T2, T3, T4 together; T5
after T1 (its D6.3 count depends on T1's final case total); T6 last.

Note to the `/cw:build` orchestrator, Phase 0: invoke as `/cw:build hardening-1-0-0
continue` with `feat/cw-plugin` checked out; never branch from `main`. Before the design
commit, run `N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1); ! grep
-qi "$N" docs/plans/hardening-1-0-0.md` (CI's name gate covers `docs`). The design commit
`docs(hardening-1-0-0): design` ends with exactly one trailer line per
`rules/workflow.md` and no session line; check it right after committing. Then stage the
two out-of-repo aids the gates use, into `~/.claude/plans/cw-plugin-gates/` (private,
already holds the release-gate scripts): `repro-hooks.sh` and `shellcheck-0.9.0`, copied
from the design session's scratchpad (the session-specific temp directory of this
project; the path is not spelled out here because the project directory name would
trip the name gate): `repro-hooks.sh` and `sc090/shellcheck-v0.9.0/shellcheck`. If that
directory is gone,
the binary comes from
`https://github.com/koalaman/shellcheck/releases/download/v0.9.0/shellcheck-v0.9.0.darwin.x86_64.tar.xz`
(resume an interrupted download with `curl -C -`), and the script's 18 rows are the
F1–F6 payloads in the Context table plus five controls (push to main, push to a
feature branch, env-prefixed push to main, bare push with cwd on main, bare push with
cwd on a feature branch); Success criterion 1 gives every row's expected code. Neither copy is a gate: the harness is; they are
checkpoint aids, and T1's verification skips the 0.9.0 run with a printed line when
the binary is absent.

Note for T1's prompt: point the implementer at this file's T1 block by path and id;
do not paste payloads into the Agent brief or into any Bash command line (the live
hook blocks push-to-main text, and a brief that spells such tests out has been denied
by the permission classifier before). State the live-hook hazard verbatim from Risks.
T2, T3 and T4 run alongside T1 and therefore call no `tests/run.sh` subcommand; T5 and
T6 run after T1 and do. Several verification strings contain backticks inside their
single-backtick code span (grep targets quoting markdown); extract a verification by
stripping the `- verification: \`` prefix and the final backtick of the line only, as
the previous round did, never by the first closing backtick.

Note on briefing, for every agent in this build: the orchestrator's context is the
scarce resource. Each implementer and reviewer writes its full report to a file under
the session scratchpad and returns at most about 1 500 tokens: the required JSON block
plus a few lines naming the file. Reviewers return findings only (severity, file:line,
one reproducing command each), never evidence walkthroughs. The orchestrator reads a
report file only when a verdict needs it. Fast-path reviews (T2–T5) run on sonnet;
only T1's deep review runs on opus.

## Task T1
- scope: Rewrite the branch guard's front end for linear normalisation, nested-shell visibility, state tracking, upstream and `--all`/`--mirror` checks and lease semantics; widen the secrets patterns; make profile-check's error path and CRLF handling correct; add `compact` to the SessionStart matcher; prove every behaviour in the hook harness.
- files_owned: [hooks/protect-branches.sh, hooks/protect-secrets.sh, hooks/profile-check.sh, hooks/hooks.json, tests/run.sh]
- files_forbidden: [skills/**, agents/**, rules/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, .claude-plugin/**, .github/**, docs/**, tests/dedupe-phrases.txt, tests/settings-keys.txt, tests/fixtures/**]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: high
- verification: `shellcheck -x hooks/*.sh tests/run.sh && SC090="${CW_SC090:-$HOME/.claude/plans/cw-plugin-gates/shellcheck-0.9.0}" && if [ -x "$SC090" ]; then "$SC090" -x hooks/*.sh tests/run.sh; else echo "shellcheck 0.9.0 not present at $SC090; CI runs it"; fi && bash tests/run.sh hooks | tail -1 | grep -q ' 0 failed' && /bin/bash tests/run.sh hooks | tail -1 | grep -q ' 0 failed' && test "$(bash tests/run.sh hooks | tail -1 | sed 's/hooks: \([0-9]*\) passed.*/\1/')" -ge 58 && jq -e '.hooks.SessionStart[0].matcher=="startup|resume|clear|compact|fork"' hooks/hooks.json && ! grep -rn '</content>' hooks tests/run.sh` — expected exit 0; a present 0.9.0 binary that reports a finding fails the chain (the build's Phase 0 note says where the binary comes from). No `tests/run.sh all` here: its size, dedupe and trailers checks read files and commits that T2–T4 change in the same window; T5 and T6 run the full gate. The reproduction script is not part of this gate either: the harness covers every row it has, and Success criterion 1 states its expected output for the checkpoint.
- commit: fix(hooks): harden the branch guard, widen secrets patterns, compact source

Specification.

`hooks/protect-branches.sh` — keep the file's shape (header comment, jq check, `block()`
helper, `check_segment`, segment loop, `exit 0`). Changes:
1. Parse with `2>/dev/null` on both jq calls; `[ -z "$CMD" ] && exit 0`.
2. Join and normalise once: replace the bash continuation-join loop (lines 158–171)
   with `CMD_JOINED=$(printf '%s\n' "$CMD" | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }')`
   (BSD and GNU awk, one process; a line ending in a backslash is joined to the next
   with a space, as the loop did; the jq check at the top of the script stays ahead of
   it, because the harness's jq-absent case runs with a PATH that has no `awk` either,
   `tests/run.sh:109`), then `CMD_NORM=$(printf '%s' "$CMD_JOINED" | tr -d
   '"'"'"'\\' | tr '\t' ' ')` (two `tr` processes).
3. Fast path on the normalised text: `case "$CMD_NORM" in *push*) ;; *) exit 0 ;; esac`.
4. Split once: the existing `sed` segment split over `CMD_NORM`, with the backtick added
   (`` s/`/\n/g ``) and a bare `&` added after the `&&` rule (`s/&/\n/g`, so a
   backgrounded chain such as `git status & git push origin main` is two segments and
   the push is examined; `2>&1` splits into harmless pieces) (one process). No further process is spawned per segment. Per
   segment, inside the existing `while IFS= read -r line` loop: skip when blank; skip
   cheaply unless the line matches the builtin glob
   `*[Gg][Ii][Tt]*|*cd*|*pushd*|*popd*` (case-insensitive `git`, so `Git push` reaches
   the scanner); then split into words with `set -f; TOK=( $line ); set +f` under the default
   IFS (a `# shellcheck disable=SC2206` directive with a comment naming the reason:
   deliberate word splitting with globbing off, no here-string, no process). Remove the
   per-character `tokenize()` entirely, and the `TAB` variable with it (shellcheck
   reports an unused variable as SC2034). A 100k-character command, whether one token
   or thousands of segments, must stay under one second (harness speed cases).
5. State tracking across segments (globals `TRACK_DIR`, `TRACK_BRANCH`, set before
   `check_segment` returns; the last change wins). A segment containing a token equal
   to `cd` or `pushd` (first occurrence, at any position, so a quote-stripped
   interpreter body such as `sh -c cd <dir>` is tracked too): `TRACK_DIR` = the next
   token when it starts with `/`, else `"$CWD/<token>"` when `CWD` is set, else the
   token; a next token of `-`, no next token, a `popd` token, or a next token
   containing `$` → `TRACK_DIR=unknown`; in every case `TRACK_BRANCH` is cleared
   (unset). A `git` segment whose subcommand is `switch`
   or `checkout`: walk the following tokens in order — `-b`, `-B`, `-c`, `-C` → the
   next token is the branch, stop; `--`, `-p`, `--patch`, `HEAD`, `-`, or a token
   containing `$` → `TRACK_BRANCH=unknown`, stop; any other token starting with `-` →
   skip; the first remaining token → `TRACK_BRANCH=<token>`, stop; no token left →
   `TRACK_BRANCH=unknown`. `git -C <dir>` sets `GITDIR` for that segment only; a
   relative `<dir>` is joined to `CWD` the same way a `cd` argument is.
6. Scanner: the first-`git`-token, first-subcommand logic stays (env assignments and
   global options skipped); the token test becomes a `case` pattern
   (`git|[Gg][Ii][Tt]|*/git|*/[Gg][Ii][Tt]`) so `GIT push` on a case-insensitive
   filesystem matches without spawning a process. Backslashes are already gone, so
   `\git` matches.
7. Option loop after `push`: `--force|-f-cluster|+ref` block "force push is not allowed.";
   `--all|--mirror` block "pushing every branch (--all/--mirror) is not allowed."; `-o`,
   `--push-option`, `--repo` consume one token; every other `-`/`--` token (including
   `--force-with-lease`, `--force-with-lease=*`, `--force-if-includes`, `--dry-run`,
   `--tags`) is skipped.
8. Destination loop: unchanged (`src:dst`, `refs/heads/` stripped, bare `main`/`master`,
   a ref containing `/` counts as explicit).
9. Refspec-less push (`has_explicit_ref` still 0, and `npos -le 1` or last positional
   `HEAD` — exactly the existing condition at line 146): when `GITDIR` is set (a `-C`
   in the push segment) resolve there and ignore the tracked state, because `git -C`
   overrides a preceding `cd` or checkout for that invocation (Research §4);
   otherwise, if `TRACK_BRANCH` is set and not `unknown` → block when it is
   `main`/`master`, else allow (a `cd` after the branch change would have cleared it,
   so a set branch is current); if `TRACK_BRANCH` or `TRACK_DIR` is `unknown` → block "cannot determine the destination after a cd or
   branch change; use an explicit refspec such as git push origin <branch>."; else
   `dir="${GITDIR:-${TRACK_DIR:-${CWD:-.}}}"`, `BR=$(git -C "$dir" rev-parse
   --abbrev-ref HEAD 2>/dev/null)` → block "current branch is <BR>; push from a feature
   branch." when main/master; additionally, on the same `dir` in both the `-C` path and the tracked/cwd path, when no
   positional is `HEAD` and `npos -le 1`, and only when `git -C "$dir" config --get
   push.default 2>/dev/null` prints `upstream` or `tracking`,
   `UP=$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)`
   → block "current branch tracks <UP> and push.default is upstream; push to a feature
   branch explicitly." when it ends in `/main` or `/master`. Resolution failure (not a repo) allows, as today.
10. Header comment: describe the normalisation, the state tracking, the scope (guardrail
    against the agent's own accidental pushes; out of scope: commands held in variables
    and `eval "$X"`, xargs-fed refspecs, wrappers and aliases not named git, `git -c
    k="v w"` before push; a `cd` or branch change the text cannot resolve blocks with a
    hint; prose is treated as command text).

`hooks/protect-secrets.sh` — pattern block line 35–39 gains `*.p12|*.netrc|*id_dsa*|
*id_ecdsa*|*.tfstate|*.tfstate.backup`. Header comment line 3 unchanged.

`hooks/profile-check.sh` — lines 110–115: `NEW=$(jq -nc … ) && OUT="$NEW"` in both
branches (OUT keeps `{}` when jq fails); in the `.claude-profiles` loop (52) add
`pline="${pline%$'\r'}"` right after the read (bash 3.2 supports `$'\r'`); line 2's
header comment lists the five sources including `compact`; line 14's directive comment
loses its version numbers ("older shellcheck reports SC2317, newer SC2329" — Research
§2 item 8 could not pin the release).

`hooks/hooks.json` — matcher line 27: `"startup|resume|clear|compact|fork"`.

`tests/run.sh` — add `HOOKS_DIR="${CW_HOOKS_DIR:-$ROOT/hooks}"` next to `BASH_BIN` and use
`"$HOOKS_DIR/…"` in every hook case (including the jq-absent case and the profile
cases). Add a helper `push_case <expected> <description> <cwd> <command>` that builds the
payload with `jq -nc --arg c "$4" --arg d "$3" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'`
and reports via `check_code`, so cases are one line each; commands must be single-quoted
literals inside the script (never typed in a Bash tool command). In `cmd_hooks`, create
four scratch repositories before the push cases, each with `user.name`/`user.email`
and `commit.gpgsign=false` set via `-c` (the scratch repos inherit the real HOME's
gitconfig): `$SCRATCH/rm` on `main` (one commit); `$SCRATCH/rf` cloned from it, then
`git checkout -b feat/x` so HEAD is `feat/x`, no upstream; `$SCRATCH/rc` like `rf` plus
`git branch --set-upstream-to=origin/main` (upstream on main, `push.default` unset);
`$SCRATCH/ru` like `rc` plus `git config push.default upstream`. No case mutates a repo
after setup, so case order does not matter. If `git init -b main` fails, the cases
that name a scratch repo (the twelve resolution cases, the two state cases naming
`$SCRATCH/rm` and the nested `sh -c` case naming it) are skipped with one plain
`printf` line, not through `report`, so the summary counts only real cases. New cases, expected code in brackets (existing
four push cases stay first):
- nested: `sh -c "git push origin main"` [2]; `bash -c 'cd /tmp && git push origin main'` [2]; `eval "git push origin main"` [2]; `` echo `git push origin main` `` [2]; `sh -c "cd $SCRATCH/rm && git push"` [2] (literal path; the `cd` inside the body is tracked after quote removal)
- backslash: `\git push origin main` [2]; `\git push -u origin feat/x` [0]
- options: `git push --all origin` [2]; `git push --mirror origin` [2]; `git push origin --all` [2]; `git push --force-with-lease origin feat/x` [0]; `git push --force-with-lease=feat/x origin feat/x` [0]; `git push --force-if-includes origin feat/x` [0]; `git push --force-with-lease origin main` [2]; `git push -fu origin feat/x` [2]; `git push origin +feat/x` [2]; `git push origin HEAD:main` [2]; `git push origin --delete main` [2]; `git push origin :main` [2]; `git push origin --dry-run feat/x` [0]
- names: `git push -u origin feat/main-nav` [0]; `git commit -m "docs: pushing to main is blocked"` [0]; `FOO=bar git push origin main` [2]; `git -c core.x=1 push origin main` [2]; `GIT push origin main` [2]
- state, cwd `/tmp` (not a repo): `git switch main && git push` [2]; `git checkout main && git push origin` [2]; `cd $SCRATCH/rm && git push` [2] (the literal absolute path substituted when the case is built); `cd "$DIR" && git push` [2] (the `$DIR` stays literal in the payload); `git checkout -b feat/y && git push -u origin HEAD` [0]; `git checkout -- README.md && git push -u origin feat/x` [0]; `git checkout -b feat/y && cd $SCRATCH/rm && git push` [2] (literal path; the `cd` clears the recorded branch); `git status & git push origin main` [2] (a bare `&` is a separator)
- resolution: cwd `$SCRATCH/rm`: `git push` [2], `git push origin` [2], `git push -u origin HEAD` [2], `git checkout -- README.md && git push` [2] (unknown branch blocks with the hint); cwd `$SCRATCH/rf`: `git push` [0], `git push -u origin HEAD` [0], `git -C $SCRATCH/rm push` [2]; cwd `$SCRATCH/ru`: `git push` [2] (upstream on main with `push.default=upstream`); cwd `$SCRATCH/rc`: `git push` [0] (same upstream, `push.default` unset: git's `simple` refuses that push itself, the guard does not); cwd `$SCRATCH/rm`: `git push feat/x` [0] (one positional containing a slash is an explicit destination, no resolution); cwd `/tmp`: `git checkout -b feat/y && git -C $SCRATCH/rm push` [2] (`-C` wins over the tracked branch), `git checkout -b feat/y && git -C $SCRATCH/rf push` [0]
- speed, each reported as one case asserting both the exit code and `[ "$SECONDS" -le 1 ]` with `SECONDS=0` set just before the hook call: (i) one token of 100 000 `a` characters followed by ` && git push origin main` [2]; (ii) 5 000 segments `echo abcd-<index>` joined with ` && ` (each contains the substring `cd`, so every segment reaches the word split) followed by ` && git push origin main` [2]; (iii) 2 000 lines of `echo line-<index>-<40 letters>` joined with newlines (about 100 000 characters, no `push`) [0], the heredoc shape, proving the join is linear
- input: stdin `not json` [0] and stderr empty (reported as one case); stdin `{}` [0]
- secrets: `Write` `/tmp/x/certs/client.p12` [2]; `Write` `/tmp/x/.netrc` [2]; `Write` `/tmp/x/id_dsa` [2]; `Write` `/tmp/x/id_ecdsa` [2]; `Write` `/tmp/x/terraform.tfstate` [2]; `Write` `/tmp/x/terraform.tfstate.backup` [2] (the script reads only the path fields, so tool names beyond `Write` add no coverage)
- profile: a `jq` shim on PATH that passes `command -v` but exits 5 on every call → stdout is exactly `{}` and exit 0; a `.claude-profiles` written with CRLF line endings whose mapping points at the active config dir → no `systemMessage` in the output
Total new cases: 58 (nested 5, backslash 2, options 13, names 5, state 8, resolution 12, speed 3, input 2, secrets 6, profile 2) on top of the existing 15, so the summary reads `hooks: 73 passed, 0 failed` when the scratch repos can be created; the fifteen repo-dependent cases (one nested, two state, twelve resolution) are the skip path, so the summary reads 58 then and the verification's floor is 58. The design draft's D6.3 (T5) names the coverage classes, not a count, so adding a case later needs no docs edit.

## Task T2
- scope: Fix the README's marketplace install route and add the guard-scope and linguist notes; add `trailers` to WORKFLOW.md's standalone list.
- files_owned: [README.md, WORKFLOW.md]
- files_forbidden: [hooks/**, tests/**, skills/**, agents/**, rules/**, CLAUDE.md, settings.example.json, .claude-plugin/**, .github/**, docs/**]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `grep -q 'plugins/cache/claude-code-setup/cw/<version>/' README.md && grep -q "claude plugin list --json" README.md && grep -q 'installPath' README.md && ! grep -q 'print the current cache path' README.md && test "$(grep -c 'separate throwaway clone' README.md)" = 1 && grep -qi 'not a sandbox' README.md && grep -q 'explicit refspec' README.md && grep -q 'linguist-generated' README.md && grep -q '(`hooks`, `size`, `dedupe`, `scan`, `trailers`)' WORKFLOW.md && test "$(wc -l < WORKFLOW.md)" -le 200 && ! grep -q '</content>' README.md WORKFLOW.md && ! grep -rnE '/(Users|home)/' README.md && ! grep -qE 'install.sh|merge-settings|/setup' README.md WORKFLOW.md` (no `tests/run.sh` call here: T1 rewrites that file in the same window; T6 runs the full gate)
- commit: docs: real plugin cache path, branch-guard scope, trailers in the test list

Exact edits.
1. README.md line 54–56 (route (b) paragraph): replace with: "This installs a copy into
   the plugin cache at `~/.claude/plugins/cache/claude-code-setup/cw/<version>/` (the
   version directory changes on every `claude plugin update cw@claude-code-setup`),
   independent of any local checkout."
2. README.md lines 129–132 (the whole (b) import bullet, four lines at head `fafca6f`,
   ending "…just for stable import paths."): replace with: "**(b) marketplace** —
   print the installed path with `claude plugin list --json | jq -r '.[] |
   select(.id==\"cw@claude-code-setup\") | .installPath'` and import
   `@<that path>/rules/workflow.md`; the path changes on every update, so re-check it
   after updating, or keep a separate throwaway clone just for stable import paths."
   (Keep the surrounding bullets; the phrase "separate throwaway clone" must occur
   exactly once in the file afterwards.)
3. README.md, after the Kill switch paragraph (line 187) and before `## Migration`, insert
   a paragraph headed `### What the branch guard does` (or a bold lead-in; a `###` is
   fine): it reads the text of each Bash command, splits it on shell separators,
   strips quotes and backslashes so nested `sh -c`/`bash -c`/`eval` strings and a
   backslash-escaped `git` are inspected too, tracks
   `cd` and `git switch`/`checkout` earlier in the same command, and blocks a `git push`
   whose destination is `main`/`master` (explicit refspec, the current branch, or an
   upstream on main), plain force pushes (`--force`, `-f`, `+ref`), and `--all`/
   `--mirror`; lease pushes (`--force-with-lease`, `--force-if-includes`) to a feature
   branch pass. When a `cd` or branch change earlier in the command cannot be resolved
   from the text (a variable, `cd -`, a path checkout), a bare `git push` after it is
   blocked with a hint to use an explicit refspec. It is a guardrail against the
   agent's own accidental pushes, not a sandbox: a command held in a variable,
   `xargs`-fed refspecs, wrappers and aliases not named `git`, and `gh api` calls are
   out of scope, and a line of prose that spells a push to main inside a command is
   blocked as if it were the command (keep such text in a file). Do not use the phrase
   "push directly to main".
4. README.md, in the section that describes the repository layout or right after
   "Running the tests" (implementer's choice, one sentence): `.gitattributes` marks
   `docs/plans/**` as `linguist-generated`, so design documents are collapsed by
   default in GitHub diffs and excluded from language statistics.
5. WORKFLOW.md line 129 (the line beginning "(`hooks`, `size`, `dedupe`, `scan`), and
   CI"): the list becomes `(\`hooks\`, \`size\`, \`dedupe\`, \`scan\`, \`trailers\`)`;
   keep the whole parenthesised list on one line (the verification greps it as one
   string) and the file at or under 200 lines.

## Task T3
- scope: One-line prompt fixes: name the task blocks `/cw:build` reads, make the implementer agent's Output section name the exit report the build gate parses, and make the ship skill pass the PR body through a file so the hardened guard never reads it as a command.
- files_owned: [rules/workflow.md, agents/implementer.md, skills/ship/SKILL.md]
- files_forbidden: [hooks/**, tests/**, skills/build/**, skills/design/**, skills/search/**, skills/compound/**, skills/google-workspace/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, .claude-plugin/**, .github/**, docs/**, rules/orchestration.md, agents/reviewer.md, agents/researcher.md, agents/design-reviewer.md, agents/direction-reviewer.md]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `grep -q 'reads the `## Task <id>` blocks of that' rules/workflow.md && ! grep -q '## Tasks' rules/workflow.md && grep -q '^5\. ' agents/implementer.md && grep -qi 'exit report' agents/implementer.md && test "$(wc -l < rules/workflow.md)" -le 40 && test "$(wc -l < agents/implementer.md)" -le 150 && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- rules agents && ! grep -q '</content>' rules/workflow.md agents/implementer.md && ! grep -qiF -f tests/dedupe-phrases.txt agents/implementer.md && grep -q -- '--body-file' skills/ship/SKILL.md && test "$(wc -l < skills/ship/SKILL.md)" -le 150 && ! grep -q '</content>' skills/ship/SKILL.md` (no `tests/run.sh` call here: T1 rewrites that file in the same window; T6 runs the full gate; the dedupe grep keeps the implementer file free of every single-home phrase, which it is today; the ship skill already holds one such phrase as its home, so its added sentence is checked by T6's dedupe run instead)
- commit: fix(skills): ship body via file, build reads Task blocks, implementer exit report

Exact edits. `rules/workflow.md` line 18–19: "`/cw:build <slug> [continue [<task-id>]]`
reads the `## Task <id>` blocks of that file, commits the design as `docs(<slug>):
design`, delegates every change to an implementer, and stops at the checkpoint before
the PR." (re-wrap so that line 18 ends with "blocks of that" and line 19 starts with
"file,": the phrase `reads the \`## Task <id>\` blocks of that` is four characters longer
than today's fill and must survive on one line). `agents/implementer.md` Output list
gains a fifth item: "5. When the orchestrator's prompt specifies an exit report, end
with that fenced JSON block exactly as specified — the build gate parses it."
`skills/ship/SKILL.md` Step 5 item 2 (the `gh pr create` instruction) gains one
sentence after its body template: "Write the body to a file in the scratchpad and pass
it with `--body-file <file>`: the branch guard reads Bash command text, and a body that
mentions a push to `main` inline would be blocked as if it were the command." Do not
add any phrase from `tests/dedupe-phrases.txt`; the three files stay under their line
caps (40, 150, 150) and the byte baseline has about 19 kB of headroom today (54 661 of
73 738 bytes), so three added lines cannot trip it.

## Task T4
- scope: Make CI validate the plugin manifest as well as the marketplace manifest.
- files_owned: [.github/workflows/ci.yml]
- files_forbidden: [hooks/**, tests/**, skills/**, agents/**, rules/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, .claude-plugin/**, docs/**]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `grep -q '^          claude plugin validate \.$' .github/workflows/ci.yml && grep -q '^          claude plugin validate \.claude-plugin/plugin\.json$' .github/workflows/ci.yml && claude plugin validate . && claude plugin validate .claude-plugin/plugin.json && { python3 -c 'import yaml' 2>/dev/null && python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml"))' || echo "yaml module absent; indentation asserted by the greps"; } && ! grep -q '</content>' .github/workflows/ci.yml`
- commit: chore(ci): validate the plugin manifest as well as the marketplace

Exact edit: in the ubuntu job's "install Claude Code CLI and validate plugin" step, add
the line `          claude plugin validate .claude-plugin/plugin.json` (ten spaces)
after `          claude plugin validate .`. If the CLI rejects a manifest path (the
`--help` text says a manifest path is accepted), report it in the exit report instead of
inventing another form; the orchestrator then drops the task.

## Task T5
- scope: Amend the released design draft where behaviour changed: the D2.4 hook paragraph and scope, the SessionStart matcher, and D6.3's description of what the hook harness covers (coverage classes instead of a case count).
- files_owned: [docs/plans/cw-plugin/cw-plugin-design-draft.md]
- files_forbidden: [hooks/**, tests/**, skills/**, agents/**, rules/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, .claude-plugin/**, .github/**, docs/plans/cw-plugin/cw-plugin-tasks.md, docs/plans/cw-plugin/cw-plugin-research-*.md, docs/plans/hardening-1-0-0.md, docs/plans/fixups-1-0-0.md]
- depends_on: [T1]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `grep -q 'startup|resume|clear|compact|fork' docs/plans/cw-plugin/cw-plugin-design-draft.md && ! grep -q 'startup|resume|clear|fork`' docs/plans/cw-plugin/cw-plugin-design-draft.md && grep -q 'nested interpreters' docs/plans/cw-plugin/cw-plugin-design-draft.md && ! grep -q '15 hook cases' docs/plans/cw-plugin/cw-plugin-design-draft.md && grep -qi 'not a sandbox' docs/plans/cw-plugin/cw-plugin-design-draft.md && grep -q 'force-with-lease' docs/plans/cw-plugin/cw-plugin-design-draft.md && ! grep -q '</content>' docs/plans/cw-plugin/cw-plugin-design-draft.md && bash tests/run.sh all` (T5 runs after T1 has landed, so the full gate is safe here)
- commit: docs(cw-plugin): design reflects the hardened guard, compact source, harness coverage

Exact edits. Lines 218–225 (the `protect-branches.sh` bullet): rewrite to describe the
shipped behaviour: fast path on `push`; split on `&&`, `||`, `;`, `|`, `(`, `)`,
backticks and newlines; quotes and backslashes stripped so nested `sh -c`/`bash -c`/
`eval` strings and `\git` are inspected; `cd`/`pushd` and `git switch`/`checkout`
earlier in the command tracked for later refspec-less pushes (unknown targets block
with an explicit-refspec hint); blocks a `git push` whose destination is main/master by
explicit refspec, tracked or resolved current branch, or an upstream on main; blocks
`--force`/`-f`/`+ref` and `--all`/`--mirror`; `--force-with-lease`,
`--force-with-lease=<ref>` and `--force-if-includes` pass to other destinations;
everything else exits 0; then the scope sentence (guardrail against the agent's own
accidental pushes, not a sandbox; the named out-of-scope forms; prose treated as
command text). Keep the no-opt-out sentence. Line 230: matcher `startup|resume|clear|
compact|fork` (keep the matcher string on one line; the line may exceed the file's
usual width). D6.3: replace `15 hook cases` with "hook cases covering nested
interpreters, an escaped git token, chained cd and branch changes, --all/--mirror,
lease variants, an upstream on main under push.default=upstream, 100k-character
timing, the secrets patterns and profile-check's error paths; 0 failed" (the phrase
`nested interpreters` on one line). Nothing else in the file.

## Task T6
- scope: Release gate re-run on the finished series, verification only.
- files_owned: []
- files_forbidden: [**]
- depends_on: [T1, T2, T3, T4, T5]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `bash tests/run.sh all && bash tests/run.sh all | grep -q '^all: trailers: PASS$' && /bin/bash tests/run.sh hooks | tail -1 | grep -q ' 0 failed' && shellcheck -x hooks/*.sh tests/run.sh && SC090="${CW_SC090:-$HOME/.claude/plans/cw-plugin-gates/shellcheck-0.9.0}" && if [ -x "$SC090" ]; then "$SC090" -x hooks/*.sh tests/run.sh; else echo "shellcheck 0.9.0 not present; CI runs it"; fi && claude plugin validate . && claude plugin validate .claude-plugin/plugin.json && jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills agents rules && ! git grep -niE 'opus needs|do not trust|be decisive|read all files fresh|claude-design-active|claude-orchestrator-active' -- skills agents rules && ! git grep -niE 'under 50 lines' -- skills agents rules && ! git grep -nE '^(disallowedTools|permissionMode|mcpServers|hooks):' -- agents && ! git grep -niE '~/.claude/plans|gitattributes|linguist|git clean' -- skills && OWNER=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1) && test -n "$OWNER" && ! git grep -qi "$OWNER" -- skills agents rules hooks tests WORKFLOW.md CLAUDE.md docs && ! grep -rn '</content>' hooks tests/run.sh README.md WORKFLOW.md rules agents docs/plans/cw-plugin/cw-plugin-design-draft.md && for s in 'fix(hooks): harden the branch guard, widen secrets patterns, compact source' 'docs: real plugin cache path, branch-guard scope, trailers in the test list' 'fix(skills): ship body via file, build reads Task blocks, implementer exit report' 'chore(ci): validate the plugin manifest as well as the marketplace' 'docs(cw-plugin): design reflects the hardened guard, compact source, harness coverage' 'docs(hardening-1-0-0): design'; do test "$(git log --format=%s main..HEAD | grep -c -F -x -- "$s")" = 1 || exit 1; done && test -z "$(git status --short)"`
- commit: none

T6 owns no file: a failed check is reported at the checkpoint with the failing command's
output; a content failure belongs to the task that owns the file; a trailer-only failure
is fixed at the checkpoint by amend or autosquash fixup and T6 re-run. The plan file
itself is in the LICENSE-name grep's scope (`docs`), which is why it names no person.
