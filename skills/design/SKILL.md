---
name: design
description: "Research-grounded feature design ending in one approved plan file for /cw:design, planning a feature, asking how to approach something, or an implementation plan; two review rounds by default (lite: one), then stops for the user's approval before any code is written."
argument-hint: "<feature description or voice note transcript> [lite]"
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

The cost model is 80/20: put the effort into planning and review, not redrafting later.
Research first, challenge the premise, draft, self-review to convergence, then stop for
approval.

## Input
$ARGUMENTS

If the last token is the word `lite`, strip it and run the lite path (fewer subagents in
Step 2, fewer review rounds by default in Step 4). Derive a short kebab-case `<slug>`
from what remains (first 3-5 meaningful words). One feature produces **one file**: the
plan. Steps 0-5 run in plan mode and write it wherever plan mode puts it — `docs/plans/`
when the profile sets `plansDirectory: docs/plans`, otherwise the default plans
location. Step 5 ends with this skill calling `ExitPlanMode` itself; approval there is
administrative, ending drafting so Step 6 can move the file. The real accept/reject
decision is `/cw:build`.

## Step 0: Office-hours gate (before any research spend)
Pose one adversarial challenge and wait for an answer:

> Before I research this: is this the right problem to solve? What is the
> cheapest way to invalidate the premise? Is there an existing solution that
> already covers it?

Recommend `lite` when the brief is a fix-up: research already exists, the change touches
3 files or fewer, and no new subsystem is involved. Adopt a redirect if one comes; "skip
— already validated" is fine. The operator's answer decides either way. Do not spend
Step 2's budget before this is answered.

## Step 1: Understand (main thread)
1. Read the project's CLAUDE.md, ARCHITECTURE.md or equivalent for conventions.
2. `git log --oneline -20` on the paths the feature touches — recent intent the
source alone will not show.
3. Read the relevant source files to see what already exists.
4. List the unknowns and assumptions. Ask the user about an ambiguous spec
rather than guessing.
5. Record `architectural: yes|no` — yes when the design introduces a new
subsystem, a public interface or schema, or changes how the loop itself works. This
gates Step 4b later, independent of the lite/full choice.

## Step 2: Parallel grounding (synchronous)
Full path spawns three subagents together, in one message, not in the background: `Explore`
plus both researchers. Lite spawns `Explore` alone, adding one researcher only for the
unknown Step 1 named.

- **`Explore`** (built-in, `model` pinned to `haiku`; routing per
`rules/orchestration.md`) — map what the feature touches: existing patterns, modules,
schemas and functions it will reference. Re-spawn with `sonnet` if too thin.
- **`cw:researcher`** #1, docs and API currency — libraries and frameworks
likely involved (name them), verify the current API surface and that nothing this design
relies on is deprecated. Prioritise context7.
- **`cw:researcher`** #2, best practices — for the architectural choices this
feature implies, current best practice and what newer pattern might supersede the
obvious one. Lean on practitioner and contrarian angles.

Every brief states the turn budget and caps the return at about 1500 tokens of
findings and citations, not a transcript; an agent that can write (Explore, via
Bash) also gets a report path under the session scratchpad; the researcher and
the reviewers return findings in the message. Run
`/cw:search` via the Skill tool when you want its full method in the main thread.
More than four angles run as one read-only ultracode workflow, not more researchers.

## Step 3: Write the plan file
`<slug>.md`, capped at 400 lines — a feature that needs more is two features. Sections,
in this order:

- **Context** — the problem, why now, the intended outcome.
- **Approach** — what to build and why this over the alternatives, citing
Research.
- **Files to create/modify** — exact paths with purpose, referencing the
patterns Step 2 found.
- **Dependencies** — new packages, keys or services, version-pinned.
- **Risks & mitigations** — what can go wrong, how it is detected, how it rolls
back.
- **Success criteria** — testable assertions.
- **Research** — a synthesis of each Step 2 report, at most about 25 lines per
angle: the findings that actually shaped a decision, each with a grade and a URL. Do not
paste a report verbatim; every architectural claim traces here or carries an explicit
"unsourced — judgment call" flag.
- **Tasks** — the task list, always last. Introduce it with a level-1 `# Tasks`
heading or a plain sentence: a `## Tasks` heading would be miscounted as a task by
`/cw:build`, which collects every `## Task <id>` block in the file.

## Step 3b: The task list
Derive it from "Files to create/modify" plus the approach; this is what `/cw:build`
executes, so each block is precise and self-contained.

The count is adaptive — one for a trivial change, as many as a large one implies; do not
pad to a number. More than eight signals splitting the feature instead. Split so no two
tasks own the same file; disjoint `files_owned` prevents conflicts and lets independent
tasks run together. Each task maps to exactly one atomic Conventional commit.

