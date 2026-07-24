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
  - Bash(touch /tmp/claude-design-active*)
  - Bash(rm -f /tmp/claude-design-active*)
  - Bash(git rev-parse:*)
  - Bash(mkdir:*)
  - Bash(git check-ignore:*)
  - Bash(git init:*)
  - Bash(git commit --allow-empty*)
---

# Research-Grounded Design

You are helping the user design a feature. The cost model is **80/20 — spend the effort in planning and review, not in redrafting later**. Research first, challenge the premise, design, self-review, then stop for human approval.

## Input
$ARGUMENTS

Derive a short kebab-case `<slug>` from the feature (first 3–5 meaningful words). All plan-mode artifacts go in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/`:
- `<slug>-research-codebase.md`, `<slug>-research-docs.md`, `<slug>-research-bestpractices.md`
- `<slug>-design-draft.md` (the design itself; the review loop reads this)
- `<slug>-tasks.md` (the executable task breakdown `/build` consumes)

## Mode

`/design` is a **hybrid**: Steps 0–5 (research, draft, review loop) run **in plan mode**,
then a short guarded window in Step 6 runs in **execute mode** to write the approved
artifact set into the project, and Step 7 is the single human checkpoint that follows.

Plan mode normally restricts writes to a single plan file; the Steps 0–5 loop is the
documented exception — it is model-invocable and writes its research/draft/task-breakdown
artifact set to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/<slug>-*.md` (all writes
confined there, matching the orchestrator-delegate-guard exemption). *Workflow judgment
call — not officially blessed by plan mode, but bounded to the plans directory.* This part
of the skill is unchanged by the hybrid model below. For meta-tooling designs (edits to
this repo's own skills/hooks, where there is no separate project `docs/plans/` to promote
into), the artifacts live and end here — an accepted limitation.

At the end of Step 5, `/design` calls `ExitPlanMode` itself — this is the explicit mode
transition; there is no longer an implicit boundary to avoid crossing. **The user's
approval at that `ExitPlanMode` call is administrative, not the go/no-go decision** — it
only ends drafting and lets the turn continue into execute mode for the Step 6 artifact
write. The real accept/reject decision point remains `/build`. If the user rejects at
`ExitPlanMode`, stay in plan mode and keep iterating per the Iteration Protocol below,
exactly as before this change. If the user approves, the same turn continues straight into
Step 6 — no new turn, no re-prompt.

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
- commit: <type>(<scope>): <subject> | none (unversioned/external target — verification-only gates)   # ONE atomic Conventional Commit; the Co-Authored-By trailer is required unless commit is `none`
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

## Step 5: Pre-Exit Summary + ExitPlanMode

Present the final `<slug>-design-draft.md`, the Step 4 convergence result ([N] iterations
run, `CONVERGED` with zero verified critical issues or `ESCALATED` after 5 iterations with
the surviving verified critical issues listed, plus any unverified risks and accumulated
minor notes), and the `<slug>-tasks.md` task count:

> "Design + task plan ready. Review loop: [N] iteration(s) → [CONVERGED, zero verified
> critical issues / ESCALATED after 5 iterations, M surviving critical issues]. Minor
> notes: [count]. Unverified risks (logged, not acted on): [count]. Tasks: [K] tasks in
> `<slug>-tasks.md`.
> Approving here exits plan mode so I can write the artifact set into the project — it's
> not the build decision, `/build` still is."

Then call **`ExitPlanMode`**. This is the explicit mode transition described in Mode
above.
- If the user **rejects**, remain in plan mode and follow the pre-promotion path of the
  Iteration Protocol below — unchanged from before this feature.
- If the user **approves**, continue in the same turn into Step 6.

## Step 6: Post-Approval Artifact Write (execute mode, same turn)

Runs only after `ExitPlanMode` is approved. This is a short guarded window, not a general
license to write anywhere — everything below is bounded by the sentinel and the routing
rule.

1. **Arm the sentinel**: `touch "/tmp/claude-design-active.$CLAUDE_CODE_SESSION_ID"` (this
   is what `hooks/design-scope-guard.sh` checks for). If `$CLAUDE_CODE_SESSION_ID` is
   empty, fall back to `touch /tmp/claude-design-active` and warn the user that session
   isolation is inactive for this run.
