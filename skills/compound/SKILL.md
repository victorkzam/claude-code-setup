---
name: compound
description: "Capture reusable lessons from a just-shipped change back into the project's CLAUDE.md or rules files so future work compounds. Use when the user says /cw:compound, or after /cw:ship when they want to record what was learned. Proposes process-rule edits, applies only the ones the user approves, and never commits them."
disable-model-invocation: true
argument-hint: "[optional commit range or PR number; defaults to the last merged feature]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - Bash(git:*)
  - Agent
---

# Compound — Post-Ship Lesson Capture

Single pass: read what just shipped, extract the few lessons worth keeping,
propose edits to the project's living process docs, apply only what the user
approves. Quality over quantity — one durable rule beats five vague ones.

## Input
$ARGUMENTS

## Step 1: Establish the shipped scope (main thread)
1. Resolve the range: use `$ARGUMENTS` if given (a commit range or PR number);
   otherwise `git log --oneline -20` and identify the most recent feature span.
2. `git diff --stat <range>` and `git log <range>` to see what changed and why.
3. Read the design file for that feature if one exists —
   `docs/plans/<slug>.md` — including whatever its review loop recorded.

## Step 2: Extract lessons (one delegated subagent)
Spawn a single `general-purpose` subagent, model `sonnet`, synchronously,
instructed not to modify files. Give it the commit range, the diff and log, the
design file path, and the review findings. Ask it to return only this JSON:

```json
{
  "lessons": [
    {
      "target_file": "CLAUDE.md | rules/<file>.md",
      "rationale": "the recurring mistake or insight this prevents next time",
      "proposed_edit": "the exact text to add, or the precise change to make"
    }
  ]
}
```

Rules for the subagent: propose a lesson only if it would change future
behaviour; prefer editing an existing section over adding a new one; no
speculative or one-off observations; if nothing is worth recording, return
`{"lessons": []}`.

## Step 3: Present for approval
Show each proposed lesson: target file, rationale, and the concrete edit (a
before/after where it changes existing text). One focused summary, not a wall
of options. Ask which to apply — all, a subset, or none. Edit nothing yet.

## Step 4: Apply approved edits
Make each approved edit in the target file, minimal and in the doc's existing
voice. If `lessons` was empty, or the user approved none, change nothing.

## Step 5: Summary
One line: what compounded (for example, "added a gate-precedence rule to
`rules/workflow.md` so the quality gate never picks the wrong command again"),
or "nothing durable to record this cycle".

## Notes
- This skill edits living process docs only — no source code, no git history.
- It proposes and applies; it never commits. A doc change the user wants
  committed is a follow-up change of its own, deliberately outside the feature
  PR that triggered this run.
