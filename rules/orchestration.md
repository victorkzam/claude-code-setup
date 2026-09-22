# Orchestration & Model Routing

## Model routing (aliases are canonical; a pinned dated model ID goes stale)
| Alias | Route here |
|-------|-----------|
| `fable` | Orchestration, planning, architecture, synthesis, ambiguous problems. Not spawned as a worker. |
| `opus` | Hard implementation (>5 files, cross-cutting schema, long-horizon), design review, high-risk code review |
| `sonnet` | Default: implementation, web research, standard code review, test writing |
| `haiku` | Bulk read-only fan-out: codebase exploration, doc fetching, mechanical checks |

- Routing is manual: a subagent or workflow agent inherits the session model
  (the expensive orchestrator) unless one is set, so every Agent call and every
  agent() in a workflow script carries an explicit model. Audit a generated
  script before a large run to confirm its per-stage model fields are there.
- Independent agents are spawned in the same turn; only dependents are sequenced.
- Route up for hard coding: sonnet→opus is better $/quality than haiku→sonnet;
  down-tiering is for simple or bulk work, not hard work.

## Workflow (ultracode) usage
- Workflows suit read-heavy fan-out: research, codebase mapping, review panels,
  multi-angle drafting, audits. Five or more parallel agents justifies one;
  below that, plain Agent calls. Prototype a new one on a small slice first.
- Implementation stays task-sequential or strictly partitioned by disjoint file
  ownership — no naive parallel writes.
- One workflow per phase; a workflow cannot pause mid-run, so human checkpoints
  sit between workflows, not inside them.
- Workflow subagents run in acceptEdits regardless of session mode: pre-populate
  the permission allowlist before large runs and let the hooks enforce limits.

## Verification & completion
- Ground truth over agent testimony: completion is git log plus actual test or
  build output, not a subagent's self-report.
- Reviewers run with fresh context on a counter-model (not the implementer's),
  framed adversarially, evidence per finding (file:line or a failing command);
  a fast-path review (conventions and the commit only) may run on `sonnet`
  whatever the implementer's model — a second model buys little there.
- Tier review depth by risk: deep review for schema, API, auth and security
  work; fast-path the trivial tasks.
- The stall ladder for NO_VERDICT (no parseable fenced JSON, or a partial
  result after maxTurns) — distinct from NEEDS_WORK, and its one home:
  - ground truth first: implementer — `git log` for the commit and the
    verification command; reviewer — its report file, when it can write one
    (a design reviewer has no write tool, JSON only).
  - nudge 1, SendMessage to the same agent: "Make no further tool calls.
    Your next message is the final report in the required JSON; list what
    you did not reach under unchecked."
  - nudge 2, harder: "No tool calls, no memory, no prose before the block."
  - respawn once, fresh, briefed with the partial report and unchecked
    list; built-in Explore/Plan agents cannot resume and skip straight here.
  - escalate. Two nudges plus one respawn is the cap; nudges consume no
    review iteration.
  Implementer variant: committed and passing → review, noting the missing
  report; uncommitted and passing → one commit nudge ("stage and commit by
  pathspec, nothing else"), then the orchestrator commits by pathspec and
  records the fold at checkpoint; failing → a failed task for Phase 4,
  never a nudge.

## Review-loop anti-ratchet (code, design docs, prose, legal)
- Reviewers output structured findings (location, evidence, severity, suggestion
  ≤25 words), not rewrites; deciding the fix is a role separate from finding.
- Accept/drop decisions happen before redrafting, against explicit size and
  scope budgets; "accepted risk" is a legitimate outcome, logged not litigated.
- Cap adversarial review at two rounds by default; a third only when round
  two produced a verified critical finding; then escalate. Round-2+ findings
  are majority false positives (measured); later rounds need a higher
  evidence bar, not a fresh mandate to find something.
- Termination, size and scope limits are checked mechanically (script or count),
  not self-declared by an agent.
- "Be concise" prompts do nothing (measured ~zero effect); enforce brevity
  structurally: scoped context per call, one bounded item per call, hard caps,
  and minimization as a separate pass, not folded into critique-and-apply.
- When one flagged span is in scope, the fixer sees only that span, not the
  whole artifact — full-context exposure alone triples growth.

## Sessions & context
- One session per phase or milestone; reset at task boundaries or after two
  failed corrections, not at a token counter.
- Re-inject standing governance rules (branch policy, commit format) at each
  phase start; compaction drops policies that are not the active goal.
- Every checkpoint tells the operator to start the next phase in a fresh
  session.
- Every brief names a report file and asks for a return of at most about
  1,500 tokens; reviewers return findings JSON only.
