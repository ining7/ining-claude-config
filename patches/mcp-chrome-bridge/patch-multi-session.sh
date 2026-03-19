#!/usr/bin/env bash
#
# patch-multi-session.sh
# Fixes mcp-chrome-bridge single-session bug to support multiple concurrent Claude Code sessions.
#
# Bug: getMcpServer() returns a singleton Server instance, but MCP SDK's Server.connect()
#      does not allow binding multiple transports to the same instance.
#      Result: only the first Claude Code session can use Chrome MCP; others get 500 error.
#
# Fix: Add createMcpServer() that creates a new Server instance per connection.
#
# Usage:
#   bash patch-multi-session.sh            # auto-detect npm global path
#   bash patch-multi-session.sh /path/to   # specify mcp-chrome-bridge root (containing dist/)
#
# Tested with: mcp-chrome-bridge@1.0.31
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Locate mcp-chrome-bridge ---
if [[ -n "${1:-}" ]]; then
    BRIDGE_DIR="$1/dist"
else
    NPM_ROOT="$(npm root -g 2>/dev/null || true)"
    if [[ -d "$NPM_ROOT/mcp-chrome-bridge/dist" ]]; then
        BRIDGE_DIR="$NPM_ROOT/mcp-chrome-bridge/dist"
    else
        error "Cannot find mcp-chrome-bridge. Install with: npm i -g mcp-chrome-bridge"
    fi
fi

MCP_SERVER_JS="$BRIDGE_DIR/mcp/mcp-server.js"
SERVER_INDEX_JS="$BRIDGE_DIR/server/index.js"

[[ -f "$MCP_SERVER_JS" ]]  || error "File not found: $MCP_SERVER_JS"
[[ -f "$SERVER_INDEX_JS" ]] || error "File not found: $SERVER_INDEX_JS"

info "Bridge dir: $BRIDGE_DIR"

# --- Check if already patched ---
if grep -q "createMcpServer" "$MCP_SERVER_JS" 2>/dev/null && \
   grep -q "mcp_server_multi_1" "$SERVER_INDEX_JS" 2>/dev/null; then
    info "Both files already patched. Nothing to do."
    exit 0
fi

# --- Backup originals ---
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"
info "Backing up originals (suffix: $BACKUP_SUFFIX)"
cp "$MCP_SERVER_JS"  "$MCP_SERVER_JS$BACKUP_SUFFIX"
cp "$SERVER_INDEX_JS" "$SERVER_INDEX_JS$BACKUP_SUFFIX"

# --- Patch using Python (cross-platform, no sed quirks) ---
info "Applying patches..."

python3 << PYEOF
import sys

# ====== Patch mcp-server.js ======
mcp_path = "$MCP_SERVER_JS"
with open(mcp_path, "r") as f:
    content = f.read()

if "createMcpServer" not in content:
    # 1. Update exports declaration
    content = content.replace(
        "exports.getMcpServer = exports.mcpServer = void 0;",
        "exports.createMcpServer = exports.getMcpServer = exports.mcpServer = void 0;"
    )

    # 2. Insert createMcpServer function before sourceMappingURL
    new_func = '''// Create a new independent MCP Server instance per connection (multi-session support)
const createMcpServer = () => {
    const server = new index_js_1.Server({
        name: 'ChromeMcpServer',
        version: '1.0.0',
    }, {
        capabilities: {
            tools: {},
        },
    });
    (0, register_tools_1.setupTools)(server);
    return server;
};
exports.createMcpServer = createMcpServer;
'''
    content = content.replace(
        "//# sourceMappingURL=mcp-server.js.map",
        new_func + "//# sourceMappingURL=mcp-server.js.map"
    )

    with open(mcp_path, "w") as f:
        f.write(content)
    print("[PATCH] mcp-server.js: OK")
else:
    print("[PATCH] mcp-server.js: already patched, skipped")

# ====== Patch server/index.js ======
srv_path = "$SERVER_INDEX_JS"
with open(srv_path, "r") as f:
    content = f.read()

if "mcp_server_multi_1" not in content:
    # 1. Add multi-session reference after mcp_server_1 require
    content = content.replace(
        'const mcp_server_1 = require("../mcp/mcp-server");',
        'const mcp_server_1 = require("../mcp/mcp-server");\nconst mcp_server_multi_1 = { createMcpServer: mcp_server_1.createMcpServer };'
    )

    # 2. Replace SSE endpoint singleton
    content = content.replace(
        "const server = (0, mcp_server_1.getMcpServer)();",
        "const server = (0, mcp_server_multi_1.createMcpServer)();"
    )

    # 3. Replace StreamableHTTP endpoint singleton
    content = content.replace(
        "await (0, mcp_server_1.getMcpServer)().connect(transport);",
        "await (0, mcp_server_multi_1.createMcpServer)().connect(transport);"
    )

    with open(srv_path, "w") as f:
        f.write(content)
    print("[PATCH] server/index.js: OK")
else:
    print("[PATCH] server/index.js: already patched, skipped")
PYEOF

# --- Restart bridge ---
info "Restarting mcp-chrome-bridge..."
BRIDGE_PIDS=$(lsof -ti :12306 2>/dev/null || true)
if [[ -n "$BRIDGE_PIDS" ]]; then
    # Only kill the listening process (bridge), not connected clients
    LISTEN_PID=$(lsof -i :12306 2>/dev/null | grep LISTEN | awk '{print $2}' | head -1)
    if [[ -n "$LISTEN_PID" ]]; then
        kill "$LISTEN_PID" 2>/dev/null || true
        info "Killed old bridge (PID $LISTEN_PID)."
    fi
    info "Chrome extension will auto-restart the bridge when needed."
    info "Open/refresh any Chrome tab to trigger restart."
    sleep 3
    NEW_PID=$(lsof -i :12306 2>/dev/null | grep LISTEN | awk '{print $2}' | head -1 || true)
    if [[ -n "$NEW_PID" ]]; then
        info "New bridge started (PID $NEW_PID)."
    else
        warn "Bridge not yet restarted. Open a Chrome tab to trigger it."
    fi
else
    warn "No bridge process found on port 12306. It will start when Chrome needs it."
fi

# --- Verify ---
info "Verifying patch..."
ERRORS=0
if ! grep -q "createMcpServer" "$MCP_SERVER_JS"; then
    error "mcp-server.js patch verification failed"
    ERRORS=1
fi
if ! grep -q "mcp_server_multi_1" "$SERVER_INDEX_JS"; then
    error "server/index.js patch verification failed"
    ERRORS=1
fi

if [[ "$ERRORS" -eq 0 ]]; then
    echo ""
    info "Patch applied and verified successfully."
    info "Restart your Claude Code sessions to use multi-session Chrome MCP."
    echo ""
    info "To revert: restore from backup files (*$BACKUP_SUFFIX)"
fi
