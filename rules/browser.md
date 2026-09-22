# Browser (Claude in Chrome)

Chrome is the operator's signed-in browser and the only route to anything
behind a login. Playwright is for public pages and clean-session tests only.
This runbook applies when the profile's CLAUDE.md says the operator has chosen
Claude Code over the Claude desktop app for Chrome control and has authorised
the steps below; then run them, do not ask.

Why it breaks: the extension probes native hosts in a fixed order, the Claude
desktop app's `com.anthropic.claude_browser_extension` first and Claude Code's
`com.anthropic.claude_code_browser_extension` second, and stops at the first
that answers. Whenever the desktop manifest exists, the desktop app owns the
extension even if the app is closed (anthropics/claude-code #51519, #54567;
Anthropic's docs do not mention the conflict). Every desktop-app update puts
the manifest back. Moving it aside means the desktop app loses its own Chrome
control until it is restored.

## When any `mcp__claude-in-chrome__*` call says "extension is not connected"
Fix it yourself, in this order, and only then continue the task. Do not ask
the operator to quit an app, rename a file, or run `/chrome`.

1. Diagnose (30 s, all read-only):
   - Account and pairing: `python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.claude.json')));print(d.get('oauthAccount',{}).get('emailAddress'), d.get('chromeExtension'))"`
   - Manifests in `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`:
     `com.anthropic.claude_code_browser_extension.json` must exist (Claude
     Code rewrites it at session start); `com.anthropic.claude_browser_extension.json`
     is the desktop app's and, when present, takes the extension away from
     Claude Code.
   - `pgrep -lf chrome-native-host` (the helper exists only while Chrome runs)
     and `pgrep -x "Google Chrome"`.
   - The profile to use: in Chrome's `Local State`, `profile.info_cache`, the
     entry whose `user_name` equals the Claude Code account; confirm
     `<profile dir>/Extensions/<id>` exists, `<id>` from the `allowed_origins`
     of the Claude Code manifest.
2. Fix:
   - `osascript -e 'tell application "Claude" to quit'`, then
     `pkill -f 'Claude.app/Contents/Helpers/chrome-native-host'` (exit 1 is
     fine): the extension keeps a port open to the desktop helper and does
     not re-probe until that port is severed. Then quit `"Google Chrome"` the
     same way and wait until `pgrep -x "Google Chrome"` is empty (up to 20 s).
   - Move the desktop manifest aside: `mv .../com.anthropic.claude_browser_extension.json{,.off}`.
     It comes back after a desktop-app update; moving it is the fix each time.
   - Relaunch the right profile with the operator's tabs:
     `open -na "Google Chrome" --args --profile-directory="<dir>" --restore-last-session`
     (tabs come back only if Chrome's own "continue where you left off" is
     on or this flag is honoured).
   - Wait about 12 s, confirm the running helper is `claude --chrome-native-host`
     (Claude Code's, not `/Applications/Claude.app/...`), then call
     `tabs_context_mcp` with `createIfEmpty: true`. After any Chrome restart,
     earlier tab ids are stale: fetch the context again before acting
     (#95158, #87774).
3. If it is still not connected, two causes remain, both outside an agent's
   reach: this Claude Code session cached the desktop socket path at start
   and needs a fresh `claude` session (#51519), or the pairing went stale
   after an account switch and the extension must be reinstalled in that
   profile (#94764). Say which one the diagnosis points to, hand the task's
   browser part back, and continue everything that does not need the
   extension. "Receiving end does not exist" is different: the service
   worker went idle; quitting and relaunching Chrome as above revives it.
4. If lookups to `claude.ai` time out (`dig +short +time=3 @1.1.1.1 claude.ai`
   versus the router), the relay will drop. Setting reliable resolvers is the
   remedy; that is a system change, so do it only when the profile allows it,
   and say so in the summary.

## Working in the browser
- One tab group per session; create tabs, close what you opened, leave a tab
  open only when the operator should see it.
- Batch actions with `browser_batch`; read values with `javascript_tool` or
  `read_page`, never from a screenshot.
- Secrets read from a page (API keys) go straight to the operator's secret
  store through a temp file or stdin, never into a command line, a log or the
  reply; report the last four characters only.
- Never type a password; if a page asks for one, stop and report the URL.
- After a fix, append what worked, dated, to the troubleshooting memo the
  profile names.
