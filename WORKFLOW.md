# Agentic Workflow Harness

Documentation for the `/design` -> `/build` -> `/ship` workflow. Installed at `~/.claude/` (user-level, works in every project).

---

## Quick Start

**Install**: clone the repo, open Claude Code in it, then run `/setup` — the
setup skill checks prerequisites, installs agents/skills/hooks/rules, and merges
`settings.json`/`CLAUDE.md` with your existing config (dry-run + consent at each
step; see the README's Quick Start section for the full flow).

**Use**:

```
/design <paste voice note transcript or feature description>
  -> iterates with research until you approve

/build
  -> implements via subagents, reviews, iterates up to 3x
  -> stops for your approval

/ship [optional PR title]
  -> commits, pushes, creates PR
```

Two human checkpoints: **after design** (you approve the plan), **before PR** (you approve the code).

---

## Architecture

| Primitive | What | Where |
|---|---|---|
| CLAUDE.md | Always-on advisory rules | `~/.claude/CLAUDE.md` |
| `/design` | Research-grounded planning skill | `~/.claude/skills/design/SKILL.md` |
| `/build` | Implementation orchestrator skill | `~/.claude/skills/build/SKILL.md` |
| `/ship` | Commit + PR automation skill | `~/.claude/skills/ship/SKILL.md` |
| `/compound` | Post-ship lesson capture into CLAUDE.md/.claude/rules (offered by `/ship`) | `~/.claude/skills/compound/SKILL.md` |
| `/search` | 3-angle web research skill | `~/.claude/skills/search/SKILL.md` |
| researcher | `sonnet` agent, read-only, web tools | `~/.claude/agents/researcher.md` |
| implementer | `sonnet` default / `opus` per-call, writes code + atomic commit, no push | `~/.claude/agents/implementer.md` |
| reviewer | `opus` agent, read-only, runs tests | `~/.claude/agents/reviewer.md` |
| design-reviewer | `opus` agent, read-only, doc/codebase fidelity (loops until findings converge, escalates after 5) | `~/.claude/agents/design-reviewer.md` |
| direction-reviewer | `opus` agent (effort xhigh), read-only, premise/direction (once) | `~/.claude/agents/direction-reviewer.md` |
| Branch protection | Hook: blocks push *to* main/master + force push (by destination, not branch name) | `~/.claude/hooks/protect-branches.sh` |
| Secrets protection | Hook: blocks edits to .env/keys/credentials/secrets (broadened) | `~/.claude/hooks/protect-secrets.sh` |
| Delegate guard | Hook: session-scoped; blocks orchestrator source edits while `/build` active | `~/.claude/hooks/orchestrator-delegate-guard.sh` |
| Design scope guard | Hook: session-scoped; confines `/design`'s post-approval Write\|Edit calls (not a hard filesystem guarantee) to design artifact paths (`docs/plans/` — where `/design` writes both its design draft and research files — `docs/research/`, a separately allowlisted research-output path not written by `/design`, plans dir), sentinel-armed, same trust class as the delegate guard | `~/.claude/hooks/design-scope-guard.sh` |
| Syntax check | Hook: multi-language (py/js/sh/json/swift), surfaces errors | `~/.claude/hooks/syntax-check.sh` |

---

## Workflow Detail

### Phase 1: `/design`

**What it does**: Research-grounded feature design. Spawns researcher subagents to investigate unknowns, then synthesizes findings into a plan.

**How it works**:
1. Reads project CLAUDE.md + explores codebase
2. Identifies unknowns and assumptions
3. Spawns grounding subagents in parallel: `Explore` (codebase map, **`haiku`** — fan-out navigation) + two `researcher` (`sonnet`, 3-angle methodology)
   - Only structured summaries return to main context (~500-1K tokens each)
   - Raw research (10-50K tokens) stays in subagent context
4. Synthesizes a design draft **and** `<slug>-tasks.md` (adaptive task count — 1 to many, never a fixed range; each task: disjoint files, assigned model, verification, one atomic Conventional commit — or `commit: none` for unversioned/external targets, verification-only)
5. **design-reviewer** loop (fresh context each pass, continues until findings converge, escalates after 5 iterations) for consistency/codebase-fit/best-practices, then **direction-reviewer** once (`opus`, premise/problem-fit)
6. `/design` calls **`ExitPlanMode` itself** — provisional and skill-invoked, not the real go/no-go; approving here only continues the same turn into the guarded write below (rejecting stays in plan mode and re-runs the loop)
7. **Guarded promotion write** (execute mode, same turn; session-scoped sentinel via `design-scope-guard.sh`) — writes the approved artifact set into `$ROOT/docs/plans/<slug>/`, unless `$ROOT` is the config repo itself or `docs/plans/` is gitignored there, in which case artifacts stay in the plans dir
8. **STOPS for your approval** — the real checkpoint, now *after* the write, on the project copy; presents both verdicts + the artifact path

**Iteration**: feedback given before the provisional `ExitPlanMode` approval iterates entirely on the plans-dir copies (regenerate design + `<slug>-tasks.md`, re-run the review loop + direction review). Feedback given at the post-write checkpoint re-arms the sentinel and iterates on the project copies in `docs/plans/<slug>/` instead — the plans-dir drafts are inert scratch by then. Either path stops again at a single checkpoint.

**Context impact**: Research stays out of main context. Only summaries enter.

### Phase 2: `/build`

**What it does**: Orchestrates implementation using subagents. The main agent NEVER writes code and NEVER re-decomposes — it consumes `<slug>-tasks.md`, delegates, and reviews. Runs in execute mode.

**How it works**:
1. **Pre-flight**: Resolves the tasks file — project copy first (`$ROOT/docs/plans/<slug>/<slug>-tasks.md`), falling back to the legacy `~/.claude/plans/` (arg / newest-by-mtime-with-confirm) — creates feature branch, commits a promoted project design copy as a `docs(<slug>): add design + research artifacts` commit, then writes the session-scoped sentinel
2. **Consume tasks**: Executes exactly the tasks `<slug>-tasks.md` defines — adaptive count (1 to many), in `depends_on` order, independent ones in parallel
3. **Implement**: Spawns a context-pinned **implementer** per task (only its task entry + relevant excerpt); the implementer makes **one atomic Conventional commit per task** (co-author trailer; no push) — except `commit: none` tasks (unversioned/external targets), which are verification-only
4. **Review**: Spawns **reviewer** subagent that reads files FRESH from disk and checks commit atomicity (no implementer bias)
5. **Iterate**: If reviewer finds issues:
   - Iteration 1-2: Spawns NEW implementer with reviewer's feedback
   - Iteration 3: Escalates to you with full context
6. **STOPS for your approval** with summary of what was built, test results, and manual test instructions

**Context impact**: All code writing and reviewing happens in subagents. Main context stays clean.

### Phase 3: `/ship`

**What it does**: Verifies the commit series, updates product docs, pushes, creates PR, then offers `/compound`. Runs in execute mode.

**How it works**:
1. Verifies NOT on main (refuses if so)
2. **Verifies** the atomic per-task Conventional commit series (does NOT squash or author a catch-all commit; stops on stray uncommitted changes) — a `docs(<slug>):` artifacts commit is exempt from the one-commit-per-task accounting
3. Updates **product** docs (README, ARCHITECTURE, CHANGELOG) if needed — distinct from `/compound`'s process-rule capture
4. Quality gate must pass; opens PR only after the feature is fully built AND green
5. Pushes branch, creates PR via `gh pr create`, then **offers `/compound`** (HITL; never commits process-rule edits into this PR)

**Safety**: Never pushes to main, never force pushes, never commits secrets, never squashes the per-task series.

---

## Recommended Sequence

```
/design <spec>   → research + draft + <slug>-tasks.md + design-reviewer loop + direction-reviewer
   ↓  (/design exits plan mode itself, provisionally, then writes the approved
      artifacts into docs/plans/<slug>/ — you approve there, after the write;
      /build is still the real go/no-go)
/build [<slug>]  → consume tasks.md; one atomic commit per task; reviewer
   ↓  (you approve the commit series)
/ship            → verify series, product-doc updates, quality gate, push, PR
   ↓  (offered, optional)
/compound        → propose CLAUDE.md/.claude/rules lessons (HITL; never committed into the PR)
```

Two non-negotiable human checkpoints: **after design**, **before PR**. `/compound` is a
separate, user-driven step chained from `/ship` — it is never merged into `/ship` and
never lands process-rule edits inside the feature PR.

## Mode Transitions

`/design` is a **hybrid**: plan mode for its research/draft/review loop (Steps 0-5),
then a short guarded execute-mode window (Step 6) that writes the approved artifacts
into the project, followed by the real human checkpoint (Step 7) — the checkpoint now
comes *after* that write, not before it.

| Stage | Mode | Notes |
|---|---|---|
| `/design` Steps 0-5 (research, draft, review loop) | **plan** | Documented exception: may write only `~/.claude/plans/<slug>-*.md` (judgment call, bounded to that dir) |
| `/design` Step 5 `ExitPlanMode` | — | **Provisional, skill-invoked.** `/design` calls `ExitPlanMode` itself; approving here is administrative — it only continues the same turn into Step 6, it is not the go/no-go |
| `/design` Step 6 (execute, same turn) | **execute**, guarded | `design-scope-guard.sh`'s session-scoped sentinel confines Write\|Edit calls (not a hard filesystem guarantee) to `docs/plans/<slug>/` (where `/design`'s own research files land, alongside the design draft + tasks), `docs/research/` (a separately allowlisted research-output path, not written by `/design`), and the plans dir while the approved artifact set is promoted into `$ROOT/docs/plans/<slug>/` (also `~/.claude/plans/<slug>-*.md` during this window) |
| `/design` Step 7 checkpoint | — | **The real human checkpoint**, now after the promotion write, on the project copy. You approve or iterate here — `/build` remains the true go/no-go |
| `/build`, `/ship` | **execute** (default/acceptEdits) | `disable-model-invocation: true`; run explicitly after approval |

