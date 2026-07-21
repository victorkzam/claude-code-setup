# Orchestration & Model Routing

## Model routing table (use aliases, never pinned IDs)
| Alias | Route here |
|-------|-----------|
| `fable` (currently Fable 5) | Orchestration, planning, architecture, synthesis, ambiguous problems ONLY. Never spawn as a worker. |
| `opus` (currently Opus 4.8) | Hard implementation (>5 files, cross-cutting schema, long-horizon), design review, high-risk code review |
| `sonnet` (currently Sonnet 5) | Default: implementation, web research, standard code review, test writing |
| `haiku` (currently Haiku 4.5) | Bulk read-only fan-out: codebase exploration, doc fetching, mechanical checks |

Aliases are canonical; never pin dated model IDs in config.

- Routing is MANUAL: every subagent/workflow agent inherits the session model
  (Fable — expensive) unless a model is explicitly set. Every Agent call and
  every agent() in a workflow script MUST carry an explicit model.
- Route UP for hard coding: Sonnet→Opus is better $/quality than Haiku→Sonnet
  on hard tasks. Down-tiering is for simple/bulk work, not hard work.
- Audit generated workflow scripts before large runs: confirm per-stage model
  fields exist. Prototype on a small slice first.

## Workflow (ultracode) usage
- Workflows for READ-heavy fan-out: research, codebase mapping, review panels,
  multi-angle drafting, audits. Roughly ≥5 parallel agents justifies a workflow;
  below that, plain Agent calls.
- Implementation stays task-sequential or strictly partitioned by disjoint file
  ownership — never naive parallel writes.
- One workflow per phase; workflows cannot pause mid-run, so human checkpoints
  sit BETWEEN workflows, never inside.
- Workflow subagents run in acceptEdits (file edits auto-approved) regardless of
  session mode: pre-populate the permission allowlist before large runs and rely
  on hooks for hard constraints.

## Verification & completion
- Ground truth over agent testimony: completion = git log + actual test/build
  output, never a subagent's self-report.
- Reviewers: fresh context, different model than the implementer, adversarial
  framing, evidence required per finding (file:line or failing command).
- Tier review depth by risk: deep review for schema/API/auth/security tasks;
  fast-path trivial ones.
- Review loops: NO_VERDICT (silence/unparseable) is distinct from NEEDS_WORK —
  retry once fresh, then escalate; never burn iterations or deadlock on it.

## Sessions & context
- One session per phase/milestone; reset at task boundaries or after two failed
  corrections — not at a token counter.
- Re-inject standing governance rules (branch policy, commit format) at each
  phase start — compaction drops non-active-goal policies.
