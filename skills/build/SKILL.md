---
name: build
description: "Implement an approved design by orchestrating subagents. Consumes the plan's task list, delegates each task to an implementer, verifies the result against git and the task's own verification command, reviews with a second model, and stops at a checkpoint before any PR."
disable-model-invocation: true
argument-hint: "<slug> [continue [<task-id>]]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Agent
  - Bash(git:*)
  - Bash(bash:*)
  - Bash(jq:*)
  - Bash(shellcheck:*)
  - Bash(claude plugin:*)
  - Bash(npm:*)
  - Bash(python:*)
  - Bash(pip:*)
  - Bash(pytest:*)
  - Bash(swift:*)
  - Bash(xcodebuild:*)
---

# Build — Orchestrator Pattern

You are the orchestrator: you edit no file, and every change in this run is an
implementer's — the review gate is what enforces that. You do not re-decompose
the design either; `/cw:design` already wrote the task list. Consume it,
delegate, verify, review, iterate, stop.

Execute mode. Implementers need the session in auto mode or `acceptEdits` to
write without a prompt per edit. Starts only after the design checkpoint.

## Input
$ARGUMENTS — `<slug>`, optionally followed by `continue` and a task id.

## Phase 0: Pre-flight
1. **Resolve the plan.** `ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`;
   read `$ROOT/docs/plans/<slug>.md`. Absent → fall back to the folder layout
   `$ROOT/docs/plans/<slug>/<slug>-tasks.md` with `<slug>-design-draft.md`
   beside it; that pair has to be complete — both present and non-empty — or
   refuse and say which half is missing. Neither shape → "No plan found for
   `<slug>` — run `/cw:design` first." Do not invent a task count.
2. **Clean tree**, except an untracked or modified design file for this slug —
   that is what step 1 just read, not build drift. Stash with plain `git stash`
   only: `-u` or `-a` would sweep that file in, leaving step 4 no delta.
3. **Branch** `feat/<slug>` or `fix/<slug>` from `main`; on `continue`, reuse
   the existing branch.
4. **Commit the design** when its file is untracked or modified: stage it by
   explicit pathspec (the plan file, or the folder-layout pair plus its
   research files), never `git add .`, and make one commit, `docs(<slug>):
   design`, ending with exactly the one trailer line the workflow rules define
   and no other attribution or session line (a harness reminder proposing a
   second co-author line yields to that rule). No delta → skip silently. Not a
   repo, or the commit fails → report and carry on with the file uncommitted,
   no retry loop. This commit is orchestrator-authored and is excluded from
   every per-task commit count below.
5. Read the project's CLAUDE.md for conventions.

## Phase 1: Consume the task list
Collect every `## Task <id>` block in the plan file (the folder layout keeps
them in `<slug>-tasks.md`) and execute exactly those — one or many.

- Run them in `depends_on` order. Tasks with no dependency between them are
  independent by construction (disjoint `files_owned`): spawn them together,
  several Agent calls in one message, synchronously. Dependents run in
  sequence.
- A task's model is whatever its `model:` field says (`sonnet` by default,
  `opus` where stated). Do not re-derive it.
- **`continue`**: read `git log --format=%s main..HEAD` and skip every task
  whose `commit:` subject is already there. Given a `<task-id>`, start at that
  task and skip everything before it.

## Phase 2: Implement — delegate to `cw:implementer`
One implementer per task, the Agent call's `model` taken from the task.
Context-pin it: its own task block and the relevant design excerpt, never the
whole plan. The prompt carries:

1. The task's `scope` — one sentence on what to build and why.
2. Only the design excerpt this task covers.
3. `files_owned` and `files_forbidden` — it reads current contents itself; do
   not paste file bodies into the prompt.
4. A reference pattern: "follow the pattern in `<existing_file>:<symbol>`".
5. The task's `verification` — exact command(s) and expected result.
6. The task's `commit:` line, plus: *"When the work is done and `verification`
   passes, make exactly one atomic commit from this `commit:` line, in
   Conventional format, ending with exactly the one trailer line the workflow
   rules define and no other attribution or session line, staging only
   `files_owned` by explicit path. One task, one commit. Do not push."* Omit
   this entirely for a `commit: none` task (an unversioned or external target)
   — that task is verification-only.
7. A required exit report: its final message ends with a fenced JSON block
   matching exactly this schema:
   ```json
   {"status": "success|partial|failed", "commit_sha": "<sha>", "files_touched": ["..."], "verification_output": "...", "unresolved_issues": ["..."]}
   ```
   The report is testimony, not proof; the gate below checks it.

