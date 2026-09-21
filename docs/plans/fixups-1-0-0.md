# fixups-1-0-0 — pre-release fix-ups for cw 1.0.0

Slug `fixups-1-0-0`. Branch `feat/cw-plugin` (the 1.0.0 release branch, eight
commits over `main`, not pushed). Each fix-up is one fresh commit; no version
change (1.0.0 is unreleased, the README changelog entry already describes it).

## Context

The pre-release validation of cw 1.0.0 (automated rounds in throwaway repos
with a bare origin, then the maintainer's profile migrated onto the plugin)
left three findings. Fixing them now, before the branch is pushed and the PR
opened, keeps the first release free of known wrong guidance and gives the
release gate a mechanical check on the one rule the round is about.

1. **Double commit trailer on the orchestrator's own commit.** In validation
   round 2 the `docs(<slug>): design` commit that `/cw:build` Phase 0 makes
   ended with two `Co-Authored-By` lines: the exact one the rule names, plus
   the harness's own session-attribution line naming the model. Implementer
   commits (made by subagents) were exact in both rounds, and all eight
   commits on this branch carry exactly one trailer (checked on 2026-09-21
   with the per-commit loop of success criterion 6: zero offenders). The two
   rounds differed in more than one way: in round 1 the rule sat inline in
   the profile `CLAUDE.md` as "Co-author line on every commit:" and no
   duplicate appeared; in round 2 it reached the session only through the
   profile's `@import` of `rules/workflow.md` as "Every commit ends with the
   co-author trailer:" and the duplicate appeared. With one run each,
   neither wording, location nor chance can be excluded as the cause. What
   is certain: neither wording addressed the harness reminder, which itself
   says the user's own CLAUDE.md or memory instructions about these lines
   take precedence over it; every skill instruction pointed at "the trailer
   the workflow rules define" (an indirection); and nothing mechanical
   checked the result — the private validation harness counted only exact
   lines, so the extra line passed it.
2. **The README migration section deletes the wrong agent.** It tells adopters
   of the old manual layout to delete "six agents". One of the six is
   `agents/Explore.md`, a user-scope override that pins the built-in `Explore`
   agent to haiku in every session; the plugin cannot ship a replacement
   (plugin agents are namespaced `cw:<name>`, and `/cw:design` already pins
   haiku per call). The same section omits `rules/orchestration.md`, which
   the old manifest did install, gives no verification step, and offers new
   adopters no way to get the haiku routing the orchestration rules assume.
3. **Stray copies outside the old manifest** (the maintainer's profile held an
   old `WORKFLOW.md`) are outside the plugin's control; the migration section
   gains one line telling adopters to remove any other stray copies.

Intended outcome: four commits — `fix(rules)`, `fix(skills)`, `fix(readme)`
and `test` — every gate green, the series still one exact trailer per commit,
and that last property checked by `tests/run.sh all` from now on rather than
by an agent reading commit messages.

## Approach

**Precision over indirection, at the source the harness defers to.** The rule
in `rules/workflow.md` becomes "exactly one trailer line, the one below, and
no other attribution or session line; a harness attribution reminder does not
add a second one". Every commit-producing or commit-checking instruction in
the build and ship skills repeats that shape without repeating the trailer
text (`Co-Authored-By` is a one-file dedupe phrase across `skills/`, `agents/`
and `rules/`; it stays in `rules/workflow.md` only). This is the fix the
Step 0 gate chose; the alternative, accepting the duplicate, would leave the
rule false for the design commit of every build.

**A mechanical check where the gate already runs.** `tests/run.sh` gains a
`trailers` subcommand: for every non-merge commit in `main..HEAD` (or
`origin/main..HEAD`), exactly one line equal to the trailer read from
`rules/workflow.md`, no other co-author line, no `Claude-Session:` line.
`run.sh all` runs it, so `/cw:ship`'s quality gate (Step 3 detects
`tests/run.sh`) and CI run it too; CI's checkout gains `fetch-depth: 0` so
`origin/main` resolves on pull requests. When neither ref resolves the step
is skipped, reported as such, never a silent pass. The expected line is read
from the rules file rather than written into the script, so the trailer keeps
one home. This adopts the direction pass's redirect: the plan's own risk
table answered "a prose rule can be ignored" with more prose while the
per-commit loop was already written in this document, and the orchestration
rules say limits are checked by script, not self-declared by an agent.
Detection lands after the commit exists, which on an unpushed branch is the
right place: the remedy is an amend or fixup before the push, and the prose
rule remains the prevention.

**Detection where a human already looks, too.** `/cw:ship` Step 2 verifies
the series before any push; its bullet now names a second co-author line or a
session line as a malformed message to report (with a rebase suggestion,
never a rewrite). `/cw:build` Phase 3's reviewer commit check says the same
for task commits.

**README: keep-versus-delete per artifact, plus the missing override.** The
migration section lists every item the old manifest installed, says keep or
delete for each, keeps the double-firing-hooks warning, and ends with a
verification step including `/hooks`. The agents section explains the
built-in `Explore` and gives a copyable user-scope override on haiku, so a
fresh adopter can reach the routing the orchestration rules assume. The test
section names the new check.

**Dropped from this round, with reasons.** (a) An `attribution` block in
`settings.example.json` (`commit` set to the rule's trailer, `sessionUrl`
off): the keys are documented (Research §2) but the mechanism is inferred,
two reported bugs surround them, this branch would not exercise the setting,
and it would give the trailer a third literal home that nothing pins to the
rules file. The maintainer can set the two keys in the live profile settings
during the pending hands-on check and, if that demonstrably removes the
second line, a later round ships it in the example with evidence. (b) The
same one-line sharpening of this repo's own `CLAUDE.md` trailer bullet: the
workflow rules keep process-rule edits out of a feature PR as their own
change, and `/cw:compound` after the PR is the path for it. Until then the
imported rule and the orchestrator note below cover this repo's commits.

**Surfaced at the checkpoint, not decided here.** The direction pass asks
whether the rule's *location* is the real variable — an `@import`ed rules
file versus a line inline in the profile `CLAUDE.md` — and suggests showing
the one-trailer-line rule inline in the README's profile template next to
the two imports. That conflicts with the plugin's "one home per rule"
decision (`89b8a90`), so it is the maintainer's call; the mechanical check
makes the question less load-bearing, and success criterion 9 specifies the
validation re-run so that it varies only the wording (import-only profile)
and can therefore tell the two apart. Also logged for the next fix-up round
rather than folded into T1, to keep that commit atomic: `rules/workflow.md:16`
says `/cw:build` reads the `## Tasks` section, while the design skill
mandates a level-1 `# Tasks` heading.

