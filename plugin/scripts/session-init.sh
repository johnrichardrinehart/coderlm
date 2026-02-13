#!/usr/bin/env bash
# plugin/scripts/session-init.sh
# Check if coderlm-server is running and auto-create session.
# Called by the SessionStart hook when the plugin is installed.
# Always exits 0 to never block session start.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLI="$PLUGIN_ROOT/skills/coderlm/scripts/coderlm_cli.py"
CODERLM_PORT="${CODERLM_PORT:-3002}"

BASE_STATE_DIR=".claude/coderlm_state"
if [ -n "${CODERLM_INSTANCE:-}" ]; then
    STATE_FILE="$BASE_STATE_DIR/sessions/$CODERLM_INSTANCE/session.json"
else
    STATE_FILE="$BASE_STATE_DIR/session.json"
fi

# Check server health
if ! curl -s --max-time 2 "http://127.0.0.1:${CODERLM_PORT}/api/v1/health" > /dev/null 2>&1; then
    echo "[coderlm] Server not running. Start it with: cd server && cargo run -- serve" >&2
    exit 0
fi

# Create a stable project-local symlink so the skill can find the CLI
# regardless of whether the plugin is installed at user or project level
mkdir -p "$(dirname "$STATE_FILE")"
ln -sf "$CLI" "$(dirname "$STATE_FILE")/coderlm_cli.py"

# Auto-init if no active session
if [ ! -f "$STATE_FILE" ]; then
    python3 "$CLI" init --port "$CODERLM_PORT" 2>&1 || true
fi

exit 0
