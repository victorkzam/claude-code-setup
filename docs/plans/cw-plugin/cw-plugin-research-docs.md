## §R2 Research: docs currency (researcher sonnet 2026-09-16 against the live docs; context7's snapshots stop at v2.1.89, so every claim comes from a direct fetch; installed v2.1.273)

1. Plugin manifest: only `name` is required (kebab-case); optional `displayName`, `version`,
   `description`, `author{name,email,url}`, `homepage`, `repository`, `license`, `keywords`,
   `metadata`, `userConfig`, `dependencies`, `defaultEnabled`; component paths are relative to
   the root and start with `./` (`skills` adds to `skills/`; `agents` and `commands` replace;
   `hooks`, `mcpServers`, `lspServers` take paths or inline config). Only `plugin.json` lives
   inside `.claude-plugin/`; `skills/`, `agents/`, `hooks/` sit at the plugin root (nesting
   them inside `.claude-plugin/` is a documented "common mistake").
   https://code.claude.com/docs/en/plugins-reference
2. Marketplace: `.claude-plugin/marketplace.json` with `name` (kebab-case), `owner{name}`,
   `plugins[{name, source, description?, version?}]`; `source: "./"` is valid when the repo is
   the marketplace ("Paths resolve relative to the marketplace root, which is the directory
   containing `.claude-plugin/`"); users run `claude plugin marketplace add <owner>/<repo>`
   then `claude plugin install <plugin>@<the name inside marketplace.json>`; relative sources
   resolve for git-added marketplaces, not for a raw-URL `marketplace.json`; `strict`
   defaults to true (plugin.json authoritative). Installs land under the plugin cache
   (`~/.claude/plugins/cache/<marketplace>/<plugin>/`), replaced on `claude plugin update`.
   https://code.claude.com/docs/en/plugin-marketplaces
3. `claude plugin validate <path>`: static schema validation (unknown fields warn, `--strict`
   fails; agent frontmatter parsed since v2.1.233); exit 0 valid, 1 invalid, 2 the run failed;
   no login documented and a practitioner CI runs it unauthenticated after installing the CLI
   (§R3 row 5). `claude plugin eval` (v2.1.269) runs model calls with credentials — a
   follow-up. https://code.claude.com/docs/en/plugin-evals
4. Skills-directory plugins: "Any folder under a skills directory that contains a
   `.claude-plugin/plugin.json` manifest is loaded as a plugin named `<name>@skills-dir` on
   the next session, with no marketplace and no install step"; SKILL.md edits apply
   immediately; `hooks/`, `agents/`, `.mcp.json` need `/reload-plugins` or a restart;
   `claude plugin disable <name>@skills-dir`; nothing to uninstall. The doc names
   `~/.claude/skills/` and `<cwd>/.claude/skills/`; relocation by `CLAUDE_CONFIG_DIR` is not
   stated, but the private probe of 2026-09-15 under a temporary config dir loaded a
   symlinked plugin folder: `claude plugin list` showed it loaded and `claude plugin details`
   printed the inventory (skills 1, agents 1, hooks 1).
   https://code.claude.com/docs/en/plugins-reference
5. `hooks/hooks.json`: `{"hooks": {<Event>: [{matcher, hooks: [{type: "command", command,
   if?, timeout}]}]}}` (`if` sits inside the handler object next to `command`); `timeout` in
   seconds (default 600); `${CLAUDE_PLUGIN_ROOT}` substituted. `if` is "permission rule
   syntax to filter when this hook runs", evaluated only on tool events, before spawning; the
   Bash matcher strips env prefixes and checks each subcommand of a chain, but "when the
   shell parser can't determine expansion … the hook runs anyway", and the doc itself says
   "Because the `if` filter is best-effort, use the permission system rather than a hook to
   enforce a hard allow or deny" (§R3 row 6). File-write coverage:
   "Use explicit matchers if you need those: `Edit|Write|MultiEdit|NotebookEdit`".
   SessionStart matchers: `startup`, `resume`, `clear`, `compact`, `fork`. **Exit code 2 on
   SessionStart: "Blocks session initialization"** (effect table) — a notice must use exit 0
   with JSON; `systemMessage` in JSON stdout surfaces a message to the user ("Some events
   discard it or deliver it elsewhere"); for SessionStart, plain stdout and
   `hookSpecificOutput.additionalContext` are "context that Claude can see and act on". A
   plugin hook and a settings hook with the same command both fire ("A plugin's or skill's
   copy of the same handler stays separate"). Stdin carries `session_id`, `cwd`,
   `hook_event_name`, `tool_name`, `tool_input` (`command` for Bash, `file_path` for file
   tools), `tool_use_id`. https://code.claude.com/docs/en/hooks
6. SKILL.md frontmatter: `name`, `description`, `when_to_use` ("trigger phrases or example
   requests. Appended to `description` in the skill listing and counts toward the
   1,536-character cap"), `argument-hint`, `disable-model-invocation` ("prevent Claude from
   automatically loading this skill … trigger manually with `/name`"), `user-invocable`,
   `allowed-tools` ("Tools Claude can use without asking permission during the turn that
   invokes this skill"), `disallowed-tools` ("Tools removed from Claude's available pool
   while this skill is active … The restriction clears when you send your next message"),
   `model`, `effort` ("Overrides the session effort level" while active), `context: fork`,
   `agent`, `paths`, `hooks`, `shell`. Plugin skills are `/<plugin>:<skill>`; the bare
   `/name` also works unless another command uses it; the model invokes `plugin:skill`
   through the Skill tool. Description-based triggering is documented as probabilistic
   ("Strengthen the skill's `description` … or use hooks to enforce behavior
   deterministically"). VS Code extension bug #74363: a plugin skill whose bare name collides
   with a built-in command becomes unreachable there — none of the six `cw` names collide.
   https://code.claude.com/docs/en/skills
7. Agent frontmatter: `model` (`sonnet`, `opus`, `haiku`, `fable`, a full id, `inherit`),
   `effort`, `maxTurns`, `tools` (incl. `Agent(type)` allowlists), `disallowedTools`,
   `permissionMode`, `memory` (`user|project|local`), `skills`, `mcpServers`, `hooks`,
   `background`, `isolation`, `color`. **"For security reasons, plugin subagents don't support
   the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields. These fields are ignored
   when loading agents from a plugin."** Precedence: managed > `--agents` > project > user >
   plugin; "A user or project subagent named `Explore` overrides the built-in" — a plugin
   agent cannot. Plugin agents register as `<plugin>:<agent>`.
   https://code.claude.com/docs/en/sub-agents
8. `plansDirectory`: settings-reference row "Choose where plan mode writes plan files" (any
   scope); open bugs #39481 (absolute paths ignored) and #19537 (project-level value ignored
   in some cases); plan mode writes one random-named file (observed again this session). The
   design moves the plan file at Step 6 wherever it landed.
9. Auto-update and symlinks: #50052 (auto-update silently removed symlinks under
   `~/.claude/skills/`, opened 2026-04-17, closed "not planned"); whether it hits a symlinked
   skills-dir plugin folder is not documented either way; no fix in 2.1.269–273.
   `autoUpdates` is a legacy `~/.claude.json` key (#60956 reports it ignored on native
   installs); `DISABLE_AUTOUPDATER=1` is the reliable switch. Plan A's concern; plan B
   documents the real-directory fallback and the marketplace path.
10. CLAUDE.md imports: "Both relative and absolute paths are allowed … maximum depth of four
    hops"; the external-import approval dialog applies to project-scope files only — "User-scope
    memory files, such as `~/.claude/CLAUDE.md` and `~/.claude/rules/` … Claude Code loads their
    imports without the dialog". Behaviour on a missing target is undocumented (profile-check
    reports it). Plugins list no CLAUDE.md or rules component. https://code.claude.com/docs/en/memory
11. `/deep-research <question>` is a built-in workflow ("Fans out web searches … returns a
    cited report"); needs WebSearch and dynamic workflows (paid plans; Pro toggles it in
    `/config`; `disableWorkflows` turns it off). https://code.claude.com/docs/en/workflows
12. Changelog 2.1.269–2.1.273: `claude plugin eval` (269), plugin MCP/LSP/headless fixes
    (271), nothing on `if`, skills-dir loading, agent frontmatter, `plansDirectory` or
    `validate`. https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
13. Settings keys for the example file: the settings-reference page lists every top-level
    `settings.json` key (incl. `model`, `effortLevel`, `plansDirectory`, `permissions`,
    `autoMode`, `enabledPlugins`, `hooks`, `tui`, `theme`, `forceLoginMethod`,
    `forceLoginOrgUUID`). https://code.claude.com/docs/en/settings-reference
