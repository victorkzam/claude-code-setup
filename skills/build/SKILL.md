---
name: build
description: "Implement an approved design by orchestrating subagents. Use when the user says /build, 'implement this', 'build this', or approves a /design output. Main agent acts as orchestrator: decomposes work, delegates to implementer subagent, reviews via reviewer subagent, iterates up to 3 times, then stops for human approval."
disable-model-invocation: true
argument-hint: <slug | path to <slug>-tasks.md>
allowed-tools:
  - Read
  - Glob
  - Grep
  - Agent
  - Bash(git:*)
  - Bash(npm:*)
  - Bash(python:*)
  - Bash(pip:*)
  - Bash(pytest:*)
  - Bash(swift:*)
  - Bash(xcodebuild:*)
  - Bash(gh:*)
  - Bash(touch /tmp/claude-orchestrator-active*)
  - Bash(rm -f /tmp/claude-orchestrator-active*)
---

# Build Workflow — Orchestrator Pattern

You are the orchestrator. You do not write code yourself and you do **not** re-decompose
the design — `/design` already produced `<slug>-tasks.md`. You consume that task list,
delegate each task to a subagent, review results, and iterate. Your context stays clean;
all heavy lifting happens in subagents.

**Mode:** `/build` runs in **execute mode** (default/acceptEdits), never plan mode. It
begins only after the `/design` Step 5 human checkpoint approved the plan.

Delegation is enforced, not just advised: while `/build` is active a session-scoped
sentinel makes a PreToolUse hook deny direct source edits from the orchestrator, via an
exit-code-2 block. If you find yourself wanting to edit a source file, that is the signal
to spawn an implementer instead — note that a sentinel exit-2 block may simply stop the
turn rather than auto-delegate (known issue #24327), so never assume the block will
self-heal into an implementer spawn: treat the block itself as your cue to spawn one.

## Input
$ARGUMENTS

## Phase 0: Pre-flight (orchestrator, main thread)
1. **Resolve the tasks file** (`$ARGUMENTS`):
   - explicit slug or path argument → `~/.claude/plans/<slug>-tasks.md` (or the given path).
   - no argument → glob `~/.claude/plans/*-tasks.md`, pick the newest by mtime, **show the match and confirm with the user before proceeding** (do not silently guess).
   - no tasks file exists → "No `<slug>-tasks.md` found — run `/design` to generate one, or confirm you want me to decompose ad hoc." Do not invent a fixed task count.
2. Check git status — ensure clean working tree or stash changes.
3. Create feature branch from main: `feat/<slug>` or `fix/<slug>`.
4. Read project CLAUDE.md for coding conventions.
5. **Allowlist-coverage check**: if permission prompts have come up frequently this
   session, suggest running `/fewer-permission-prompts` before spawning implementers —
   a well-populated allowlist keeps delegation moving without repeated interruptions.
6. **Write the session-scoped delegation sentinel:**
   `touch "/tmp/claude-orchestrator-active.$CLAUDE_CODE_SESSION_ID"`
   (this env var matches the `session_id` the guard hook reads from stdin; requires
   Claude Code ≥ v2.1.132 — if `$CLAUDE_CODE_SESSION_ID` is empty, fall back to
   `touch /tmp/claude-orchestrator-active` and warn that session isolation is inactive).
   **Remove it on every exit path** (Phase 5 success, Phase 4 iteration-3 escalation,
   any abort, pre-flight failure) with `rm -f "/tmp/claude-orchestrator-active.$CLAUDE_CODE_SESSION_ID"`.
   The guard hook also self-heals a stale sentinel after its TTL, but that is a backstop —
   always remove yours explicitly.

## Phase 1: Consume the task plan (orchestrator, main thread)
**Do not decompose. Do not invent a task count.** Read the resolved `<slug>-tasks.md`
and execute exactly the tasks it defines — 1 or many, whatever the file says.

- Iterate tasks in `depends_on` order.
- Tasks with no dependency relationship are independent (their `files_owned` are disjoint by construction) — spawn them **in the same turn (multiple Agent calls in one message), synchronously**. Dependent tasks run sequentially.
- **Re-`touch` the session sentinel at the start of each task** (`touch "/tmp/claude-orchestrator-active.$CLAUDE_CODE_SESSION_ID"`) so its mtime stays fresh for the whole active build — only a stalled or killed run trips the guard hook's TTL.
- Per-task model is whatever the task's `model:` field says — do not re-derive it (the design already assigned Sonnet vs Opus).

## Phase 2: Implement (delegate to implementer subagent)
For each task, spawn an **implementer** subagent. **Context-pin it** — give it only its
own single task entry and the relevant design excerpt, never the whole design or the
whole `<slug>-tasks.md`. The prompt includes:
1. **The task's `scope`** (one sentence: what to build and why)
2. **Relevant design excerpt only** — the portion of `<slug>-design-draft.md` this task covers
3. **`files_owned`** — the implementer reads current contents itself (do not paste file contents)
4. **A reference pattern**: "Follow the pattern in [existing_file:symbol]"
5. **The task's `verification`** — exact command(s) + expected result
6. **The task's `commit:` line** and this instruction: *"When the code is complete and `verification` passes, make exactly ONE atomic commit using this `commit:` line (Conventional format, inheriting CLAUDE.md's generic co-author trailer — never hardcode a model-specific trailer), committing only the files in `files_owned`. One task = one commit. Do NOT push."*
7. **A required exit report**: instruct the implementer that its final message must end
   with a fenced JSON block matching exactly this schema:
   ```json
   {"status": "success|partial|failed", "commit_sha": "<sha>", "files_touched": ["..."], "verification_output": "...", "unresolved_issues": ["..."]}
   ```
   This report is testimony, not proof — it is checked against ground truth in the gate below before any review starts.

