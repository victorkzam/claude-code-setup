## §R1 Research: codebase (Explore haiku + orchestrator git inspection, 2026-09-16)

### R1.1 Baseline tree
Repo `claude-code-setup`, commit 53b6bb9 = head of PR #2 (`feat/project-local-docs`, 19 commits
over `main` e87cac6, no divergence, so the merge result equals this tree). Line counts (`wc -l`):
- `skills/`: design 285, build 272, ship 153, search 129, compound 59.
- `agents/`: direction-reviewer 78, design-reviewer 69, researcher 59, reviewer 47, implementer 43,
  Explore 34.
- `rules/orchestration.md` 47. No `rules/workflow.md`, no `rules/google-workspace.md`.
- `hooks/`: orchestrator-delegate-guard 128, design-scope-guard 127, protect-branches 97,
  syntax-check 38, protect-secrets 26. No `hooks.json`, no profile check.
- `scripts/`: check.sh 298, merge-settings.sh 269, install.sh 241, lib.sh 174, merge-claude-md.sh
  160, manifest.txt 17 (manifest-driven installer for user-scope copies).
- `tests/`: merge-settings.bats 356, install.bats 331, hooks.bats 329, check.bats 326,
  merge-claude-md.bats 195, e2e.bats 128, test_helper.bash 50, manual-setup-checklist.md 51.
  `hooks.bats` covers ONLY the delegate guard and the design-scope guard; protect-branches.sh
  and protect-secrets.sh have no behaviour tests today.
- `.github/workflows/ci.yml` 65: job `lint-and-test` (ubuntu: `shellcheck -x --severity=error
  scripts/*.sh hooks/*.sh` — the severity floor tolerates five pre-existing findings in the
  two protect hooks —, `bats tests/*.bats`, manifest diff) and job `bats-macos` (system bash
  3.2).
