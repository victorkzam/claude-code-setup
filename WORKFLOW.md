# Workflow

`cw` is a Claude Code plugin implementing a `/cw:design` -> `/cw:build` ->
`/cw:ship` pipeline: research-grounded planning, delegated implementation with
one atomic commit per task, and a verified, gated release. `/cw:compound`
closes the loop by feeding lessons back into project rules.

## Roles

| Who | Does |
|---|---|
| You | Approve the design, approve the commit series, review the PR |
| The orchestrating session (main thread) | Runs `/cw:design`, `/cw:build`, `/cw:ship`; never writes application code itself |
| `cw:researcher` (sonnet) | Web research with citations, read-only |
| `cw:implementer` (sonnet, opus for hard tasks) | Implements one task, makes its commit |
| `cw:reviewer` (opus) | Reviews an implementer's diff, read-only |
| `cw:design-reviewer` (opus) | Checks a draft design against the codebase and current docs, read-only |
| `cw:direction-reviewer` (opus, effort xhigh) | Checks the design targets the right problem, read-only |

## `/cw:design <description>`

Plan mode. Reads project context, spawns `Explore` (haiku) and
`cw:researcher` (sonnet) subagents in parallel to ground the plan in the real
codebase and current sources, drafts one plan file with a task list, then
loops `cw:design-reviewer` (fresh context each pass, until findings converge,
escalating after 5 iterations) followed by `cw:direction-reviewer` once.

The skill calls `ExitPlanMode` itself when the review loop converges — that
approval only ends drafting; it is not the real checkpoint. Plan mode writes
the draft (into `docs/plans/` when the profile sets
`plansDirectory: docs/plans`, else the default plans dir); on approval the
design step moves it to `docs/plans/<slug>.md` in the repo, which
`/cw:build` then reads.

**Checkpoint 1 (non-negotiable): you approve the plan file before anything
gets built.**

## `/cw:build <slug> [continue [<task-id>]]`

Execute mode (needs auto mode or `acceptEdits` — a plugin agent cannot grant
itself a permission mode). The orchestrating session:

1. Resolves the plan (`docs/plans/<slug>.md`, or the folder-layout fallback),
   creates the feature branch, commits the plan as `docs(<slug>): design`.
2. Reads the task list and works it in `depends_on` order, independent tasks
   in parallel, never re-decomposing it.
3. Delegates each task to a fresh `cw:implementer`, scoped to only that
   task's entry and its file ownership. The implementer makes exactly one
   atomic Conventional commit for its task — or, for a `commit: none` task
   (an unversioned or external target), verifies without committing.
4. Independently re-runs the task's own verification command and checks
   `git log` for the claimed commit before trusting an implementer's report —
   an implementer's exit report is evidence, not proof.
5. Spawns `cw:reviewer` — a different model tier than the implementer used —
   to review the diff fresh from disk. `NEEDS_WORK` respawns a new
   implementer with the feedback (up to 2 retries); a reviewer that returns
   no parseable verdict at all is retried once fresh, not treated as a pass
   or a fail.
6. Stops for your approval once every task's commit is in and the tasks-file
   quality gate passes.

`continue [<task-id>]` resumes a `/cw:build` run, skipping tasks whose commit
subject is already in `git log main..HEAD`.

**Checkpoint 2 (non-negotiable): you approve the commit series before any
PR.**

## `/cw:ship [title]`

Execute mode. Refuses to run on `main`/`master`. Verifies the commit series
against the plan's task list (no squashing, no catch-all commit), runs the
project's quality gate (`bash tests/run.sh all` when this repo owns the
gate), pushes the branch, and opens the PR with `gh pr create` only once the
gate is green. Ends by offering `/cw:compound`.

## `/cw:compound [range]`

Optional, user-driven, never folded into `/cw:ship`. Reads what just shipped,
extracts the handful of lessons actually worth keeping, proposes edits to the
project's CLAUDE.md or rules files, and applies only what you approve.
Process-rule edits from `/cw:compound` are never committed into the feature
PR that prompted them — they are their own change.

## `/cw:search [--quick|--deep] <query>`

Cross-references Context7, Exa, and WebSearch (whichever are available;
missing MCP servers degrade an angle to WebSearch, never a hard failure) into
one structured, citation-backed answer. `--deep` hands off to the bundled
`/deep-research` workflow, which needs dynamic workflows enabled.

## `/cw:google-workspace`

A reference playbook, not a pipeline step: hard-won routes and dead ends for
driving Google Docs/Drive from Claude, triggered when a task needs one.

## Rules

`rules/workflow.md` carries the process rules above (branch policy, commit
format, checkpoints, mode transitions) and is meant to be imported by a
profile's `CLAUDE.md`. `rules/orchestration.md` carries the model-routing
table (public aliases, route-up-for-hard-work, the workflow-fan-out
threshold) and the review-loop semantics (`NO_VERDICT` vs `NEEDS_WORK`,
counter-model review, ground-truth verification). If a rule and this file
ever disagree, the rules file wins.

## Hooks

Three hooks, registered by the plugin itself (`hooks/hooks.json`), fire in
every session the plugin is enabled in:

| Hook | Event | What it does |
|---|---|---|
| `protect-branches.sh` | PreToolUse (Bash) | Blocks a push whose destination is main/master, and any force push |
| `protect-secrets.sh` | PreToolUse (Write\|Edit\|MultiEdit\|NotebookEdit) | Blocks writes to `.env`, credentials, keys, and similar secret paths |
| `profile-check.sh` | SessionStart | Warns if the active profile doesn't match `~/.claude-profiles`, or if a `CLAUDE.md` `@import` target is missing |

A hook that exits non-zero is enforced, not advisory — CLAUDE.md conventions
get followed inconsistently; a `PreToolUse` hook that exits 2 blocks the call
outright. `claude plugin disable cw@<source>` turns all three off at once.

## Tests

`bash tests/run.sh all` runs everything: hook behavior (`hooks`), file-size
budgets against the tracked baseline plus the `WORKFLOW.md` and
description-length caps (`size`), a cross-file phrase-duplication check
(`dedupe`), the `settings.example.json` / `tests/settings-keys.txt`
cross-check, and, if `$CW_SCAN_PATTERNS` points at a pattern file, a scan for
private strings in the tracked tree. Each subcommand also runs standalone
(`hooks`, `size`, `dedupe`, `scan`, `trailers`), and CI (`.github/workflows/ci.yml`) runs
the same `all` target on every push and PR.
