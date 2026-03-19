# Web Content Access Rules

When you need to access a URL (e.g., Confluence, internal wiki, any webpage):

1. **Always prefer Chrome MCP tools first** — Use `chrome_get_web_content`, `chrome_computer` etc. to read page content from the user's authenticated Chrome browser. This avoids login walls, saves context, and doesn't create temporary files.
2. **Only fall back to WebFetch** if Chrome MCP is unavailable (e.g., failed to connect). Never use `curl` to fetch web content.
3. For pages that require navigation, use `chrome_computer` to open the URL in an existing tab, wait for load, then use `chrome_get_web_content` to extract text.

# Chrome MCP Troubleshooting

## Architecture
```
Claude Code session → mcp-chrome-stdio (stdio subprocess, per session)
                          ↓ StreamableHTTP client
                     mcp-chrome-bridge :12306 (HTTP server, started by Chrome extension)
                          ↓ Native Messaging
                     Chrome browser extension
```

- `mcp-chrome-bridge` (process: `node .../mcp-chrome-bridge/dist/index.js`) is launched by Chrome extension via Native Messaging, listens on `127.0.0.1:12306`
- `mcp-chrome-stdio` is spawned by each Claude Code session as a stdio subprocess, connects to bridge via HTTP
- Config: `~/.claude.json` top-level `mcpServers.chrome-mcp-server` (type: stdio, command: mcp-chrome-stdio)
- Bridge URL hardcoded in `/opt/homebrew/lib/node_modules/mcp-chrome-bridge/dist/mcp/stdio-config.json`

## Common Issue: "Failed to connect to MCP server"

**Root cause:** The `mcp-chrome-stdio` process in the current session lost its HTTP connection to the bridge. This happens when:
1. The bridge process (`mcp-chrome-bridge`) was killed or restarted (e.g., Chrome restart, manual kill)
2. The stdio process does NOT auto-reconnect — it stays alive but broken

**Diagnosis steps:**
```bash
# 1. Check if bridge is running and listening
lsof -i :12306

# 2. Check all mcp-chrome processes
ps aux | grep mcp-chrome | grep -v grep

# 3. Test bridge HTTP endpoint
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:12306/ping
# Should return 200. If connection refused → bridge is down.
```

**Fix:**
1. Kill the stale bridge if it exists: `kill <bridge_pid>`
2. Reopen any Chrome tab or trigger the extension to let Chrome restart the bridge
3. **Restart the Claude Code session** (the broken stdio subprocess cannot be recovered in-place; `/mcp` showing "Connected" is misleading because it only checks the stdio pipe, not the HTTP connection to bridge)

**Prevention:** If MCP fails in a session, do not try to fix it in the same session. Start a new Claude Code session after ensuring the bridge is healthy.

# Plan Mode Rules

When in Plan Mode, before exiting plan mode (ExitPlanMode), you MUST follow this review cycle:

1. Use the `/code-review` skill to send the current plan to an independent Claude instance for review
2. Include the full plan content as the argument
3. Present the review feedback to the user clearly, separating:
   - MUST-FIX issues (with reasons)
   - Suggestions (optional improvements)
4. Ask the user how to proceed:
   - Revise the plan based on feedback → make changes and go back to step 1
   - Proceed as-is → ExitPlanMode
   - Partially adopt → user specifies which items to address, revise accordingly, then go back to step 1
5. Only ExitPlanMode when the user explicitly approves
