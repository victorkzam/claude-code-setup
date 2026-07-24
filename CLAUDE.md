# Global Development Environment Rules

This is a template `~/.claude/CLAUDE.md`. It is always-on advisory context for
every project Claude Code touches. Sections marked "example — replace with
your own" are personal-preference blocks you should adapt or delete; the
`Workflow Rules` section is the transferable system this repo ships (see
`WORKFLOW.md`) and is meant to be kept largely as-is.

## Identity (example — replace with your own)
PM-turned-engineer. Quality and learning over speed. Always explain WHY behind architectural decisions, not just WHAT.

<!-- BEGIN claude-code-setup workflow-rules v1 -->
## Workflow Rules
- Never push directly to main/master. Feature branches only.
- Conventional Commits: feat:, fix:, refactor:, docs:, chore:, test:
- Co-author line on every commit:
  Co-Authored-By: Claude <noreply@anthropic.com>
- No implementation without an approved design. If uncertain, ask first.
- Two human checkpoints are non-negotiable: after design, before PR.
- Each task maps to exactly one atomic Conventional Commit, made by the implementer that did the task. `/ship` verifies the series; it never creates a catch-all or squashed commit.
- A PR is opened only after the feature/milestone is fully built AND the quality gate has passed. No PR on a red gate; no PR mid-build.
- Mode transitions: `/design` runs in plan mode; on plan approval it writes the artifact set to `<project>/docs/plans/<slug>/` (project copy canonical; plans-dir drafts banner-stamped; plans dir itself for non-repo/meta-tooling work); the post-design checkpoint precedes `/build`; `/build` commits the set as its leading `docs:` commit on the feature branch; `/build` and `/ship` run in execute mode.
- `/ship` ends by offering `/compound`. Process-rule edits (CLAUDE.md, `.claude/rules`) are never committed into the feature PR.
- Model routing and workflow usage follow ~/.claude/rules/orchestration.md.

## Research-First Design
- Before making architecture decisions, check official docs (use context7) and search for best practices (use exa/WebSearch).
- Flag unsourced decisions explicitly: "Note: this approach is unsourced — my judgment call."
- Prefer boring, proven patterns over novel ones unless there's a clear reason.

## Context Hygiene
- Use subagents for tasks whose output would bloat the main context (exploration, review, large diffs).
- Suggest /clear between unrelated tasks.
- For large features: suggest one session per phase.
<!-- END claude-code-setup workflow-rules v1 -->

## Stack Preferences (example — replace with your own; used only when a project's own CLAUDE.md is silent)
- iOS: SwiftUI, async/await, no completion handlers, // MARK: sections
- Python: type hints, Pydantic models, pytest, functions under 50 lines
- Web: Next.js App Router, TypeScript strict mode
- All: graceful error handling, no over-engineering

## MCP Servers (OPTIONAL)
The workflow degrades gracefully without these — see `skills/search/SKILL.md`'s
fallback rules. Install docs: [context7](https://github.com/upstash/context7),
[exa](https://github.com/exa-labs/exa-mcp-server).
- context7: Library/framework docs. Use BEFORE writing code against any API.
- exa: Semantic web search. Use for research, competitive analysis, best practices.
