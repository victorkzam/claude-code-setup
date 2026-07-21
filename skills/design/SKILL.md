---
name: design
description: "Research-grounded feature design with a convergence-driven auto-review loop (no fixed iteration count). Use when the user says /design, starts planning a feature, or needs to explore an approach. Challenges the premise, grounds the design in the real codebase + current web best practices, self-reviews until findings converge (or escalates after 5 iterations), then stops for human approval before any implementation."
argument-hint: <feature description or voice note transcript>
allowed-tools:
  - Read
  - Glob
  - Grep
  - Agent
  - Write
  - Edit
  - Bash(git log:*)
  - Bash(git diff:*)
---

# Research-Grounded Design

You are helping the user design a feature. The cost model is **80/20 — spend the effort in planning and review, not in redrafting later**. Research first, challenge the premise, design, self-review, then stop for human approval.

## Input
$ARGUMENTS

Derive a short kebab-case `<slug>` from the feature (first 3–5 meaningful words). All artifacts go in `~/.claude/plans/`:
- `<slug>-research-codebase.md`, `<slug>-research-docs.md`, `<slug>-research-bestpractices.md`
- `<slug>-design-draft.md` (the design itself; the review loop reads this)
- `<slug>-tasks.md` (the executable task breakdown `/build` consumes)

## Mode

`/design` runs **in plan mode**. Plan mode normally restricts writes to a single plan
file; `/design` is the documented exception — it is model-invocable and writes its
`~/.claude/plans/<slug>-*.md` artifact set (all writes confined there, matching the
orchestrator-delegate-guard exemption). *Workflow judgment call — not officially blessed
by plan mode, but bounded to the plans directory.* The Step 5 Human Checkpoint is the
**exit-plan-mode boundary**: do not exit plan mode before it. `/build` and `/ship` run
afterward in execute mode.

## Step 0: Office-Hours Gate (before any research spend)

Pose one adversarial challenge to the user and wait for their answer:

> Before I research this: is this the right problem to solve? What's the cheapest way to invalidate the premise? Is there an existing solution that already covers it?

- If the user redirects, adopt the new framing.
- If the user says "skip — already validated", proceed.
- Do not spend on Step 2 research until this is answered.

## Step 1: Understand (main thread)
1. Read the project's CLAUDE.md / ARCHITECTURE.md (or equivalent) for conventions.
2. `git log --oneline -20` on the paths relevant to the feature — recent intent the source alone won't show.
3. Explore relevant source files to understand what exists.
4. List explicit unknowns and assumptions. Ask the user clarifying questions if the spec is ambiguous — do not guess.

## Step 2: Parallel Grounding (synchronous)

Spawn these three subagents **in the same turn (three Agent calls in one message), synchronously** — do not use background execution, and do not spawn them one at a time. Opus needs the fan-out stated explicitly.

- **`Explore`** — map the codebase areas the feature touches: existing patterns, the modules/schemas/functions it will reference, where similar things already live. **Set this Agent call's `model` to `haiku`** — fan-out codebase navigation is the Haiku tier; do not let it inherit Opus. *Single fallback:* if its returned summary is too thin to ground the design, re-spawn that one Explore call with `sonnet`.
- **`researcher`** #1 (docs/API currency) — "For libraries/frameworks likely involved (name them), verify the current API surface and that nothing the design will rely on is deprecated." Tell it to prioritize context7.
- **`researcher`** #2 (best-practices/architecture) — "For the architectural choice(s) this feature implies, what is the current best practice and what newer/better pattern might supersede the obvious one?" Tell it to emphasize the practitioner + contrarian angles.

Subagents are read-only and return summaries. **You (the orchestrator) write each returned summary to its file**: the Explore summary → `<slug>-research-codebase.md`, researcher #1 → `<slug>-research-docs.md`, researcher #2 → `<slug>-research-bestpractices.md`. These files are the fresh-context input for the review loop, so write them verbatim enough to stand alone.