Set the Agent call's `model` to the task's `model:` field (`sonnet` default, `opus` where
the task says so). Spawn independent tasks in one turn, synchronously; dependent tasks
sequentially (per Phase 1).

For a cost-bounded run, set a `task_budget` (advisory, minimum 20k tokens; use whichever
task-budgets beta header is supported at run time — check current Claude Code release
notes rather than assuming a fixed value) on the implementer spawn. Skip it for
quality-critical tasks where the work should not be scoped to a budget.

## Phase 2→3 Gate: Verify against ground truth (orchestrator, main thread)
Before any reviewer is spawned, the orchestrator itself checks the implementer's exit
report against ground truth — never proceeds on testimony alone:
- Run `git log --oneline main..HEAD` (or the task's expected range) and confirm
  `commit_sha` exists, is Conventional-format, and touches only the task's `files_owned`.
- Re-run the task's `verification` command yourself and compare the real output against
  the reported `verification_output`.
- If `status != "success"`, or the report doesn't match ground truth (commit missing,
  verification actually fails, files touched outside `files_owned`), treat the task as
  failed: do not proceed to Phase 3 — fold this into Phase 4's iteration logic instead
  (or escalate immediately if the iteration budget is already exhausted).

## Phase 3: Review (delegate to reviewer subagent)
Only after the ground-truth gate passes, spawn a **reviewer** subagent.

**Counter-model rule**: the reviewer's model is always the opposite of the implementer's
for this task — `opus` reviews work an implementer did as `sonnet`, and `sonnet` reviews
work an implementer did as `opus`. Never reuse the implementer's own model for review.

