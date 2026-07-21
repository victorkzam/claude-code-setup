# Claude Code Setup

A user-level `~/.claude` configuration for [Claude Code](https://claude.com/claude-code):
a `/design` → `/build` → `/ship` agentic workflow, six specialized subagents,
model-routing rules, and a small set of hooks that turn advisory conventions into
enforced ones. This is a sanitized export of a daily-driver setup, offered as a
clone-and-use template.

## 1. Why this exists

The cost model behind this setup is simple: **research and review are cheap;
redoing finished work is expensive.** A wrong architectural assumption caught in
`/design` costs a few minutes of subagent research. The same assumption caught
after `/build` has already written code costs a revert, a re-plan, and a second
implementation pass. Every non-negotiable rule in `WORKFLOW.md` — the two human
checkpoints, the research-before-code sequencing, the review loop that verifies
findings before acting on them — exists to keep mistakes cheap by catching them
as early as possible.

The other half of the cost model is context-window economics. A single Claude
Code session has a finite context window, and research, exploration, and code
review all produce far more raw tokens than anyone needs to actually read.
Delegating that work to subagents — `researcher`, `Explore`, `reviewer` — keeps
only their ~500-1K token *summaries* in the main thread, while the 10-50K tokens
of raw search results, file contents, and diffs stay contained in the subagent
that produced them. A full `/design` → `/build` → `/ship` cycle costs roughly
5-10K tokens in the main context; doing the same research and review inline
would cost 50K+ and degrade quality as the window fills.

## 2. The workflow

```
/design <feature description>   → research + draft + task breakdown + review loop
   ↓  (checkpoint 1 — you approve, then exit plan mode)
/build [<slug>]                 → implement via subagents, one atomic commit per task
   ↓  (checkpoint 2 — you approve the commit series)
/ship                           → verify commits, quality gate, push, open PR
   ↓  (offered, optional)
/compound                       → propose durable lessons back into CLAUDE.md / rules
```

Two human checkpoints are **non-negotiable and not configurable**: after design,
and before a PR opens. They exist at exactly the two points where a wrong turn is
otherwise expensive to unwind — before any code gets written, and before anyone
outside the loop sees the result. Every other step in the pipeline can retry,
escalate, or auto-resolve itself; these two cannot, by design.

## 3. Model routing

Every role is pinned to a **public alias** (`opus`, `sonnet`, `haiku`) in
`rules/orchestration.md`, never a dated or context-window-tagged model ID — the
routing table is the single place model choice lives, so an alias's underlying
model can change without touching every skill and agent file that references it.

The routing principle is **route up for hard work**: Sonnet → Opus is a better
$/quality trade than Haiku → Sonnet when the task is genuinely hard (schema
design, cross-cutting review, direction judgment). Down-tiering to Haiku is for
bulk, read-only, mechanical fan-out — codebase exploration, not implementation.

Parallel subagent fan-out (workflows) is reserved for **read-heavy work at
roughly ≥5 parallel agents** — research, codebase mapping, review panels. Below
that threshold, plain sequential or small-batch subagent calls are simpler and
just as fast. Implementation never runs naive-parallel: tasks are partitioned by
disjoint file ownership (`files_owned` in `<slug>-tasks.md`) so independent tasks
can run in parallel without merge conflicts, while dependent tasks stay
sequential.

## 4. Failure modes that shaped it

A few concrete failure modes are baked into the design, not just aspirational:

- **`NO_VERDICT` is not `NEEDS_WORK`.** A reviewer that returns no parseable
  verdict at all (silence, malformed JSON) is a distinct failure state from one
  that reviewed the code and found problems. Conflating them either burns a
  fix-iteration on nothing, or worse, quietly treats a review that never
  happened as a review that passed. The fix: retry once with a fresh reviewer
  instance, then escalate to a human — never loop on it, never guess.
- **Ground truth over agent testimony.** An implementer's own exit report is
  evidence, not proof. Before any reviewer is spawned, the orchestrator
  independently re-runs the task's verification command and checks `git log`
  for the claimed commit — an implementer that reports success on a task that
  didn't actually commit, or whose tests don't actually pass, is caught before
  it reaches review, not after.
- **Counter-model review.** The reviewer for a task is always the model tier
  the implementer *didn't* use — Opus reviews Sonnet's work and vice versa.
  Reusing the same model for implementation and review correlates its blind
  spots with itself.
- **Hooks as executable guardrails, not advisory text.** CLAUDE.md conventions
  get followed roughly 70% of the time in practice; a `PreToolUse` hook that
  exits 2 gets followed 100% of the time, because it isn't a suggestion. Two of
  the hooks in this repo exist because of specific upstream Claude Code
  behavior: `orchestrator-delegate-guard.sh` works around a case where a
  blocked tool call can end the turn instead of prompting a delegate spawn
  (see [anthropics/claude-code#51609](https://github.com/anthropics/claude-code/issues/51609)),
  and `skills/build/SKILL.md` notes a related known issue where a sentinel
  block doesn't self-heal into automatic delegation
  ([anthropics/claude-code#24327](https://github.com/anthropics/claude-code/issues/24327)) —
  in both cases the mitigation is to treat the block itself as the cue to act,
  rather than assume the platform will recover on its own.

## 5. Redaction note

This is a sanitized export of a real, daily-driver `~/.claude` configuration —
not a from-scratch example. Omissions are deliberate, not incomplete coverage.
Redacted categories:

- **Employer/client paths and names** — absolute paths, project codenames, and
  any client-identifying strings from the source machine.
- **Personal data** — email addresses, account identifiers, and anything tied
  to a specific individual.
- **Personal permission entries** — the source `settings.json` allow-list
  accumulated project-specific paths and a long `WebFetch` domain trail; the
  shipped `settings.example.json` replaces it with a short, generic example set.
- **Removed safety-toggle overrides** — the source config enabled several
  local convenience flags (skipped permission prompts, disabled workflow
  warnings, plugin toggles) that weaken default safety behavior for a specific
  trusted machine. None of those are appropriate defaults for someone else's
  environment, so they are excluded entirely rather than carried over.
- **One project-specific skill excluded** — a `/deep-research` skill existed in
  the source config but isn't included here; `WORKFLOW.md` and `skills/search/`
  have been edited so nothing dangling references it.

## 6. Quick Start (clone-and-use)

```bash
# Agents — auto-register from their directory, available immediately
cp agents/*.md ~/.claude/agents/

# Skills — auto-register from their directory, available immediately
cp -r skills/design skills/build skills/ship skills/compound skills/search ~/.claude/skills/

# Hooks — require the settings.json wiring below AND a session restart
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# Rules
mkdir -p ~/.claude/rules
cp rules/orchestration.md ~/.claude/rules/
```

**CLAUDE.md**: merge, don't clobber. If you already have a `~/.claude/CLAUDE.md`,
adapt the blocks in this repo's `CLAUDE.md` marked "example — replace with your
own" (Identity, Stack Preferences) into your existing file rather than
overwriting it — the `Workflow Rules` section is the part worth keeping intact.

**settings.json**: hooks only take effect once wired into `~/.claude/settings.json`.
Copy the `hooks` block from `settings.example.json` into your own settings file
(merge, don't overwrite, if you have other settings), then **restart Claude Code**
— hooks load at session start.

## 7. Prerequisites

- **jq** — REQUIRED. `protect-branches.sh` and `protect-secrets.sh` fail closed
  without it: they block the corresponding git operations/edits entirely rather
  than silently skip the check if `jq` isn't installed. `brew install jq` /
  `apt install jq`.
- **gh** — the GitHub CLI, required for `/ship`'s PR creation.
- **git** — obviously.
- **Claude Code ≥ v2.1.132** — required for session-scoped sentinel isolation in
  `orchestrator-delegate-guard.sh`; below this version the guard falls back to a
  legacy global sentinel with only a TTL as backstop.
- **Claude Code ≥ v2.1.198** — required for the custom `Explore` agent's model
  override to take effect (below this version, the built-in Explore agent
  inherits the session's main-thread model instead of running on `haiku`).
- **context7 + exa MCP servers** — OPTIONAL. `skills/search/SKILL.md` falls back
  to `WebSearch` for any angle where an MCP tool is unavailable; nothing breaks
  without them, research just loses some precision (context7's version-pinned
  docs, exa's semantic search).

## 8. What to adapt vs keep

**Yours to replace**: the `Identity` and `Stack Preferences` blocks in
`CLAUDE.md` (marked "example — replace with your own"), the generic example
`permissions.allow` list in `settings.example.json`, and the model alias
mappings in `rules/orchestration.md` if you have different tier preferences.

**The transferable system**: the `/design` → `/build` → `/ship` workflow rules
and mode transitions, the model routing table's *principles* (public aliases,
route-up-for-hard-work, the ≥5-agent workflow threshold), the review-loop
semantics (`NO_VERDICT` vs `NEEDS_WORK`, counter-model review, ground-truth
verification), and the hooks — these are the parts built from real failure
modes and are worth keeping close to as-is.