2. **Resolve the project root**: `ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`.
3. **Routing rule** — decide whether artifacts stay in the plans dir or promote into the
   project:
   - If `ROOT` equals `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` (this repo IS the config
     repo — a meta-tooling design), OR `git -C "$ROOT" check-ignore -q docs/plans/probe`
     reports that class of path as gitignored, the project doesn't want these files
     tracked — **artifacts stay in the plans dir**, and the Step 7 checkpoint says so.
     Always root-anchor the `check-ignore` probe (`git -C "$ROOT" check-ignore -q
     docs/plans/probe`), never a cwd-relative one — a cwd-relative probe run from a
     subdirectory can false-positive.
   - Otherwise, promote: `mkdir -p "$ROOT/docs/plans/<slug>"`.
4. **Write the artifact set** (promotion path only) **with the `Write` tool — never
   `cp`** — so the write goes through the design-scope-guard and protect-secrets rails
   like every other artifact write in this skill:
   - The two core files: `<slug>-design-draft.md` and `<slug>-tasks.md`.
   - Every `<slug>-research-*.md` file present in the plans dir (a bounded glob on the
     exact slug prefix — `login-research-*` cannot cross-match `login-flow-research-*` —
     so legitimate extra research variants are captured without over-matching a
     similarly-named design).
5. **Self-check gate**: only stamp promotion if BOTH hold —
   - the two core files exist in `$ROOT/docs/plans/<slug>/` and are non-empty, AND
   - the count of `<slug>-research-*.md` files written into the project equals the count
     of `<slug>-research-*.md` source files in the plans dir.
   If the gate passes, stamp each **plans-dir** source draft (not the project copies) with
   this as its first line:
   `> PROMOTED to $ROOT/docs/plans/<slug>/ — the project copy is canonical.`
   If any write fails, or the gate does not pass: report the failure, leave the plans dir
   as the canonical copy, and stamp nothing.
6. **No repo at all** (`ROOT` empty): ask the user whether to run `git init -b main && git
   commit --allow-empty -m "chore: initial commit"` so promotion has somewhere to land, or
   to stay in the plans dir for this design.
7. **Disarm the sentinel** before stopping: `rm -f "/tmp/claude-design-active.$CLAUDE_CODE_SESSION_ID"`
   (or the unsuffixed fallback path if that's what was armed).

## Step 7: Human Checkpoint (the one stop)

This is the single STOP for the whole `/design` run — it comes after the write, not
before it. Print the artifact directory path verbatim (`$ROOT/docs/plans/<slug>/` if
promoted, otherwise the plans dir) and name the two files to open first:
`<slug>-design-draft.md`, then `<slug>-tasks.md`. If `$ROOT` is under `$HOME/Documents/`,
note that this location is phone-readable (e.g. via a synced Files app) — omit that note
otherwise.

> "Design + task plan written to `[path]`. Open `<slug>-design-draft.md` first, then
> `<slug>-tasks.md`. Exiting plan mode above was provisional — `/build <slug>` is still
> the real decision point. These files are untracked until `/build` commits them, so
> avoid a bulk `git add .` in the meantime.
> What would you like to adjust before I implement?"

## Iteration Protocol (post-checkpoint human feedback)

Two paths, depending on which checkpoint the feedback arrives at:

**Pre-promotion** (feedback given when the user rejects at the Step 5 `ExitPlanMode`
call) — nothing has been written to the project yet, so iterate exactly as before this
feature, entirely on the plans-dir copies:
1. For feedback that introduces a new unknown, spawn a `researcher` and update the relevant research file.
2. Revise `<slug>-design-draft.md`.
3. **Regenerate `<slug>-tasks.md`** (Step 3b) so it never lags an edited draft.
4. Re-run Step 4 (the convergence review loop, including its `direction-reviewer` pass) on the revised draft + tasks.
5. Return to Step 5 (present + `ExitPlanMode` again). A `REDIRECT` from the re-run is **folded into this single checkpoint** (Step 4 already surfaces it as a flagged human decision) — it does not create a second, separate stop. Repeat until the user approves at `ExitPlanMode`.

**Post-promotion** (feedback given at the Step 7 checkpoint, after artifacts were written
into the project) — ALL references re-point to the project copies: revisions, Step 3b
regeneration, and the Step 4 re-review reviewer prompts all use
`$ROOT/docs/plans/<slug>/<slug>-*.md` paths, never the plans dir. The plans-dir drafts are
now inert bannered scratch (Step 6's `PROMOTED` stamp) — a re-review must never converge
on them.
1. Re-arm the sentinel for this revision turn (Step 6.1).
2. Run steps 1–4 of the pre-promotion path above, but reading and writing
   `$ROOT/docs/plans/<slug>/<slug>-*.md` instead of the plans dir.
3. Present the revised checkpoint (Step 7) and STOP again; disarm the sentinel (Step 6.7)
   before stopping. Repeat until the user says to proceed.
