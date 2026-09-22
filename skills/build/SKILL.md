---
name: build
description: "Implement an approved design via subagents: delegates each task to an implementer, verifies against git and the task's verification command, reviews with a second model, and stops at a checkpoint before any PR."
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
implementer's, enforced by the review gate. You do not re-decompose the
design either; `/cw:design` wrote the task list. Consume it, delegate,
verify, review, iterate, stop.

Execute mode. Implementers need the session in auto mode or `acceptEdits` to
write without a prompt per edit. Starts after the design checkpoint.

## Input
$ARGUMENTS — `<slug>`, optionally followed by `continue` and a task id.

## Phase 0: Pre-flight
1. **Resolve the plan.** `ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`; read `$ROOT/docs/plans/<slug>.md`. Absent → fall back to the folder layout `$ROOT/docs/plans/<slug>/<slug>-tasks.md` with `<slug>-design-draft.md` beside it; both present and non-empty or refuse, naming which half is missing. Neither shape → "No plan found for `<slug>` — run `/cw:design` first." Do not invent a task count.
2. **Clean tree**, except an untracked or modified design file for this slug — what step 1 just read, not build drift. Stash with plain `git stash` only: `-u` or `-a` would sweep that file in, leaving step 4 no delta.
3. **Branch** `feat/<slug>` or `fix/<slug>` from `main`; on `continue`, reuse the existing branch.
4. **Commit the design** when its file is untracked or modified: stage it by explicit pathspec (the plan file, or the folder-layout pair plus research files), never `git add .`; one commit, `docs(<slug>): design`, with exactly the workflow rules' one trailer line and nothing else — a harness reminder's own co-author or session line yields to it. No delta → skip silently. Not a repo, or the commit fails → report and carry on uncommitted, no retry loop. Orchestrator-authored; excluded from every per-task commit count below.
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
One implementer per task, the Agent call's `model` taken from the task, turn
budget 50. Context-pin it: its own task block and the relevant design excerpt,
never the whole plan. The prompt carries:

1. The task's `scope` — one sentence on what to build and why.
2. Only the design excerpt this task covers.
3. `files_owned` and `files_forbidden` — it reads current contents itself; do
   not paste file bodies into the prompt.
4. A reference pattern: "follow the pattern in `<existing_file>:<symbol>`".
5. The task's `verification` — exact command(s) and expected result.
6. A report file path under the session scratchpad, the 50-turn budget, and
   "return at most about 1,500 tokens in your final message."
7. The task's `commit:` line, plus: *"When `verification` passes, make exactly
   one atomic commit from this `commit:` line, Conventional format, ending
   with the one trailer line the workflow rules define, no other attribution
   or session line. `git add -- <files_owned> && git commit -- <files_owned>`
   — never a bare `git commit`, the index is shared. One task, one commit. Do
   not push."* Omit for a `commit: none` task — verification-only.
8. A required exit report: its final message ends with a fenced JSON block
   matching exactly this schema:
   ```json
   {"status": "success|partial|failed", "commit_sha": "<sha>", "files_touched": ["..."], "verification_output": "...", "unresolved_issues": ["..."]}
   ```
   The report is testimony, not proof; the gate below checks it.

## Phase 2→3 gate: check the report against the repo
Completion is what git and real command output show, not what a subagent
says. A missing or partial exit report is not itself a failure — ground
truth decides. Before any reviewer is spawned:

- **`commit: none` task** — re-run its `verification` yourself and compare the
  real output with any reported `verification_output`. No commit to check.
- **Any other task**, read off the tree. Ground truth decides in this
  order:
  - Commit present (Conventional, or a `fixup!` of the task's sha awaiting
    squash — see Phase 4), touching only `files_owned`, `verification`
    re-run green → review it, noting a missing exit report rather than
    failing it.
  - No commit, `verification` re-run green, nothing outside `files_owned` →
    one commit nudge by SendMessage: "stage and commit by pathspec with the
    task's commit line, nothing else." Still uncommitted after the nudge →
    the orchestrator commits by pathspec with that line itself — the one
    exception to "you edit no file"; it commits, not edits — and lists
    the fold at the checkpoint.
  - `verification` red, files outside `files_owned`, or a malformed subject
    → failed task, folded into Phase 4 rather than reviewed; the
    out-of-scope check applies before the orchestrator commits by pathspec
    too.
- Phase 0's `docs(<slug>): design` commit may sit in the range; exclude it.

