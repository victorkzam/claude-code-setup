# Manual pre-PR checklist — `/setup` walkthrough

This is the **pre-PR human gate** for the repo-scoped `/setup` router skill
(`.claude/skills/setup/SKILL.md`). The skill orchestrates the four scripts and cannot be
fully verified by the automated `.bats` suites, because its behavior is a *conversation*
(diffs shown, consent taken, prompts raised). Walk a temp clone through `/setup` and confirm
each item below before opening the PR.

## Setup

1. `git clone` this repo (or copy the working tree) into a scratch dir, e.g.
   `/tmp/ccs-setup-test`.
2. Point Claude Code's config dir at a **throwaway** location (do NOT test against your real
   `~/.claude`) — e.g. export the config-dir override the scripts honor, or use a disposable
   `$HOME`. Confirm the target is disposable before running any `--apply`/`--force`.
3. Open Claude Code inside the clone and run `/setup`.

## Checklist

### Preflight (P1)

- [ ] `/setup` runs `bash scripts/check.sh` first, before any install/merge.
- [ ] **Exit-2 stops the whole flow.** Force a FAIL (e.g. a config the check rejects); confirm
      the flow STOPS, shows the `FAIL:` lines verbatim, and does NOT proceed to install.
- [ ] On a WARN (exit 1), the session presents the warnings and **asks** before continuing.

### Install (P2)

- [ ] A **dry-run (`install.sh --dry-run --diff`) plan is shown before** the real install.
- [ ] The real `install.sh` run triggers a **permission prompt** (writing form is not
      pre-approved) — the prompt is expected, not a bug.
- [ ] The `CCS-STATUS:backup-dir:<path>` first status line is captured and reported.
- [ ] Differing files are **skipped**; per-category diff is shown and keep-vs-overwrite is
      asked; overwrite uses `install.sh --force=<category> --backup-dir <path>`.

### Merges (P3)

- [ ] A **unified diff is shown before EVERY consent** — for `settings.json` and for
      `CLAUDE.md`, no exceptions.
- [ ] Targets are handled **one at a time**: `settings.json` first, then `CLAUDE.md`.
- [ ] **A declined merge is respected:** decline one merge and confirm NO write happens, and
      there is **no nag-loop** / re-ask (the decline is just recorded in conversation).
- [ ] **Existing-config path shows the withheld-convenience-keys note** (model / statusLine /
      defaultMode not merged; copy from `settings.example.json` if wanted). Test against a
      pre-existing `settings.json`, not a fresh write.

### Backup threading (cross-phase)

- [ ] The **backup dir from install is threaded into every apply/force** — one run dir, one
      receipt for the whole session. Confirm no second/stray backup dir is created.

### Handoff (P4) + idempotency

- [ ] Handoff prints the **receipt location + backup dir** and the "what behaves differently
      now" 3-line summary (main pushes blocked; delegation guard during `/build`; design +
      pre-PR checkpoints enforced).
- [ ] Post-restart steps are handed to the **user to run after restarting** (not executed by
      the skill): restart → `bash scripts/check.sh --post` → `/hooks`.
- [ ] After restart, `check.sh --post` **verifies success** and `/hooks` shows the managed
      hook entries loaded.
- [ ] **Re-run `/setup` after an abort resumes idempotently:** abort partway, re-run, and
      confirm unchanged files no-op (`CCS-STATUS:unchanged:...`) and no duplicate writes.

## Cleanup

- [ ] Delete the scratch clone and the throwaway config dir. Confirm your real `~/.claude` was
      never touched.