## Phase 2→3 gate: check the report against the repo
Completion is what git and real command output show, not what a subagent says.
Before any reviewer is spawned:

- **`commit: none` task** — re-run its `verification` yourself and compare the
  real output with the reported `verification_output`. No commit to check.
- **Any other task** — in `git log --oneline main..HEAD` (or the task's
  expected range), confirm `commit_sha` exists, is Conventional-format, and
  touches only `files_owned`; then re-run `verification` yourself and compare.
- `status != "success"`, a missing commit, a verification that actually fails,
  or files touched outside `files_owned` → the task failed: fold it into Phase
  4's iteration logic instead of reviewing it.
- Phase 0's `docs(<slug>): design` commit may sit in the range; exclude it.

## Phase 3: Review — delegate to `cw:reviewer`
Only once the gate passes, and on the other model of the pair: `opus` reviews
what a `sonnet` implementer wrote, `sonnet` reviews what an `opus` one wrote.

**Depth from `risk:`** — deep review when `risk: high`, or the task touches
schema, API, auth or security, or `files_owned` spans more than three files:
full checklist, adversarial framing, every finding reproduced. Otherwise
fast-path: conventions and the commit check only.

The prompt carries the confirmed list of changed files; the design requirements
for them; adversarial framing ("your job is to find problems, not to approve —
the implementer's exit report is not evidence of anything"); "read the files
fresh from disk, run `git diff`, run the tests"; and reproduce-before-report
("every finding needs a file:line plus a failing command or a specific
reproducible scenario; drop what you cannot back").

Commit check: "confirm the task produced exactly one commit in `git log
--oneline main..HEAD`, Conventional format, with exactly the project's one
trailer line (a second co-author line or a session line is malformed), touching
only `files_owned`; flag a missing, squashed or malformed one, and exclude the
`docs(<slug>): design` commit, which is not a task commit." Skip it entirely
for a `commit: none` task.

Required verdict, as `agents/reviewer.md` defines it — the reviewer's final
message ends with a fenced JSON block matching exactly this schema:

```json
{"verdict": "PASS|NEEDS_WORK", "findings": [{"file": "...", "line": 0, "issue": "...", "evidence": "..."}]}
```

Reviewers report every finding they can evidence; filtering by severity is your
pass, not theirs. Cross-field rule you enforce: `PASS` cannot co-occur with a
critical finding — that combination is a malformed verdict, so reprompt or
escalate rather than accept it.

## Phase 4: Iterate
- **Missing or unparseable verdict** (no fenced block, unreadable JSON, a
  silent reviewer) is not a NEEDS_WORK: spawn one fresh reviewer on the same
  task and retry once, then escalate if it is no better. This retry does not
  consume one of the three iterations below.
- **PASS** → next task, then the checkpoint.
- **NEEDS_WORK, iterations 1–2** → a new implementer gets the reviewer's
  file:line findings and the original requirements: "fix exactly these issues,
  do not refactor beyond them, and fold the fix into this task's existing
  commit (`git commit --amend` or an autosquash fixup), so the series keeps
  one atomic commit per task." For a `commit: none` task instead: "re-edit the
  owned files only; do not run `git commit` or `git commit --amend` — this
  task has no commit of its own, and amending would rewrite unrelated history
  on the target." Then re-run the reviewer.
- **NEEDS_WORK, iteration 3** → stop and escalate with what was built, what was
  flagged, what was attempted, and "three review iterations did not resolve
  these issues. How would you like to proceed?" After two failed corrections
  the problem is usually the design, not the code.

## Phase 5: Checkpoint
Summarise: what was built; the `git log --oneline main..HEAD` series
(`commit: none` tasks contribute nothing there, as expected); design deviations
and why; final verdicts and remaining nits; test results; what to test by hand.
Then: "Review the changes. Resume an unfinished run with `/cw:build <slug>
continue [<task-id>]`, or run `/cw:ship` when you are ready for the PR." Do not
open a PR here.

## Anti-patterns
- Editing a file yourself instead of spawning an implementer.
- Re-decomposing the design, or padding it to a task count.
- A squashed or catch-all commit; each task self-commits.
- Passing the whole plan, or file contents, to an implementer.
- Reviewing before the gate passes, or on the implementer's own model.
- Running the fix loop past three iterations, or fixing findings yourself.
- `git add .`, or `git add -f` past a project's own `.gitignore`.
- Amending for a `commit: none` task; re-edit its owned files instead.