The shipped template sets `defaultMode: "auto"` — a convenience key, deliberately
withheld from merges into existing configs. The plan-first guarantee comes from
`/design`'s Steps 0-5 running in plan mode and Step 6's write window being confined by
`design-scope-guard.sh`, not from a global `"plan"` default.

## Model Usage Map

Roles are pinned to **aliases**, never dated model IDs — this table is a summary
for orientation only. The authoritative routing table lives in
`~/.claude/rules/orchestration.md`; if the two ever disagree, that file wins.

| Role | Model | Tier rationale |
|---|---|---|
| Main thread / `/design` orchestrator | `opus` | Orchestration / architecture |
| `/design` `Explore` subagent | `haiku` | Fan-out codebase navigation |
| `researcher` | `sonnet` | Research |
| `design-reviewer` | `opus` | Doc/codebase fidelity |
| `direction-reviewer` | `opus` (effort `xhigh`) | Premise/direction judgment |
| `implementer` | `sonnet` → `opus` per-call | Implementation |
| `reviewer` | `opus` | Code review |
| `/compound` subagent | `sonnet` | Lesson extraction |

Effort: `opus` agents use `xhigh` (Opus's recommended default, matching the global
`effortLevel`); `sonnet` agents keep `high` (Sonnet has no `xhigh` — `high` is its
top balanced level).

