# Workflow Rules

Process rules for the cw plugin, imported by a profile's CLAUDE.md. Model
routing and workflow usage follow the orchestration rules.

## Workflow
- Feature branches only; work reaches the default branch through a pull request.
- Conventional Commits: feat:, fix:, refactor:, docs:, chore:, test:.
- Every commit ends with the co-author trailer:
  Co-Authored-By: Claude <noreply@anthropic.com>
- No implementation without an approved design. If uncertain, ask first.
- Two human checkpoints, both non-negotiable: after the design, before the PR.
- `/cw:design` runs in plan mode; on approval the single plan file moves to the
  project's `docs/plans/<slug>.md`, which is the canonical copy. In a folder
  that is not a repo the file stays where plan mode put it.
- `/cw:build <slug> [continue [<task-id>]]` reads the `## Tasks` section of that
  file, commits the design as `docs(<slug>): design`, delegates every change to
  an implementer, and stops at the checkpoint before the PR.
- `/cw:ship` runs the quality gate, pushes the branch, opens the PR, and ends by
  offering `/cw:compound`.
- `/cw:build` and `/cw:ship` run in execute mode (auto or acceptEdits).
- Edits to process rules (a CLAUDE.md, these rules files) stay out of the
  feature PR; they are their own change.

## Research-first design
- Check official docs with context7 before writing code against any API.
- Search for best practices (exa or web search) before architecture decisions.
- Flag unsourced decisions explicitly: "Note: this approach is unsourced — my
  judgment call."
- Prefer boring, proven patterns over novel ones unless there is a clear reason.

## Context hygiene
- Use subagents for tasks whose output would bloat the main context:
  exploration, review, large diffs.
- Suggest `/clear` between unrelated tasks.
- For large features, suggest one session per phase.