- `README.md` 372 (14 sections; install by `git clone https://github.com/<you>/...` with a
  `<you>` placeholder for the owner), `WORKFLOW.md` 298, `CLAUDE.md` 48 (a template for the
  adopter's user-scope CLAUDE.md with fenced `workflow-rules v1` markers, merged by the
  installer — not a project file for this repo), `settings.example.json` 90 (registers the
  five hook scripts by `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/...`; its top-level keys
  include two `_comment_*` entries), `.claude/skills/setup/SKILL.md` 184 (`/setup`
  orchestrating the scripts), `LICENSE` (MIT, the maintainer's name as copyright holder),
  `src.txt` (an untracked, ignored placeholder — not part of the tree). No `.gitattributes`.
- Bytes of `skills/*/SKILL.md` + `agents/*.md` + `rules/*.md` at 53b6bb9: **73,738** (the
  lean-cut baseline).
- `.gitignore` is default-deny (`*`) with an allowlist: `.gitignore`, `.gitattributes`,
  README, LICENSE, CLAUDE.md, WORKFLOW.md, settings.example.json, `rules/**`, `agents/**`,
  `skills/**`, `hooks/**`, `scripts/**`, `tests/**`, `docs/plans/**`, `docs/research/**`,
  `.github/**`, `.claude/skills/setup/**`; explicit ignores for local state (incl.
  `settings.local.json`) and `.claude/settings.json`; an uncommitted working-tree line ignores
  a stale mirror directory of the private predecessor design (byte-identical to its private
  archive). **`.claude-plugin/` is not allowlisted, so a plugin manifest would be ignored until
  the allowlist changes.** `docs/plans/cw-plugin/x` is un-ignored (line 33).
- Personal or employer strings in the tree (case-insensitive: the owner's handle, absolute home
  paths, employer names, a personal repo name, the owner's first name): only `LICENSE:3`
  (copyright, keep) and `scripts/merge-claude-md.sh:5` (a comment; the file is deleted).

### R1.2 Frontmatter at 53b6bb9
- Skills: build and ship and compound carry `disable-model-invocation: true`; design and search
  are model-invocable with trigger phrases; build's `argument-hint` lacks `continue` (the live
  copy has it); design has no `effort:`.
- Agents: design-reviewer `model: opus, effort: xhigh, maxTurns: 25, skills: [search],
  mcpServers, memory: project`; direction-reviewer `opus, xhigh, 15, tools: Read/Glob/Grep,
  memory: project`; implementer `sonnet, high, 50, permissionMode: acceptEdits, mcpServers:
  [context7], memory: project`; reviewer `opus, xhigh, 20, tools: Read/Glob/Grep/Bash,
  disallowedTools: Write/Edit, memory: project`; researcher `sonnet, high, 30, skills:
  [search], mcpServers`; Explore `haiku, tools: Read/Glob/Grep` (exists only to force haiku on the
  built-in Explore, which inherits the session model since v2.1.198). All six carry
  `disallowedTools` (dropped by the rewrite).

### R1.3 Live-ahead items to carry (live profile `~/.claude` versus the repo)
- `rules/orchestration.md`: live 63 lines; the repo lacks the "Review-loop anti-ratchet"
  section (structured findings, accept/drop before redraft, 1–2 round cap, mechanical limits,
  minimal fixer context). Base the rewrite on LIVE.
- `hooks/protect-secrets.sh`: live 30 lines; only LIVE has the template allowlist
  (`.env.example|.env.sample|.env.template|env.example` by basename → allow); its comment
  carries personal context (strip). Only the REPO has the jq presence check. Both: lowercase
  the path; block `*.env`, `*.env.*`, `*.envrc`, `*credentials*`, `*secret*`, `*config.swift`,
  key files (`.pem .key .p8 .pfx .jks .keystore`, `id_rsa*`, `id_ed25519*`), `.aws/`, `.ssh/`,
  `.gnupg/`, `secrets/`, `*service-account*.json`, `*gcp*key*.json`; read
  `.tool_input.file_path // .tool_input.filePath`.
- `hooks/protect-branches.sh`: live 107 lines; only LIVE has a machine-specific exemption — a
  block that sets an `EXEMPT` flag plus four later branch points that read it (remove all of
  them); the REPO blocks every `--force` uniformly and has the jq check. Both live hooks
  carry shellcheck findings at the default severity (the old CI gated at `--severity=error`
  for that reason); the ports must be clean at the default severity.
- `hooks/check-account-routing.sh` (live only, 17 lines, unwired): the precursor of
  profile-check; it exits 2 on SessionStart, which would block session start (§R2.5), so its
  shape is not reused. Both:
  tokenise the command (env assignments, git global options), detect `push`, resolve a
  refspec-less push to the current branch, block a main/master destination and bare
  `--force`/`-f`, allow branch names that merely contain "main" (e.g. `feat/main-nav`).
- `skills/build/SKILL.md`: live 259 lines; only LIVE has the `continue` argument hint (resume
  a build; refreshed artifacts excluded from one-commit-per-task accounting) — the hint only;
  Phase 0 has no `continue` branch in either copy. Repo 272 lines.
- `skills/design/SKILL.md`: live 275, repo 285 (the repo carries the fuller Step 6 promotion
  and guard choreography that the rewrite deletes).
- Live-only files: `rules/google-workspace.md` (27 lines: capability matrix for the Drive/Docs
  connector, upload routes, seven landmines; four lines carry personal context — strip) and
  `skills/deep-research/` (not in the repo; the bundled `/deep-research` replaces it).
- The live `~/.claude/CLAUDE.md` (37 lines) holds the workflow rules the new `rules/workflow.md`
  bases on: branch policy, Conventional Commits with the `Co-Authored-By: Claude
  <noreply@anthropic.com>` trailer, design-first with two checkpoints, one commit per task,
  PR only after the gate, `/ship` offers `/compound`, process-rule edits never in the feature
  PR, research-first (context7 before APIs, unsourced decisions flagged), context hygiene.

### R1.4 Lean-cut targets found in the repo prompts
- Whole-word capitals: NEVER ×5 in ship (safety list), ×1 build; MUST in search and
  orchestration; ALWAYS/NEVER in syntax-check.sh (deleted); none in agents.
- Sentinel choreography (`/tmp/claude-design-active`, `/tmp/claude-orchestrator-active`):
  design lines 14–15, 194, 196, 244; build 97, 112, 124 — deleted with the guards.
- Rule phrases present in more than one prompt file (the dedupe clusters, §D2.2): never push
  main (ship, and CLAUDE.md/WORKFLOW/README docs), one atomic commit per task (design 81,
  build throughout), trailer (design 135, build 96, ship 41), NO_VERDICT (design 164, build
  218–221 and 269, orchestration 40), fresh-context counter-model reviewer (orchestration
  36–37, design 145, build 179–180), same-turn spawn (design 81, build 123), root-anchored
  check-ignore (design 205, build 88), context7 before APIs (implementer 32, design-reviewer
  40), three-angle methodology (design-reviewer 40, search), functions under 50 lines
  (reviewer 33), explicit model per Agent call (orchestration 15, design 81–83),
  `/compound` never commits (compound 3). Docs (README, WORKFLOW) may restate rules; the
  dedupe gate covers `skills/`, `agents/`, `rules/` only.
- Model workarounds and nudges to delete: "Opus needs the fan-out stated explicitly"
  (design), "Read all files FRESH … Do NOT trust prior summaries" (build reviewer prompt),
  "known issue #24327" sentinel note (build), `.gitattributes` linguist line (build Phase 0),
  `git clean` allowed-tools grant (design), `docs/research` allowlist (guards). The design
  skill's Explore calls pass `model: haiku` (keep; the built-in inherits the session model).

### R1.5 The live `/build` and `/ship` that drive this build
`~/.claude/skills/build/SKILL.md` resolves `$ROOT/docs/plans/<slug>/<slug>-tasks.md` only when
`<slug>-design-draft.md` is present too (both written by `/design` Step 6), needs a clean
tree apart from `docs/plans/<slug>/`, creates `feat/<slug>` from `main`, commits the artifact
set as `docs(<slug>): add design + research artifacts` (and adds `docs/plans/**
linguist-generated=true` to `.gitattributes`, which the allowlist tracks), then runs tasks in
`depends_on` order with context-pinned implementers (each sees only its own task entry), a
ground-truth gate in which the orchestrator re-runs each task's `verification` itself,
counter-model reviewers, at most three iterations, and a human checkpoint; `commit: none`
tasks are verification-only; its `allowed-tools` pre-approve only `git`, `npm`, `python`,
`pip`, `pytest`, `swift`, `xcodebuild`, `gh`, so other commands prompt unless allowlisted.
The live `/ship` verifies the series, refuses staged files matching `*secret*` and `.env*`
(a rewritten `hooks/protect-secrets.sh` matches and must be waved through by the human),
detects the quality gate (`.claude/rules/pr-merge-policy.md` → a test command stated in the
project CLAUDE.md → convention fallback, where a `tests/` directory means `python -m pytest
-q`), offers a 3-lens panel when the design is tagged `risk: high`, pushes, opens the PR,
offers `/compound`. The live secrets hook blocks Write/Edit on any path matching `*secret*`,
so `hooks/protect-secrets.sh` must be written with Bash.
