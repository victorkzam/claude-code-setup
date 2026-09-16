---
name: ship
description: "Ship current changes: ensure commits are clean, push branch, create PR. Use when the user says /ship, 'push this', 'create a PR', or 'ship it'. Handles final commit cleanup, branch push, PR creation with structured body, and optional docs update."
disable-model-invocation: true
argument-hint: [optional PR title]
allowed-tools:
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(python:*)
  - Bash(pytest:*)
  - Bash(npm:*)
  - Bash(xcodebuild:*)
  - Bash(make:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
---

# Ship Changes

Push and create a PR for the current feature branch.

**Mode:** `/ship` runs in **execute mode**. It assumes `/build` already produced an
atomic, per-task Conventional commit series — `/ship` *verifies* that series, it does
not author it.

## Input
$ARGUMENTS

## Step 1: Pre-flight Checks
1. Run `git status` — verify we are NOT on main/master (refuse if so)
2. Run `git diff --cached` and `git diff` — check for uncommitted changes
3. Run `git log --oneline main..HEAD` — review commits on this branch
4. Verify no staged files match: .env*, *credentials*, *secret*, Config.swift

## Step 2: Verify the Commit Series
`git log --oneline main..HEAD`. The series must **already** be one atomic Conventional
commit per task, each with the `Co-Authored-By` trailer (produced by `/build`'s
implementers).
- Any orchestrator-authored `docs(<slug>): add design + research artifacts` commit
  (produced by `/build` Phase 0 step 4's promotion of the project's design docs) is an
  **expected series member** — it does not count against one-commit-per-task, and it does
  not have to be the leading commit; a later refresh of the artifacts can land anywhere in
  the range. Do not flag it as a stray or extra commit.
- **Do NOT create a catch-all "final commit"** and do NOT squash the per-task series.
- If there are stray **uncommitted** changes, **STOP and report** — that means a `/build`
  task did not self-commit; do not paper over it with a squash commit. The fix is to
  finish/redo that task in `/build`, not to absorb it here.
  - **Targeted exception**: untracked files under `docs/plans/<slug>/` with **no**
    `docs(<slug>):` commit anywhere in the series is the documented ceiling state for a
    `/build` that couldn't commit the design artifacts (e.g. the root-anchored
    trackability pre-check skipped them, or the commit itself failed — see `/build` Phase
    0 step 4). This is not a silently-skipped task commit — offer to commit the artifacts
    now (`docs(<slug>): add design + research artifacts`, same trailer) rather than
    hard-stopping the ship over it.
- Verify (do not rewrite) format and atomicity. If messages are messy, *suggest* an
  interactive rebase but never force one.

## Step 2.5: Quality Gate (project-agnostic)

`/ship` is a global skill — never hardcode a project's test command. Detect the gate in this precedence and run exactly what you find:

1. **`.claude/rules/pr-merge-policy.md`** (authoritative). If it exists, extract the command(s) under its "mergeable when…" / pre-PR checklist and run those. This wins over CLAUDE.md when both define a gate.
2. **Project `CLAUDE.md`** — a stated test/verify command (e.g. a "Tests" section). Use it only if step 1 found nothing.
3. **Convention fallback** (only if 1 and 2 are silent):
   - `pyproject.toml` or `tests/` present → `python -m pytest -q`
   - `package.json` with a `test` script → `npm test`
   - `*.xcodeproj`/`*.xcworkspace` present → `xcodebuild test`
4. **Nothing detected** → skip with a one-line notice: "No project test gate detected — relying on the human checkpoint."

If a detected gate runs and fails, **abort `/ship` before pushing** and show the failing output. Do not push or open a PR on a red gate. (Exception already in policy: docs-only changes may bypass — if every staged file is under `docs/`, `README`, or `CLAUDE.md`, note it and skip the gate.)

**PR-timing rule:** a PR is opened **only after the feature/milestone is fully built AND
this quality gate has passed**. Never open a PR mid-build or on a red gate.

## Step 3: Update Documentation (if applicable)
This step updates **product docs** only — what the code does / how to use it. It is
deliberately distinct from `/compound`, which captures **process rules** into
CLAUDE.md / `.claude/rules` (offered separately in Step 5, never committed into this PR).

Check if any of these need updating based on the changes:
- Project README.md (new features, changed setup steps)
- ARCHITECTURE.md (new services, changed data flow)
- CHANGELOG.md (if project has one)

If updates are needed, make them in a `docs:` commit (one atomic commit, co-author
trailer — same series discipline as the rest).

## Step 3.5: Optional Pre-PR Review Panel (risk: high milestones)

If the milestone/design doc is tagged `risk: high`, **before opening the PR** offer the user
a 3-lens review panel — this is an **offer, not a mandatory gate**:

> "This milestone is tagged `risk: high`. Want me to run a 3-lens review panel
> (correctness / security / conventions) before opening the PR?"

If the user accepts:
1. Launch one Sonnet subagent per lens (correctness, security, conventions), each
   reviewing the same diff (`git diff main..HEAD`) independently.
2. **Evidence-gated findings only** — each lens must cite a `file:line` or a failing
   command output to support a finding. Drop any finding that lacks one; do not report
   vague or unsubstantiated concerns.
3. Summarize surviving findings to the user before proceeding to Step 4. Fixes are
   the user's call — `/ship` does not auto-apply panel findings.

If the user declines, or the milestone isn't tagged `risk: high`, skip this step entirely
and proceed straight to Step 4.

## Step 4: Push & Create PR
1. Push branch: `git push -u origin HEAD`
2. Create PR via `gh pr create`:
   - Title: conventional format, under 70 chars. Use $ARGUMENTS if provided.
   - Body format:
     ```
     ## Summary
     - [bullet points of what changed and why]

     ## Test Plan
     - [ ] [manual test steps]
     - [ ] [automated test results]

     ## Design Reference
     [link to design doc or plan file if applicable]
     ```
     For **Design Reference**, point to the committed project copy —
     `docs/plans/<slug>/<slug>-design-draft.md` (canonical once `/build` Phase 0 step 4
     has committed it as part of the feature branch) — falling back to the legacy
     `~/.claude/plans/<slug>-design-draft.md` only when no project copy was ever promoted
     (e.g. a plans-dir-resolved build with no project docs to commit).
3. Report PR URL to the user

## Step 5: Offer `/compound` (HITL chain)
After reporting the PR URL, ask once:

> "Want to capture reusable lessons from this into the project's CLAUDE.md /
> .claude/rules? I can run `/compound` now — it proposes edits for your approval and
> does **not** commit them into this PR."

If the user says yes, hand off to the `/compound` skill. `/compound` stays a separate,
user-driven skill: it proposes process-rule edits, applies only what the user approves,
and does not commit (so workflow-rule changes never land inside this feature PR). If
the user declines, end here.

## Safety Rules
- NEVER push to main/master
- NEVER force push
- NEVER commit files matching: .env*, *credentials*, *secret*, Config.swift
- NEVER create empty commits
- NEVER squash or rewrite the per-task atomic commit series — `/ship` verifies it, `/build` authors it
- NEVER open a PR before the quality gate passes or before the feature/milestone is fully built