**Tiered depth** (from the task's `risk:` field):
- **Deep review** — required when `risk: high`, or the task touches
  schema/API/auth/security, or the task's `files_owned` spans more than 3 files. Full
  checklist below, adversarial framing, every finding reproduced before it's reported.
- **Fast-path** — everything else: conventions check + commit check only, no adversarial
  deep-dive needed.

The reviewer prompt includes:
1. The list of changed files (from the implementer's exit report `files_touched`, already
   confirmed against ground truth above)
2. The original design requirements for these changes
3. **Adversarial framing**: "Your job is to find problems, not to approve. You cannot
   return PASS without having personally checked correctness, conventions, safety, and
   complexity — do not take the implementer's exit report or summary as evidence of any
   of these."
4. Instruction: "Read all files FRESH from disk. Run `git diff`. Run tests. Do NOT trust
   prior summaries."
5. **Reproduce-before-report**: "Every finding must include a file:line AND either a
   concrete failing command or a specific reproducible failure scenario. Findings without
   evidence are dropped — do not include them in your verdict."
6. **Commit check:** "Confirm the task produced exactly one commit (`git log --oneline main..HEAD`), in Conventional format, with CLAUDE.md's co-author trailer, touching only `files_owned`. Flag a missing commit, a squashed/multi-task commit, or a malformed message."
7. **Required structured verdict**: instruct the reviewer that its final message must end
   with a fenced JSON block matching exactly this schema:
   ```json
   {"verdict": "PASS|NEEDS_WORK", "findings": [{"file": "...", "line": 0, "issue": "...", "evidence": "..."}]}
   ```
   **Cross-field rule (orchestrator-checked)**: `PASS` can never co-occur with a critical
   finding. If the reviewer returns `PASS` alongside a critical-severity finding, the
   orchestrator treats this as a malformed verdict — not a pass — and reprompts the
   reviewer or escalates rather than accepting it at face value.

The reviewer reads files from disk with fresh context — no implementer bias.

## Phase 4: Iterate (orchestrator decides)
Based on the reviewer's verdict:

- **NO_VERDICT** (the reviewer's final message is missing the fenced JSON block, or it's
  unparseable, or the reviewer went silent): this is distinct from NEEDS_WORK. Spawn a
  fresh reviewer instance (new context, same task/files) and retry once. If the retry is
  also NO_VERDICT, stop and escalate to the user immediately rather than guessing a verdict.
  A NO_VERDICT retry does NOT consume one of the 3 implement-review iterations below.
- **PASS**: Proceed to Human Checkpoint
- **NEEDS WORK** (iteration 1-2): Spawn a NEW implementer subagent with:
  - The reviewer's specific issues (file:line + description)
  - The original design requirements
  - Instruction: "Fix these specific issues. Do not refactor beyond what's listed. Fold the fix into THIS task's existing commit (`git commit --amend` or an autosquash fixup), so the series stays exactly one atomic commit per task — do not add a second commit for the same task."
  - Then re-run the reviewer
- **NEEDS WORK** (iteration 3): STOP and escalate to the user with:
  - What was implemented
  - What the reviewer flagged
  - What was attempted to fix it
  - Ask: "3 review iterations didn't resolve these issues. How would you like to proceed?"

Max 3 implement-review iterations. After 2 failed corrections, the problem is usually the design, not the code.

## Phase 5: Human Checkpoint
Present a summary to the user:
- **What was built**: Files created/modified with brief descriptions
- **Commit series**: `git log --oneline main..HEAD` — one atomic Conventional commit per task, each with the co-author trailer (this is what `/ship` will verify, not rewrite)
- **Design deviations**: Any places the implementer diverged and why
- **Review result**: Final reviewer verdict + any remaining nits
- **Test results**: Pass/fail with details
- **Manual test instructions**: What the user should test (project-specific)

Ask: "Review the changes. Want me to adjust anything, or ready to ship?"

Remove the session sentinel: `rm -f "/tmp/claude-orchestrator-active.$CLAUDE_CODE_SESSION_ID"` (also do this if you escalate at Phase 4 iteration 3 or abort earlier — the sentinel must never outlive the `/build` run).

Do not proceed to PR creation. the user will run /ship when ready.

## Anti-patterns to avoid
- Do NOT write code yourself — always delegate to the implementer subagent
- Do NOT re-decompose the design or invent a task count — consume `<slug>-tasks.md` as-is (1 or many tasks)
- Do NOT create a single squashed or catch-all commit — each task self-commits atomically (one task = one commit)
- Do NOT pass the full design doc or the whole tasks file to the implementer — only its one task entry + the relevant excerpt
- Do NOT include file contents in the implementer prompt — let it read them
- Do NOT let the implement-review loop run more than 3 times
- Do NOT fix issues yourself after reviewer flags them — spawn a new implementer
- Do NOT proceed to Phase 3 on the implementer's exit report alone — verify `commit_sha` and re-run `verification` yourself first
- Do NOT reuse the implementer's model for review — the reviewer must be the counter-model
- Do NOT treat NO_VERDICT as NEEDS_WORK — retry fresh once, then escalate; it must never consume a fix-iteration
- After 2 failed iterations, the problem is usually spec ambiguity — escalate to the user
