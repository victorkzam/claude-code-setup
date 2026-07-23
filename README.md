# Claude Code Setup

A user-level `~/.claude` configuration for [Claude Code](https://claude.com/claude-code):
a `/design` → `/build` → `/ship` agentic workflow, six specialized subagents,
model-routing rules, and a small set of hooks that turn advisory conventions into
enforced ones. This is a sanitized export of a daily-driver setup, offered as a
clone-and-use template — installed via a repo-scoped `/setup` skill (see
[Quick Start](#6-quick-start-clone-and-use)) that installs and merges everything
with a diff and your explicit consent, or, if you'd rather skip the
conversational flow, [four scripts](#7-standalone-install-no-llm-run-the-scripts-directly)
you can run by hand.

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
git clone https://github.com/<you>/claude-code-setup.git
cd claude-code-setup
claude
```

When Claude Code opens inside the clone for the first time, it shows a **trust
dialog** for the folder. **Accept it.** Trusting the repo is what gates access
to its `.claude/` directory — until you accept, the repo-scoped `/setup` skill
and its pre-approved read-only commands (`check.sh`, the `--dry-run` forms of
the install/merge scripts) aren't available to the session at all. This is a
one-time, per-directory Claude Code trust decision, not something this repo
configures.

Once trusted, type:

```
/setup
```

`/setup` walks a **preflight → install → merge → handoff** flow
(`.claude/skills/setup/SKILL.md`). It runs a dry-run and shows you a diff
before every write, and asks for explicit consent before anything actually
changes your `~/.claude` config — nothing is written silently. Differing files
are skipped by default per category (agents/hooks/rules/skills); you choose
keep-vs-overwrite per category. `settings.json` and `CLAUDE.md` are merged one
at a time, each behind its own diff-then-consent step.

> [!WARNING]
> **Never clone this repo directly into `~/.claude`, and never point
> `CLAUDE_CONFIG_DIR` at this clone.** The scripts refuse to install a repo
> onto itself (a source-equals-destination guard checks for exactly this), but
> don't rely on that guard — treat the clone and your Claude config dir as two
> separate locations, always. The scripts honor `CLAUDE_CONFIG_DIR` as an
> override for the config dir they install into/read from (default
> `~/.claude`); set it if your Claude Code config lives somewhere non-default.

## 7. Standalone install (no LLM, run the scripts directly)

If you'd rather not run `/setup` conversationally — or you're scripting an
install — the four scripts it orchestrates can be run by hand, in this order.
**Run them with `bash`, not `sh`** — they're bash scripts (`set -euo pipefail`,
bash-specific idioms) and will fail or behave incorrectly under a POSIX `sh`:

```bash
bash scripts/check.sh                                   # preflight
bash scripts/install.sh --dry-run --diff                # see the plan first
bash scripts/install.sh                                  # real install (prints a backup-dir path — save it)
bash scripts/merge-settings.sh --dry-run                # see the settings.json diff
bash scripts/merge-settings.sh --apply --backup-dir <path>
bash scripts/merge-claude-md.sh --dry-run               # see the CLAUDE.md diff
bash scripts/merge-claude-md.sh --apply --backup-dir <path>
```

Thread the same `--backup-dir <path>` (captured from `install.sh`'s first
`CCS-STATUS:backup-dir:<path>` line) into every later `--apply`/`--force` call,
so the whole install shares one backup run dir and one receipt.

## 8. Verify the install

1. **Restart Claude Code** — hooks and skills load at session start, so a
   fresh install/merge only takes effect after a restart.
2. Run:

   ```bash
   bash scripts/check.sh --post
   ```

   to confirm the managed artifacts landed under your config dir.
3. Run **`/hooks`** and confirm the managed hook entries appear.

## 9. Updating

```bash
cd claude-code-setup   # your existing clone
git pull
```

Then, **from inside the clone**, run `/setup` again. Any file you've
customized since the last install surfaces as a per-category diff/prompt —
it's **skipped by default** and only overwritten if you explicitly consent;
nothing you've changed is clobbered silently.

## 10. Uninstalling

There's no uninstall script yet (deliberately deferred — see below); removal
is manual but deterministic because every write is logged to a **receipt**.
The receipt for a given install lives at `<backup-run-dir>/receipt.txt`, where
`<backup-run-dir>` is a timestamped directory under
`~/.claude/backups/claude-code-setup/<timestamp>/` (or under `$CLAUDE_CONFIG_DIR`
if you've overridden it). Each line is tab-separated:
`action  path  backup-path  repo-sha  timestamp`.

Walk the receipt and act **per `action`**, in this order — the ordering
matters because it's what protects data that predates the install:

- **`installed`** — the file didn't exist before `/setup`; `rm` it.
- **`overwritten`** — a file you already had was replaced; **restore it from
  the backup path on that line** (do **not** `rm` it — `rm` would destroy the
  original the backup exists specifically to preserve).
- **`merged`** — if the backup-path field is non-empty, same as
  `overwritten`: **restore from the backup path** on that line (never `rm`
  it). If the backup-path field is **empty**, the file didn't exist before
  `/setup` and was created fresh by the merge — `rm` it, same as `installed`.
- **`unchanged`** — the file already matched what `/setup` would have
  written, so nothing was touched; leave it alone. (Earlier runs' lines still
  govern it if you ran `/setup` more than once.)
- **`skipped`** — nothing was written; leave it alone.

If you ran `/setup` more than once (e.g. across an update), restore from the
**earliest** run's backups — that's the true pre-setup state; later runs'
backups are snapshots of an already-modified file, not the original.

## 11. Prerequisites

- **jq** — REQUIRED. `protect-branches.sh` and `protect-secrets.sh` fail closed
  without it: they block the corresponding git operations/edits entirely rather
  than silently skip the check if `jq` isn't installed. `brew install jq` /
  `apt install jq`.
- **git** — obviously; also needed for `git identity` (`user.name` /
  `user.email`) so the workflow's own commits (one per `/build` task, plus
  `/ship`) have an author.
- **Claude Code ≥ v2.1.53** — REQUIRED. This is a security floor
  (CVE-2026-33068); `check.sh` fails closed below it.
- **Claude Code ≥ v2.1.198** — RECOMMENDED, for the full feature set: the
  custom `Explore` agent's model override (below this version it inherits the
  session's main-thread model instead of running on `haiku`), and
  session-scoped sentinel isolation in `orchestrator-delegate-guard.sh` (fully
  available from ≥ v2.1.132; below that the guard falls back to a legacy
  global sentinel with only a TTL as backstop).
- **gh** — the GitHub CLI, needed **only for `/ship`'s** PR creation, not for
  install. Run `gh auth login` before your first `/ship`.
- **shellcheck + bats** — DEV-ONLY, for contributing to this repo's own
  scripts/tests. Not required to adopt or run `/setup`.
- **context7 + exa MCP servers** — OPTIONAL. `skills/search/SKILL.md` falls
  back to `WebSearch` for any angle where an MCP tool is unavailable; `/design`
  and `/search` degrade gracefully without them, just with less precision
  (context7's version-pinned docs, exa's semantic search).

## 12. Troubleshooting

- **`/setup` doesn't appear.** Confirm you accepted the folder's **trust**
  dialog, and that you're running Claude Code from inside the clone (the skill
  is repo-scoped, not installed globally). Then restart Claude Code once —
  skill discovery has known upstream flakiness on a fresh trust grant
  ([anthropics/claude-code#45956](https://github.com/anthropics/claude-code/issues/45956),
  [anthropics/claude-code#43092](https://github.com/anthropics/claude-code/issues/43092)).
  If it still doesn't appear, `bash scripts/check.sh` will surface targeted
  fixes for common environment issues.
- **`check.sh --post` shows a `FAIL:` line.** A managed artifact is missing
  from your config dir — re-run `/setup` to install it.
- **`check.sh --post` shows a `WARN: ... ignore if you declined this merge`.**
  This is informational, not an error — it means you chose not to merge
  `settings.json` or `CLAUDE.md`, and the check is just confirming that.
- **A hook is blocking legitimate work.** See the `protect-secrets` note
  below.

**`protect-secrets` self-lockout note**: once installed, the `protect-secrets`
hook blocks Claude Code itself from writing/editing files matching secret
patterns (`.env`, `*credentials*`, `*.pem`, SSH/AWS/GCP key paths, etc.) — and
it applies in **every** project you use Claude Code in afterward, not just this
one, because it's wired into your global `~/.claude/settings.json`. If it
blocks something you legitimately need to edit, that settings file is yours:
edit or remove the hook entry directly. Re-running `/setup` later will offer
to re-merge it, but it will never force the merge back in without your
consent.

**Plugin packaging (future work)**: a Claude Code plugin is a plausible future
distribution mechanism for this setup. Today's clone-and-use + `/setup`
approach was chosen deliberately instead — current plugin docs impose
verbatim-file limits that don't fit this repo's merge-not-clobber model for
`settings.json`/`CLAUDE.md`.

**Backups accumulate**: backup run directories under
`~/.claude/backups/claude-code-setup/` are never auto-deleted (there's no
pruning script yet). They're cheap to keep and are what makes uninstall
deterministic, but feel free to delete old ones by hand once you're confident
you won't need to restore from them.

## 13. What to adapt vs keep

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