---

## Agents

### researcher (`sonnet`)
- **Purpose**: Web research with structured findings and citations
- **Tools**: Read, Glob, Grep, WebSearch, WebFetch, exa, context7
- **Cannot**: Write files, edit files, run bash commands
- **Preloads**: `/search` skill (3-angle methodology)
- **Output**: Structured findings with URLs, confidence levels, consensus, gaps

### implementer (`sonnet` default / `opus` per-call)
- **Purpose**: Implement one task; make exactly one atomic Conventional commit for it — or, for `commit: none` tasks (unversioned/external targets), verification-only with no commit
- **Model**: `sonnet`; the design assigns `opus` per-call for >5-file / long-horizon / cross-cutting tasks
- **Tools**: Read, Write, Edit, Glob, Grep, Bash, context7
- **Cannot**: `git push`, `gh pr create`, checkout main (commits ARE allowed and required)
- **Config**: `permissionMode: acceptEdits`, `effort: high`, `memory: project`
- **Output**: Files created/modified, the task's commit, design deviations, test results

### reviewer (`opus`)
- **Purpose**: Code review for quality, correctness, conventions, commit atomicity
- **Tools**: Read, Glob, Grep, Bash (for tests)
- **Cannot**: Write, Edit, push, delete
- **Config**: `memory: project`
- **Output**: PASS/NEEDS WORK verdict, issues list, test results, design adherence

### design-reviewer (`opus`)
- **Purpose**: Pre-code fidelity review — consistency, codebase-fit, best-practices, research-ignored (loops until findings converge, escalates after 5 iterations)
- **Tools**: Read, Glob, Grep, web/exa/context7; **Cannot**: Write, Edit
- **Output**: Strict JSON verdict (PASS/NEEDS_WORK) + issues + suggested_fixes

### direction-reviewer (`opus`, effort xhigh)
- **Purpose**: Premise/problem-fit review — "is this plan aimed at the right outcome" (runs once, after the design-reviewer loop; no auto-loop)
- **Tools**: Read, Glob, Grep only (no web — research already happened); **Cannot**: Write, Edit
- **Output**: Strict JSON verdict (PASS/REDIRECT) + concerns + recommended_reframe

See `~/.claude/rules/orchestration.md` for the authoritative role → model routing table.

---

## Hooks

