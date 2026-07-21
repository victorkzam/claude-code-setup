---
name: compound
description: "Capture reusable lessons from a just-shipped change back into the project's CLAUDE.md / .claude/rules so future work compounds. Use when the user says /compound, or after /ship when they want to record what was learned. User-driven only; never auto-invoked. Proposes edits and applies them only on explicit approval."
disable-model-invocation: true
argument-hint: [optional commit range or PR number; defaults to the last merged feature]
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

Single-pass. Read what just shipped, extract the few lessons worth keeping, propose edits to the project's living docs, apply only on the user's approval. Quality over quantity — one durable rule beats five vague ones.

## Input
$ARGUMENTS

## Step 1: Establish the shipped scope (main thread)
1. Determine the range: use `$ARGUMENTS` if given (a commit range or PR number); otherwise `git log --oneline -20` and identify the most recent merged/feature span.
2. `git diff --stat <range>` and `git log <range>` to see what changed and why.
3. Locate the design artifact if one exists (`~/.claude/plans/<slug>-design-draft.md` or a `docs/` design doc) and any `/design` review-loop findings recorded with it.

## Step 2: Extract lessons (one delegated subagent)
Spawn a single **`general-purpose`** subagent, model `sonnet`, read-only behavior (instruct it not to modify files), synchronously. Give it: the commit range, the diff/log, the design doc path, and the review-loop findings. Ask it to return ONLY structured JSON:

```json
{
  "lessons": [
    {
      "target_file": "CLAUDE.md | .claude/rules/<file>.md",
      "rationale": "what recurring mistake/insight this prevents next time",
      "proposed_edit": "the exact text to add or the precise change to make"
    }
  ]
}
```

Rules for the subagent: only propose a lesson if it would change future behavior; prefer editing an existing section over adding a new one; no speculative or one-off observations; if nothing is worth recording, return `{"lessons": []}`.

## Step 3: Present for approval (HITL)
Show the user each proposed lesson: target file, rationale, and the concrete edit (as a diff-style before/after where it changes existing text). One focused summary, not a wall of options. Ask which to apply (all / a subset / none). Do not edit anything yet.

## Step 4: Apply approved edits
For each approved lesson, make the edit to the target file. Keep edits minimal and in the existing voice of the doc. If `lessons` was empty or the user approved none, make no changes.

## Step 5: Summary
One line: what compounded (e.g., "Added a gate-precedence rule to .claude/rules/pr-merge-policy.md so /ship never picks the wrong Tier-1 command again"), or "Nothing durable to record this cycle."

## Notes
- This skill edits living docs only — never source code, never git history.
- It does not commit. If the user wants the doc change committed, that's a follow-up `/ship` or a manual commit.
