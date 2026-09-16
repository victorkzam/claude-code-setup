# cw — a Claude Code workflow plugin

This repo *is* the Claude Code plugin `cw`: six skills, five agents, three
hooks, two rule files, one test runner, and CI. It implements a
`/cw:design` -> `/cw:build` -> `/cw:ship` pipeline — research-grounded
planning, delegated implementation with one atomic commit per task, and a
verified, gated release — plus `/cw:compound` to feed lessons back into your
own project's rules. See `WORKFLOW.md` for the full pipeline narrative and
`rules/orchestration.md` for the model-routing table.

## Requirements

- **Claude Code >= 2.1.269** — the version this plugin was built and tested
  against (plugin agent-frontmatter parsing, `claude plugin eval`).
- **git** — for the workflow's own commits and branch checks.
- **jq** — used by every hook. Without it, `protect-branches.sh` and
  `protect-secrets.sh` each print a warning to stderr and stand down (exit 0,
  no enforcement) rather than block your session.
- **A session in auto mode or `acceptEdits` for `/cw:build`** — a plugin
  agent cannot grant itself a permission mode, so the implementer subagents
  need the session already in one of these modes to write without a prompt
  per edit.

## Install

Three ways to load this plugin, in order of how much you intend to edit it.

### (a) In place — for editing the plugin itself

```bash
ln -s /path/to/your/checkout "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/cw"
```

Claude Code loads any folder under a skills directory that has a
`.claude-plugin/plugin.json` as a plugin named `cw@skills-dir` — no
marketplace, no install step. `SKILL.md` edits apply immediately; reload
agents and hooks with `/reload-plugins`.