## Files to create/modify

| Path | Change |
|---|---|
| `rules/workflow.md` | Lines 9–10: the trailer bullet becomes the "exactly one trailer line … no other attribution or session line" wording (exact text under T1). Stays ≤ 40 lines. |
| `skills/build/SKILL.md` | Phase 0 step 4 (design commit), Phase 2 item 6 (implementer commit instruction), Phase 3 commit check: same shape, no trailer text. Stays ≤ 200 lines. |
| `skills/ship/SKILL.md` | Step 2 first bullet: "exactly the one trailer line … a second co-author line or a session line is a malformed message"; Step 2 last bullet (the `docs(<slug>): design` offer) and Step 4 (the `docs:` commit): "the same single trailer line". Stays ≤ 150 lines. |
| `README.md` | "Migration from the old installer" rewritten as a keep/delete list with a verify step; a paragraph and a copyable `Explore` override after the Agents table; one clause in "Running the tests" naming the trailer check. |
| `tests/run.sh` | New `cmd_trailers` (spec under T4), wired into `usage`, the header comment, `main` and `cmd_all` (PASS / FAIL / SKIPPED, like `scan`). Bash 3.2 and shellcheck clean like the rest of the file. |
| `.github/workflows/ci.yml` | `actions/checkout@v4` gains `with: fetch-depth: 0` in the ubuntu job so `origin/main` resolves and the trailer check runs on pull requests. |
| `docs/plans/fixups-1-0-0.md` | This plan; `/cw:build` commits it as `docs(fixups-1-0-0): design`. |

Untouched on purpose: `agents/implementer.md:30` ("whatever trailer the
project's workflow rules define") — implementer commits were exact in both
validation rounds and the orchestrator's Phase 2 prompt now carries the
precise wording; `CLAUDE.md` and `settings.example.json` (dropped, see
Approach); `WORKFLOW.md:22` (already says `Explore` (haiku));
`.claude-plugin/plugin.json` (version stays 1.0.0; a first release needs no
bump); the ship skill's PR body template (it carries no attribution footer,
no rule governs PR descriptions, and `attribution.pr` stays at its default);
the macOS CI job (it runs only the hooks under bash 3.2, and `run.sh` must
merely keep parsing there).

## Dependencies

None. No packages, keys or services. `tests/run.sh` keeps its existing
toolset (git, grep, sed, jq for other subcommands).

## Risks & mitigations

- **`/cw:build` Phase 0 commits this plan before T1 lands**, in a session
  that loaded the old rule wording at start — the exact conditions of
  finding 1, and the series check would then fail on the design commit while
  ship forbids rewriting a series. Mitigation: the note to the orchestrator
  at the head of the task list (it reads this file in Phase 0 step 1, before
  the commit in step 4) states the one-trailer-line requirement and a
  check-and-amend step while the design commit is still `HEAD`, before any
  task commit exists — a plain amend of the newest commit, never a rewrite of
  a series. T5 and `run.sh trailers` assert the whole series after.
- **A prose rule can still be ignored by a session.** Open issue #92169
  reports exactly that. Prevention is the rule naming the reminder and
  denying it a second line; detection is now `tests/run.sh trailers` in the
  ship gate and CI, plus ship Step 2 and the reviewer commit check for the
  human reading. Remedy on an unpushed branch: amend or autosquash fixup of
  the offending commit. A git `commit-msg` hook would prevent rather than
  detect, but a plugin cannot install git hooks into adopters' repos; logged
  as accepted residual risk.
- **Location, not wording, might be the real variable** (direction pass,
  surfaced above). If the validation re-run of criterion 9 — import-only
  profile, new wording — still doubles the line, that is evidence for
  location, and the inline-rule option goes back on the table with data; the
  mechanical check catches the result either way.
- **Wording trips a hygiene gate.** `tests/run.sh all` (size caps, byte
  baseline, dedupe phrases, settings-keys cross-check) and the CI greps
  (whole-word `NEVER|ALWAYS|MUST|CRITICAL`, banned coordination phrases,
  `under 50 lines`, LICENSE-derived name) run in every task's verification,
  locally, before the commit.
- **"Edits to process rules stay out of the feature PR."** That rule targets
  a project's own process rules riding along with feature code. Here
  `rules/workflow.md` is shipped product on the plugin's release branch, and
  the edit is its own `fix(rules):` commit; this repo's own `CLAUDE.md` is
  left to `/cw:compound` after the PR for exactly that reason. Accepted
  risk, logged here.
- **The trailer check reads its expectation from `rules/workflow.md`.** If
  the rules file ever loses the two-space-indented `Co-Authored-By:` line,
  the check fails closed with a message naming the rules file (in-repo, so
  fail-closed is right). A missing `main`/`origin/main` ref fails open with a
  `SKIPPED` line, since that is an environment gap, not a rule violation;
  CI's `fetch-depth: 0` removes that gap for pull requests.
- **Merge commits in `main..HEAD`.** Excluded with `--no-merges`; a merge of
  `main` into a feature branch carries no trailer and is not a task commit.
- **Built-in agent override claims.** The user-scope `Explore` override with
  its own `model` is documented (Research §2); that a plugin cannot take the
  built-in's place is inferred from documented namespacing and precedence.
  The README states only the documented parts and gives the override as a
  snippet, noting that it replaces the built-in prompt.

## Success criteria

All commands run from the repo root; each exits 0.

