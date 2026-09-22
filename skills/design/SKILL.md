---
name: design
description: "Research-grounded feature design that ends in one approved plan file. Use when the user says /cw:design, starts planning a feature, asks how to approach something, or needs an implementation plan. Challenges the premise first, grounds the design in the real codebase and current web sources, self-reviews until findings converge (escalating after 5 iterations), then stops for the user's approval before any code is written."
argument-hint: "<feature description or voice note transcript>"
effort: xhigh
allowed-tools:
  - Read
  - Glob
  - Grep
  - Agent
  - Skill
  - Write
  - Edit
  - Bash(git:*)
  - Bash(mkdir:*)
  - Bash(mv:*)
---

# Research-Grounded Design

The cost model is 80/20: spend the effort in planning and review, not in
redrafting later. Research first, challenge the premise, draft, self-review to
convergence, then stop for the user's approval.

## Input
$ARGUMENTS

Derive a short kebab-case `<slug>` (first 3–5 meaningful words). One feature
produces **one file**: the plan. Steps 0–5 run in plan mode and write it
wherever plan mode puts plan files — `docs/plans/` when the profile sets
`plansDirectory: docs/plans`, otherwise the default plans location. Step 5 ends
with this skill calling `ExitPlanMode` itself, the explicit mode transition;
approval there is administrative, ending drafting so Step 6 can move the file.
The real accept/reject decision is `/cw:build`.

## Step 0: Office-hours gate (before any research spend)
Pose one adversarial challenge and wait for an answer:

> Before I research this: is this the right problem to solve? What is the
> cheapest way to invalidate the premise? Is there an existing solution that
> already covers it?

Adopt a redirect if one comes; "skip — already validated" is a fine answer.
Do not spend Step 2's budget before this is answered.

## Step 1: Understand (main thread)
1. Read the project's CLAUDE.md, ARCHITECTURE.md or equivalent for conventions.
2. `git log --oneline -20` on the paths the feature touches — recent intent the
   source alone will not show.
3. Read the relevant source files to see what already exists.
4. List the unknowns and assumptions. Ask the user about an ambiguous spec
   rather than guessing.

## Step 2: Parallel grounding (synchronous)
Spawn three subagents together, three Agent calls in one message — not in the
background, not one at a time:

