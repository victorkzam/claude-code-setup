---
name: ship
description: "Verify the commit series, run the quality gate, push the branch and open the PR. Use when the user says /cw:ship, 'push this', 'create a PR', or 'ship it'."
disable-model-invocation: true
argument-hint: "[optional PR title]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(bash:*)
  - Bash(npm:*)
  - Bash(python:*)
  - Bash(pytest:*)
  - Bash(xcodebuild:*)
  - Bash(make:*)
---

# Ship Changes

Push the current feature branch and open its PR. Runs in execute mode, and
assumes `/cw:build` already produced the commit series — this skill verifies
that series, it does not author it.

## Input
$ARGUMENTS

## Step 1: Pre-flight
1. `git status` — refuse to run on `main` or `master`.
2. `git diff --cached` and `git diff` — look for uncommitted work.
3. `git log --oneline main..HEAD` — the commits this PR will carry.
4. Confirm no staged file matches `.env*`, `*credentials*`, `*secret*`, or
   `Config.swift`. A match stops the run.

## Step 2: Verify the commit series
Against the plan's task list (`docs/plans/<slug>.md`):

- Each task's `commit:` subject appears exactly once, in Conventional format,
  carrying exactly the one trailer line the workflow rules define; a second
  co-author line or a session line is a malformed message — report it and
  suggest a rebase. Tasks marked `commit: none` contribute nothing here — that
  is expected, not a gap.
- A `docs(<slug>): design` commit from `/cw:build` is an expected member of the
  series and does not have to lead it.
- No catch-all or squashed commit. Do not create one, and do not rewrite the
  series to tidy it; a messy message earns a suggestion to rebase, not a forced
  rebase.
- Stray **uncommitted** changes mean a task did not self-commit: stop and
  report. The fix is to finish that task in `/cw:build`, not to absorb it here.
  The one exception is an uncommitted design file with no `docs(<slug>):`
  commit anywhere in the range — offer to commit it now as `docs(<slug>):
  design` with the same single trailer line.

## Step 3: Quality gate
This skill is project-agnostic; detect the gate in this precedence and run
exactly what you find.

1. `tests/run.sh` present → `bash tests/run.sh all`.
2. A rules file that states the pre-PR checklist (for example
   `rules/pr-merge-policy.md`) → run the command(s) it names.
3. Project `CLAUDE.md` — a stated test or verify command. Only if 1 and 2 are
   silent.
4. Convention fallback, only if nothing above matched:
   - `pyproject.toml` or `tests/` present → `python -m pytest -q`
   - `package.json` with a `test` script → `npm test`
   - `*.xcodeproj` or `*.xcworkspace` present → `xcodebuild test`
5. Nothing detected → skip with one line: "No project test gate detected —
   relying on the human checkpoint."

A detected gate that fails aborts the run before any push; show the failing
output. A PR is opened only after the feature or milestone is fully built and
this gate has passed — not mid-build, and not on a red gate. Documented
exception: if every changed file is under `docs/`, `README`, or a `CLAUDE.md`,
note it and skip the gate.

## Step 4: Product docs (if applicable)
This step covers product docs only — what the code does and how to use it.
Process-rule capture is `/cw:compound`'s job, offered separately in Step 6.

Check whether the change makes any of these stale: the project README (new
features, changed setup), `ARCHITECTURE.md` (new services, changed data flow),
`CHANGELOG.md`. If so, update them in one atomic `docs:` commit with the same
single trailer line as the rest of the series.

## Step 5: Push and open the PR
1. `git push -u origin HEAD`.
2. `gh pr create` with a Conventional title under 70 characters ($ARGUMENTS
   when given) and this body:
   ```
   ## Summary
   - [what changed and why]

   ## Test Plan
   - [ ] [manual test steps]
   - [ ] [automated test results]

   ## Design Reference
   docs/plans/<slug>.md
   ```
   Write the body to a file in the scratchpad and pass it with
   `--body-file <file>`: the branch guard reads Bash command text, and a body
   that mentions a push to `main` inline would be blocked as if it were the
   command.
3. Report the PR URL.

## Step 6: Offer `/cw:compound`
Ask once, after the URL:

> "Want to capture reusable lessons from this into the project's CLAUDE.md or
> rules files? `/cw:compound` proposes edits for your approval and keeps them
> out of this PR."

Hand off if the user agrees; otherwise end here.

## Safety rules
- Do not push directly to main or master, and do not force-push any branch.
  Work reaches the default branch through this PR.
- Do not commit a file matching `.env*`, `*credentials*`, `*secret*`, or
  `Config.swift`, and do not create empty commits.
- Do not squash or rewrite the per-task commit series — this skill verifies it,
  `/cw:build` authors it.