All hooks are in `~/.claude/settings.json` and `~/.claude/hooks/`. They provide 100% enforcement (vs CLAUDE.md's ~70% compliance).

| Hook | Event | What it does |
|---|---|---|
| protect-branches.sh | PreToolUse (Bash, git) | Blocks pushes whose *destination* is main/master + force push; allows feature branches named like `feat/main-*` |
| protect-secrets.sh | PreToolUse (Write\|Edit) | Blocks edits to .env/.envrc, credentials, secrets, keys (.pem/.key/.p8/.pfx/.jks/.keystore), id_rsa, .aws/.ssh/.gnupg, service-account/gcp json, Config.swift |
| orchestrator-delegate-guard.sh | PreToolUse (Write\|Edit) | While `/build` active, blocks orchestrator (main-thread) source edits; **session-scoped** (`/tmp/claude-orchestrator-active.$SESSION_ID`) with TTL self-heal |
| design-scope-guard.sh | PreToolUse (Write\|Edit) | While `/design`'s Step 6 write window is active, confines Write\|Edit calls (not a hard filesystem guarantee) to design artifact paths (`docs/plans/` — where `/design` writes both the draft and its research files — `docs/research/`, a separately allowlisted research-output path not written by `/design`, the plans dir); **session-scoped** (`/tmp/claude-design-active.$SESSION_ID`), same trust class + TTL self-heal as the delegate guard |
| syntax-check.sh | PostToolUse (Write\|Edit) | Multi-language check (py/js/sh/json/swift), surfaces real errors; never blocks |
| Notification | Notification event | macOS notification when Claude needs attention (macOS-only, uses `osascript`) |

**How hooks work**:
- `PreToolUse` hooks run BEFORE a tool executes. Exit 2 = blocked. Exit 0 = allowed.
- `PostToolUse` hooks run AFTER. Informational only.
- Hooks load at session start. **Changes require restarting Claude Code.**
- The delegate guard is session-scoped via `CLAUDE_CODE_SESSION_ID` (matches the hook-stdin `session_id`) and self-heals a stale sentinel after `TTL_MINUTES` (default 90). **Session isolation requires Claude Code ≥ v2.1.132**; below that it falls back to the legacy global path with the TTL as sole guard.
- `design-scope-guard.sh` mirrors the same session-scoped sentinel pattern, armed/disarmed by `/design` itself around its Step 6 promotion write (TTL 120 min — generous, since the sentinel only needs to survive a single short write window rather than a whole `/build` run).
- Debug: `claude --debug` | View loaded hooks: `/hooks`

---

## Context Window Strategy

The harness is designed to keep the main conversation's context clean:

| What | Where it happens | Tokens in main context |
|---|---|---|
| Voice note / spec | User pastes | ~500 |
| Research (per question) | researcher subagent | ~500-1K (summary only) |
| Codebase exploration | Explore subagent | ~200-500 (summary only) |
| Design output | Main thread | ~2K |
| Implementation | implementer subagent | ~500 (summary only) |
| Code review | reviewer subagent | ~500 (summary only) |
| Ship / PR | Main thread | ~1K |

**Full feature cycle**: ~5-10K tokens in main context. Without subagents, research alone can consume 50K+.

**Tips**:
- Use `/clear` between unrelated tasks
- For large features: one session per phase
- The status bar shows context usage — watch for >70%

---

## CLAUDE.md (Global Rules)

`~/.claude/CLAUDE.md` contains always-on advisory rules:
- Feature branches only, conventional commits, co-author line
- Research-first design: check docs before making architecture decisions
- Flag unsourced decisions explicitly
- Context hygiene: use subagents for heavy output
- Stack preferences: SwiftUI async/await, Python type hints, Next.js strict TS

These have ~70% compliance. For critical rules (branch protection, secrets), hooks provide 100% enforcement.

---

## Modifying the Harness

### Add a new hook
1. Create script in `~/.claude/hooks/`
2. Add entry to `hooks` in `~/.claude/settings.json`
3. Restart Claude Code

### Add a new skill
1. Create `~/.claude/skills/<name>/SKILL.md` with YAML frontmatter
2. Available immediately (no restart needed)

### Add a new agent
1. Create `~/.claude/agents/<name>.md` with YAML frontmatter
2. Available immediately for spawning

### Key frontmatter fields
- **Skills**: `name`, `description`, `allowed-tools` (pre-approval), `disable-model-invocation`, `argument-hint`
- **Agents**: `name`, `description`, `model`, `effort` (sets the subagent's reasoning effort tier), `tools`, `disallowedTools`, `maxTurns`, `skills`, `mcpServers`, `memory`, `permissionMode`, `color` (named colors only)

---

## Future Expansions

Deferred until 1-2 weeks of use:
- **Stop hook**: Prompt-type hook checking if Claude explained reasoning
- **SessionStart hook**: Auto-inject git status, recent commits at session start
- **Auto-format hook**: Run prettier/black/swiftformat after writes
- **`/test` skill**: Project-specific test orchestration
- **`/retro` skill**: Post-merge retrospective generation
- **Xcode MCP**: `claude mcp add --transport stdio xcode -- xcrun mcpbridge` for SwiftUI previews + diagnostics
- **XcodeBuildMCP**: Headless builds, tests, simulators via [github.com/getsentry/XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)

---
