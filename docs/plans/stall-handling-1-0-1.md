# stall-handling-1-0-1

cw plugin release 1.0.1: sub-agent stall prevention and recovery, the lean orchestration
loop (plan C), and a session-labelled desktop notifier. Design date 2026-09-22, Claude Code
2.1.280, base `main` at 2e56128 (cw 1.0.0).

## Context

Three measured problems since 1.0.0 shipped, all recorded in the operator's project notes:

1. **Stalls.** Deep-review `cw:reviewer` agents (`maxTurns: 20`) ended without a verdict
   in 4 of 4 runs on 2026-09-21 and 2 of 4 on 2026-09-22; a resumed-turn nudge ("make no
   further tool calls, return the report") recovered every one in a single turn. Two
   `cw:implementer` runs on hook work exhausted 50 turns after the code was done, once
   with the commit made and once with the tree uncommitted; the orchestrator recovered
   both from `git status` plus the verification command. The skills and the orchestration
   rule still prescribe "retry once fresh", which discards 30+ tool uses of context.
   `memory: project` on the three reviewer agents spends turns writing memory files at the
   end of a run (documented behaviour, Research B9b); one stall was traced to exactly that.
2. **Loop cost.** One session that ran a build, a ship, a merge panel and a design measured
   about 1.6M sub-agent tokens plus a full orchestrator window: every reviewer returned a
   5–10k-token report inline, the orchestrator wrote a 730-line plan and edited it ~45
   times, research was folded verbatim, and the design loop allows 5 iterations plus a
   direction pass. The operator's feedback on 2026-09-22 asked for a redesign, not patches.
3. **Notifications.** The operator's user-level `Notification` hook has an empty matcher and
   a fixed text: 110 banners in one day, 62% of them the built-in `idle_prompt` 60–90 s after
   a turn end while background agents still ran, 6% coinciding with a sub-agent result, no
   session label across five concurrent sessions, and a Focus mode once swallowed a whole
   day (99 hook runs, 0 banners). Design input: the public brief in the operator's
   notification-hook folder (aggregate numbers only; nothing from its private notes is
   copied here).

Step 0 decisions (2026-09-22): premise validated, no cheap-invalidation detour; full plan C
folded in; notification presence policy ships behind a config flag, off by default; carry
the commit-pathspec and manifest nits, leave the protect-secrets self-exclusion for
`/cw:compound` (its exemption needs its own anchoring design).

Intended outcome: a stalled agent is recovered in one resumed turn and stalls become rare;
a design costs two review rounds and a plan under 400 lines; each phase starts fresh; the
desktop shows one ping, titled `<folder> · <session>`, only when a human is needed.

## Approach

**A. Stall prevention (agents).** Drop `memory: project` from `reviewer`, `design-reviewer`
and `direction-reviewer` (fresh context is their point; memory writes cost turns). Raise
`maxTurns` to 40 on `reviewer` and `design-reviewer` (deep briefs need 30–40 tool uses,
measured); `direction-reviewer` keeps 15 (three read tools, never stalled); `implementer`
keeps 50 but gains a commit-first rule. Both reviewer schemas gain `"unchecked": [...]` so an
honest partial report is structured, not a stall. Every agent's Output section becomes a
contract: full report to the file the prompt names, final message ≤ ~1 500 tokens (the JSON
block plus the path), no side work. The Agent tool has no per-call `maxTurns`, so sizing
lives in the agent file plus brief sizing (Research B9a, B10).

**B. Stall ladder (one home).** `rules/orchestration.md` replaces its NO_VERDICT bullet with
the ladder; the build and design skills point to it in one line each ("apply the stall
ladder in the orchestration rules"). Steps: (1) detect — the final message has no parseable
fenced JSON, or the result is marked partial after `maxTurns`; (2) ground truth first —
implementer: `git log` for the commit subject and the task's verification command;
reviewer: read its report file when it could write one (a design reviewer has no write tool
and returns JSON only); (3) nudge 1 by SendMessage to the same agent:
"Make no further tool calls. Your next message is the final report in the required JSON;
list what you did not reach under unchecked."; (4) nudge 2, harder: "No tool calls, no
memory, no prose before the block."; (5) respawn once, fresh, briefed with the partial report
and the unchecked list; (6) escalate. Nudges never consume a review iteration; the cap is two
nudges plus one respawn (Research BP7, BP20). Built-in `Explore`/`Plan` agents are one-shot
and skip to (5). Implementer variant: committed and verification passes → review, noting
the missing report; uncommitted and passes → one commit nudge ("stage and commit by
pathspec, nothing else"), then the orchestrator commits by pathspec with the task's
`commit:` line and records the fold at the checkpoint; verification fails → a failed task
for Phase 4, never a nudge.

**C. Lean loop.** Bounded returns (every brief names a report file under the session
scratchpad; the agent writes there when it has a write tool or Bash; the return is ≤ ~1 500
tokens; reviewers return findings JSON only). Design review capped at two rounds; a third
only when round two produced a verified critical finding; then escalate. `/cw:design
<description> lite` (the word `lite` as the last token of the arguments, stripped before the
slug is derived): Explore only (one researcher only for a named unknown), one review round
(valve two), no direction pass; Step 0 recommends `lite` for fix-ups (existing research, ≤ 3
files, no new subsystem). Direction pass only when Step 1 records the design as
architectural (a new subsystem, a public interface or schema, or a change to how the loop
itself works), whatever the path: "architectural" and "lite" are different axes. Research section is a
synthesis (≤ ~25 lines per angle: the findings that shaped a decision, grade, URL). Plan ≤ 400
lines; a feature that needs more is two features (this two-track release, at about 600 lines,
is the operator's stated exception). Every checkpoint (design Step 7, build Phase 5, ship end)
tells the operator to start the next phase in a fresh session. Fast-path reviews run on
`sonnet` whatever the implementer's model; deep reviews stay on a model other than the
implementer's. That is an explicit exception to the reviewer-model rule (a fast path checks
conventions and the commit only, where a second model buys little — unsourced, a judgment
call backed only by the 2026-09-22 build, where four sonnet fast-path reviews of sonnet work
passed and the gate found nothing they missed), so T2 rewords the rule in
`rules/orchestration.md` and T4 the two spots in the build skill. A deep-review brief
carries at most six numbered checks; beyond that the orchestrator splits the review by file
ownership into two reviewers.
Plan authorship stays with the orchestrator while `/cw:design` runs in plan mode: whether a
sub-agent may write the plan file there is unverifiable (Research B12b) and the built-in
`Plan` agent has no Write tool; the size cap and the synthesis rule are the levers instead.
Note: this choice is unsourced — a judgment call.

**D. Notifier.** New `hooks/notify.sh` bound in `hooks/hooks.json` to `Notification` (matcher
`permission_prompt|worker_permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|push_notification|idle_prompt`),
`Stop` and `StopFailure`. Immediate pings: the two permission types (a worker's prompt, from
agent teams, reads "Permission needed (worker)"), the two elicitation types,
`agent_needs_input` and `push_notification`. The "waiting for you" ping is the built-in
`idle_prompt`, which already waits 60 s for a human to answer, gated on state that `Stop`
records: every `Stop` writes `<count> <epoch>` (the length of `background_tasks`) to
`<state>/<session_id>.bg`, `StopFailure` writes `0` (a turn that ended on an API error is
idle too; Research A3), and `idle_prompt` pings only when the recorded count is 0. No record,
or one older than `stale_seconds` (1800), counts as 0: the hook fails open. This removes the
measured 62% at its cause (idle pings while background agents still run), keeps one ping per
genuinely waiting session across five terminals, and needs no frontmost-app probe (the
direction pass's reframe, adopted). Silent: `agent_completed`, `auth_success`,
`computer_use_enter`, `computer_use_exit` and the three quota types. Inside a sub-agent
(`agent_id` present) only the two permission types pass, the message naming `agent_type`.
Title = `<cwd basename> · <registry name>`, the derived `<folder>-<hex>` form collapsed to
`<folder> · <hex>`, folder alone when the registry file is absent or unparsable. Presence
routing is a config flag, default off, and covers routing only: away (HIDIdleTime ≥ 300 s or
a locked screen, Darwin probes) with a Remote Control bridge id in the registry skips the
banner (the phone channel delivers), away without one banners; any probe failure counts as
"at the machine", so a probe can never silence a needed ping. Delivery passes text as
`osascript` argv (`on run argv`), never interpolated into script source; `notify-send` on
Linux when present; otherwise no-op. Always exit 0 (exit 2 on `Stop` would block the turn).
Headless guard: `CLAUDE_CODE_ENTRYPOINT` must be `cli` or unset (configurable). The config
file `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cw-notify.json` is the opt-in: the hook is silent
until it exists (an empty `{}` turns it on with defaults), because a published plugin must
not add banners to installs that did not ask for them; `CW_NOTIFY=0` is the kill switch;
`CW_NOTIFY_DRY_RUN=1` prints the would-be banner (the harness and CI path). Brief open
decisions resolved: JSON config file plus one env kill switch; `agent_needs_input` kept
(rare, cheap); `CLAUDE_CLIENT_PRESENCE_FILE` not touched this round; 300 s / 1800 s
configurable (unsourced defaults); the frontmost rule dropped.

**E. Carry-ins.** Build briefs say `git add -- <files_owned> && git commit -- <files_owned>`
(the 2026-09-22 index race); `marketplace.json` gains the top-level `description` that
`claude plugin validate` warns about; `plugin.json` version 1.0.1 (semver would call a new
hook 1.1.0; the slug fixes 1.0.1 — flagged at the checkpoint).

Alternatives set aside: respawn-only recovery (loses context; the measured recovery is the
nudge); a per-call turn budget (not in the Agent tool); `Stop` as the "waiting" signal (pings
every turn end, attended ones included, and its frontmost-app patch silences every session
at once — rejected by the direction pass); `idle_prompt` ungated (its payload lacks
`background_tasks`; solved by recording the count at `Stop`); the frontmost app via System
Events (Automation prompt can hang a background process, error -1743 after a rejection) or
`lsappinfo` (cannot tell five sessions apart); touching `CLAUDE_CLIENT_PRESENCE_FILE` from the hook (side effects on the phone
channel, deferred); working around a macOS Focus mode that drops banners (an OS setting the
hook cannot see; out of scope — the phone channel over Remote Control is the operator's
mitigation for it).

## Files to create/modify

| Path | Change |
|---|---|
| `agents/reviewer.md` | `maxTurns: 40`, no `memory:`, budget/report-first rules, schema with `unchecked`, bounded final message |
| `agents/design-reviewer.md` | `maxTurns: 40`, no `memory:`, budget rule, schema with `unchecked`; JSON only (no write tool) |
| `agents/direction-reviewer.md` | no `memory:` (keeps 15), bounded final message |
| `agents/implementer.md` | commit-first rule, exit report last, ≤ ~10 lines before the JSON block |
| `agents/researcher.md` | Output: ≤ ~1 500 tokens, numbered findings with grade and URL, unsourced list |
| `rules/orchestration.md` | stall ladder (the one home; keeps the single `NO_VERDICT` token), two-round cap wording, bounded-return rule, checkpoint-says-fresh-session |
| `rules/workflow.md` | `/cw:design <description> [lite]`, `/clear` between phases |
| `skills/design/SKILL.md` | lite flag, two-round cap, synthesis research, plan ≤ 400 lines, report path + budget in briefs, ladder pointer, fresh-session line; ≤ 200 lines |
| `skills/build/SKILL.md` | report path + budget + commit pathspec in briefs, missing-report gate branches, brief sizing, fast-path on sonnet, ladder pointer, fresh-session line; ≤ 200 lines |
| `skills/ship/SKILL.md` | fresh-session line at the end |
| `hooks/notify.sh` (new) | the notifier, spec in Task T5 |
| `hooks/hooks.json` | `Notification` (matcher incl. `idle_prompt`), `Stop`, `StopFailure` entries, timeout 5; existing three entries untouched |
| `tests/run.sh` | `hooks_notify_cases` + `notify_case` helper, wired into `cmd_hooks` |
| `README.md` | agents table gains a turn-cap column, "Notifications" section, loop description (rounds, lite, ladder pointer) |
| `WORKFLOW.md` | loop semantics paragraph updated; ≤ 200 lines |
| `docs/plans/cw-plugin/cw-plugin-design-draft.md` | "Release 1.0.1" section, ≤ 40 lines |
| `.claude-plugin/plugin.json` | `"version": "1.0.1"` (T7, with the release gate) |
| `.claude-plugin/marketplace.json` | top-level `description` (T7) |

Patterns to follow: stdin/jq/exit conventions in `hooks/profile-check.sh:14-19` (`trap finish
EXIT`, `# shellcheck disable=SC2317,SC2329`, always exit 0) and `hooks/protect-secrets.sh:14`
(field fallback with `//`); harness helpers `report`, `check_code`, `push_case` in `tests/run.sh:31-66`
and the jq-absent PATH shim in `hooks_jq_absent_case` (`tests/run.sh:203`); `${CLAUDE_PLUGIN_ROOT}`
command form in `hooks/hooks.json:9`.

## Dependencies

None new. `jq` (already required by the other hooks; absence tolerated). macOS system tools
`osascript`, `ioreg`, `plutil`; Linux `notify-send` optional. Claude Code ≥ 2.1.145
for `background_tasks`; verified against 2.1.280.

## Risks & mitigations

1. **Size gate.** Baseline 73 738 bytes, tree at 59 773 (81.1%); caps 200 lines for the design
   and build skills, 150 for every other scoped file, 200 for WORKFLOW.md. Every task carries
   a line cap in its verification; growth budget: T1 ≤ +1 800 bytes, T2 ≤ +2 500, T3 ≤ +800,
   T4 ≤ +1 200 (net of the compaction each skill needs to stay under 200 lines). Detected by
   `bash tests/run.sh size` at T7; rollback is a minimisation pass on the same file by the
   same task (one home per rule: skills reference the rules, they do not restate them).
2. **Dedupe gate.** `tests/dedupe-phrases.txt` phrases (`NO_VERDICT`, `counter-model`, `ground
   truth over`, `one atomic commit per task`, `in the same turn`, `explicit model`, `never
   commits`, `two human checkpoints`, `context7 before`, …) must each stay in exactly one
   scoped file. New skill and agent text says "missing verdict" and "stall ladder", never the
   token `NO_VERDICT`; T1–T4 verifications grep for the token.
3. **Registry is undocumented and unstable** (not updated on `/clear`, deleted at process exit;
   Research A7). The label falls back to the folder; the harness uses fixture files; a parse
   error never blocks. If the schema changes, the banner loses its session part and nothing
   else.
4. **Exit code on `Stop`.** Exit 2 would block the turn from ending. The EXIT trap forces 0;
   every harness case asserts exit 0, including malformed stdin and jq absent.
5. **Text injection.** Payload `message` reaches `osascript` only as argv; the harness case with
   quotes, backslashes and newlines proves one sanitised line.
6. **Presence probes.** HIDIdleTime is contested under Screen Sharing and on some Apple Silicon
   reports; the screen-lock key is absent while unlocked; System Events prompts (Research
   BP15–17). Presence is off by default; probes use `ioreg` and `plutil` only, no Apple
   Events; any failure reads as "at the machine".
7. **`Stop` reliability.** Claude Code issues #29881/#87972 report `Stop` not firing on
   stall-terminated turns, with `StopFailure` firing instead. A missed `Stop` leaves a stale
   record; `StopFailure` writes 0 and a record older than `stale_seconds` counts as 0, so the
   worst case is one late ping, never a silenced session. The brief's issue #15250 could not
   be located (unverified).
8. **`maxTurns` enforcement.** One 2026 issue (#41143) reports it unenforced; the operator's
   runs on 2.1.27x–2.1.280 hit the cap at exactly 20 and 50. The ladder works either way.
9. **Nudge loops.** Capped at two nudges plus one respawn (deterministic backstop; Research
   BP7, BP20).
10. **Live hooks.** The plugin is live in the operator's profile; a malformed `hooks.json`
    silently disables the guard hooks for new sessions. T5 writes the new file to a temp path,
    validates with `jq .`, diffs the three existing entries for byte identity, then moves it in.
11. **The private step.** The notifier is opt-in, so nothing changes for the operator until
    they create `cw-notify.json` and, in the same by-hand step, remove the static user-level
    Notification hook from both profiles. Out of PR by rule; noted at the checkpoint. Other
    installers see no banner unless they create the file.
12. **Plan mode and sub-agent writes.** If a later Claude Code version lets a sub-agent write the
    plan file in plan mode, delegated authorship becomes a one-line change in Step 3; the
    design records the constraint rather than designing around it.
13. **Rules edited inside a feature PR.** `rules/workflow.md` keeps process-rule edits out of
    feature PRs; in this repository the rules files are the product, and T2 edits them under
    the same accepted-risk exemption fixups-1-0-0 logged. Recorded, not litigated.
14. **CI hygiene greps.** `.github/workflows/ci.yml` rejects emphatic capitals (`NEVER|ALWAYS|
    MUST|CRITICAL` as words), banned coordination phrases, `under 50 lines`, internal paths
    (`~/.claude/plans`, `gitattributes`, `linguist`, `git clean`) in skills, an agent file
    missing `model`/`tools`/`effort`/`maxTurns`, a design skill without the word `haiku`, and
    the LICENSE name anywhere in prompts or docs. T1–T4 verifications carry the greps that
    apply to their files and T7 runs the whole set, so a red CI after the push cannot come
    from this series.
15. **Undocumented environment.** `CLAUDE_PID` and `CLAUDE_CODE_ENTRYPOINT` are in the binary and
    in live sessions but not in the hooks reference. Both are used fail-open: no `CLAUDE_PID`
    → folder-only title; no `CLAUDE_CODE_ENTRYPOINT` → proceed.

## Success criteria

1. `bash tests/run.sh all` prints `all: hooks: PASS`, `all: size: PASS`, `all: dedupe: PASS`,
   `all: settings-keys: PASS`, `all: trailers: PASS` and exits 0; the hooks line reports at
   least 140 passed (108 existing + 32 notifier cases), 0 failed.
2. `shellcheck -x hooks/*.sh tests/run.sh` exits 0 on 0.11 (local) and 0.9.0 (CI's).
3. `out=$(claude plugin validate . 2>&1) && ! printf '%s' "$out" | grep -qi warning` exits 0,
   and `claude plugin validate .claude-plugin/plugin.json` exits 0 (its root-CLAUDE.md
   warning is pre-existing and accepted).
4. `grep -L '^memory:' agents/reviewer.md agents/design-reviewer.md agents/direction-reviewer.md`
   lists all three; `grep -c '^maxTurns: 40' agents/reviewer.md agents/design-reviewer.md` = 1
   each; `grep -c '"unchecked"' agents/reviewer.md agents/design-reviewer.md` ≥ 1 each.
5. `grep -rl 'NO_VERDICT' skills agents rules` lists exactly `rules/orchestration.md`;
   `grep -c 'stall ladder' rules/orchestration.md` ≥ 1, `skills/build/SKILL.md` ≥ 1,
   `skills/design/SKILL.md` ≥ 1; `grep -c 'lite' skills/design/SKILL.md` ≥ 3.
6. `wc -l` ≤ 200 for `skills/design/SKILL.md`, `skills/build/SKILL.md`, `WORKFLOW.md`; ≤ 150 for
   every other file under `skills/`, `agents/`, `rules/`.
7. The 32 notifier cases in T5 pass under `bash tests/run.sh hooks` on macOS bash 3.2, bash 5
   and ubuntu (dry run, no `osascript`).
11. The CI hygiene greps of Risk 14 all pass on the final tree (T7 runs them verbatim).
8. `git log --format=%s main..HEAD` holds the seven task subjects once each plus
   `docs(stall-handling-1-0-1): design` (eight commits), one exact trailer per commit.
9. Field acceptance (manual, after `claude plugin update cw` and the config file): a
   permission prompt shows one banner titled `<folder> · <session>`; a run with three
   parallel sub-agents shows no banner while they run and one "Waiting for your input"
   banner about 60 s after the final turn ends; a turn the operator answers within 60 s
   shows nothing; banners per day fall from ~110 to the day's genuine waits.
10. `grep -E -c '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|@[a-z0-9.-]+\.[a-z]{2,}' docs/plans/stall-handling-1-0-1.md` = 0
    and the LICENSE-name gate passes on the plan.

## Research

### Codebase (Explore, haiku)

- Retry rule to replace: `rules/orchestration.md:37-38` ("retry once fresh, then escalate");
  `skills/build/SKILL.md:149-152` (missing verdict → one fresh reviewer); `skills/design/SKILL.md:146-147`.
  Caps: `skills/design/SKILL.md:3,148-150` (5 iterations); `skills/build/SKILL.md:154-165`
  (three iterations, kept); `rules/orchestration.md:45-46` ("one or two rounds").
- Verbatim research fold: `skills/design/SKILL.md:74-77`. Direction pass: `:152-156`. Plan
  authorship: `:83-98` (orchestrator); build commits the design at `skills/build/SKILL.md:48-51`.
- Frontmatter: `agents/reviewer.md:6,12` (20, memory), `agents/design-reviewer.md:6,18` (25,
  memory), `agents/direction-reviewer.md:6,11` (15, memory), `agents/implementer.md:6` (50),
  `agents/researcher.md:6` (30).
- Harness: `tests/run.sh:16` `HOOKS_DIR="${CW_HOOKS_DIR:-$ROOT/hooks}"`; helpers `report`,
  `check_code`, `push_case` at `:31-66` (payload via `jq -nc`, `HOME="$SCRATCH/base"`,
  `"$BASH_BIN"`); `cmd_hooks` at `:546-575` lists the case groups; jq-absent shim at `:203`;
  size at `:14` (`BASELINE_BYTES=73738`), line caps `:681-700`, WORKFLOW cap `:703-711`;
  `check_settings_keys` `:1087-1107`; `cmd_all` `:1110`.
- Hook conventions: `hooks/profile-check.sh:14-19` (`trap finish EXIT`, always exit 0, JSON on
  stdout); `hooks/protect-branches.sh:56-62` (jq absent → exit 0; `INPUT=$(cat)`);
  `hooks/hooks.json:1-38` (`${CLAUDE_PLUGIN_ROOT}`, `timeout: 10`). CI: `shellcheck -x hooks/*.sh tests/run.sh`.
- Docs: `README.md:82-91` agents table (no turn-cap column yet); `:164-181` settings example notes;
  `WORKFLOW.md:102` names the verdict semantics. Task format exemplar:
  `docs/plans/hardening-1-0-0.md:426-482`.
- Current sizes (`wc -l`): design 192 lines / 9 803 B, build 183 / 9 782, ship 124, orchestration 60,
  workflow 38, reviewer 55, design-reviewer 85, direction-reviewer 79, implementer 44,
  researcher 59, WORKFLOW.md 130, README 289.

### Docs and API (researcher, sonnet; orchestrator checks on the 2.1.280 binary)

- **A1 Notification types**: the 2.1.280 binary's enum is exactly `permission_prompt, idle_prompt,
  auth_success, elicitation_dialog, agent_needs_input, agent_completed, elicitation_url_dialog,
  worker_permission_prompt, push_notification, computer_use_enter, computer_use_exit,
  quota_auto_resume_fired, quota_auto_resume_stale, quota_auto_resume_disabled`;
  `push_notification` is emitted when the push tool runs. The docs page lists a subset and
  adds `elicitation_complete`/`elicitation_response` (present as strings, not in the enum) —
  https://code.claude.com/docs/en/hooks. Matcher = regex over `notification_type`; text in `message`.
- **A2 `agent_id`/`agent_type`**: "Present only when the hook fires inside a subagent call" (hooks
  reference, general hook input; no per-event exclusion stated). The design labels when present
  and never depends on it.
- **A3 `Stop` and `StopFailure`**: payload `background_tasks` (2.1.145+), `stop_hook_active`, `last_assistant_message`;
  matchers ignored; exit 2 blocks stopping; stdout not shown — https://code.claude.com/docs/en/hooks.
  **`StopFailure`**: in the binary's event list; docs: fires "when the turn ends due to an API
  error", output discarded. Plugins may bind `Notification` and `Stop`
  (https://code.claude.com/docs/en/hooks-guide). Default command-hook timeout 600 s (the entry
  sets 5 s).
- **A4 Env**: `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID`,
  `CLAUDE_CODE_SESSION_ATTENDED` present in the binary and in this session's environment but
  absent from the hooks reference (undocumented; used fail-open, Risk 15).
  `CLAUDE_CODE_SESSION_ATTENDED` is static at spawn, so it is set aside as a presence signal.
  `CLAUDE_CLIENT_PRESENCE_FILE` documented (2.1.181+, https://code.claude.com/docs/en/env-vars).
  `messageIdleNotifThresholdMs` exists in source, not in the settings schema — not relied on.
  Documented plugin mechanisms set aside with reasons: `CLAUDE_PLUGIN_DATA` (persistent data
  dir; a per-session state file is ephemeral, so `TMPDIR` fits better) and plugin options
  (`${user_config.*}` / `CLAUDE_PLUGIN_OPTION_<KEY>`; install-time prompting and untested on
  a symlinked local plugin — a JSON file the harness can fixture is the safer v1; unsourced,
  judgment call) — https://code.claude.com/docs/en/hooks.
- **A7 Registry** `~/.claude/sessions/<pid>.json`: undocumented internal (issues #95439, #36213,
  #85281); on this machine (2.1.280) it holds `sessionId, cwd, name, nameSource, status,
  bridgeSessionId, entrypoint, kind, …`; interactive terminal sessions report `entrypoint: cli`.
- **B9–B11 Sub-agents** (https://code.claude.com/docs/en/sub-agents): B9a on `maxTurns`
  exhaustion the output is marked partial and an agent id is returned; B10 resume by id or
  name keeps the full history, built-in Explore/Plan are one-shot; B9b `memory` scopes give
  the agent Read/Write/Edit on its memory dir and it spends tool calls writing there;
  `background: true` strips Agent, AskUserQuestion, ExitPlanMode; B11 docs recommend "1–3
  paragraphs" summaries and verbose output to files. **B12** `plansDirectory` documented; a
  sub-agent writing the plan file in plan mode (B12b): unverifiable. **A8** Changelog
  2.1.279–280: `SubagentStop` matcher fix, Stop prompt-hook label; nothing on Notification.

### Best practices (researcher, sonnet)

- BP1–5 (H/M): no framework forces a final answer on budget exhaustion — Claude Agent SDK
  `error_max_turns`, OpenAI `MaxTurnsExceeded`, LangGraph recursion error, AutoGen
  `MAX_TURNS` — so the orchestrator owns recovery. https://code.claude.com/docs/en/agent-sdk/agent-loop
- BP6 (M): resume the same named agent, do not respawn; respawn loses context.
  https://github.com/laurigates/claude-plugins/blob/main/agent-patterns-plugin/skills/parallel-agent-dispatch/references/failure-recovery.md
- BP7/BP20 (M): 94/98 nudge-recoverable failures were "computed but not presented as final";
  cap nudges (≈3) with a deterministic backstop or the nudge loop becomes the loop.
  https://arxiv.org/pdf/2606.24839
- BP8–10 (M): git log as ground truth for stranded implementers is the converged pattern; no
  measured better alternative. https://github.com/trinity-ai-labs/orchestration-skills/issues/440
- BP11–13 (H/M): review depth tiered by size/risk — Anthropic Code Review (84% of >1 000-line
  PRs get findings vs 31% under 50 lines, <1% wrong) https://claude.com/blog/code-review; Meta
  RADAR auto-lands low-risk diffs at one third the revert rate https://arxiv.org/html/2605.30208v1.
- BP14: no round-over-round false-positive curve beyond the prior 75% figure (gap).
- BP15–17 (M/H): HIDIdleTime contested (Screen Sharing, some Apple Silicon reports)
  https://developer.apple.com/forums/thread/721530; System Events `tell` blocks trigger an
  Automation prompt that can hang a non-interactive process, -1743 after rejection
  https://scriptingosx.com/2020/09/avoiding-applescript-security-and-privacy-requests/;
  screen-lock key absent while unlocked, `None` over SSH.
- BP18–19 (L): #15250 not found; #29881/#87972 describe `Stop` missing stall-terminated turns
  with `StopFailure` firing instead. https://github.com/anthropics/claude-code/issues/29881
- BP21–22 (L): a live turn budget cannot be resized (argument for resume over respawn); no
  source argues the ladder is over-engineering (gap).
- Prior research 2026-09-22 (operator's notes): ≤ 1–2k-token returns with file reports (H),
  delegated authorship (M), clear context per phase (H), two-round cap (M), synthesis (L).

# Tasks

Seven commits. T1–T5 own disjoint files and run together; T6 (docs) after T1–T5; T7
(release manifests, whose verification is the release gate) last. Review depth follows the
build skill's own rule: T5 deep on `opus` (risk high: executable code on every `Stop`,
payload text reaching `osascript`), T1 deep on `opus` (five files, the behavioural core),
T3 and T4 deep on `sonnet` (risk high: compressed rewrites of the two skills that run the
loop; the reviewer's checklist is "every specification bullet landed, every pre-existing
safety rule and anti-pattern survived, the file is under its cap"), T2, T6 and T7 fast-path
on `sonnet`. Fix iterations in this build never use `git commit --amend`: T1–T5 commit in
parallel, so a fix goes in as `git commit --fixup=<task sha> -- <files_owned>` and the
orchestrator squashes it with `GIT_SEQUENCE_EDITOR=true git rebase --autosquash --no-autostash
<task sha>~1` once every agent has returned, before T7's count runs.

Note to the `/cw:build` orchestrator, Phase 0: fresh session, auto mode, plain
`/cw:build stall-handling-1-0-1` (branch `feat/stall-handling-1-0-1` from `main`; the
plugin files live on `main` since 2e56128). Before the design commit run
`N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1); ! grep -qi "$N" docs/plans/stall-handling-1-0-1.md`
(CI's name gate covers `docs`). The design commit ends with exactly one trailer line per
`rules/workflow.md` and no session line; check it right after committing.

Note on briefing, for every agent in this build: the orchestrator's context is the scarce
resource. Each implementer and each `cw:reviewer` (it has Bash) writes its full report to a
file under the session scratchpad (`reports/<task>-<role>.md`; pass the absolute path in the
brief) and returns at most about 1 500 tokens: the required JSON block plus a few lines
naming the file. Reviewers return findings only (severity, file:line, one reproducing
command each), never evidence walkthroughs. Every brief states the agent's turn budget (40
for reviewers, 50 for implementers) and that the report comes before any optional check.
Implementers stage and commit by explicit pathspec — `git add -- <files_owned> && git commit
-- <files_owned>` — because T1–T5 share one index; on an `index.lock` or ref-lock error they
wait a few seconds and retry the git command. Prompt text in skills, agents and rules must
pass the CI greps of Risk 14 (no `NEVER`/`ALWAYS`/`MUST`/`CRITICAL` as words, no internal
paths in skills, every agent keeps `model`, `tools`, `effort`, `maxTurns`). T1–T4 run
alongside T5 and call no `tests/run.sh` subcommand; T5's verification runs `bash tests/run.sh
hooks`, which reads only `hooks/` and `tests/`. A stalled agent (no JSON block, or a partial
result) gets the ladder from Approach B: ground truth, one report-only nudge by SendMessage,
a second, then one respawn — never a fresh respawn first.

## Task T1
- scope: Turn the five agent files into stall-resistant contracts: no memory on reviewers, sized turn caps, `unchecked` in both reviewer schemas, report-first and commit-first rules, bounded final messages.
- files_owned: [agents/reviewer.md, agents/design-reviewer.md, agents/direction-reviewer.md, agents/implementer.md, agents/researcher.md]
- files_forbidden: [rules/, skills/, hooks/, tests/, README.md, WORKFLOW.md, docs/, .claude-plugin/]
- depends_on: none
- agent: implementer
- model: sonnet
- risk: normal
- verification: `cd "$(git rev-parse --show-toplevel)" && ! grep -q '^memory:' agents/reviewer.md agents/design-reviewer.md agents/direction-reviewer.md && [ "$(grep -c '^maxTurns: 40$' agents/reviewer.md)" -eq 1 ] && [ "$(grep -c '^maxTurns: 40$' agents/design-reviewer.md)" -eq 1 ] && grep -q '^maxTurns: 15$' agents/direction-reviewer.md && grep -q '^maxTurns: 50$' agents/implementer.md && grep -q '"unchecked"' agents/reviewer.md && grep -q '"unchecked"' agents/design-reviewer.md && grep -q 'before any optional check' agents/implementer.md && grep -qi '1 500\|1,500\|1500' agents/researcher.md && [ "$(cat agents/*.md | wc -c | tr -d ' ')" -le 13806 ] && ! grep -rn 'NO_VERDICT\|</content>' agents/ && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- agents && for f in agents/*.md; do [ "$(wc -l < "$f")" -le 150 ] || exit 1; for k in model tools effort maxTurns; do grep -q "^$k:" "$f" || exit 1; done; done`, expected exit 0
- commit: fix(agents): no reviewer memory, sized turn caps, unchecked lists and bounded reports

Specification:
- `reviewer.md`: frontmatter `maxTurns: 40`, delete the `memory: project` line. Reword the
  description (line 3) and the read-only sentence (line 19) to "no Write or Edit tool; Bash
  writes only the report file the prompt names, nothing else in the tree", so the report
  rule below does not contradict them. Add a `## Budget`
  section (≤ 8 lines): the turn budget is finite and stated in the prompt; open the report file
  the prompt names on the first turn and append each finding as it is confirmed (Bash `>>`);
  emit the final JSON when the checks are done or about two thirds of the budget is spent,
  whichever comes first; unreached checks go under `unchecked`; no memory notes, no summaries
  beyond the report. Output schema becomes
  `{"verdict": "PASS|NEEDS_WORK", "findings": [...], "unchecked": ["..."]}`; the final message
  is the JSON block plus one line naming the report file, nothing else. Severity wording and
  the PASS/critical rule stay.
- `design-reviewer.md`: `maxTurns: 40`, delete `memory: project`; a shorter Budget section
  (no write tool, so no report file: keep a running list of confirmed issues in your own
  reasoning and emit the JSON at two thirds of the budget at the latest, unreached checks
  under `unchecked`); schema gains `"unchecked": ["..."]` beside `issues` and
  `suggested_fixes`.
- `direction-reviewer.md`: delete `memory: project`; add one line to Output: the JSON is the
  whole final message.
- `implementer.md`: in Rules, replace the commit bullet with: as soon as `verification` passes,
  stage and commit by explicit pathspec (`git add -- <files> && git commit -- <files>`) before
  any optional check, tidy-up or re-read; the exit report is the last thing written; never
  spend turns on notes or memory. Output: full notes to the report file the prompt names;
  the final message is at most about ten lines plus the exit-report JSON block.
- `researcher.md`: Output section: at most about 1 500 tokens — numbered findings of 2–3
  lines each with a grade (H official docs / M practitioner with numbers / L inference) and
  one URL, then a short "unsourced" list; no narrative, no restated questions.
- Keep every file ≤ 150 lines; do not touch other sections' wording.

## Task T2
- scope: Make `rules/orchestration.md` the single home of the stall ladder and the two-round cap, and add the lite flag and per-phase `/clear` to `rules/workflow.md`.
- files_owned: [rules/orchestration.md, rules/workflow.md]
- files_forbidden: [rules/browser.md, agents/, skills/, hooks/, tests/, README.md, WORKFLOW.md, docs/, .claude-plugin/]
- depends_on: none
- agent: implementer
- model: sonnet
- risk: normal
- verification: `cd "$(git rev-parse --show-toplevel)" && [ "$(grep -c 'NO_VERDICT' rules/orchestration.md)" -eq 1 ] && grep -q 'stall ladder' rules/orchestration.md && grep -q 'SendMessage' rules/orchestration.md && grep -qi 'two nudges' rules/orchestration.md && grep -q 'whatever the implementer' rules/orchestration.md && [ "$(grep -c 'counter-model' rules/orchestration.md)" -eq 1 ] && ! grep -q 'retry once fresh' rules/orchestration.md && ! grep -q 'one or two rounds' rules/orchestration.md && grep -q 'lite' rules/workflow.md && grep -q 'between phases' rules/workflow.md && [ "$(sed -n 's/^  \(Co-Authored-By: .*\)$/\1/p' rules/workflow.md | wc -l | tr -d ' ')" -eq 1 ] && ! grep -rn '</content>' rules/ && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- rules && [ "$(wc -l < rules/orchestration.md)" -le 150 ] && [ "$(wc -l < rules/workflow.md)" -le 150 ] && [ "$(wc -c < rules/orchestration.md)" -le 6400 ]`, expected exit 0
- commit: feat(rules): stall ladder as the one home, two-round review cap, lite design path

Specification:
- `rules/orchestration.md` "Verification & completion": replace the NO_VERDICT bullet with a
  `stall ladder` sub-list (≤ 14 lines) worded per Approach B: detection (no fenced JSON, or a
  partial result after `maxTurns`) is NO_VERDICT, distinct from NEEDS_WORK; ground truth
  first (git + verification for an implementer, the report file for a reviewer); nudge 1 and
  nudge 2 by SendMessage to the same agent with the quoted texts; one fresh respawn briefed
  with the partial report; escalate; two nudges plus one respawn is the cap; nudges consume no
  iteration; built-in Explore/Plan agents cannot be resumed and go straight to the respawn;
  the implementer variant (committed → review; uncommitted and green → commit nudge, then
  the orchestrator commits by pathspec and records the fold; red → failed task).
- "Review-loop anti-ratchet": rewrite the cap bullet to "two rounds by default; a third only
  when round two produced a verified critical finding; then escalate" (this resolves the
  documented mismatch with the design skill).
- "Verification & completion", the reviewer bullet (line 33): keep the counter-model wording
  for deep reviews (the phrase stays in this file only) and add that a fast-path review
  (conventions and commit check) may run on `sonnet` whatever the implementer's model.
- "Sessions & context": add that every checkpoint tells the operator to start the next phase
  in a fresh session, and that every brief names a report file and asks for a return of at
  most about 1 500 tokens (findings JSON only for reviewers).
- `rules/workflow.md`: the `/cw:design` bullet gains `[lite]` (Explore only, one review round,
  no direction pass; for fix-ups); Context hygiene: "`/clear` between phases, not only between
  unrelated tasks". Keep the dedupe phrases where they are.

## Task T3
- scope: Rewrite `skills/design/SKILL.md` for the lean loop: lite flag, two-round cap, synthesis research, plan size cap, report paths and budgets in briefs, ladder pointer, fresh-session checkpoint, within 200 lines.
- files_owned: [skills/design/SKILL.md]
- files_forbidden: [skills/build/, skills/ship/, skills/compound/, skills/search/, skills/google-workspace/, agents/, rules/, hooks/, tests/, README.md, WORKFLOW.md, docs/, .claude-plugin/]
- depends_on: none
- agent: implementer
- model: opus
- risk: high
- verification: `cd "$(git rev-parse --show-toplevel)" && f=skills/design/SKILL.md && [ "$(wc -l < $f)" -le 200 ] && [ "$(grep -c 'lite' $f)" -ge 3 ] && grep -qi 'one round' $f && grep -qi 'architectural' $f && grep -q 'stall ladder' $f && grep -q '400 lines' $f && grep -qi 'fresh session' $f && grep -q 'haiku' $f && ! grep -q 'verbatim enough' $f && ! grep -q '5 iterations\|after 5' $f && grep -q 'ExitPlanMode' $f && grep -q '# Tasks' $f && ! grep -q 'NO_VERDICT\|</content>' $f && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- $f && ! git grep -niE '~/.claude/plans|gitattributes|linguist|git clean' -- $f && [ "$(wc -c < $f)" -le 10600 ]`, expected exit 0
- commit: feat(design): lite path, two-round cap, synthesis research and bounded briefs

Specification (keep the seven-step shape, the `ExitPlanMode` transition, Step 6's move and
Step 7's checkpoint text; compact prose elsewhere to fit):
- Input: the feature description, optionally ending in the word `lite`; that last token is
  stripped before the slug is derived. Step 0 adds: recommend `lite` when the brief is a
  fix-up (research exists, ≤ 3 files, no new subsystem); the operator's answer decides.
- Step 2: full path = Explore (haiku) + the two researchers; lite = Explore only, one
  researcher only for an unknown Step 1 named. Every brief names a report path under the
  session scratchpad where the agent can write, states the turn budget, and asks for a
  return of at most about 1 500 tokens; the ultracode alternative stays as one sentence.
- Step 3: Research is a synthesis — at most about 25 lines per angle: the findings that
  shaped a decision, each with grade and URL; full returns are not pasted. The plan stays
  under 400 lines; when Step 1 finds more than eight tasks, split the feature instead.
- Step 4: two rounds by default; a third only when round two produced a verified critical
  finding; then escalate with the surviving findings. Lite: one round, a second only on a
  verified critical finding. A missing verdict → the stall ladder in the orchestration rules
  (one line, no restatement). Everything else in the loop (verify
  critical findings, minor notes, fresh reviewer per pass) stays.
- Step 1 records `architectural: yes|no` (a new subsystem, a public interface or schema, or
  a change to how the loop itself works). Step 4b runs only on `yes`, whatever the path.
- Steps 5 and 7: the summary states rounds used and the path; the checkpoint adds "start
  `/cw:build` in a fresh session". The frontmatter description drops "escalating after 5
  iterations" for "two review rounds".

## Task T4
- scope: Rewrite the build skill's briefing, gate and review phases for bounded returns, commit pathspec, the missing-report branches, brief sizing and the ladder pointer; add the fresh-session line to ship.
- files_owned: [skills/build/SKILL.md, skills/ship/SKILL.md]
- files_forbidden: [skills/design/, skills/compound/, skills/search/, skills/google-workspace/, agents/, rules/, hooks/, tests/, README.md, WORKFLOW.md, docs/, .claude-plugin/]
- depends_on: none
- agent: implementer
- model: opus
- risk: high
- verification: `cd "$(git rev-parse --show-toplevel)" && b=skills/build/SKILL.md && s=skills/ship/SKILL.md && [ "$(wc -l < $b)" -le 200 ] && [ "$(wc -l < $s)" -le 150 ] && grep -q 'git commit -- ' $b && grep -q 'stall ladder' $b && grep -qi 'fresh session' $b && grep -qi 'fresh session' $s && grep -q 'six numbered checks\|six checks' $b && grep -q 'whatever the implementer' $b && grep -q 'fixup' $b && ! grep -q 'git commit --amend' $b && grep -q '"unchecked"' $b && ! grep -q 'spawn one fresh reviewer on the same' $b && ! grep -q "on the implementer's own model" $b && grep -q 'commit: none' $b && ! grep -q 'NO_VERDICT\|</content>' $b $s && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- $b $s && ! git grep -niE '~/.claude/plans|gitattributes|linguist|git clean' -- $b $s && [ "$(wc -c < $b)" -le 11000 ]`, expected exit 0
- commit: feat(build): bounded briefs, commit by pathspec, stranded-implementer gate and the ladder pointer

Specification (`skills/build/SKILL.md`, keep the five-phase shape and every existing
safety rule):
- Phase 2 prompt list: add the report path, the turn budget (50), "return at most about
  1 500 tokens"; the commit instruction becomes explicit — `git add -- <files_owned> && git
  commit -- <files_owned>`, never a bare `git commit` (shared index across parallel tasks).
- Phase 2→3 gate: a missing or partial exit report is not a failure by itself. Ground truth
  decides: commit present and verification green → review, noting the missing report;
  tree green but uncommitted → one commit nudge by SendMessage ("stage and commit by
  pathspec with the task's commit line, nothing else"); still uncommitted → the
  orchestrator commits by pathspec with that line (the one exception to "you edit no file";
  it commits, it does not edit) and lists the fold at the checkpoint; verification red →
  a failed task for Phase 4.
- Phase 3: fast-path reviews run on `sonnet` whatever the implementer's model; deep reviews
  stay on the other model of the pair (rewrite the model sentence at lines 114-115 and the
  anti-pattern at line 180 so both say exactly that). A deep brief carries at most six numbered checks;
  beyond that, split by file ownership into two reviewers. Every reviewer brief names a
  report path and the 40-turn budget and asks for findings JSON only.
- Phase 3, the restated verdict schema (lines 136-141): add `"unchecked": ["..."]` so it
  matches the agent file after T1; the cross-field PASS rule stays.
- Phase 4: replace the missing-verdict bullet with one line pointing at the stall ladder in
  the orchestration rules; nudges and the one respawn consume no iteration. The fix fold
  (lines 154-158) no longer offers `git commit --amend`: after parallel tasks HEAD is another
  task's commit. A fix implementer commits `git commit --fixup=<task sha> -- <files_owned>`;
  once no agent is reading the tree, the orchestrator squashes with
  `GIT_SEQUENCE_EDITOR=true git rebase --autosquash --no-autostash <task sha>~1` (git 2.44+;
  the tree stays byte-identical), so the series keeps one commit per task.
- Phase 5: add "start `/cw:ship` in a fresh session". Anti-patterns: add "respawning a
  stalled agent before its nudges".
- `skills/ship/SKILL.md`: after Step 6, one sentence: the next phase (`/cw:compound` or the
  next design) starts in a fresh session.

## Task T5
- scope: Ship the notifier: `hooks/notify.sh`, its `hooks.json` bindings and 32 harness cases.
- files_owned: [hooks/notify.sh, hooks/hooks.json, tests/run.sh]
- files_forbidden: [hooks/protect-branches.sh, hooks/protect-secrets.sh, hooks/profile-check.sh, tests/dedupe-phrases.txt, tests/settings-keys.txt, tests/fixtures/, skills/, agents/, rules/, README.md, WORKFLOW.md, docs/, .claude-plugin/]
- depends_on: none
- agent: implementer
- model: sonnet
- risk: high
- verification: `cd "$(git rev-parse --show-toplevel)" && jq -e '.hooks.PreToolUse|length==2' hooks/hooks.json >/dev/null && jq -e '.hooks.Notification[0].matcher == "permission_prompt|worker_permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|push_notification|idle_prompt" and (.hooks.Stop|length)==1 and (.hooks.StopFailure|length)==1' hooks/hooks.json >/dev/null && shellcheck -x hooks/notify.sh tests/run.sh && bash tests/run.sh hooks | tee /dev/stderr | grep -Eq 'hooks: 1[4-9][0-9] passed, 0 failed' && /bin/bash tests/run.sh hooks | grep -Eq 'hooks: 1[4-9][0-9] passed, 0 failed' && ! grep -rn '</content>' hooks/ tests/run.sh`, expected exit 0
- commit: feat(hooks): session-labelled notifier on Notification, Stop and StopFailure with harness cases

Specification — `hooks/notify.sh` (bash 3.2 clean, no `set -u`, `trap finish EXIT` with
`# shellcheck disable=SC2317,SC2329`, always exit 0, no output unless dry run):
1. Read `INPUT=$(cat)`. `command -v jq` missing → exit. `CW_NOTIFY=0` → exit. Parse the
   string fields `hook_event_name`, `notification_type`, `message`, `session_id`, `cwd`,
   `agent_id`, `agent_type` with `jq -r '.x // empty'`; `stop_hook_active` with
   `jq -r '.stop_hook_active == true'`; the background count with
   `jq '(.background_tasks // []) | length'` (never `-r ... // empty` on the array: an empty
   array is truthy in jq and would print `[]`); a jq parse error → exit.
2. Config: `CW_NOTIFY_CONFIG` or `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cw-notify.json`. The
   file is the opt-in: absent → exit; present but unparsable → defaults. Keys `enabled`
   (true), `presence` (false), `idle_seconds` (300), `stale_seconds` (1800), `entrypoints`
   (`["cli"]`), `idle_message` ("Waiting for your input"); every key optional. `enabled`
   false → exit.
3. Headless guard: `CLAUDE_CODE_ENTRYPOINT` set and not in `entrypoints` → exit.
4. Dispatch on `hook_event_name`. State file:
   `${CW_NOTIFY_STATE_DIR:-${TMPDIR:-/tmp}/cw-notify}/<session_id>.bg`, one line
   `<count> <epoch>` (`date +%s`, no `stat`). `Stop` → `mkdir -p` the directory, write
   `<background count> <epoch>`, exit (a write failure is ignored). `StopFailure` → write
   `0 <epoch>`, exit. `Notification`: type must be one of the seven matcher types
   (defensive re-check); `agent_id` non-empty → only `permission_prompt` and
   `worker_permission_prompt` continue, message "Permission needed (agent: <agent_type>)".
   Messages: `permission_prompt` → "Permission needed"; `worker_permission_prompt` →
   "Permission needed (worker)"; `elicitation_dialog`/`elicitation_url_dialog` → "Input
   needed"; `agent_needs_input`/`push_notification` → payload `message` or "Attention
   needed"; `idle_prompt` → read the state file: missing or unparsable → ping
   `idle_message`; count above zero and epoch younger than `stale_seconds` → exit; else
   ping `idle_message`. Any other event → exit.
5. Title: folder = basename of payload `cwd` (else `$PWD`); registry
   `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/${CLAUDE_PID}.json` → `.name`; empty or
   unreadable → title = folder; name starting with `<folder>-` → `<folder> · <rest>`; else
   `<folder> · <name>`.
6. Sanitise the message: CR/LF and control characters → spaces, squeeze, truncate to 200
   characters. Quotes and backslashes stay (argv delivery).
7. Presence (only when `presence` is true; runs on every OS so the override is testable
   everywhere): state = `CW_NOTIFY_PRESENCE` when set to `at` or `away`; otherwise, on
   Darwin only, probe idle = `ioreg -c IOHIDSystem` HIDIdleTime in seconds and locked =
   `ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw -`
   printing `true` or `1` (`plutil` prints booleans as `true`; the key is absent while
   unlocked), away = idle ≥ `idle_seconds` or locked; on other systems or on any probe
   error, state = at. Away and registry `.bridgeSessionId` non-empty → exit; otherwise
   continue. Presence off → none of this runs.
8. Delivery: `CW_NOTIFY_DRY_RUN=1` → `printf 'notify: %s | %s\n' "$title" "$msg"`, exit 0.
   Darwin → `osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$title" "$msg" >/dev/null 2>&1`,
   guarding a leading `-` in either value: if `osascript -e 'on run argv' -e 'return item 1 of argv' -e 'end run' -- -x`
   prints `-x`, pass `--` before the values; otherwise prefix a value that starts with `-`
   with a space (checked once by the implementer, recorded in the exit report). Linux with
   `notify-send` → `notify-send "$title" "$msg"`; else nothing.
- `hooks/hooks.json`: add `Notification` (the matcher above), `Stop` and `StopFailure` (no
  matcher) entries, each `bash "${CLAUDE_PLUGIN_ROOT}/hooks/notify.sh"`, `timeout: 5`.
  Write to a temp file, `jq .` it, confirm the three existing entries are unchanged, then
  move it in (Risk 10).
- `tests/run.sh`: `notify_case <expect-output:0|1> <needle> <description> <payload-json> [ENV=VAL ...]`
  runs the hook with `CW_NOTIFY_DRY_RUN=1 CW_NOTIFY_STATE_DIR=$SCRATCH/notify CLAUDE_CONFIG_DIR=$SCRATCH/cfg CLAUDE_PID=4242 CLAUDE_CODE_ENTRYPOINT=cli HOME=$SCRATCH/base`
  plus the case's overrides, asserts exit 0 and, per `<expect-output>`, empty stdout or
  stdout of exactly one line containing `<needle>` (`grep -F`, and `wc -l` = 1). Each
  state-driven pair (a `Stop` or `StopFailure` then an `idle_prompt`) shares one
  `session_id` of its own; every other case uses a fresh one. `hooks_notify_cases` writes
  `$SCRATCH/cfg/cw-notify.json` as `{}` (the opt-in) and the fixture registry
  `$SCRATCH/cfg/sessions/4242.json` with `jq -n` (`name` "proj-a0", `cwd` `$SCRATCH/proj`,
  `bridgeSessionId` null), then runs, in this order: (1) agent_completed silent; (2)
  auth_success silent; (3) quota_auto_resume_fired silent; (4) computer_use_enter silent;
  (5) permission_prompt → `proj · a0 | Permission needed`; (6) permission_prompt with
  agent_id/agent_type "reviewer" → `agent: reviewer`; (7) worker_permission_prompt, no
  agent_id → `Permission needed (worker)`; (8) agent_needs_input with agent_id silent; (9)
  agent_needs_input with message "Need a choice" → `Need a choice`; (10) push_notification
  message with `"`, `\` and an embedded newline → one output line containing both halves;
  (11) elicitation_dialog → `Input needed`; (12) Stop with `"background_tasks": ["x"]` →
  silent and the state file's first field is `1`; (13) idle_prompt, same session → silent;
  (14) Stop with `"background_tasks": []` → silent, first field `0`; (15) idle_prompt, same
  session → `Waiting for your input`; (16) idle_prompt, fresh session, no state file →
  output; (17) Stop with the `background_tasks` field absent → first field `0`; (18)
  StopFailure, fresh session → silent, first field `0`, then idle_prompt → output; (19)
  idle_prompt with a hand-written record `3 <epoch two hours old>` → output (stale = fail
  open); (20) registry absent → title `proj |`; (21) registry name "mysession" →
  `proj · mysession`; (22) config `{"presence":true}` + `CW_NOTIFY_PRESENCE=away` + registry
  bridgeSessionId "b1" + idle_prompt with a `0` record → silent; (23) same without bridge →
  output; (24) config `{}` + away + bridge → output (presence off by default); (25)
  `CLAUDE_CODE_ENTRYPOINT=sdk-cli` silent; (26) `CW_NOTIFY=0` silent; (27) config file
  absent → silent (opt-in); (28) config `{"enabled":false}` silent; (29) stdin `not json` →
  exit 0, silent; (30) jq absent (PATH shim as in `hooks_jq_absent_case`) → exit 0, silent;
  (31) `hooks/hooks.json` shape check with `jq -e` (the expression in this task's
  verification); (32) `CW_NOTIFY_STATE_DIR` pointing at a regular file: Stop exits 0
  silently, then idle_prompt → output. Call `hooks_notify_cases` from `cmd_hooks` after
  `hooks_profile_crlf_case`. Cases 22–24 run on every OS because the override is read before
  any probe (step 7).
- By hand once, on the implementer's own session: create the config file, let a turn go
  idle, and confirm one banner titled with the session name arrives about 60 s later;
  record the result in the exit report.

## Task T6
- scope: Document 1.0.1: agents table, notifications section, loop description and the design-draft release note.
- files_owned: [README.md, WORKFLOW.md, docs/plans/cw-plugin/cw-plugin-design-draft.md]
- files_forbidden: [skills/, agents/, rules/, hooks/, tests/, .claude-plugin/, docs/plans/stall-handling-1-0-1.md, docs/plans/fixups-1-0-0.md, docs/plans/hardening-1-0-0.md]
- depends_on: [T1, T2, T3, T4, T5]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `cd "$(git rev-parse --show-toplevel)" && grep -qi 'cw-notify.json' README.md && grep -q 'idle_prompt' README.md && grep -q 'stall ladder' README.md && grep -Eq 'reviewer.*\b40\b' README.md && grep -qi 'Script Editor' README.md && grep -q 'worker_permission_prompt' README.md && [ "$(wc -l < WORKFLOW.md)" -le 200 ] && grep -q '1.0.1' docs/plans/cw-plugin/cw-plugin-design-draft.md && N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1) && [ -n "$N" ] && ! grep -qi "$N" docs/plans/cw-plugin/cw-plugin-design-draft.md README.md WORKFLOW.md && ! grep -rn '</content>' README.md WORKFLOW.md docs/plans/cw-plugin/`, expected exit 0
- commit: docs: 1.0.1 notifier, turn caps, lean loop and stall ladder in README, WORKFLOW and the draft

Specification: README agents table gains a turn-cap column (40/40/15/50/30) and drops any
memory mention; a "Notifications" section (≤ 40 lines): that the notifier is opt-in (create
`cw-notify.json`, `{}` is enough), which events ping at once and how the idle ping is gated
on the background count `Stop` records, the title format, the config keys with defaults,
the `CW_NOTIFY=0` kill switch, presence off by default and what turning it on does, why
`agent_completed` and the quota types are excluded, Linux behaviour, that on macOS 15+ the
banner is delivered as Script Editor and needs that
app allowed in System Settings › Notifications (practitioner-sourced: the command exits 0
and shows nothing otherwise), and one paragraph on removing a pre-existing user-level
Notification hook (the plugin's replaces it; the operator edits their settings by hand). The loop description states two review rounds, the `lite`
flag, the ladder by pointer. `WORKFLOW.md` line ~102 and the review-loop paragraph reflect the
same. The design draft gains a "Release 1.0.1" section (≤ 40 lines): what changed and why,
with the measured numbers from Context. The two manifests are T7's.

## Task T7
- scope: Bump the plugin version to 1.0.1, add the marketplace description, and run the release gate on the finished series as this task's verification.
- files_owned: [.claude-plugin/plugin.json, .claude-plugin/marketplace.json]
- files_forbidden: [skills/, agents/, rules/, hooks/, tests/, README.md, WORKFLOW.md, docs/]
- depends_on: [T6]
- agent: implementer
- model: sonnet
- risk: trivial
- verification: `cd "$(git rev-parse --show-toplevel)" && grep -q '"version": "1.0.1"' .claude-plugin/plugin.json && jq -e '.description | length > 0' .claude-plugin/marketplace.json >/dev/null && jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json && out=$(claude plugin validate . 2>&1) && ! printf '%s' "$out" | grep -qi warning && claude plugin validate .claude-plugin/plugin.json >/dev/null 2>&1 && CW_SCAN_PATTERNS="${CW_SCAN_PATTERNS:-$HOME/.claude/private/pii-patterns.txt}" bash tests/run.sh all && /bin/bash tests/run.sh hooks | grep -q ' 0 failed' && shellcheck -x hooks/*.sh tests/run.sh && { [ -x "$HOME/.claude/plans/cw-plugin-gates/shellcheck-0.9.0" ] && "$HOME/.claude/plans/cw-plugin-gates/shellcheck-0.9.0" -x hooks/*.sh tests/run.sh || echo "shellcheck 0.9.0 absent, skipped"; } && ! git grep -niE 'opus needs|do not trust|be decisive|read all files fresh|claude-design-active|claude-orchestrator-active' -- skills agents rules && ! git grep -nwE 'NEVER|ALWAYS|MUST|CRITICAL' -- skills agents rules && ! git grep -niE 'under 50 lines' -- skills agents rules && ! git grep -nE '^(disallowedTools|permissionMode|mcpServers|hooks):' -- agents && for f in agents/*.md; do for k in model tools effort maxTurns; do grep -q "^$k:" "$f" || exit 1; done; done && ! git grep -niE '~/.claude/plans|gitattributes|linguist|git clean' -- skills && grep -q haiku skills/design/SKILL.md && ! grep -rn '</content>' skills agents rules hooks tests README.md WORKFLOW.md docs/plans/cw-plugin && N=$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE | cut -d' ' -f1) && [ -n "$N" ] && ! git grep -qi "$N" -- skills agents rules hooks tests WORKFLOW.md CLAUDE.md docs && [ "$(grep -E -c '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|@[a-z0-9.-]+\.[a-z]{2,}' docs/plans/stall-handling-1-0-1.md)" -eq 0 ] && [ "$(git log --format=%s main..HEAD | wc -l | tr -d ' ')" -eq 8 ] && [ "$(git log --format=%s main..HEAD | sort | uniq -d | wc -l | tr -d ' ')" -eq 0 ] && git diff --quiet && git diff --cached --quiet`, expected exit 0
- commit: chore(release): version 1.0.1 and the marketplace description

Specification: `plugin.json` `"version": "1.0.1"` only; `marketplace.json` gains a top-level
`"description"` (one sentence on what the marketplace offers) beside `name`, `owner` and
`plugins`. The `</content>` residue grep excludes `docs/plans/*.md` on purpose: earlier plans
and this one quote the literal inside their own guards. Run the verification after the
commit; a failing clause is a finding for the checkpoint, not a reason to edit files this
task does not own.