This is the least robust path: Claude Code's auto-update has been reported to
silently remove symlinks under the config dir
([issue #50052](https://github.com/anthropics/claude-code/issues/50052)). If
that bites you, fall back to a real directory instead of a symlink — move
your checkout itself under `<config dir>/skills/cw`, and symlink *back* from
wherever you actually edit (your normal projects directory, an IDE workspace,
etc.) to that real location.

### (b) Marketplace — the reliable path for adopters

```bash
claude plugin marketplace add victorkzam/claude-code-setup
claude plugin install cw@claude-code-setup
```

This installs a copy into the plugin cache
(`~/.claude/plugins/cache/claude-code-setup/cw/`), independent of any local
checkout. Update it with `claude plugin update cw@claude-code-setup`.

### (c) Trial — no install at all

```bash
claude --plugin-dir /path/to/your/checkout
```

Loads the plugin for that session only.

## Commands

| Command | What it does | Claude may invoke it on its own? |
|---|---|---|
| `/cw:design <description>` | Research-grounded design; ends in one approved plan file | Yes — description-triggered |
| `/cw:build <slug> [continue [<task-id>]]` | Orchestrates implementation via subagents, one commit per task | No — manual only |
| `/cw:ship [title]` | Verifies the commit series, runs the gate, pushes, opens the PR | No — manual only |
| `/cw:compound [range]` | Captures lessons from a shipped change into CLAUDE.md/rules | No — manual only |
| `/cw:search [--quick\|--deep] <query>` | Multi-source web research with citations | Yes — description-triggered |
| `/cw:google-workspace` | Google Docs/Drive routes and dead ends playbook | Yes — description-triggered |

`/cw:build`, `/cw:ship`, and `/cw:compound` are marked
`disable-model-invocation: true` deliberately — they change files, branches,
or open PRs, so they only run when you type the command.

## Agents

| Agent | Model | Role |
|---|---|---|
| `cw:researcher` | sonnet | Web research, read-only |
| `cw:implementer` | sonnet (opus per-task for hard work) | Writes code, makes the task's commit |
| `cw:reviewer` | opus | Reviews an implementer's diff, read-only |
| `cw:design-reviewer` | opus | Doc/codebase fidelity review of a design draft |
| `cw:direction-reviewer` | opus, effort xhigh | Premise/direction review, once per design |

## A profile CLAUDE.md

A profile's `CLAUDE.md` is deliberately short — an identity line and two
imports for the process rules this plugin ships:

```markdown
# Your profile
Profile: acme
@<checkout>/rules/workflow.md
@<checkout>/rules/orchestration.md
```

Stack preferences (language conventions, framework choices) belong in your
*project* `CLAUDE.md` files, not in this profile file — this one is workflow
process, not stack opinion.

The import path depends on how you installed:

- **(a) in place / (c) trial** — import from your checkout directly:
  `@<checkout>/rules/workflow.md`.
- **(b) marketplace** — run `claude plugin details cw@claude-code-setup` to
  print the current cache path and import from there; that path changes on
  every `claude plugin update cw@claude-code-setup`, so re-check it after
  updating, or keep a separate throwaway clone just for stable import paths.

Also set `plansDirectory: docs/plans` in your settings so `/cw:design`'s plan
mode writes the plan file into the project instead of the default location.

## Extra profiles

Run more than one Claude Code identity (work vs. personal, or one per client)
with `CLAUDE_CONFIG_DIR`:

```bash
alias claude-acme='CLAUDE_CONFIG_DIR=$HOME/.claude-acme claude'
```

An alias survives GUI launchers better than a one-off shell export. List the
mapping between project paths and config dirs in `~/.claude-profiles`, one
per line, `<folder prefix>|<config dir>`, `#` comments allowed:

```
~/work/acme|~/.claude-acme
~/side-projects|~/.claude-personal
```

The `profile-check.sh` `SessionStart` hook reads this file and reports a
`wrong profile: ...` notice if the active config dir doesn't match the
mapped one for your current directory, and a `missing import: ...` notice
for any `@import` line in `CLAUDE.md` whose target doesn't exist.

## settings.example.json

Use `settings.example.json` as a starting point, not a drop-in replacement —
copy it to `settings.json` and adapt it. It sets `defaultMode: "auto"`,
`effortLevel: "high"`, `plansDirectory: "docs/plans"`, a short generic
`permissions.deny`/`allow`/`ask` set, `autoMode.allow: ["$defaults"]`, and
`enabledPlugins` for the official TypeScript, Python, and Rust LSP plugins
from the `claude-plugins-official` marketplace. It carries no `hooks` key —
this plugin registers its own hooks, and a plugin hook and a settings hook
with the same command both fire, so don't add them again in `settings.json`.

**What to adapt**: the `permissions.allow`/`deny` lists for your own
workflow, the model alias mappings in `rules/orchestration.md` if you have
different tier preferences, and the identity line in your profile
`CLAUDE.md`. **What to keep as-is**: the workflow rules in
`rules/workflow.md`, the checkpoint semantics, and the hooks.

## Kill switch

```bash
claude plugin disable cw@skills-dir        # install path (a)
claude plugin disable cw@claude-code-setup # install path (b)
```

Turns all three hooks off at once. This is also the answer for a repo that
pushes to `main` by convention — `protect-branches.sh` has no opt-out
environment variable by design, so disabling the plugin is the supported
escape hatch, not a bypass flag on the hook itself.

## Migration from the old installer

If you previously installed this project's skills, agents, and hooks
directly into `~/.claude` (five skills, six agents, five hooks) rather than
as a plugin: delete those user-scope copies, and remove their `hooks` entries
from `settings.json`. A plugin hook and a settings hook that share the same
command both fire, so leaving the old entries in place double-runs them.

## `/cw:search --deep`

The `--deep` flag hands off to the bundled `/deep-research` workflow, which
needs dynamic workflows enabled (a paid-plan feature; `disableWorkflows`
turns it off). Without that, `/cw:search` falls back to its default
multi-source mode.

## Update and uninstall

- **(a) in place** — `git pull` in your checkout; a symlinked install picks
  it up on the next `/reload-plugins`, a real-directory install picks it up
  immediately. Remove the symlink (or directory) to uninstall.
- **(b) marketplace** — `claude plugin update cw@claude-code-setup` to pull
  the latest version; `claude plugin uninstall cw@claude-code-setup` to
  remove it.
- **(c) trial** — nothing persists; just stop passing `--plugin-dir`.

## Running the tests

```bash
bash tests/run.sh all
```

Runs hook behavior, file-size budgets, a cross-file phrase-duplication check,
and the `settings.example.json`/`tests/settings-keys.txt` cross-check.
Optionally set `CW_SCAN_PATTERNS=<your private pattern file>` to also scan
the tracked tree for private strings you've defined — this is empty by
default and off unless you set it.

## Changelog

### 1.0.0

First release as a Claude Code plugin. Converts the prior clone-and-use,
conversationally-installed configuration into a proper plugin (`cw`): a
plugin manifest and marketplace entry, lean skill and agent prompts, hooks
registered through `hooks/hooks.json` (including a new `profile-check.sh`
`SessionStart` hook), a single `tests/run.sh` test runner replacing the old
per-script tests, and CI running the same checks on every push and PR.