- **`Explore`** (the built-in agent, this call's `model` pinned to `haiku`) —
  map what the feature touches: existing patterns, the modules, schemas and
  functions it will reference, where similar things already live. Fan-out
  navigation is the haiku tier; do not let it inherit the orchestrator model.
  If its summary is too thin to ground the design, re-spawn that one call with
  `sonnet`.
- **`cw:researcher`** #1, docs and API currency — "for the libraries and
  frameworks likely involved (name them), verify the current API surface and
  that nothing this design relies on is deprecated." Tell it to prioritise
  context7.
- **`cw:researcher`** #2, best practices — "for the architectural choices this
  feature implies, what is current best practice, and what newer pattern might
  supersede the obvious one?" Tell it to lean on the practitioner and
  contrarian angles. Invoke `/cw:search` through the Skill tool when you want
  its full method in the main thread.

Subagents are read-only. Fold each returned summary into the plan's Research
section verbatim enough to stand alone — the review loop reads it there with
fresh context. Every architectural claim traces to that section or carries an
explicit "unsourced — judgment call" flag.

Grounding that needs more than four angles (a large feature spanning several
subsystems) runs as one read-only ultracode workflow instead of more researcher
agents, writing its synthesis into the same section.

## Step 3: Write the plan file
`<slug>.md`, in this order:

- **Context** — the problem, why now, the intended outcome.
- **Approach** — what to build and why this over the alternatives, citing
  Research.
- **Files to create/modify** — exact paths with purpose, referencing the
  patterns Step 2 found.
- **Dependencies** — new packages, keys or services, version-pinned.
- **Risks & mitigations** — what can go wrong, how it is detected, how it rolls
  back.
- **Success criteria** — testable assertions.
- **Research** — the Step 2 summaries: codebase, docs/API, best practices.
- **Tasks** — the task list, always last. Introduce it with a level-1 `# Tasks`
  heading or a plain sentence: a `## Tasks` heading would be miscounted as a
  task by `/cw:build`, which collects every `## Task <id>` block in the file.

## Step 3b: The task list
Derive it from "Files to create/modify" plus the approach; this is what
`/cw:build` executes, so each block is precise and self-contained.

The count is adaptive — one task for a trivial change, as many as the design
implies for a large one. There is no target range: do not pad to a number or
cap at one. Split so no two tasks own the same file; disjoint `files_owned` is
what prevents conflicts and lets independent tasks run together. Each task maps
to exactly one atomic Conventional commit.

When the feature spans layers, order tasks as vertical slices —
schema→API→UI→test for slice 1, then the same for slice 2 — rather than every
schema task before any API task. Each slice ends at its own verification gate,
and a failure there blocks only that slice's downstream tasks.

```
## Task <id>
- scope: one-sentence boundary of what this task delivers
- files_owned: [exact paths — disjoint across all tasks]
- files_forbidden: [other tasks' files_owned, plus anything out of scope]
- depends_on: [task ids | none]
- agent: implementer
- model: sonnet | opus   # opus for >5 files, long-horizon, or cross-cutting schema
- risk: high | normal | trivial   # feeds the review depth /cw:build applies
- verification: exact command(s), expected exit 0   # the acceptance contract, never narrative
- commit: <type>(<scope>): <subject> | none   # `none` = unversioned/external target, verification-only
```

## Step 4: Convergence review loop (synchronous)
Counter starts at 1; loop until convergence or the safety valve fires.

1. Spawn a fresh **`cw:design-reviewer`** on the plan file. Fresh context every
   pass is the point — never feed a prior iteration's findings into the next
   reviewer's prompt.
2. **Verify every critical finding before acting on it.** A file:line claim:
   read that file yourself and confirm it says what the finding says. A
   citation claim: check it against the plan's Research section; unbacked means
   unverified. A finding you cannot verify is logged as an unverified risk and
   carried to Step 5 — not acted on, and not blocking convergence.
3. Revise the plan (and the task list, when boundaries move) from the verified
   critical findings only. Minor findings accumulate as notes for Step 5 and
   are never actioned mid-loop.
4. Re-review with a brand-new reviewer instance against the revised plan.

**Exit**: an iteration producing zero verified critical findings has converged.
**Unparseable reply**: a reviewer that returns no verdict, or one that cannot
be parsed, is not a NEEDS_WORK — retry that reviewer once, fresh, then escalate
rather than burning loop iterations.
**Safety valve**: after 5 iterations without convergence, stop and escalate
with the surviving verified critical findings listed. No sixth iteration, no
silent finalisation.

## Step 4b: Direction pass (once)
After convergence, run **`cw:direction-reviewer`** once on the original
`$ARGUMENTS` plus the finished plan. Its `REDIRECT` is a decision for the user,
not an auto-fix: fold it in when its reframe cites concrete evidence, otherwise
surface it at the checkpoint. It does not loop and does not block on its own.

## Step 5: Summary, then `ExitPlanMode`
Present the plan, the loop result ([N] iterations, converged or escalated with
M surviving findings), the minor-note and unverified-risk counts, the direction
verdict, and the task count. Then call `ExitPlanMode`, noting that approving
there moves the file into the project and that `/cw:build` is still the real
decision point. On rejection, stay in plan mode and follow the iteration
protocol; on approval, continue straight into Step 6 without a new turn.

## Step 6: Move the plan into the project
1. `ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`. Empty (not a repo) →
   leave the file where plan mode put it, say so, and go to Step 7.
2. `mkdir -p "$ROOT/docs/plans"`, then move the file to
   `$ROOT/docs/plans/<slug>.md` — `git mv` when plan mode's copy is already
   tracked, plain `mv` otherwise.
3. `git -C "$ROOT" check-ignore -q docs/plans/<slug>.md`. If the destination is
   ignored, print the fix by name rather than a bare warning:
   > the design file is ignored by .gitignore; un-ignore docs/plans/<slug>.md before /cw:build

## Step 7: Checkpoint (the one stop)
Print the final path verbatim and stop:

> "Plan written to `[path]`. `/cw:build <slug>` is the real decision point —
> exiting plan mode above was provisional. The file is untracked until
> `/cw:build` commits it, so avoid a bulk `git add .` in the meantime. What
> would you like to adjust before I implement?"

## Iteration protocol
Feedback at either stop follows one path, against whichever copy of the plan
exists then (plan mode's before Step 6, the project's after):

1. Spawn a `cw:researcher` for any new unknown and update the Research section.
2. Revise the plan, then regenerate the task list so it never lags the prose.
3. Re-run Steps 4 and 4b on the revised plan.
4. Return to the checkpoint you came from and stop again, until the user says
   to proceed.
