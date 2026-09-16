# claude-code-setup

This repo is the Claude Code plugin `cw`: skills, agents, hooks, and rules for
a design -> build -> ship workflow.

Tests: bash tests/run.sh all

## Conventions
- Conventional Commits: feat:, fix:, refactor:, docs:, chore:, test:.
- Every commit ends with:
  Co-Authored-By: Claude <noreply@anthropic.com>
- Design docs: a single-file plan at `docs/plans/<slug>.md` is tracked by
  default. A folder-style artifact set needs both `!docs/plans/<slug>/` and
  `!docs/plans/<slug>/**` added to `.gitignore` before `/cw:build` runs
  against it.
- Feature branches only; work reaches the default branch through a pull
  request, opened only after the quality gate passes.
