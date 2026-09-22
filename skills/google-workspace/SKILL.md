---
name: google-workspace
description: "Hard-won routes and dead ends for driving Google Workspace from Claude. Use when the user asks to export or upload a Google Doc, create Docs suggestions or comments from a docx, share a Drive file, or automate Google Workspace through the Drive/Docs MCP connector or the browser. Says which capabilities the connector genuinely has, which have no API at all, and the working workaround for each."
---

# Google Workspace — what actually works

## Capability matrix (Drive/Docs MCP connector)
| Need | MCP/API? | Working route |
|---|---|---|
| Read Doc text + comments | YES — `read_file_content` (includeComments) | direct |
| Search/list/rename/move files | YES | direct |
| Export a Doc (docx/text) | YES but base64-through-context (~25k tokens/100KB) | prefer browser: navigate to `docs.google.com/document/d/<ID>/export?format=docx` → lands in ~/Downloads, zero context cost |
| Upload a binary (docx etc.) | **NO** — MCP `create_file` caps ~8KB binaries, streams tokens | see "Upload routes" below |
| Create Google Docs SUGGESTIONS | **NO API EXISTS** (Docs API SUGGEST mode is Workspace-preview-gated; silently applies edits if unenrolled) | docx with `w:ins`/`w:del` tracked changes → upload with convert → suggestions appear natively |
| Create Docs COMMENTS | **NO MCP tool** (Drive API has comments.create but connector doesn't expose it) | put `w:comment` in the docx (see caveats) or add manually in UI |
| Share a file externally | **NO, two walls**: auto-mode classifier blocks it AND, even with an allow rule for `mcp__claude_ai_Google_Drive__share_file`, Google returns "The caller does not have permission" — the connector's OAuth grant lacks sharing rights | the user shares in the UI (fastest) or browser automation |

## Upload routes for binaries, in order of preference
1. **The user at a computer**: OAuth Playground token (tick FULL-URL scopes `https://www.googleapis.com/auth/drive.file` — bare "drive" → invalid_scope; add `.../drive.readonly` if downloading too) + curl multipart with metadata `mimeType: application/vnd.google-apps.document` → converts docx→Doc in seconds.
2. **Browser automation (Claude-in-Chrome)**: Docs home → "Open file picker" → Upload tab. The picker is an IFRAME opaque to the accessibility tree — drive it with javascript_tool only. Activate the Upload tab by clicking the tab BUTTON found via `contentDocument` traversal; an `input[type=file]` then mounts. Inject the file via `new File(...)` + `DataTransfer` + `input.files = dt.files` + `change` event. Get bytes in via base64 chunks pushed to `window.__b64` across calls (≤~23KB per call). If the account has "Convert uploads" on, the docx converts to a native Doc automatically.
3. Drive-for-desktop sync folder (`~/Library/CloudStorage/GoogleDrive-*`) — only if installed.

## Landmines (each cost real time)
- **fetch to 127.0.0.1/localhost from a Google page**: Chrome Private-Network-Access silently hangs it; the CDP evaluate times out at 45s — but the async page code may still complete later. Never rely on it; never assume it failed either — check ground truth (Drive search) before retrying.
- **javascript_tool results containing URLs/query strings get classifier-redacted** ("[BLOCKED]") — return only hostnames, counts, booleans.
- **Native macOS file dialogs are unreachable**: osascript keystrokes need Accessibility permission the host app doesn't have (reading process names works; sending keys doesn't). If a native dialog opens, only a human or a Chrome restart (`osascript -e 'tell app "Google Chrome" to quit'` — app-level scripting IS allowed) clears it.
- **docx→Docs comment conversion**: comments anchored to text INSIDE `w:ins` runs in TABLE CELLS are dropped; comments elsewhere survive but Google RE-ANCHORS by first text match of the quoted span — anchor on text unique in the whole doc or it lands on the wrong occurrence. Fix comments in the UI after import, never by re-import.
- **Google Docs docx exports normalize U+200B away**; typographic apostrophes (U+2019) survive. Byte-match anchors against the actual export, not assumptions.
- **Suggestion verification without the UI**: a Doc's text export shows pending suggestions as old-text immediately followed by new-text (deletions retained + insertions included). Old+new adjacent = pending suggestions; only-new = silently applied (bad); only-old = import failed.
- **Tracked-changes docx build**: string surgery on document.xml works (proven twice); split runs that mix `w:t` with `w:br` into atom-runs first; `<w:rPr/>` self-closed needs its own regex branch; verify by reconstructing reject-all text (must equal original exactly) and accept-all text (must contain every insert).
- Gmail MCP: good for search/read/drafts; not an attachment transport for binaries.