**Workflow-scale escape hatch**: if grounding this feature needs more than 4 research angles (large features, PRD milestones spanning multiple subsystems), do not spawn more individual researcher agents — instead run Step 2 as **one ultracode workflow**: a single read-only fan-out + synthesis workflow covering all the angles, which then writes the same three files (`<slug>-research-codebase.md`, `<slug>-research-docs.md`, `<slug>-research-bestpractices.md`) from its synthesized output. This replaces the three individual Agent calls above for that design only — Step 3 onward proceeds unchanged.

Every architectural claim in the design must trace to one of these files or carry an explicit "unsourced — judgment call" flag.

## Step 3: Synthesize the Design Draft

Write `<slug>-design-draft.md` with these sections:

- **Context** — the problem, why now, intended outcome.
- **Approach** — what to build and why this over alternatives. Cite the research files.
- **Files to Create/Modify** — exact paths with purpose; reference existing patterns found in Step 2.
- **Dependencies** — new packages/keys/services, version-pinned where possible.
- **Risks & Mitigations** — what could go wrong, how to detect it, how to roll back.
- **Success Criteria** — testable assertions.
- **Implementation Plan** — ordered steps grouped into logical commits.

## Step 3b: Synthesize the Task Breakdown

Derive `<slug>-tasks.md` from the design's "Files to Create/Modify" + "Implementation
Plan". This is the artifact `/build` executes — make it precise and self-contained.

The task **count is adaptive**: 1 task for a trivial change, as many as the design
implies for a large one. **There is no fixed range** — never pad to or cap at a number.
Split so that no two tasks own the same file (disjoint `files_owned` prevents merge
conflicts and lets independent tasks run in parallel). Each task maps to **exactly one
atomic Conventional commit**.

**Vertical-slice ordering**: when the feature spans layers (schema/API/UI/etc.), order
tasks as vertical slices — schema→API→UI→test for slice 1, then schema→API→UI→test for
slice 2 — never all-of-layer-N across every slice before layer-N+1 starts. Each slice
ends at its own compile/test gate: that slice's task(s) `verification` must pass before
the next slice's tasks begin. A gate failure blocks only that slice's downstream tasks,
not unrelated slices.

Schema per task:

```
## Task <id>
- scope: one-sentence boundary of what this task delivers
- files_owned: [exact paths — disjoint across all tasks]
- files_forbidden: [paths this task must NOT touch — other tasks' files_owned, plus anything explicitly out of scope]
- depends_on: [task ids | none]
- agent: implementer
- model: sonnet | opus   # opus only if >5 files, long-horizon, or cross-cutting schema
- risk: high | normal | trivial   # optional; feeds /build's tiered review depth (deep review for high, fast-path for trivial)
- verification: exact command(s) + expected exit 0   # verification IS the acceptance contract (Proposal 4.2 acceptance: folded in deliberately) — this is what /build checks against ground truth, never narrative
- commit: <type>(<scope>): <subject>           # ONE atomic Conventional Commit; the Co-Authored-By trailer is required
```

(Spec-driven best practice: Pimzino/claude-code-spec-workflow, gotalab/cc-sdd; one
atomic commit per task: Simon Willison agentic-git, MIT Missing Semester agentic-coding.)

## Step 4: Convergence Review Loop (synchronous, no fixed stage count)

Loop until convergence or the safety valve fires. Counter starts at 1.

1. **Parallel fresh-context review** — spawn three subagents in the same turn, synchronously:
   - **`design-reviewer`** — codebase/docs alignment. Pass it `<slug>-design-draft.md` and the three research files. It re-reads them fresh and returns a strict JSON verdict.
   - **`direction-reviewer`** — end-goal alignment (*"is this plan aimed at the right outcome"*), orthogonal to design-reviewer's consistency/codebase-fit checks. Pass it the original `$ARGUMENTS`, `<slug>-design-draft.md`, and `<slug>-tasks.md`. Parse its strict JSON.
   - **`reviewer`** (set `model` to `opus`) as a **completeness critic** — prompt it explicitly with "What is this plan missing? Do not re-check consistency or premise — the other two reviewers cover those. Find gaps: missing edge cases, missing tasks, missing rollback/observability, unstated assumptions." Pass it `<slug>-design-draft.md` and `<slug>-tasks.md`.

   Each is a fresh instance by construction — never pass a prior iteration's findings into the next pass's reviewer prompt.