When the feature spans layers, order tasks as vertical slices — schema→API→UI→test for
slice 1, then the same for slice 2 — rather than every schema task before any API task.
Each slice ends at its own verification gate, and a failure there blocks only that
slice's downstream tasks.

```
## Task <id>
- scope: one-sentence boundary of what this task delivers
- files_owned: [exact paths — disjoint across all tasks]
- files_forbidden: [other tasks' files_owned, plus anything out of scope]
- depends_on: [task ids | none]
- agent: implementer
- model: sonnet | opus   # routing: rules/orchestration.md
- risk: high | normal | trivial   # feeds the review depth /cw:build applies
- verification: exact command(s), expected exit 0   # the acceptance contract, never narrative
- commit: <type>(<scope>): <subject> | none   # `none` = unversioned/external target, verification-only
```

## Step 4: Convergence review loop (synchronous)
Full path: two rounds by default, a third only when round two produced a verified
critical finding. Lite path: one round by default, a second only on a verified critical
finding. Reviewer briefs match Step 2's turn budget and return cap; findings return as
JSON in the message — reviewers have no write tool, no report path.

1. Spawn a fresh **`cw:design-reviewer`** on the plan file — never feed a prior round's
findings into the next reviewer's prompt.
2. **Verify every critical finding before acting on it.** A file:line claim:
read that file yourself and confirm it says what the finding says. A citation claim:
check it against the plan's Research section; unbacked means unverified. A finding you
cannot verify is logged as an unverified risk and carried to Step 5 — not acted on, and
not blocking convergence.
3. Revise the plan (and the task list, when boundaries move) from the verified
critical findings only. Minor findings accumulate as notes for Step 5 and are never
actioned mid-round.
4. Zero verified critical findings: stop, converged. Otherwise spawn a
brand-new reviewer for the next round the caps allow — full path: round 2's verified
critical finding opens round 3; lite: round 1's opens round 2. A verified critical
finding surviving that final round escalates to the user at Step 5 with the surviving
findings, not looped further.

**Missing or unparseable verdict**: follow the stall ladder in `rules/orchestration.md`,
not a round burned retrying blind.

## Step 4b: Direction pass (once, architectural only)
When Step 1 recorded `architectural: yes`, run **`cw:direction-reviewer`** once on the
original `$ARGUMENTS` plus the finished plan — full or lite path alike; skip it
otherwise. Bound its turn budget and return cap like Step 4's briefs, findings only.
Its `REDIRECT` is a decision for the user, not an
auto-fix: fold it in when its reframe cites concrete evidence, otherwise surface it at
the checkpoint. It does not loop and does not block on its own.

## Step 5: Summary, then `ExitPlanMode`
Present the plan, path taken (full or lite), rounds used and result (converged or
escalated with the surviving findings), minor-note and unverified-risk counts,
direction verdict, and task count. Then call `ExitPlanMode`, noting approval there moves the file into the
project and `/cw:build` is still the real decision point. On rejection, stay in plan
mode and follow the iteration protocol; on approval, continue straight into Step 6,
without a new turn.

## Step 6: Move the plan into the project
1. `ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`. Empty (not a repo) →
leave the file where plan mode put it, say so, and go to Step 7.
2. `mkdir -p "$ROOT/docs/plans"`, then move the file to
`$ROOT/docs/plans/<slug>.md` — `git mv` when plan mode's copy is already tracked, plain
`mv` otherwise.
3. `git -C "$ROOT" check-ignore -q docs/plans/<slug>.md`. If ignored, name the
fix rather than a bare warning:
   > the design file is ignored by .gitignore; un-ignore docs/plans/<slug>.md before /cw:build

## Step 7: Checkpoint (the one stop)
Print the final path verbatim and stop:

> "Plan written to `[path]`. Start `/cw:build <slug>` in a fresh session — the
> real decision point; exiting plan mode above was provisional. The file is
> untracked until `/cw:build` commits it, so avoid a bulk `git add .` in the
> meantime. What would you like to adjust before I implement?"

## Iteration protocol
Feedback at either stop follows one path, against whichever copy of the plan exists then
(plan mode's before Step 6, the project's after):

1. Spawn a `cw:researcher` for any new unknown, turn-budgeted with Step 2's
findings-only cap; update the Research section.
2. Revise the plan, then regenerate the task list so it never lags the prose.
3. Re-run Steps 4 and 4b on the revised plan, same round caps as before.
4. Return to the checkpoint you came from and stop again, until the user says
to proceed.