## Phase 3: Review — delegate to `cw:reviewer`
Only once the gate passes. Fast-path runs on `sonnet` whatever the
implementer's model; deep review runs on the pair's other model: `opus`
reviews `sonnet`'s work, `sonnet` reviews `opus`'s.

**Depth from `risk:`** — deep review when `risk: high`, or the task touches
schema, API, auth or security, or `files_owned` spans more than three files:
full checklist, adversarial framing, every finding reproduced. Otherwise
fast-path: conventions and the commit check only. A deep-review brief carries
at most six numbered checks; beyond that, split the review by file ownership
into two reviewers instead.

The prompt carries the confirmed changed-file list; the design requirements
for them; adversarial framing ("find problems, don't approve — the exit
report is not evidence"); "read the files fresh from disk, run `git diff`,
run the tests"; reproduce-before-report ("every finding needs a file:line
plus a failing command or reproducible scenario; drop what you cannot
back"); a report file path under the session scratchpad and the 40-turn
budget; and "return findings JSON only."

Commit check: "confirm the task produced exactly one commit in `git log
--oneline main..HEAD`, Conventional format (a `fixup!` awaiting squash counts
with its target, not malformed — Phase 4), with exactly the project's one
trailer line (a second co-author line or a session line is malformed),
touching only `files_owned`; flag anything else missing, squashed or
malformed, and exclude the `docs(<slug>): design` commit." Skip it entirely
for a `commit: none` task.

Required verdict, as `agents/reviewer.md` defines it — the reviewer's final
message ends with a fenced JSON block matching exactly this schema:

```json
{"verdict": "PASS|NEEDS_WORK", "findings": [{"file": "...", "line": 0, "issue": "...", "evidence": "..."}], "unchecked": ["..."]}
```

Reviewers report every finding they can evidence; filtering by severity is
yours, not theirs. A check the reviewer did not reach lands in `unchecked`, not
silently dropped. Cross-field rule you enforce: `PASS` cannot co-occur with a
critical finding — that combination is a malformed verdict, so reprompt or
escalate rather than accept it.

## Phase 4: Iterate
- **A missing or unparseable verdict** follows the stall ladder in
  `rules/orchestration.md`; its nudges and one respawn consume no
  iteration.
- **PASS** → next task, then the checkpoint.
- **NEEDS_WORK, iterations 1–2** → a new implementer gets the reviewer's
  file:line findings and the original requirements: "fix exactly these
  issues, do not refactor beyond them, then commit the fix separately:
  `git add -- <files_owned> && git commit --fixup=<task sha> -- <files_owned>`."
  Once no agent is reading the tree, the orchestrator squashes each fixup with
  `GIT_SEQUENCE_EDITOR=true git rebase --autosquash --no-autostash <task
  sha>~1` (git 2.44+), so the series keeps one commit per task; until then, a
  `fixup!` commit awaiting the squash counts with its target in the commit
  check. For a `commit: none` task instead:
  re-edit the owned files only — no commit, no amend; this task has no commit
  of its own, and amending would rewrite unrelated history on the target.
  Then re-run the reviewer.
- **NEEDS_WORK, iteration 3** → stop and escalate with what was built, flagged
  and attempted, and "three review iterations did not resolve
  these issues. How would you like to proceed?" After two failed corrections
  the problem is usually the design, not the code.

## Phase 5: Checkpoint
Summarise: what was built; the `git log --oneline main..HEAD` series
(`commit: none` tasks contribute nothing there); design deviations
and why; final verdicts and remaining nits; test results; what to test by hand.
Then: "Review the changes. Resume an unfinished run with `/cw:build <slug>
continue [<task-id>]`, or start a fresh session and run `/cw:ship` when you
are ready for the PR." Do not open a PR here.

## Anti-patterns
- Editing a file yourself instead of spawning an implementer.
- Re-decomposing the design, or padding it to a task count.
- A squashed or catch-all commit; each task self-commits, a fix folds in by
  fixup, not hand-edited history.
- Passing the whole plan, or file contents, to an implementer.
- Reviewing before the gate passes, or off Phase 3's model rule (fast-path on
  `sonnet` whatever the implementer's model, deep review on a model other
  than the implementer's).
- Running the fix loop past three iterations, or fixing findings yourself.
- `git add .`, `git add -f` past a project's own `.gitignore`, or a bare
  `git commit` — pathspec only, the index is shared.
- Amending for a `commit: none` task; re-edit its owned files instead.
- Respawning a stalled agent before its nudges.