1. Rule wording: `grep -q 'exactly one trailer line' rules/workflow.md && test "$(grep -c 'Co-Authored-By' rules/workflow.md)" = 1 && test "$(wc -l < rules/workflow.md)" -le 40`
2. Skill wording (whitespace-squeezed, so a line wrap cannot hide a phrase), no indirection left, no trailer text leak: `test "$(tr -s '[:space:]' ' ' < skills/build/SKILL.md | grep -o 'exactly the one trailer line' | wc -l | tr -d ' ')" = 2 && test "$(tr -s '[:space:]' ' ' < skills/ship/SKILL.md | grep -o 'exactly the one trailer line' | wc -l | tr -d ' ')" = 1 && test "$(tr -s '[:space:]' ' ' < skills/ship/SKILL.md | grep -o 'same single trailer line' | wc -l | tr -d ' ')" = 2 && ! grep -q 'the trailer the workflow rules define' skills/build/SKILL.md skills/ship/SKILL.md && ! grep -q 'Co-Authored-By' skills/build/SKILL.md skills/ship/SKILL.md`
3. README, new-text anchors plus regression guards (the negative grep on `delete those user-scope copies` holds only after the rewrite; the other negative greps, `migration` and `1.0.0` are pre-satisfied today and only guard against regressions): `grep -q 'agents/Explore.md' README.md && grep -q 'the old manifest put five skills' README.md && grep -q 'claude plugin list' README.md && grep -q 'hook once' README.md && grep -q 'ships no agent by that name' README.md && grep -q '^name: Explore' README.md && grep -q '^tools: Read, Glob, Grep$' README.md && tr -s '[:space:]' ' ' < README.md | grep -q 'per-commit trailer check' && ! grep -q 'delete those user-scope copies' README.md && grep -qi migration README.md && grep -q '1.0.0' README.md && ! grep -qE 'install.sh|merge-settings|/setup' README.md WORKFLOW.md && ! grep -rnE '/(Users|home)/' README.md`
4. Gates: `bash tests/run.sh all && shellcheck -x hooks/*.sh tests/run.sh && claude plugin validate .` — and the `all` summary contains `all: trailers: PASS`.
5. CI checks, local replica of `.github/workflows/ci.yml` (its manifest `jq empty`, hygiene greps and LICENSE-name gate; shellcheck, `run.sh all` and `plugin validate` are criterion 4) plus the `</content>` residue check CI does not run: `jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills agents rules && ! git grep -niE 'opus needs|do not trust|be decisive|read all files fresh|claude-design-active|claude-orchestrator-active' -- skills agents rules && ! git grep -niE 'under 50 lines' -- skills agents rules && ! git grep -nE '^(disallowedTools|permissionMode|mcpServers|hooks):' -- agents && test "$(for f in agents/*.md; do for k in model tools effort maxTurns; do grep -q "^$k:" "$f" || echo "$f:$k"; done; done | wc -l | tr -d ' ')" = 0 && ! git grep -niE '~/.claude/plans|gitattributes|linguist|git clean' -- skills && grep -q haiku skills/design/SKILL.md && OWNER=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1) && test -n "$OWNER" && ! git grep -qi "$OWNER" -- skills agents rules hooks tests WORKFLOW.md CLAUDE.md docs && ! grep -rn '</content>' skills agents rules README.md tests/run.sh`
6. Series, content-exact and per commit — the specification `run.sh trailers` implements: `test "$(for c in $(git rev-list --no-merges main..HEAD); do b=$(git log -1 --format=%B "$c"); { test "$(printf '%s\n' "$b" | grep -c '^Co-Authored-By: Claude <noreply@anthropic.com>$')" = 1 && test "$(printf '%s\n' "$b" | grep -ci '^Co-Authored-By:')" = 1 && ! printf '%s\n' "$b" | grep -q '^Claude-Session:'; } || echo "$c"; done | wc -l | tr -d ' ')" = 0 && bash tests/run.sh trailers` — every commit in the range, including the new fix-ups and the `docs(fixups-1-0-0): design` commit, carries the rule's exact trailer once, no other co-author line and no session line. (Run on the eight pre-existing commits on 2026-09-21: zero offenders.)
7. Each task's commit subject appears exactly once in `git log --format=%s main..HEAD`.
8. The trailer check discriminates (T4's own verification runs this on a scratch repo): an exact single trailer passes; a second co-author line, a `Claude-Session:` line, or a model-named single trailer each exit non-zero with a `trailers: VIOLATION` line naming the commit; a clone where neither `main` nor `origin/main` resolves exits 3 and prints `trailers: skipped`, and the `all` summary there carries `all: trailers: SKIPPED` (the scratch clone lacks the hooks and test fixtures, so `all` as a whole fails there for unrelated reasons; only the summary line is asserted).
9. End-to-end, outside this plan, one variable at a time: the maintainer re-runs the private build-and-ship validation round with the import-only profile (the rule reaching the session through `@import` of `rules/workflow.md`, exactly as in round 2, no inline trailer line in any CLAUDE.md the round loads, no `attribution` keys set). Expected: the `docs(two-task): design` commit shows one `Co-Authored-By` line and `/cw:ship`'s Step 2 reports nothing. A duplicate there is evidence that location, not wording, is the variable, and reopens the inline-rule option with data.

## Research

### Codebase (Explore, haiku, 2026-09-21)

Verbatim findings, file:line.

- Trailer wording sites: `skills/build/SKILL.md:52` ("with the trailer the
  workflow rules define"), `:85` ("ending with the trailer the workflow rules
  define"), `:127-128` (reviewer commit check: "with the project's trailer");
  `skills/ship/SKILL.md:42` ("carrying the trailer the workflow rules
  define"), `:53` ("with the same trailer"), `:84` ("trailer as the rest of
  the series"); `rules/workflow.md:9-10` ("Every commit ends with the
  co-author trailer: / Co-Authored-By: Claude <noreply@anthropic.com>");
  `agents/implementer.md:30` ("whatever trailer the project's workflow rules
  define"); `CLAUDE.md:10-11` (project file: "Every commit ends with:" and
  the trailer); `tests/dedupe-phrases.txt:3` = `Co-Authored-By`;
  `tests/settings-keys.txt:14` = `attribution` (listed, unused by
  `settings.example.json`). The pre-plugin profile `CLAUDE.md` (round 1)
  said "Co-author line on every commit:" above the same trailer.
- Explore sites: `skills/design/SKILL.md:58-61` (built-in agent, `model`
  pinned to `haiku` per call); `WORKFLOW.md:22` ("spawns `Explore` (haiku)");
  `rules/orchestration.md:9` (haiku tier); `.github/workflows/ci.yml:59-60`
  requires the word `haiku` in `skills/design/SKILL.md`. No `agents/Explore.md`
  in the plugin; the pre-plugin one (`git show main:agents/Explore.md`) was a
  34-line user-scope agent: `name: Explore`, `model: haiku`, tools Read,
  Glob, Grep, and a short read-only method.
- Migration sites: `README.md:171-177` ("five skills, six agents, five hooks";
  "delete those user-scope copies, and remove their `hooks` entries");
  `README.md:9,100,154` reference `rules/orchestration.md` as a shipped file;
  `README.md:196-206` "Running the tests" lists hooks, size, dedupe and the
  settings cross-check; `README.md:89-90` end the Agents table, line 90 blank.
- Old installer manifest (`git show main:scripts/manifest.txt`):
  `agents/Explore.md`, `agents/design-reviewer.md`,
  `agents/direction-reviewer.md`, `agents/implementer.md`,
  `agents/researcher.md`, `agents/reviewer.md`, `hooks/design-scope-guard.sh`,
  `hooks/orchestrator-delegate-guard.sh`, `hooks/protect-branches.sh`,
  `hooks/protect-secrets.sh`, `hooks/syntax-check.sh`,
  `rules/orchestration.md`, and the five `skills/*/SKILL.md`. So "six agents,
  five hooks, five skills" is right and `rules/orchestration.md` is the
  missing item; three of the five old hooks no longer exist in the plugin.
- Test runner (`tests/run.sh`, 800 lines, `#!/bin/bash`, header: "Must work
  on macOS system bash 3.2 and bash 5, BSD and GNU coreutils: no
  mapfile/readarray, no ${var,,}, no associative arrays, no sed -i without a
  suffix, no grep -P. Deliberately no `set -u`"): `usage()` lists
  `{hooks|size|dedupe|scan|all}`; `main()` dispatches by first word;
  `cmd_all()` runs `cmd_hooks`, `cmd_size`, `cmd_dedupe`,
  `check_settings_keys`, then `cmd_scan` only when `CW_SCAN_PATTERNS` is set
  (else prints `all: scan: skipped (...)` and records `SKIPPED`), builds a
  `summary` of `all: <step>: PASS|FAIL|SKIPPED` lines and returns 1 on any
  FAIL. `ROOT` is derived from the script's own location. Size caps 150
  lines per file in `skills/`, `agents/`, `rules/`, 200 for the design and
  build skills, `WORKFLOW.md` ≤ 200, skill `description`+`when_to_use` ≤ 1536
  chars; total byte budget `BASELINE_BYTES=73738` for skills+agents+rules
  (`bash tests/run.sh size` on 2026-09-21: 54112 bytes, 73.4%); dedupe = each
  phrase in `tests/dedupe-phrases.txt` in at most one file across `skills/`,
  `agents/`, `rules/` (case-insensitive fixed string); settings-keys =
  top-level keys of `settings.example.json` ⊆ `tests/settings-keys.txt`.
  README, CLAUDE.md, tests/ and .github/ are in no `run.sh` scope.
- CI (`.github/workflows/ci.yml`): ubuntu job — `actions/checkout@v4` with
  no `fetch-depth` (shallow, so no `main`/`origin/main` ref), `shellcheck -x
  hooks/*.sh tests/run.sh`, `jq empty` on the three JSON files, `bash
  tests/run.sh all`, hygiene greps over `skills agents rules` (banned phrases
  `opus needs|do not trust|be decisive|read all files fresh|
  claude-design-active|claude-orchestrator-active`, whole-word
  `NEVER|ALWAYS|MUST|CRITICAL`, `under 50 lines`, disallowed agent
  frontmatter keys, required agent keys `model tools effort maxTurns`,
  internal-path references in skills, the `haiku` word in the design skill,
  the LICENSE-derived name absent from prompts and docs), then `claude
  plugin validate .`; macOS job re-runs `run.sh hooks` under bash 3.2.
- Current sizes: `skills/build/SKILL.md` 179, `skills/ship/SKILL.md` 118,
  `rules/workflow.md` 36, `README.md` 217, `WORKFLOW.md` 130, `CLAUDE.md` 17.
- Version: `.claude-plugin/plugin.json:3` = `1.0.0`; `README.md:210` = `### 1.0.0`.
- Recent intent: `aab9b0b refactor(skills)`, `89b8a90 refactor(rules): one
  home per rule`, `ddccf56 docs: plugin install story`, `bb85af9
  fix(settings)` — the lean rewrite that introduced the indirection "the
  trailer the workflow rules define" (the trailer text moved from inline
  skill prose to the rules file to satisfy the one-file dedupe rule).

### Docs and API currency (cw:researcher, sonnet, 2026-09-21; installed CLI 2.1.278)

- **`attribution` settings.** Documented on the settings reference
  (https://code.claude.com/docs/en/settings-reference, fetched directly this
  session): `attribution.commit` — "Change or hide the trailer Claude Code
  adds to commits"; `attribution.pr` — "Change or hide the attribution line
  in pull request descriptions"; `attribution.sessionUrl` — "Omit the
  claude.ai session link from cloud and Remote Control commits";
  `includeCoAuthoredBy` — "Deprecated; use `attribution` to hide or change
  commit and PR attribution". Confidence high for those four rows. The
  researcher also quoted "`commit` | Attribution for git commits, including
  any trailers. Empty string hides commit attribution" and "The `attribution`
  setting takes precedence over the deprecated `includeCoAuthoredBy`
  setting", attributed to the settings page
  (https://code.claude.com/docs/en/settings). That page was restructured:
  today it covers files and precedence only (fetched twice on 2026-09-21,
  zero matches for "attribution"); the quoted rows match an earlier version
  of it, as reproduced in issues #69614 and #19176, and issue #45137 shows
  `commit` handled as a string template in the CLI. So the two sentences are
  historical rather than current docs, consistent with the reference rows
  above. `attribution.commit` is the template for the trailer the harness
  adds (that the reminder text is rendered from it is inferred), and the
  `Claude-Session:` line is a separate switch (`sessionUrl`), only emitted in
  cloud and Remote Control sessions — which includes a local session followed
  from another device. Used here only to justify dropping the settings task
  and to suggest a profile-side trial during the hands-on check.
- **Known harness bugs around these keys.** Issue #45137 (2026-04, self-
  reported across several versions): an empty `attribution.commit` did not
  stop the co-author trailer because a hardcoded prompt block asked for it;
  issue #77830 / #41873: an empty `commit` template did not suppress the
  session line, only `attribution.sessionUrl: false` (or
  `CLAUDE_CODE_SUPPRESS_SESSION_ATTRIBUTION=1`) did. Confidence medium-high
  for the pattern; not reproduced on 2.1.278.
- **Precedence of a CLAUDE.md rule over the reminder** is stated by the
  reminder text itself (verified live this session: "the user's own
  instructions about these lines, such as a CLAUDE.md or memory rule, take
  precedence over this reminder, but do not add attribution lines this
  reminder leaves out"), not by a docs page. Open issue #92169 (2026-09-04, no
  maintainer reply) reports the model treating the reminder as outranking a
  standing CLAUDE.md preference — the same symptom as finding 1. A web
  summary claiming a fix in 2.1.275 could not be found in the raw CHANGELOG:
  unverified, treated as false. Whether an `@import`ed rules file reads as
  "the user's own CLAUDE.md" to the model is undocumented; the import is
  presented to the model under the CLAUDE.md heading, which is the plan's
  working assumption and the thing criterion 9 tests.
- **Agent precedence and the built-in `Explore`.** Sub-agents doc
  (https://code.claude.com/docs/en/sub-agents): "A user or project subagent
  named `Explore` overrides the built-in and keeps its own `model` field, so
  define one with `model: haiku` to keep exploration on a lower-cost model."
  Resolution order, highest first: managed settings, `--agents`, project
  `.claude/agents/`, user `~/.claude/agents/`, a plugin's `agents/`. Plugins
  reference (https://code.claude.com/docs/en/plugins-reference): plugin
  agents load under their scoped name, "`agents/reviewer.md` in a plugin
  named `my-plugin` loads as `my-plugin:reviewer`". Whether a plugin agent
  could replace a built-in is not stated; namespacing plus lowest precedence
  make it the safe reading that it cannot. Confidence high for the user-scope
  override, low (inferred) for the plugin limit — the README wording states
  only the documented parts.
- **Do subagents see the reminder?** Docs: a non-fork subagent gets "the
  agent's own prompt plus environment details that Claude Code appends, not
  the Claude Code system prompt". Issue #77830 reports the session-link
  directive riding in the Bash tool description for subagents too. Not
  documented either way; consistent with the observed asymmetry (orchestrator
  doubled, implementers exact).
- **Version.** `plugin.json` `version` is optional semver; when set, users
  get updates only when the string changes (plugin-marketplaces doc). No
  bump is required before a first release; fix-ups before 1.0.0 stay 1.0.0.

### Best practices (cw:researcher, sonnet, 2026-09-21)

- **Git and GitHub do not dedupe raw trailers.** `git interpret-trailers
  --if-exists` (default `addIfDifferentNeighbor`) only acts when something
  invokes it; a message typed with two `Co-Authored-By` lines keeps both
  (https://git-scm.com/docs/git-interpret-trailers). GitHub renders one
  co-author avatar per line; with the `noreply@anthropic.com` address it
  resolves to no account, so the duplicate is cosmetic, not an identity
  problem (dev-common issue #259, 2026-09-21; Crash Override knowledge base,
  2026-05). Same-email-different-name collapsing is undocumented.
- **A checked-in prose rule is the practitioner-standard fix.** One
  organisation resolved the identical fleet-wide symptom with a CLAUDE.md
  rule alone, forward-only, no hook and no history rewrite, reasoning that
  "the harness's own instruction says a user's CLAUDE.md or memory rule takes
  precedence over it. So a checked-in rule is both correct and sufficient"
  (dev-common #259). A peer project hit the failure mode this plan avoids:
  two governance texts prescribing different literal strings for the same
  line, "a dev receiving both cannot satisfy either" — pick a side in the
  governance text (objectstack #19202, 2026-09-19). Adopted for the wording;
  the plan adds a mechanical check on top because the orchestration rules
  require limits to be checked by script, and because the plan's own
  validation harness missed the duplicate by counting exact lines only.
- **Deterministic enforcement exists but sits in git, not in prompts:** a
  `commit-msg` hook stripping or normalising trailers (e.g. `sed
  '/^Co-Authored-By:.*<noreply@anthropic.com>/d'`) is the only mechanism with
  documented reliability (issue #45137 workaround; Crash Override). A plugin
  cannot install git hooks into adopters' repos; a Claude `PreToolUse` hook
  rewriting `git commit` commands would be a fourth hook script — out of scope
  for a fix-up round. The `tests/run.sh trailers` step is the in-reach
  equivalent: detection in the gate every push already passes through.
- **Literal beats indirect for agents.** Practitioner consensus: models "take
  instructions quite literally", so leave "no room for interpretation";
  template-based, schema-constrained prompts are recommended for reliability.
  No controlled study measures "exactly one … nothing else" against an
  indirect "the trailer the rules define" for this task; the closest study
  (arXiv 2508.01523, code-edit prompting) is an analogy only. Treated as a
  reasonable inference, not a proven result.
- **Contrarian angles, logged not adopted:** (a) let the harness name the
  real model for provenance — countered by model names drifting or being
  wrong in immutable history (objectstack #19202); (b) emit no AI co-author
  line at all, since tooling treats it as an authorship claim (issue #66602).
  The rule keeps the fixed, model-free trailer the project already uses.
- **Migration section pattern** (matthewswong.com, 2026, a Claude Code
  dotfiles-to-plugin migration): enumerate every installed artifact by type,
  give a keep/delete decision per item, warn that "hook entries merge across
  settings levels rather than replacing each other … a plugin's copy is
  counted separately from a settings copy" (both fire), and verify again
  after deleting the originals (`/hooks` shows per-event counts and sources).
  T3 follows that shape.

# Tasks

Four commits plus one verification-only task. T1–T3 own disjoint files and
run together; T4 runs after them, because it rewrites `tests/run.sh`, the
script their verifications execute; T5 runs last.

Note to the `/cw:build` orchestrator, for Phase 0 step 3: this round runs on
the existing `feat/cw-plugin` release branch — the files it fixes exist only
there, and every series check uses `main..HEAD` on it. Do not create
`fix/fixups-1-0-0` from `main`. Invoke the build as `/cw:build fixups-1-0-0
continue` with `feat/cw-plugin` checked out, which reuses the current branch;
no task commit exists yet, so nothing is skipped.

Note to the `/cw:build` orchestrator, for T5: its series check has no owning
file. If it fails on a specific commit, do not iterate T5 — fix that commit's
message at the checkpoint (an amend when it is `HEAD`, otherwise an
autosquash fixup; the branch is unpushed), re-run T5's verification
yourself, and report the fix in the checkpoint summary. The same applies
when a `continue` run re-verifies T1, T2 or T3 after T4 has landed and their
closing `bash tests/run.sh all` fails only on its `trailers` line: that is a
commit-message problem, not a defect in the task. Run this build in auto
mode: the verifications use `mktemp`, `cp`, `grep` and `test`, which the
build skill does not pre-approve for an `acceptEdits` session.

Note to the `/cw:build` orchestrator, for Phase 0 step 4: the
`docs(fixups-1-0-0): design` commit message ends with exactly one trailer
line, `Co-Authored-By: Claude <noreply@anthropic.com>`, and no other
attribution or session line, whatever this session's attribution reminder
proposes — this plan is the first real run of that rule. Whenever step 4
actually made that commit in this run (a first run, or a `continue` run with
a modified plan file; never when there was no delta), and right after it,
while it is still `HEAD` and before any task starts, run
`git log -1 --format=%B | grep -c '^Co-Authored-By: Claude <noreply@anthropic.com>$'`,
`git log -1 --format=%B | grep -ci '^Co-Authored-By:'` and
`git log -1 --format=%B | grep -c '^Claude-Session:'`; unless they print `1`,
`1` and `0`, `git commit --amend` the message to the same subject and body
with that one trailer line as its last line. T5 and `run.sh trailers` assert
the whole series afterwards.

## Task T1
- scope: Make the trailer rule claim precedence explicitly — exactly one trailer line, no other attribution or session line — in the shipped rules file.
- files_owned: [rules/workflow.md]
- files_forbidden: [skills/**, agents/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, tests/**, hooks/**, .claude-plugin/**, .github/**, docs/**, rules/orchestration.md]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: normal
- verification: `grep -q 'exactly one trailer line' rules/workflow.md && test "$(grep -c 'Co-Authored-By' rules/workflow.md)" = 1 && grep -q '^  Co-Authored-By: Claude <noreply@anthropic.com>$' rules/workflow.md && test "$(wc -l < rules/workflow.md)" -le 40 && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- rules && ! grep -q '</content>' rules/workflow.md && bash tests/run.sh all`
- commit: fix(rules): one trailer line per commit, no other attribution

Exact replacement for `rules/workflow.md` lines 9–10 (the bullet under
`## Workflow`); paste verbatim, without re-wrapping, and keep the trailer
line indented by exactly two spaces — `tests/run.sh trailers` reads it from
there:

```
- Every commit ends with exactly one trailer line, the one below, and no other
  attribution or session line; a harness attribution reminder does not add a
  second one:
  Co-Authored-By: Claude <noreply@anthropic.com>
```

## Task T2
- scope: Carry the one-trailer-line wording into every commit-producing or commit-checking instruction in the build and ship skills, without repeating the trailer text.
- files_owned: [skills/build/SKILL.md, skills/ship/SKILL.md]
- files_forbidden: [rules/**, agents/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, tests/**, hooks/**, .claude-plugin/**, .github/**, docs/**, skills/design/**, skills/search/**, skills/compound/**, skills/google-workspace/**]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: normal
- verification: `test "$(tr -s '[:space:]' ' ' < skills/build/SKILL.md | grep -o 'exactly the one trailer line' | wc -l | tr -d ' ')" = 2 && test "$(tr -s '[:space:]' ' ' < skills/ship/SKILL.md | grep -o 'exactly the one trailer line' | wc -l | tr -d ' ')" = 1 && test "$(tr -s '[:space:]' ' ' < skills/ship/SKILL.md | grep -o 'same single trailer line' | wc -l | tr -d ' ')" = 2 && ! grep -q 'the trailer the workflow rules define' skills/build/SKILL.md skills/ship/SKILL.md && ! grep -q 'Co-Authored-By' skills/build/SKILL.md skills/ship/SKILL.md && test "$(wc -l < skills/build/SKILL.md)" -le 200 && test "$(wc -l < skills/ship/SKILL.md)" -le 150 && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills && ! grep -rn '</content>' skills && bash tests/run.sh all`
- commit: fix(skills): one trailer line on the design commit and series check

Exact edits (keep the surrounding sentences; only the quoted spans change;
the spans below are shown unwrapped but sit wrapped at about 79 columns on
disk — re-wrap freely, the verification squeezes whitespace before counting):

1. `skills/build/SKILL.md` Phase 0 step 4 — replace "make one commit,
   `docs(<slug>): design`, with the trailer the workflow rules define." with:
   "make one commit, `docs(<slug>): design`, ending with exactly the one
   trailer line the workflow rules define and no other attribution or session
   line (a harness reminder proposing a second co-author line yields to that
   rule)."
2. `skills/build/SKILL.md` Phase 2 item 6, inside the quoted implementer
   instruction — replace "ending with the trailer the workflow rules define,"
   with: "ending with exactly the one trailer line the workflow rules define
   and no other attribution or session line,".
3. `skills/build/SKILL.md` Phase 3 commit check — replace "with the project's
   trailer, touching only `files_owned`;" with: "with exactly the project's
   one trailer line (a second co-author line or a session line is malformed),
   touching only `files_owned`;".
4. `skills/ship/SKILL.md` Step 2 first bullet — replace "carrying the trailer
   the workflow rules define." with: "carrying exactly the one trailer line
   the workflow rules define; a second co-author line or a session line is a
   malformed message — report it and suggest a rebase."
5. `skills/ship/SKILL.md` Step 2 last bullet — replace "offer to commit it now
   as `docs(<slug>): design` with the same trailer." with: "offer to commit
   it now as `docs(<slug>): design` with the same single trailer line."
6. `skills/ship/SKILL.md` Step 4 — replace "in one atomic `docs:` commit with
   the same trailer as the rest of the series." with: "in one atomic `docs:`
   commit with the same single trailer line as the rest of the series."

## Task T3
- scope: Rewrite the README migration section as a keep/delete list with a verify step, explain the built-in Explore agent with a copyable haiku override after the Agents table, and name the trailer check in the tests section.
- files_owned: [README.md]
- files_forbidden: [skills/**, agents/**, rules/**, WORKFLOW.md, CLAUDE.md, settings.example.json, tests/**, hooks/**, .claude-plugin/**, .github/**, docs/**]
- depends_on: [none]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `grep -q 'agents/Explore.md' README.md && grep -q 'the old manifest put five skills' README.md && grep -q 'claude plugin list' README.md && grep -q 'hook once' README.md && grep -q 'ships no agent by that name' README.md && grep -q '^name: Explore' README.md && grep -q '^tools: Read, Glob, Grep$' README.md && tr -s '[:space:]' ' ' < README.md | grep -q 'per-commit trailer check' && ! grep -q 'delete those user-scope copies' README.md && grep -qi migration README.md && grep -q '1.0.0' README.md && ! grep -qE 'install.sh|merge-settings|/setup' README.md WORKFLOW.md && ! grep -rnE '/(Users|home)/' README.md && ! grep -q '<you>' README.md && ! grep -q '</content>' README.md && bash tests/run.sh all`
- commit: fix(readme): migration keeps Explore override, names trailer check

The eight positive greps up to `per-commit trailer check` match only the
new text, and the negative grep on `delete those user-scope copies` holds
only after the rewrite; the remaining greps are regression guards,
pre-satisfied today. Paste the two fenced blocks verbatim, without
re-wrapping — their greps are line-bound; the tests sentence may be
re-wrapped, its grep squeezes whitespace.

Exact replacement for the section `## Migration from the old installer`
(README.md lines 171–177), heading kept:

~~~
## Migration from the old installer

If you previously installed this project's files directly into `~/.claude`
rather than as a plugin, the old manifest put five skills (`build`,
`compound`, `design`, `search`, `ship`), six agents, five hooks and
`rules/orchestration.md` there. To migrate:

- Delete the user-scope copies of the five skills, the five hooks and
  `rules/orchestration.md`, and remove the five `hooks` entries from
  `settings.json` — a plugin hook and a settings hook that share the same
  command both fire, so leaving the old entries in place double-runs them.
  Three of the old hooks (`design-scope-guard.sh`,
  `orchestrator-delegate-guard.sh`, `syntax-check.sh`) have no plugin
  replacement: 1.0.0 retires them on purpose.
- Delete the five agents the plugin now ships under the `cw:` prefix, but keep
  `agents/Explore.md` if you had it: a user-scope agent named `Explore`
  overrides the built-in one and keeps its own `model: haiku`, and this
  plugin ships no agent by that name (`/cw:design` pins haiku per call
  regardless).
- Replace any workflow rules pasted into your profile `CLAUDE.md` with the two
  imports shown above, and remove any other stray copies of the old layout.

Verify with `claude plugin list` (one `cw` entry), by checking that the
`skills/`, `agents/` and `hooks/` folders under your config dir hold none of
the old files (apart from `agents/Explore.md` if you kept it), and, inside a
session, with `/hooks`: each event lists the plugin's hook once, with no copy
from `settings.json`.
~~~

One paragraph and a fenced block inserted after the blank line that follows
the Agents table (after README.md line 90, so the table extension does not
absorb them as rows), followed by a blank line:

~~~
`/cw:design` also spawns the built-in `Explore` agent with `model: haiku` on
each call; the plugin ships no agent by that name — its agents load under the
`cw:` prefix. To keep every session's exploration on haiku, add a user-scope
override at `~/.claude/agents/Explore.md`; it replaces the built-in prompt
with yours, so keep it short and read-only:

```markdown
---
name: Explore
description: Fast, read-only codebase exploration. Locates files, symbols and patterns; reports paths and line numbers.
model: haiku
tools: Read, Glob, Grep
---
Locate what the request names with Glob and Grep, read only the ranges you
need to confirm a finding, and report file paths with line numbers. Do not
modify anything.
```
~~~

In `## Running the tests`, replace the sentence "Runs hook behavior,
file-size budgets, a cross-file phrase-duplication check, and the
`settings.example.json`/`tests/settings-keys.txt` cross-check." with:
"Runs hook behavior, file-size budgets, a cross-file phrase-duplication
check, the `settings.example.json`/`tests/settings-keys.txt` cross-check, and
a per-commit trailer check on `main..HEAD` (skipped, and reported as such,
only when neither `main` nor `origin/main` resolves)."

## Task T4
- scope: Add a `trailers` subcommand to the test runner that checks every non-merge commit in `main..HEAD` for exactly one trailer line equal to the one in `rules/workflow.md` and no session line, wire it into `all`, and give CI a full-depth checkout so it runs on pull requests.
- files_owned: [tests/run.sh, .github/workflows/ci.yml]
- files_forbidden: [skills/**, agents/**, rules/**, README.md, WORKFLOW.md, CLAUDE.md, settings.example.json, hooks/**, .claude-plugin/**, docs/**, tests/dedupe-phrases.txt, tests/settings-keys.txt, tests/fixtures/**]
- depends_on: [T1, T2, T3]
- agent: implementer
- model: sonnet
- risk: high
- verification: `shellcheck -x tests/run.sh && bash tests/run.sh hooks && bash tests/run.sh size && bash tests/run.sh dedupe && bash tests/run.sh all | grep -qE '^all: trailers: (PASS|FAIL|SKIPPED)$' && grep -q '^        with:$' .github/workflows/ci.yml && grep -q '^          fetch-depth: 0$' .github/workflows/ci.yml && grep -q 'trailers|all' tests/run.sh && grep -q 'exit 3' tests/run.sh && R=$(mktemp -d) && git -C "$R" init -q -b main && mkdir -p "$R/tests" "$R/rules" && cp tests/run.sh "$R/tests/run.sh" && cp rules/workflow.md "$R/rules/workflow.md" && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm base && git -C "$R" checkout -qb feat/x && echo a > "$R/a" && git -C "$R" add a && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm "$(printf 'feat: a\n\nCo-Authored-By: Claude <noreply@anthropic.com>')" && bash "$R/tests/run.sh" trailers && echo b > "$R/b" && git -C "$R" add b && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm "$(printf 'feat: b\n\nCo-Authored-By: Claude <noreply@anthropic.com>\nCo-Authored-By: Claude X <noreply@anthropic.com>')" && ! bash "$R/tests/run.sh" trailers && bash "$R/tests/run.sh" trailers 2>&1 | grep -q 'trailers: VIOLATION' && git -C "$R" -c user.name=t -c user.email=t@example.com commit -q --amend -m "$(printf 'feat: b\n\nCo-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: https://example.invalid/s')" && ! bash "$R/tests/run.sh" trailers && bash "$R/tests/run.sh" trailers 2>&1 | grep -q 'trailers: VIOLATION' && git -C "$R" -c user.name=t -c user.email=t@example.com commit -q --amend -m "$(printf 'feat: b\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>')" && ! bash "$R/tests/run.sh" trailers && bash "$R/tests/run.sh" trailers 2>&1 | grep -q 'trailers: VIOLATION' && git -C "$R" -c user.name=t -c user.email=t@example.com commit -q --amend -m "$(printf 'feat: b\n\nCo-Authored-By: Claude <noreply@anthropic.com>')" && bash "$R/tests/run.sh" trailers && D=$(mktemp -d) && git clone -q --depth 1 --branch feat/x "file://$R" "$D/c" && { bash "$D/c/tests/run.sh" trailers; test $? -eq 3; } && bash "$D/c/tests/run.sh" trailers | grep -q 'trailers: skipped' && bash "$D/c/tests/run.sh" all | grep -q '^all: trailers: SKIPPED$'`

This verification exercises the check on a scratch repo and only confirms
that `all` reports a `trailers` line on this branch; the real series is
asserted by T5, so a malformed commit elsewhere on the branch cannot fail
this task.
- commit: test: per-commit trailer check in run.sh, wired into all and CI

Specification (the implementer writes the code; follow the file's own
conventions — `local` declarations, `report`-style messages prefixed with
the subcommand name, `>&2` for errors, no bash-4 features, shellcheck clean):

1. `cmd_trailers()` — `[ $# -eq 0 ] || usage`. Read the expected line from
   the rules file: `expected=$(sed -n 's/^  \(Co-Authored-By: .*\)$/\1/p'
   "$ROOT/rules/workflow.md" | head -n 1)`; empty → print
   `trailers: cannot read the expected trailer from rules/workflow.md` to
   stderr and return 1 (fail closed: the rules file is in-repo). Skip path
   next: when `git -C "$ROOT" rev-parse --is-shallow-repository` prints
   `true`, or neither `main` nor `origin/main` resolves with `git -C "$ROOT"
   rev-parse --verify -q <ref>`, print `trailers: skipped (shallow
   repository or no main/origin/main ref)` on stdout (like `all: scan:
   skipped`) and return 3 — a shallow history can hide commits and would
   pass falsely. Otherwise the base ref is `main` when it resolves, else
   `origin/main`. For each commit from
   `git -C "$ROOT" rev-list --no-merges "$base..HEAD"` (read with a `while
   read -r` loop over process substitution, so a flag set inside persists),
   take `body=$(git -C "$ROOT" log -1 --format=%B "$c")` and require all
   three: `printf '%s\n' "$body" | grep -c -F -x -- "$expected"` equals 1;
   `printf '%s\n' "$body" | grep -ci '^Co-Authored-By:'` equals 1; and
   `printf '%s\n' "$body" | grep -q '^Claude-Session:'` fails. Otherwise
   print `trailers: VIOLATION <short sha> <subject>: expected exactly one
   trailer line "<expected>" and no session line` and set the failure flag.
   End: `trailers: OK (<base>..HEAD, <n> commits)` and return 0, or return 1.
2. `usage()` — `{hooks|size|dedupe|scan|trailers|all}`; the header comment's
   subcommand list gains `trailers`, and its exit-code line becomes exactly
   "Usage errors exit 2; check failures exit 1; a skipped trailers check
   returns exit 3; success exits 0." `cmd_trailers` uses `return 3`: `main`
   propagates it as the script's exit status when run directly, and
   `cmd_all` reads it as a return code.
3. `main()` — a `trailers)` arm before `all)`, same shape as the others.
4. `cmd_all()` — after the settings-keys block: run `cmd_trailers`, map exit
   0 → `all: trailers: PASS`, 3 → `all: trailers: SKIPPED` (not a failure),
   anything else → `all: trailers: FAIL` and `fail=1`, appending to `summary`
   exactly like the existing steps.
5. `.github/workflows/ci.yml` — in the ubuntu job only, right under line 15
   (`      - uses: actions/checkout@v4`, six spaces before the dash), add two
   lines: `        with:` (eight spaces, aligned with `uses:`) and
   `          fetch-depth: 0` (ten spaces), so the history is complete and
   `origin/main` resolves on pull-request and push runs; the macOS job is
   unchanged. No local gate parses this YAML, so the indentation is asserted
   by exact-match greps in the verification.

## Task T5
- scope: Release gate re-run on the finished series, verification only.
- files_owned: []
- files_forbidden: [**]
- depends_on: [T1, T2, T3, T4]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `bash tests/run.sh all && bash tests/run.sh all | grep -q '^all: trailers: PASS$' && shellcheck -x hooks/*.sh tests/run.sh && claude plugin validate . && jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json && test "$(for c in $(git rev-list --no-merges main..HEAD); do b=$(git log -1 --format=%B "$c"); { test "$(printf '%s\n' "$b" | grep -c '^Co-Authored-By: Claude <noreply@anthropic.com>$')" = 1 && test "$(printf '%s\n' "$b" | grep -ci '^Co-Authored-By:')" = 1 && ! printf '%s\n' "$b" | grep -q '^Claude-Session:'; } || echo "$c"; done | wc -l | tr -d ' ')" = 0 && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills agents rules && ! git grep -niE 'opus needs|do not trust|be decisive|read all files fresh|claude-design-active|claude-orchestrator-active' -- skills agents rules && ! git grep -niE 'under 50 lines' -- skills agents rules && ! git grep -nE '^(disallowedTools|permissionMode|mcpServers|hooks):' -- agents && test "$(for f in agents/*.md; do for k in model tools effort maxTurns; do grep -q "^$k:" "$f" || echo "$f:$k"; done; done | wc -l | tr -d ' ')" = 0 && ! git grep -niE '~/.claude/plans|gitattributes|linguist|git clean' -- skills && grep -q haiku skills/design/SKILL.md && OWNER=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1) && test -n "$OWNER" && ! git grep -qi "$OWNER" -- skills agents rules hooks tests WORKFLOW.md CLAUDE.md docs && test -z "$(git status --short)"`
- commit: none

T5 owns no file by design: a failed check here is reported at the checkpoint
with the failing command's output. A content failure belongs to the task that
owns the offending file (`/cw:build <slug> continue <task-id>`). A
trailer-only failure has no owning file: the named commit's message is fixed
at the checkpoint by an amend when it is `HEAD`, otherwise by an autosquash
fixup — the branch is unpushed, and this is the same remedy Phase 4 applies
to a task commit — and T5 is re-run.