2. **Adversarial verification of critical findings** — for every finding any of the three reviewers tags `critical`/`blocking`, verify it before acting:
   - File:line claims — Read the cited file/line yourself (main thread) and confirm the finding accurately describes what's actually there.
   - Citation claims (docs/best-practice) — check the finding against the relevant `<slug>-research-*.md` file; if the citation isn't backed by a research file, treat it as unverified.
   - `direction-reviewer`'s `REDIRECT` verdict is always treated as critical for this pipeline: if its `recommended_reframe` cites concrete evidence (a conflicting requirement in `$ARGUMENTS` or a research file), it's verified and folded into the revision below; if it's a values/priority call that can't be file-verified, don't auto-resolve it — flag it for the Step 5 checkpoint as a human decision (a `REDIRECT` is a human decision, not an auto-fix), and it does not block convergence on its own.
   - A finding that cannot be verified this way is **logged as an unverified risk** and carried to Step 5 as a note — it is NOT acted on and does NOT block convergence.

3. **Revise from verified findings only** — in the main thread, update `<slug>-design-draft.md` (and `<slug>-tasks.md` if the change affects task boundaries) using only the verified critical/blocking findings. Minor findings are never actioned mid-loop — every reviewer's minor findings accumulate across iterations and are carried to Step 5 as notes regardless of verification status.

4. **Re-review fresh** — the next iteration re-runs step 1 with brand-new reviewer instances against the revised draft; never reuse a prior iteration's reviewer context.

**Exit condition**: an iteration whose review + verification pass produces **zero verified critical issues** → convergence reached. Finalize the design draft as-is and proceed to Step 5.

**NO_VERDICT handling**: a reviewer that returns unparseable output or no verdict/findings at all is `NO_VERDICT`, not `NEEDS_WORK` — retry that one reviewer once, fresh. If it's still `NO_VERDICT`, escalate to the user immediately rather than burning further loop iterations on it.

**Safety valve**: after 5 iterations without convergence, stop looping and escalate to the user with the full list of surviving (verified, unresolved) critical issues — do not silently finalize, and do not attempt a 6th iteration.

## Step 5: Human Checkpoint

Present the final `<slug>-design-draft.md`, the Step 4 convergence result ([N] iterations
run, `CONVERGED` with zero verified critical issues or `ESCALATED` after 5 iterations with
the surviving verified critical issues listed, plus any unverified risks and accumulated
minor notes), and the `<slug>-tasks.md` task count. **Print the tasks-file path and the
exact next command verbatim** so they survive a `/clear` or a new session. Then STOP:

> "Design + task plan ready. Review loop: [N] iteration(s) → [CONVERGED, zero verified critical issues / ESCALATED after 5 iterations, M surviving critical issues]. Minor notes: [count]. Unverified risks (logged, not acted on): [count]. Tasks: `~/.claude/plans/<slug>-tasks.md` ([K] tasks).
> When ready: `/build <slug>` (or just `/build` and I'll confirm the most recent tasks file).
> What would you like to adjust before I implement?"

**This is the exit-plan-mode boundary.** Do not proceed to implementation and do not
exit plan mode yourself — the user approves, exits plan mode, and runs `/build` (execute
mode) when ready.

## Iteration Protocol (post-checkpoint human feedback)
If the user gives feedback:
1. For feedback that introduces a new unknown, spawn a `researcher` and update the relevant research file.
2. Revise `<slug>-design-draft.md`.
3. **Regenerate `<slug>-tasks.md`** (Step 3b) so it never lags an edited draft.
4. Re-run Step 4 (the convergence review loop, including its `direction-reviewer` pass) on the revised draft + tasks.
5. Present and STOP again. A `REDIRECT` from the re-run is **folded into this single Step 5 checkpoint** (Step 4 already surfaces it as a flagged human decision) — it does not create a second, separate stop. The human sees exactly one checkpoint per iteration cycle, consistent with the two-checkpoint rule. Repeat until the user says to proceed.
