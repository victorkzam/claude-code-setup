# cw-plugin — /design artifact set (single-file form while in plan mode)

Slug `cw-plugin`. Plan mode allows exactly one writable file, so the five artifacts live here as
sections. At Step 6 the `/design` session itself splits them, by section, into five named
files under `<repo>/docs/plans/cw-plugin/`: `cw-plugin-research-codebase.md` (§R1),
`cw-plugin-research-docs.md` (§R2), `cw-plugin-research-bestpractices.md` (§R3),
`cw-plugin-design-draft.md` (§D) and `cw-plugin-tasks.md` (§T); `/build` commits them. The
live `/design` skill's routing rule would keep workflow designs about this repo local; the
maintainer's instruction of 2026-09-16 overrides it for this set (these files carry no
personal information), and the session executing Step 6 follows the instruction, not the
rule. P0 verifies the five files are present before `/build`.

Lineage: plan B of the 2026-09-16 split of a private predecessor design (rev 8.1). Plan A
(the maintainer's private profiles design) follows and links the published plugin. Scrub rule for every section: no absolute home paths (write `~/...`), no employer or
client names, no organisation ids, no private folder layouts or private design slugs; the repo
owner is "the maintainer", adopters are "the user"; the maintainer's name appears in this set
only through a check that derives it from `LICENSE` at run time.

---

## §D Design draft — cw-plugin rev 2

### D0 Revision log and review status
Risk: high (rewrites the workflow this repo's own build and ship depend on).
Rev 1 (2026-09-16) derived from the private predecessor design rev 8.1 (§D2.1–D2.4, D2.7,
D2.10; tasks T1–T6, T12) with the 2026-09-16 decisions applied (prefix `cw`; auto-updates on,
so no symlink mitigation; five-line CLAUDE.md with two imports; stack preferences move to
project CLAUDE.md files; Chrome not enabled by default; no subagent caps) and the non-blocking
findings of the PR #2 review folded (the `git clean` grant, the README reinstall claim, the
undocumented `.gitattributes` line, the unused `docs/research` allowlist, the NotebookEdit
refusal — all vanish with the rewrite). Research deltas folded before review: plugin agents
ignore `mcpServers`, `hooks` and `permissionMode` (§R2.7); no `if` on the safety hooks (§R3
row 6); profile-check never exits 2 (§R2.5); `disallowed-tools` on `/cw:build` replaces the
delegate guard (§R2.6, §R3 row 7); marketplace name distinct from the plugin name (§R3 row 4);
`claude plugin validate` in CI (§R3 row 5).
Rev 2 (2026-09-16) after review round 1 (direction PASS with advisories; design-reviewer
NO_VERDICT once, re-nudged; completeness NEEDS_WORK). Verified and folded: the scrub check
would have matched the committed artifacts (the name is now derived from `LICENSE` at check
time); P0 lacked the artifact write and forbade it with a clean-tree check (Step 6 of `/design`
writes the set; the check tolerates it); `disallowed-tools` is scoped to the invoking turn
(stated; follow-ups re-invoke the skill; binding verified at P0); the live `/build` has no
`continue` branch (resume and fix-ups restated); the live `/ship` gate needs a project
CLAUDE.md test line (CLAUDE.md becomes this repo's project file); jq absence would brick
sessions (hooks fail open with a warning); no main-push opt-out (`CW_ALLOW_MAIN_PUSH=1`);
implementer loses `acceptEdits` (documented requirement); rules delivery on the marketplace
path (documented); migration for installer users (README); `settings-keys.txt` moves to T6;
`scan --report`; fixture contract; haiku pin check; per-skill `allowed-tools`; `-w` greps;
root-anchored probes; a zero-count cluster leaves the dedupe list (16 phrases); kill switch;
profile-check edge cases; description cap; post-merge install check; pattern-file sanity;
allowlist for the build session; the allowlist narrowed to `docs/plans/cw-plugin/`; the cut
line. Deviations from rev 8.1, each a judgment call: the transcript-secret scanner leaves for
plan A (replaced by the generic `run.sh scan`, which also works outside git trees); the stale
private mirror is deleted at P0 and the `docs/plans` allowlist narrowed instead of ignored by
name; the template CLAUDE.md becomes a project CLAUDE.md; the release task is numbered T7.
Accepted risks (logged): `cw:google-workspace` stays in 1.0.0 (requested; a hold for 1.1 is the
maintainer's call at the checkpoint); `profile-check.sh` stays in the plugin (requested; its
user-visible channel is verified at P0); the CI `validate` step costs one minute per push; CI
is red between the T1 and T2 commits.
Round 2 (higher evidence bar; direction PASS with two advisories, design-reviewer NEEDS_WORK
on two verified majors, completeness NEEDS_WORK on one critical and three majors, all
verified and folded; a third round is not run, per the anti-ratchet rule): folded — Step 6
of `/design` (this session) writes the five named files under the maintainer's override of
the skill's carve-out and P0 counts them; each dedupe cluster has one named home (D2.2 table)
and the stack-preference cluster leaves the prompts; the jq-absent case runs with a scratch
bin that lacks jq; the project CLAUDE.md carries the commit conventions; the shell-wide main-push opt-out dropped (the kill switch
serves that case; a variable would silently follow the maintainer across profiles); the
allowlist admits `docs/plans/*.md` so future single-file designs in this repo are tracked,
`/cw:design` names the fix when a destination is ignored, the project CLAUDE.md states the
convention, and `run.sh all` scans tracked files whenever the private pattern file is set;
`run.sh scan` uses `git grep --untracked` so new files are scanned before their commit, and
index-dependent clauses are marked "(after the commit)"; the build skill's allowed-tools
check uses a portable pattern; no agent keeps a `skills:` preload; the G-load fixture is
copied into the scratch repo as `docs/plans/two-task.md`; plan A's slug left the header; P0
confirms the stale mirror is untracked, pre-approves the remaining verification commands,
and its probe also checks that a subagent can still write while `disallowed-tools` is active;
private paths left P0 (the pattern file is `<pattern file>`); loops in verifications became
single commands; the README no longer mentions the legacy `.gitattributes` marker. Review
status: converged after two rounds with every verified critical folded; the unverified
items (whether `claude plugin list` runs non-interactively under a scratch config dir — the
2026-09-15 probe says yes —, `plugin details` output shape, `memory: project` in plugin
agents) are checked at T1 and G-load.
P0 probe answers (2026-09-16, print mode with `--plugin-dir`, edits pre-approved): (1) the
SessionStart hook's `systemMessage` arrived in the session stream as a `system/hook_response`
event; (2) `disallowed-tools: Write, Edit` on an inline skill bound — the orchestrator's Write
was denied at call time; (3) it also propagated — a subagent spawned in that turn had no Write
tool at all ("Write is disabled for this session, in subagents as well as here"). Consequence
applied: `/cw:build` carries no `disallowed-tools`; its delegation boundary is the one-sentence
rule plus the review gate (D2.5, D5).

### D1 Context
The maintainer's Claude Code coding workflow (five skills, five agents, five hooks, rules, a
manifest installer with merge scripts and bats suites) was written for Opus 4.8 and now runs
under Fable 5.1, for which Anthropic recommends fewer, plainer instructions (§R3 row 1). The
same files exist in two divergent copies (the live profile and this repo, whose latest port is
PR #2). The maintainer needs one copy of the workflow shared by several Claude Code profiles
(config dirs), never per-profile copies, and wants the repo published in a state anyone can
adopt. Outcome of this plan: the repo IS a Claude Code plugin named `cw` — one checkout, loaded
in place by every profile through a `skills/cw` symlink, or installed from the repo's own
marketplace by adopters — with lean prompts, two safety hooks plus a profile check, one test
runner, CI, and no personal information anywhere. Profile setup (settings parity, MCP policy,
logins, symlinks) is plan A and out of scope here.

### D2 Approach

D2.1 The repo is the plugin `cw`. Add `.claude-plugin/plugin.json` (`name: cw`, `version:
1.0.0`, description, `author.name` = the maintainer's public GitHub display name, `repository`
= the public repo URL, `license: MIT`, keywords) and `.claude-plugin/marketplace.json`
(marketplace `claude-code-setup` — distinct from the plugin name, §R3 row 4 — with one plugin
entry `cw`, `source: "./"`), keep `skills/`, `agents/`, `hooks/`, `rules/`. Published identity,
deliberate and confirmed at the checkpoint: the maintainer's display name in `LICENSE` and
`plugin.json`, the GitHub handle in repository URLs; nowhere else. Three load paths, all
documented in the README: (a) in place — `ln -s <checkout> <config dir>/skills/cw` →
`cw@skills-dir`, SKILL.md edits live, agents and hooks after `/reload-plugins`; the
maintainer's path and the live-edit path, the least robust one (§R3 row 8), with the
real-directory fallback beside it (move the checkout under `skills/cw`, symlink back for
editing); (b) marketplace — `claude plugin marketplace add <owner>/claude-code-setup && claude
plugin install cw@claude-code-setup` (a copy in the plugin cache, updated with `claude plugin
update`; the reliable path for adopters); (c) trial — `claude --plugin-dir <checkout>`.
Commands `/cw:design`, `/cw:build`, `/cw:ship`, `/cw:compound`, `/cw:search`,
`/cw:google-workspace` (none collides with a built-in command, §R2.6); agents
`cw:implementer`, `cw:reviewer`, `cw:researcher`, `cw:design-reviewer`,
`cw:direction-reviewer`; hooks self-register through `hooks/hooks.json`. Model invocation:
design, search and google-workspace keep trigger phrases in `description` (or `when_to_use`)
and may be invoked by Claude; build, ship and compound keep `disable-model-invocation: true`.
The custom Explore agent is retired (a plugin cannot override the built-in; every Explore
call passes `model: haiku`). The installer, merge scripts, manifest, bats suites, `/setup`
skill and the CLAUDE.md template are retired; `CLAUDE.md` becomes this repo's own project
file (≤20 lines: what the repo is, `Tests: bash tests/run.sh all`, the commit conventions an
outside contributor needs — Conventional Commits and the `Co-Authored-By: Claude
<noreply@anthropic.com>` trailer, which the live `/build` and `/ship` read from the project
CLAUDE.md —, and the design-document rule of this repo: single-file designs `docs/plans/<slug>.md` are tracked;
a folder-style set needs its own `!docs/plans/<slug>/` allowlist lines before `/cw:build`) —
the project CLAUDE.md of a plugin repo is read when working in the repo, not by the plugin's
users.
Rules: `rules/workflow.md` (≤40 lines) and `rules/orchestration.md` (≤60 lines) are imported
by each profile's CLAUDE.md by absolute path — the README shows the five-line CLAUDE.md (one
identity line, a `Profile: <name>` line, the two `@` lines), says stack preferences belong in
project CLAUDE.md files, and states the import path per install mode (the checkout for (a);
for (b) the install path that `claude plugin details cw@claude-code-setup` prints, which
changes on update — or a separate clone kept for the rules; for (c) the checkout). A checkout
linked in place is the running workflow: edits on a branch are live at once (the intended
local proof); the checkout normally sits on `main`. Unsourced judgment: the two-rule-file
split.

D2.2 Lean-cut (§R3 row 1). Base copies: agents and the skills design, build, ship, compound,
search from the REPO at `main` after PR #2, carrying the live-ahead items of §R1.3 (the
`continue` hint and behaviour, the template allowlist, the anti-ratchet section);
`rules/orchestration.md` from LIVE; the two protect hooks from LIVE plus the repo's jq check
and minus the machine-specific exemption and the personal comment. Delete: emphatic capitals,
model-workaround lines, worker self-verification nudges, duplicated rules, sentinel
choreography and guard references, the plans-dir promotion machinery, the `.gitattributes`
write, the `git clean` grant, the maintainer's first name (prompts address "the user"; the
check derives the name from `LICENSE`). Keep: rationale, scope boundaries, project facts, the
JSON verdict contracts, the review-loop structure (reviewers report every finding; severity
filtering is the orchestrator's separate pass), the `model: haiku` pin on Explore calls.
Reviewer prompts may stay checklist-shaped. Fifteen rule clusters, each surviving in exactly
one prompt home (phrases in `tests/dedupe-phrases.txt`), with the home assigned here — an
operational rule lives in the skill that executes it, a policy every commit or session
inherits lives in `rules/`, and the hooks enforce the hard ones regardless of imports:
| Cluster | Home |
|---|---|
| never push main | ship (`rules/workflow.md` says "feature branches only" instead) |
| one atomic commit per task | build |
| co-author trailer (`Co-Authored-By`) | `rules/workflow.md` (build refers to "the trailer the workflow rules define") |
| PR only after the gate | ship |
| NO_VERDICT handling | `rules/orchestration.md` |
| ground truth over testimony | `rules/orchestration.md` |
| fresh-context counter-model reviewer | `rules/orchestration.md` |
| same-turn spawn | `rules/orchestration.md` |
| root-anchored check-ignore | design |
| search-source detection | search |
| three-angle methodology | search |
| two checkpoints | `rules/workflow.md` |
| explicit model per Agent call | `rules/orchestration.md` |
| context7 before APIs | `rules/workflow.md` |
| `/compound` never commits | compound |
Two former clusters leave the prompts entirely and are enforced by the categorical grep of
D6.4: sentinel choreography, and "functions under 50 lines" (a stack preference, which the
2026-09-16 decision moves to project CLAUDE.md files). Mechanical gates: every agent and rules file and the
skills search, compound, google-workspace ≤150 lines; the two orchestration skills design and
build ≤200 (they carry procedures and the verdict contracts; an implementer that cannot fit a
kept item reports the conflict rather than dropping it); `WORKFLOW.md` ≤200; each skill's
`description` plus `when_to_use` ≤1,536 characters (§R2.6); `tests/run.sh dedupe` finds each
phrase at most once across `skills/`, `agents/`, `rules/`; bytes of `skills/**/SKILL.md` +
`agents/*.md` + `rules/*.md` reported against the baseline 73,738 (the old set: five skills,
six agents, one rules file; the new set has six, five and two — a coarse gauge, reported not
gated) with a target of ≤60% and a hard fail only above 100%. Rollback: revert the lean-cut
commits (one per file group).

D2.3 Model and effort matrix (aliases only; unsupported effort clamps silently):
| Role | model | effort | maxTurns |
|---|---|---|---|
| Session orchestrator (`/cw:design` frontmatter) | inherits | `effort: xhigh` on design only | — |
| Explore (built-in, called with `model: haiku`) | `haiku` | none | — |
| cw:researcher | `sonnet` | `medium` | 30 |
| cw:implementer | `sonnet`; a task may set `opus` | `high` | 50 |
| cw:reviewer | `opus`; `risk: trivial` tasks may set `sonnet` | `high` | 20 |
| cw:design-reviewer | `opus` | `high` | 25 |
| cw:direction-reviewer | `opus` | `xhigh` | 15 |
| compound worker (inside `/cw:compound`) | `sonnet` | `medium` | — |
`tools:` allowlists (the researcher's names the exa and context7 tools it may use; MCP
access comes from the session), no `disallowedTools`, and none of `permissionMode`,
`mcpServers`, `hooks` (ignored in plugin agents, §R2.7); the three reviewers keep
`memory: project` (not listed among the ignored fields, not documented as honoured either —
checked at G-load); `cw:reviewer` adopts the JSON verdict schema `/cw:build` expects; no
agent carries a `skills:` preload (the researcher and the design-reviewer invoke `cw:search`
through the Skill tool when they need it; a preload by bare name is not known to resolve to a
plugin skill). Consequence of the dropped `permissionMode`:
`cw:implementer` cannot self-grant `acceptEdits`, so `/cw:build` expects a session in auto
mode or `--permission-mode acceptEdits` (README requirement; the maintainer runs auto mode).
No subagent caps.

D2.4 Hooks (all in `hooks/hooks.json`, commands `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<script>"`,
timeouts 10 s, no `if` field anywhere — `if` fails open on chained or unparseable commands,
§R3 row 6). Every script starts with the jq check: when `jq` is missing it prints `cw: jq not
found, hook skipped` to stderr and exits 0 (fail open with a visible warning rather than
blocking every tool call; jq is a stated requirement in the README).
- PreToolUse, matcher `Bash` → `protect-branches.sh` (LIVE base, exemption removed): fast
  path exits 0 when the normalised `tool_input.command` carries no `push` substring;
  otherwise splits the command on `&&`, `||`, `;`, `|`, `(`, `)`, backticks and newlines,
  with quotes and backslashes stripped first so a nested `sh -c`/`bash -c`/`eval` string
  and an escaped `\git` are scanned the same as a top-level command; `cd`/`pushd` and
  `git switch`/`checkout` earlier in the command are tracked so a later refspec-less
  push resolves against that state (state the text cannot resolve blocks with an
  explicit-refspec hint rather than falling through); blocks a `git push` whose
  destination is main/master by explicit refspec, by the tracked or resolved current
  branch, or by an upstream on main; blocks `--force`/`-f`/`+ref` and `--all`/`--mirror`;
  `--force-with-lease`, `--force-with-lease=<ref>` and `--force-if-includes` pass
  through to other destinations; everything else exits 0. Scope: a guardrail against
  the agent's own accidental pushes, not a sandbox; out of scope a command held in a
  variable and `eval`ed indirectly, an xargs-fed refspec, a shell wrapper or alias not
  named `git`, and `git -c k="v w"` before push (the embedded space defeats the word
  split); quoted prose that spells a push to main — inside `echo "…"`, a heredoc line,
  a `--body "…"` — is blocked as if it were the command. No opt-out switch (a
  shell-wide variable would silently follow the maintainer across profiles): a repo
  that pushes to main by convention uses the kill switch below or removes the entry
  from `hooks/hooks.json` in its fork; documented in the README.
- PreToolUse, matcher `Write|Edit|MultiEdit|NotebookEdit` → `protect-secrets.sh` (LIVE base
  incl. the template allowlist, which applies only after the directory checks — a
  `.env.example` under `secrets/`, `.ssh/` or `.aws/` stays blocked; reads `file_path //
  filePath // notebook_path`; empty path → allow).
- SessionStart, matcher `startup|resume|clear|compact|fork` → `profile-check.sh`, which always exits 0
  (exit 2 would block session initialisation, §R2.5) and always prints the JSON context line:
  reads `$HOME/.claude-profiles` (private, `<folder prefix>|<config dir>` per line, `#`
  comments and malformed lines skipped, `~` expanded; an absent file means no profile
  notices, not no output); longest-prefix match of the hook's `cwd`; collects notices —
  `wrong profile: <cwd> maps to <dir>` when the mapped config dir differs from
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` (both realpath'd), `missing import: <path>` for each
  `@` line of the active config dir's CLAUDE.md (lines starting with `@`; targets `~`-expanded,
  absolute as is, relative resolved against the config dir) whose target is missing; prints
  JSON `{"systemMessage": "<notices joined by '; '>", "hookSpecificOutput": {"hookEventName":
  "SessionStart", "additionalContext": "<the same text>"}}` when there are notices, otherwise
  `additionalContext` = `profile <basename of the config dir> · plugin cw` and no
  `systemMessage`. Claude sees the context either way; the P0 probe showed the `systemMessage` delivered to
  the session's system stream as a hook response (G-load records how the TUI renders it).
Two events, three commands. Kill switch, documented: `claude plugin disable cw@skills-dir`
(or `cw@claude-code-setup`) turns every hook off at once. Deleted: orchestrator-delegate-guard,
design-scope-guard, syntax-check (and every settings registration of them, which is plan A's
side; adopters of the old installer unregister theirs per the README migration section,
since a plugin hook and a settings hook both fire, §R2.5). No compact-time re-injection
(user-scope CLAUDE.md reloads after compaction); if plan A finds otherwise, one extra
SessionStart entry with matcher `compact` echoes the two import lines.

D2.5 Design documents and the skills. `/cw:design` runs Steps 0–5 in plan mode writing the
single plan file (wherever plan mode puts it: `docs/plans/` when `plansDirectory: docs/plans`
is set, else the default plans dir); on approval Step 6 moves it to `$ROOT/docs/plans/<slug>.md`
(`git mv` when tracked, `mv` otherwise), and when `git -C "$ROOT" check-ignore` says the
destination is ignored prints the fix by name (`the design file is ignored by .gitignore;
un-ignore docs/plans/<slug>.md before /cw:build`) instead of a bare warning; in a non-repo
folder it leaves the file where it is and says so. No sentinel, no
promotion, no mirror. Its Explore calls keep `model: haiku`. `/cw:build <slug> [continue
[<task-id>]]` reads the `## Tasks` section of `docs/plans/<slug>.md`, falls back to
`docs/plans/<slug>/<slug>-tasks.md` with `<slug>-design-draft.md` beside it (the layout this
build uses), commits the design file(s) as `docs(<slug>): design` through git when untracked
or modified (no `.gitattributes` write), hands each implementer only its task block, keeps the
ground-truth gate, counter-model review, NO_VERDICT retry and three iterations, and states
the delegation boundary in one sentence (the orchestrator edits no file; every change is an
implementer's) backed by the review gate — no guard hook and no tool restriction: the P0
probe showed that `disallowed-tools` on a skill also strips the tools from the subagents it
spawns, so it cannot be used on `/cw:build` (D0). The checkpoint text tells the user to resume
with `/cw:build <slug> continue [<task-id>]`; `continue` skips tasks whose `commit:` subject
already appears in `git log main..HEAD`.
`allowed-tools` per skill (a pre-approval list, not a restriction), without write tools on build: design `Read, Glob, Grep, Agent,
Write, Edit, Bash(git:*), Bash(mv:*), Bash(mkdir:*)`; build `Read, Glob, Grep, Agent,
Bash(git:*), Bash(bash:*), Bash(jq:*), Bash(shellcheck:*), Bash(claude plugin:*)` (plus the
language test runners it inherits from the old skill — the grants cover the verification
re-runs the orchestrator performs); ship `Read, Glob, Grep, Edit, Write, Bash(git:*), Bash(gh:*), Bash(bash:*),
Bash(npm:*), Bash(python:*), Bash(pytest:*), Bash(xcodebuild:*), Bash(make:*)`; compound
`Read, Glob, Grep, Edit, Write, Bash(git:*), Agent`; search and google-workspace none. `/cw:ship`
verifies the series, detects the quality gate with today's precedence plus one convention
(`tests/run.sh` present → `bash tests/run.sh all`), pushes, opens the PR, offers
`/cw:compound`; `/cw:compound` proposes process-rule edits and never commits. `/cw:search`
keeps source detection and the three-angle method; `--deep` points to the bundled
`/deep-research` (needs dynamic workflows, §R2.11). `/cw:google-workspace` is the live rule as
a skill, the four personal lines removed. Deliberate deviation from the multi-file convention
(§R3 row 9).

D2.6 Tests and CI. `tests/run.sh`, one subcommand per invocation, `BASELINE_BYTES=73738` as a
constant at the top:
- `hooks`: fifteen scratch cases fed on stdin under a scratch `HOME` and `CLAUDE_CONFIG_DIR`:
  push to main blocked (exit 2), feature push allowed (0), force push blocked (2), chained
  `cd x && git push origin main` blocked (2), `.env` write blocked (2), `.env.example`
  allowed (0), `secrets/.env.example` blocked (2), a `notebook_path` matching `*secret*`
  blocked (2), jq absent (a scratch `bin` holding links to every utility the hooks use except
  jq, run with `PATH=<scratch bin>`) → exit 0 and the warning on stderr,
  profile right → exit 0 and `additionalContext` starting with `profile `, wrong → exit 0 and
  `systemMessage` containing `wrong profile`, unmapped → exit 0 and no `systemMessage`,
  missing absolute import → exit 0 and `missing import` in both fields, relative import that
  exists → no notice, commented and malformed `.claude-profiles` lines ignored (assertions
  with `jq -e`).
- `size [<baseline-bytes>] [--only <dir,dir>]`: prints bytes and the percentage against the
  baseline (default the constant), fails above 100%; per-file caps (≤150 lines; ≤200 for
  `skills/design/SKILL.md` and `skills/build/SKILL.md`) apply to `skills/`, `agents/`,
  `rules/` — restricted to the `--only` directories when given —,
  `WORKFLOW.md` ≤200 and the skill `description`+`when_to_use` ≤1,536 characters are checked
  only in full mode.
- `dedupe [--only <dir>]`: each line of `tests/dedupe-phrases.txt` (15 case-insensitive fixed
  strings) occurs at most once across `skills/`, `agents/`, `rules/`.
- `scan [<pattern-file>] [--history [<range>]] [--report] [-p <path>] [-- <pathspec>...]`:
  the pattern file defaults to `$CW_SCAN_PATTERNS` (private, outside the repo; P0 exports it);
  inside a git tree `git grep --untracked -niEf` over tracked and untracked, non-ignored files
  (pathspecs pass through; new files are scanned before their commit); `-p <path>`
  scans any directory with `grep -rIniEf` (plan A's residue checks); `--history` counts hits
  in `git log -p <range>` (default `--all`); any hit exits 1 unless `--report`, which prints
  the hits and exits 0.
- `all`: `hooks`, `size` (full mode), `dedupe`, the settings-keys check (`comm -23 <(jq -r
  'keys[]' settings.example.json | sort) <(sort tests/settings-keys.txt)` empty), and `scan`
  over the tree when `$CW_SCAN_PATTERNS` is set (skipped with a notice otherwise, so CI and
  adopters run without it) — every `/cw:ship` in this repo therefore scans the tracked
  files, design documents included, before pushing.
`tests/settings-keys.txt` (written with the example settings in T6): the top-level keys of
the settings reference (§R2.13). `tests/fixtures/two-task-plan.md` in the single-file format:
two independent tasks, `risk: trivial`, `model: sonnet`, task 1 creates `a.txt` (verification
`test -f a.txt`, commit `feat: add a`), task 2 creates `b.txt` (`test -f b.txt`, `feat: add
b`). CI: job `ubuntu` (jq, shellcheck; `shellcheck -x hooks/*.sh tests/run.sh` at the default
severity — the new scripts are clean, so the old `--severity=error` floor goes; `jq empty` on
the three manifests; `bash tests/run.sh all`; the categorical greps of D6.4; `npm install -g
@anthropic-ai/claude-code && claude plugin validate .`, unauthenticated, §R3 row 5) and job
`macos` (`bash tests/run.sh hooks` on the system bash 3.2). CI runs on push and pull request,
so the red window between the T1 and T2 commits (the old bats and manifest still reference
the deleted guards) is never exercised; accepted. `claude plugin validate .` also runs
locally at T1 and T7.

D2.7 Docs and example settings. README (rewritten): what the plugin is; requirements
(Claude Code ≥ 2.1.269, git, jq — the hooks warn and stand down without it — and a session in
auto mode or `acceptEdits` for `/cw:build`); the three install paths with the fragility note
and the real-directory fallback; the command table; the five-line CLAUDE.md and the rules
import path per install mode; extra profiles (`CLAUDE_CONFIG_DIR`, the `~/.claude-profiles`
format, one shell alias per extra profile such as `alias claude-acme='CLAUDE_CONFIG_DIR=$HOME/.claude-acme
claude'` as the launch path that survives GUI launchers, `plansDirectory: docs/plans`);
`settings.example.json` as a starting point; what to adapt (models and effort in the agents,
the rules text, the deny list, the identity line); the kill switch, which is also the answer
for repos that push to main by convention;
migrating from the old installer (delete the user-scope copies of the five skills, six agents
and five hooks; remove their `hooks` entries from `settings.json`); `/cw:search --deep`
needing dynamic workflows; update and uninstall; running the tests; a changelog. (The
`.gitattributes` file the live `/build` leaves behind is legacy residue, mentioned nowhere in
the README.) The real owner replaces the `<you>`
placeholder in the marketplace command (adopters who fork adapt it). `WORKFLOW.md` (≤200
lines): the pipeline narrative and roles. `CLAUDE.md`: the project file of D2.1.
`settings.example.json`: `model: fable`, `effortLevel: high`, `plansDirectory: docs/plans`,
`permissions.defaultMode: auto`, generic deny rules (`.env`, `.env.*`, `**/.envrc`,
`~/.ssh/**`, `~/.aws/**`, `~/.config/gcloud/**`), `ask: Bash(gh pr create *)`, a short generic
allow list, `autoMode.allow: ["$defaults"]`, `enabledPlugins` for the three official LSP
plugins, no `hooks` key, no `_comment_*` keys.

D2.8 Publish. The repo is the plugin, so every commit must be publishable. T7 is a
verification-only gate (`commit: none`): it fetches `refs/pull/*/head`, runs `run.sh scan`
over the tree and `--history main..HEAD` (zero hits required) and `--history --all --report`
(older hits listed, history not rewritten), `claude plugin validate .`, shellcheck, `run.sh
all` and the temp-config-dir inventory check; the version and the changelog entry land with
T1 and T6. The live `/ship` opens the PR (the `ask` rule prompts;
its Step 1 flags the staged `hooks/protect-secrets.sh` as a `*secret*` match — expected,
waved through; the design is tagged `risk: high`, so it offers the 3-lens panel); CI green;
the maintainer merges on GitHub; never push main. After the merge, from a temp config dir:
`claude plugin marketplace add <owner>/claude-code-setup && claude plugin install
cw@claude-code-setup && claude plugin list` proves the published plugin installs. Evals
(`claude plugin eval`) are a follow-up.

D2.9 Out of scope, provided for plan A. The symlink is the maintainer's load path. Plan A
links `skills/cw` in each profile (its launch alias re-creates the link when auto-update has
removed it, §R2.9), writes the five-line CLAUDE.md and `~/.claude-profiles`, copies
`settings.example.json` into the profile template, validates profile settings with
`tests/settings-keys.txt`, and uses `run.sh scan -p <dir>` with its private pattern file for
residue checks outside git trees. Nothing in this repo names a profile other than the generic
`~/.claude-acme` example.

D2.10 Baseline, build driver and sessions. `/design` Step 6 writes this artifact set to
`docs/plans/cw-plugin/` (untracked until `/build` commits it). P0 (the maintainer, plain
shell): (1) merge PR #2 on GitHub, `git switch main && git pull`; (2) remove the stale private
mirror directory under `docs/plans/` (the only entry there besides `cw-plugin`; its canonical
archive lives in the private profile), `git checkout .gitignore`, `rm -f src.txt`; (3) create
the private pattern file (extended regexes, one per line: the home path, employer and client
names, organisation ids, private profile-dir names — NOT the public display name or handle),
export `CW_SCAN_PATTERNS=<its path>` in the shell that launches Claude Code, and prove the
file bites (it must match a local file known to carry private strings, and must not match
`LICENSE`); (4) pre-approve the verification commands for the
build session in the repo-local, ignored `.claude/settings.local.json`; (5) a two-minute probe
with `claude --plugin-dir` on a scratch plugin (answers recorded in D0); (6) `claude --version` ≥ 2.1.269, `jq`, `shellcheck`. Then
`/build cw-plugin` (the LIVE `/build` of the personal profile) creates `feat/cw-plugin` from
`main`, commits the artifact set (plus the `.gitattributes` line it insists on — accepted),
runs T1→T7 sequentially, stops at its checkpoint; G-load follows; then `/ship`. Interruption:
re-run `/build cw-plugin`, telling the orchestrator to reuse `feat/cw-plugin` and skip tasks
whose `commit:` subject already appears in `git log main..HEAD` (the live skill has no
`continue` branch). Fix-ups after G-load: fresh `fix(<scope>):` commits, one per file group.
Cut line: if T5 exhausts its three review iterations, ship 1.0.0 from T1, T2, T6 and T7 with
the prompts unchanged and land the lean cut as 1.1.0 on a second PR; plan A links either.
Every session launches from the repo root.

### D3 Files
Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`,
`hooks/profile-check.sh`, `rules/workflow.md`, `skills/google-workspace/SKILL.md`,
`tests/run.sh`, `tests/dedupe-phrases.txt`, `tests/settings-keys.txt`,
`tests/fixtures/two-task-plan.md`.
Modify: `.gitignore` (allow `.claude-plugin/`; narrow `docs/` to `docs/plans/*.md` and
`docs/plans/cw-plugin/`; drop the `scripts/`, `docs/research/` and `.claude/` allowlist
lines), the five agents, the five
skills, `hooks/protect-branches.sh`, `hooks/protect-secrets.sh`, `rules/orchestration.md`,
`README.md`, `WORKFLOW.md`, `CLAUDE.md` (template → project file), `settings.example.json`,
`.github/workflows/ci.yml`.
Delete: `agents/Explore.md`, `hooks/orchestrator-delegate-guard.sh`, `hooks/design-scope-guard.sh`,
`hooks/syntax-check.sh`, `scripts/` (six files), `tests/*.bats` (six), `tests/test_helper.bash`,
`tests/manual-setup-checklist.md`, `.claude/skills/setup/SKILL.md`. Local only: `src.txt`
(untracked, removed at P0).
Written by the live `/build`, not by a task: `docs/plans/cw-plugin/*` (this set) and
`.gitattributes`.

### D4 Dependencies
Claude Code ≥ 2.1.269 (installed 2.1.273); `jq`; `shellcheck` (local and CI); `git`; GitHub
Actions `ubuntu-latest` and `macos-latest`; node and npm on the ubuntu runner only (to
install the CLI for `claude plugin validate`). No runtime dependency on node.

### D5 Risks and mitigations
- Skills-dir plugin not discovered, or skills registered bare → T1 and T7 assert
  `cw@skills-dir` and the inventory under a temp `CLAUDE_CONFIG_DIR`; G-load runs the real
  session both with `--plugin-dir` and from a symlinked temp config dir; fallback documented
  in the README (a real directory under `skills/cw` with a symlink back for editing).
- `if:` fails open on chained or unparseable commands (§R3 row 6) → no `if`; the push guard
  splits the command on shell separators and checks every segment; `run.sh hooks` has a
  chained-command case. Cost: the hook runs on every Bash call (jq, milliseconds).
- A SessionStart exit 2 blocks session initialisation (§R2.5) → profile-check always exits 0
  and reports through `systemMessage` and `additionalContext`; the P0 probe showed
  `systemMessage` delivered as a hook response; Claude relays the context line as well.
- Missing jq → the hooks warn and exit 0 instead of blocking every tool call; README
  requirement; `run.sh hooks` covers the case. Accepted: no protection without jq.
- A future design in this repo lands in an ignored path → the allowlist admits
  `docs/plans/*.md`; `/cw:design` names the fix when a destination is ignored; the project
  CLAUDE.md states the convention; `run.sh all` scans tracked files for private strings
  whenever the maintainer's pattern file is set.
- A bad hook would block every Bash or write call in every linked profile → kill switch
  `claude plugin disable cw@skills-dir`; hooks are tested by `run.sh hooks` and G-load before
  merge; revert per commit.
- The orchestrator edits files itself during `/cw:build` (Fable 5 has overridden delegation
  rules under cost pressure, §R3 row 7) → the prose boundary plus the review gate, an
  accepted risk: the P0 probe showed `disallowed-tools` propagating to subagents, which rules
  it out, and the maintainer decided against guard hooks and sentinels.
- Plugin agents ignore `mcpServers`, `hooks`, `permissionMode` (§R2.7) → none used; the
  researcher's MCP tools come from the session's servers and are named in `tools:`; the
  implementer needs auto mode or `acceptEdits` at session level (README requirement).
- A file-write tool name missing from the matcher → `Write|Edit|MultiEdit|NotebookEdit`
  (unknown names are harmless in a regex matcher); `run.sh hooks` feeds both `file_path` and
  `notebook_path` shapes.
- Lean-cut regressions → per-file cap and dedupe only; bytes reported; round trip at G-load;
  revert per commit; the cut line of D2.10.
- The public repo leaks private strings through the artifacts themselves → the scrub rule of
  the header; `run.sh scan` runs over tracked files including `docs/`; the P0 sanity check
  proves the pattern file bites; reviewers check.
- Older refs (pull refs) already carry private strings → reported, not rewritten (they are
  already public).
- Rules cannot travel with a marketplace install (plugins expose no rules component, §R2.10)
  → README states the import path per install mode; the symlink path is the maintainer's.
- Adopters of the old installer get double-firing guards → README migration section.
- The live `/build` drives this build with the delegate and design-scope guards active →
  implementers are subagents (not guarded); the orchestrator's only write is the
  `.gitattributes` line, which the guard allows; the live secrets hook blocks Write/Edit on
  `hooks/protect-secrets.sh`, so T1 writes it with Bash (stated in T1's scope).
- The live `/build` pre-approves only git and language runners → P0 step 4 allowlists the
  verification commands in the repo-local settings; otherwise auto mode prompts.
- The live `/ship` would run pytest on `tests/` → the project CLAUDE.md states `Tests: bash
  tests/run.sh all` (precedence 2); its Step 1 `*secret*` match on the secrets hook is
  expected.
- CI is red between the T1 and T2 commits → accepted; CI runs only at push time.
- `claude plugin validate` in CI needs the npm package → one minute per push; accepted.
- Size target of 60% missed → reported; hard fail only above 100%.
- The checkout becomes the live workflow once plan A links it → branch discipline; the
  checkout sits on `main`; a half-saved edit is fixed by `git checkout` (accepted).

### D6 Success criteria
1. `claude plugin validate .` exits 0; `jq empty .claude-plugin/plugin.json
   .claude-plugin/marketplace.json hooks/hooks.json`; `jq -e '.name=="cw" and
   .version=="1.0.0"' .claude-plugin/plugin.json`; `jq -e '.name=="claude-code-setup" and
   .plugins[0].name=="cw" and .plugins[0].source=="./"' .claude-plugin/marketplace.json`.
2. Loading: `CFG=$(mktemp -d); mkdir -p "$CFG/skills"; ln -s "$PWD" "$CFG/skills/cw"; env
   CLAUDE_CONFIG_DIR="$CFG" claude plugin list | grep -q 'cw@skills-dir'`; `env
   CLAUDE_CONFIG_DIR="$CFG" claude plugin details cw@skills-dir` lists 6 skills, 5 agents and
   the hooks (2 events, 3 commands).
3. Gates: `bash tests/run.sh all` exits 0 (hook cases covering nested interpreters, an
   escaped git token, chained cd and branch changes, --all/--mirror, lease variants, an
   upstream on main under push.default=upstream, 100k-character timing, the secrets
   patterns and profile-check's error paths; 0 failed; the size ratio printed, target
   ≤60%; per-file caps; dedupe; settings keys); `shellcheck -x hooks/*.sh tests/run.sh`
   clean at the default severity; `wc -l < WORKFLOW.md` ≤ 200.
4. Categorical (tracked files): `! git grep -qniE 'opus needs|do not trust|be decisive|read
   all files fresh|claude-design-active|claude-orchestrator-active' -- skills agents rules`;
   `! git grep -qwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills agents rules`; `! git grep -qniE
   'under 50 lines' -- skills agents rules`; `! git grep -qnE
   '^(disallowedTools|permissionMode|mcpServers|hooks):' -- agents`; every agent has `model:`,
   `tools:`, `effort:`, `maxTurns:`; `! git grep -qniE '~/.claude/plans|gitattributes|linguist|git
   clean' -- skills`; `grep -q haiku skills/design/SKILL.md`; `N=$(sed -n 's/^Copyright (c)
   [0-9]* //p' LICENSE | cut -d' ' -f1); ! git grep -qi "$N" -- skills agents rules hooks
   tests WORKFLOW.md CLAUDE.md docs` (the maintainer's name appears only in `LICENSE`,
   `.claude-plugin/plugin.json` and README URLs); `bash tests/run.sh scan` exits 0 (tree,
   `$CW_SCAN_PATTERNS`).
5. Frontmatter: `grep -l 'disable-model-invocation: true' skills/*/SKILL.md | wc -l` = 3
   (build, ship, compound); `grep -q '^effort: xhigh' skills/design/SKILL.md`; `! grep -q
   '^disallowed-tools:' skills/build/SKILL.md`; `ls skills | tr '\n' ' '` = `build compound
   design google-workspace search ship `; `ls agents | wc -l` = 5.
6. Round trip (G-load, human). (a) From a scratch git repo under `/tmp` launched with
   `claude --plugin-dir <checkout>` in the logged-in profile: `/cw:design` and the other five
   `/cw:` skills are listed and the five `cw:` agents appear in `/agents`; `git push origin
   main` and `cd . && git push origin main` are blocked, a `.env` write is blocked; a dry
   `/cw:design` ends with `docs/plans/<slug>.md`; with the fixture copied into the scratch
   repo as `docs/plans/two-task.md`, a dry `/cw:build two-task` yields exactly two commits
   with the trailer, both authored through implementer subagents (the transcript shows one Agent call per task and no orchestrator Write or Edit). (b) From a temp config dir
   holding only `skills/cw -> <checkout>` (one-time login there), started in a folder mapped to
   another config dir by a scratch `~/.claude-profiles`: the six skills are listed and the
   `wrong profile` notice appears (record the channel).
7. Publish: `bash tests/run.sh scan --history main..HEAD` = 0 hits; `git fetch origin
   '+refs/pull/*/head:refs/remotes/origin/pr/*'` then `bash tests/run.sh scan --history --all
   --report` hits listed in the exit report; PR opened by `/ship`; CI green (both jobs);
   merged on GitHub; from a temp config dir `claude plugin marketplace add
   <owner>/claude-code-setup && claude plugin install cw@claude-code-setup && claude plugin
   list | grep -q 'cw@claude-code-setup'`.
8. Docs: README contains `skills/cw`, `marketplace add`, `--plugin-dir`, `.claude-profiles`,
   `plansDirectory`, `jq`, `plugin disable`, `acceptEdits`, a migration section and a
   five-line CLAUDE.md example; `! grep -q '<you>' README.md`; `! grep -qE
   'install.sh|merge-settings|/setup' README.md WORKFLOW.md`; `grep -q 'tests/run.sh all'
   CLAUDE.md && grep -q 'Co-Authored-By' CLAUDE.md && test $(wc -l < CLAUDE.md) -le 20`; `jq -e '.model=="fable" and
   .plansDirectory=="docs/plans" and (has("hooks")|not) and ([keys[]|select(startswith("_"))]|length)==0'
   settings.example.json`; `comm -23 <(jq -r 'keys[]' settings.example.json | sort) <(sort
   tests/settings-keys.txt)` empty.

### D7 Implementation plan
P0 → `/build cw-plugin` (live build, cwd = repo root): T1 manifest, hooks.json, hooks → T2
run.sh, phrases, CI, retire installer and bats → T3 rules → T4 agents → T5 skills, fixture →
T6 README (with the changelog), WORKFLOW, project CLAUDE.md, example settings, settings keys
→ T7 release gate (verification only) → `/build` checkpoint → G-load (human, both round trips; fix-ups as fresh `fix(<scope>):`
commits) → `/ship` (gate from the project CLAUDE.md; the `*secret*` match waved through) → CI
→ merge on GitHub → post-merge marketplace install check → `git switch main && git pull` →
plan A. Cut line per D2.10.
