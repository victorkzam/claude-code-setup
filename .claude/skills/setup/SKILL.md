---
name: setup
description: "Install this repo's Claude Code setup into the current machine's config dir. Runs ONLY when the user types /setup inside a clone of claude-code-setup — never model-invoked. Orchestrates the check/install/merge scripts through a preflight → install → merge → handoff flow, with a diff shown and explicit consent taken before every write."
disable-model-invocation: true
argument-hint: (no arguments — run inside a fresh clone of this repo)
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash(bash scripts/check.sh:*)
  - Bash(bash scripts/install.sh --dry-run:*)
  - Bash(bash scripts/merge-settings.sh --dry-run:*)
  - Bash(bash scripts/merge-claude-md.sh --dry-run:*)
---

# Setup Router — Adopter Install Flow

You are the session executing `/setup` inside a **clone of this repo** (this skill is
repo-scoped: it lives under `.claude/skills/` and is discovered only when Claude Code runs
in the clone — it is never installed onto an adopter's machine). Your job is to install this
setup's managed artifacts (agents/hooks/rules/skills), then merge `settings.json` and
`CLAUDE.md`, into the current machine's Claude config dir — **safely, with a diff shown and
explicit consent taken before every write**.

## Consent model (read before you start)

This flow has **two consent gates by design**, and you must not collapse either:

1. **Every write is preceded by a diff + an explicit ask.** You dry-run first, show the
   plan/diff, and ask the user to proceed.
2. **The writing commands are deliberately NOT pre-approved in `allowed-tools`.** Only the
   read-only and `--dry-run` forms are pre-approved. When you run the real install, a
   real `--force=<category>`, or a real `--apply`, Claude Code will raise a **permission
   prompt** — that prompt is the *intended* second gate, not a bug. Tell the user to expect
   it and let it happen; never try to route around it.

Do **not** invent Edit/Write shortcuts to config paths, and do not seek broader permission
grants to suppress those prompts.

## Script contract (shared by all four scripts)

- Machine lines `CCS-STATUS:<action>:<path>` print on **stdout**; human diffs/plan text also
  on stdout; refusals/errors on **stderr**.
- Exit codes: **0** success · **1** refusal / partial · **2** usage / internal.
- `scripts/install.sh` (non-dry-run) prints `CCS-STATUS:backup-dir:<path>` as its **first**
  status line. **Capture that path** — that ONE run dir is threaded via `--backup-dir <path>`
  into every later `--apply`/`--force` this session, so the whole install produces a single
  backup run dir and a single receipt.

## Global error rules (apply in every phase)

- **Any script exits 2** → STOP the entire flow. Report the script's stderr **verbatim**;
  do not attempt later phases.
- **Any script exits 1** → report its stderr **verbatim** and ask the user how to proceed
  (it is a refusal/partial, not a hard stop — the user decides).
- **Abort-safe / idempotent:** every phase is idempotent. If the flow is aborted partway,
  re-running `/setup` resumes safely — already-installed, identical files no-op
  (`CCS-STATUS:unchanged:...`), and merges recompute from current on-disk state. There is no
  state file; a declined step is simply remembered in this conversation.

---

## P1 — Preflight

Run:

```
bash scripts/check.sh
```

- **Exit 2 (FAIL)** → STOP. Present the `FAIL:` lines **verbatim** plus the fixes `check.sh`
  suggests. Do not proceed to P2.
- **Exit 1 (WARN)** → present the `WARN:` lines and **ask the user whether to proceed** given
  the warnings. Only continue if they say yes.
- **Exit 0 (PASS)** → proceed to P2.

## P2 — Install managed artifacts

1. **Dry-run first:**

   ```
   bash scripts/install.sh --dry-run --diff
   ```

   Present the plan: what would be installed (missing → install), what is identical
   (`unchanged`), and per-category **diffs for any differing files** (differing files are
   **skipped** by default, per category).

2. **Real install** (this is NOT pre-approved — expect a permission prompt; explain that to
   the user before running it):

   ```
   bash scripts/install.sh
   ```

   **Capture the first status line** `CCS-STATUS:backup-dir:<path>`. Save `<path>` — you will
   pass `--backup-dir <path>` to every later apply/force so the session shares one backup run
   dir and one receipt.

3. **Resolve skipped (differing) files.** Any file that differed was left untouched. For each
   affected **category**, show that category's diff and ask the user **keep vs overwrite**.
   Overwrite only the categories the user approves, one category per run:

   ```
   bash scripts/install.sh --force=<category> --backup-dir <path>
   ```

   (`<category>` is one of `agents`, `hooks`, `rules`, `skills`.) This run is also NOT
   pre-approved — the permission prompt is again the intended consent gate.

## P3 — Merge config files (one target at a time)

Handle **`settings.json` first, then `CLAUDE.md`**. For each target, always: dry-run → show
the unified diff → take **explicit consent** → apply with the shared `--backup-dir <path>`.

### P3a — settings.json

```
bash scripts/merge-settings.sh --dry-run
```

Show the unified diff. Ask for explicit consent. On yes:

```
bash scripts/merge-settings.sh --apply --backup-dir <path>
```

If the target already exists (an existing-config merge, not a fresh verbatim write), also
surface the **withheld-convenience-keys note** to the user:

> Convenience keys (model, statusLine, defaultMode) were not merged to avoid overwriting
> yours — copy from `settings.example.json` if wanted.

### P3b — CLAUDE.md

```
bash scripts/merge-claude-md.sh --dry-run
```

Show the unified diff. Ask for explicit consent. On yes:

```
bash scripts/merge-claude-md.sh --apply --backup-dir <path>
```

**Declines are respected.** If the user declines either merge, do not write, do not re-ask in
a loop, and do not nag — just record the decline in the conversation and move on.

## P4 — Handoff

The install is done from this session's side. Print, for the user:

- **Receipt location** and the **backup run dir** (`<path>` captured in P2).
- A short **"what behaves differently now"** summary (3 lines):
  1. Pushes to `main`/`master` are blocked (branch-protection hook).
  2. The delegation guard is active during `/build` (orchestrator can't hand-edit source).
  3. Design + pre-PR human checkpoints are enforced.

Then give the user the steps **they run AFTER restarting Claude Code**. The restart **severs
this session**, so the skill must NOT try to run these itself — hand them over as
instructions:

1. **Restart Claude Code** (so the newly installed settings/hooks/skills load).
2. Verify the install landed:

   ```
   bash scripts/check.sh --post
   ```

3. Confirm hooks loaded by running **`/hooks`** and checking the managed entries appear.

---

## Anti-patterns to avoid

- Do NOT skip the dry-run — a diff is shown before **every** consent, no exceptions.
- Do NOT collapse the two consent gates: never seek a broader grant to suppress the
  install/force/apply permission prompts.
- Do NOT thread multiple backup dirs — capture the ONE `CCS-STATUS:backup-dir:<path>` from
  P2 and reuse it for every apply/force.
- Do NOT re-ask a declined merge in a loop.
- Do NOT run the post-restart steps yourself — the restart ends this session; they are the
  user's to run.
- Do NOT continue past an exit-2 from any script — STOP and report verbatim.
