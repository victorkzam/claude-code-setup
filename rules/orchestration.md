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
  framed adversarially, evidence per finding (file:line or a failing command).
- Tier review depth by risk: deep review for schema, API, auth and security
  work; fast-path the trivial tasks.
- NO_VERDICT (silence or an unparseable reply) is distinct from NEEDS_WORK:
  retry once fresh, then escalate; do not burn iterations or deadlock on it.

## Review-loop anti-ratchet (code, design docs, prose, legal)
- Reviewers output structured findings (location, evidence, severity, suggestion
  ≤25 words), not rewrites; deciding the fix is a role separate from finding.
- Accept/drop decisions happen before redrafting, against explicit size and
  scope budgets; "accepted risk" is a legitimate outcome, logged not litigated.
- Cap adversarial review at one or two rounds: round-2+ findings are majority
  false positives (measured); later rounds need a higher evidence bar, not a
  fresh mandate to find something.
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
