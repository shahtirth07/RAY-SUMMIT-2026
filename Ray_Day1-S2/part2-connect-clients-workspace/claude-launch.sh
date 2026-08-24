#!/usr/bin/env bash
set -euo pipefail

# Self-contained launcher — copy this WHOLE file to your laptop (save as claude-launch.sh) and run:
#   bash claude-launch.sh
# It creates a local ./part2-connect-clients-workspace/ folder with the Brave web-search MCP config,
# opens an SSH tunnel to your Anyscale workspace, and starts Claude Code against the qwen LLM served
# there (direct streaming → /v1/messages on localhost:8000). Nothing else to set up.
#
# Laptop prereqs: Anyscale CLI (`anyscale login`), Claude Code, Node.js (for the MCP server via npx).
# Prompts for your workspace's console URL (or set WORKSPACE_URL=… to skip the prompt).
#   bash claude-launch.sh -p "hi"    # positional args pass straight to claude

BASE="${WORKSPACE_LLM_URL:-http://localhost:8000}"   # root, no /v1
MODEL="${WORKSPACE_MODEL:-}"   # empty → auto-detected from the served endpoint below
WS_URL="${WORKSPACE_URL:-}"   # empty → prompted for below (only if a tunnel is actually needed)
export BRAVE_API_KEY="${BRAVE_API_KEY:-BSADFwvqJAoqW-579Ip_UozyGoPP2lx}"   # baked-in Brave key (internal training)

# --- Write the Brave MCP config into a local project folder, then work from it. ---
WORKDIR="part2-connect-clients-workspace"
mkdir -p "$WORKDIR/.codex"
cat > "$WORKDIR/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@brave/brave-search-mcp-server", "--transport", "stdio"],
      "env": { "BRAVE_API_KEY": "${BRAVE_API_KEY}" }
    }
  }
}
JSON
cat > "$WORKDIR/.codex/config.toml" <<'TOML'
[mcp_servers.brave-search]
command = "npx"
args = ["-y", "@brave/brave-search-mcp-server", "--transport", "stdio"]
env_vars = ["BRAVE_API_KEY"]
TOML
cd "$WORKDIR"

command -v claude >/dev/null 2>&1 || { echo "claude-launch: claude CLI not on PATH." >&2; exit 1; }

# Open the tunnel ourselves unless localhost:8000 already answers (e.g. a second agent reusing it).
if ! curl -sf --max-time 3 "${BASE}/v1/models" >/dev/null 2>&1; then
  command -v anyscale >/dev/null 2>&1 || { echo "claude-launch: anyscale CLI not on PATH." >&2; exit 1; }
  if [ -z "$WS_URL" ]; then
    read -rp "claude-launch: paste your workspace URL from the Anyscale console: " WS_URL || true
  fi
  # The console URL carries the workspace id. Resolve by id, not name: `ssh -n <name>` only
  # searches your default project, so a workspace in any other project comes back "not found".
  WS_ID=$(printf '%s' "$WS_URL" | grep -oE 'expwrk_[A-Za-z0-9]+' | head -1 || true)
  [ -n "$WS_ID" ] || { echo "claude-launch: no workspace id (expwrk_…) in that input — paste the full console URL." >&2; exit 1; }
  # Talk to whichever console the URL came from, unless the caller already pinned a host.
  if [ -z "${ANYSCALE_HOST:-}" ]; then
    WS_HOST=$(printf '%s' "$WS_URL" | grep -oE 'https://console[A-Za-z0-9.-]*' | head -1 || true)
    [ -n "$WS_HOST" ] && export ANYSCALE_HOST="$WS_HOST"
  fi
  echo "claude-launch: opening SSH tunnel to ${WS_ID} (localhost:8000) …" >&2
  anyscale workspace_v2 ssh --id "$WS_ID" -- -N -L 8000:localhost:8000 &
  TUNNEL_PID=$!
  trap 'kill "$TUNNEL_PID" 2>/dev/null || true' EXIT INT TERM
  for _ in $(seq 1 60); do
    curl -sf --max-time 3 "${BASE}/v1/models" >/dev/null 2>&1 && break
    kill -0 "$TUNNEL_PID" 2>/dev/null || { echo "claude-launch: tunnel exited early — is the workspace RUNNING, and does your 'anyscale login' match ${ANYSCALE_HOST:-the prod console}?" >&2; exit 1; }
    sleep 1
  done
  curl -sf --max-time 3 "${BASE}/v1/models" >/dev/null 2>&1 || { echo "claude-launch: ${BASE} still not reachable after 60s — is the serve app up in the workspace?" >&2; exit 1; }
  echo "claude-launch: tunnel up." >&2
else
  echo "claude-launch: localhost:8000 already reachable — reusing the open tunnel." >&2
fi

# Read the served model id straight from the endpoint — no hardcoding (override with WORKSPACE_MODEL).
if [ -z "$MODEL" ]; then
  MODEL="$(curl -sf --max-time 5 "${BASE}/v1/models" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null || true)"
  [ -n "$MODEL" ] || { echo "claude-launch: couldn't auto-detect the model id from ${BASE}/v1/models — set WORKSPACE_MODEL." >&2; exit 1; }
fi

# localhost serve has no auth, but Claude Code requires a non-empty token — send a dummy.
export ANTHROPIC_BASE_URL="${BASE%/}"
export ANTHROPIC_AUTH_TOKEN="workspace-local"
unset ANTHROPIC_API_KEY   # avoid the "both AUTH_TOKEN and API_KEY set" warning
export ANTHROPIC_MODEL="${MODEL}"
# Remap every named tier so /model, subagents, and background tasks all land on qwen.
export ANTHROPIC_DEFAULT_OPUS_MODEL="${MODEL}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${MODEL}"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${MODEL}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export API_TIMEOUT_MS="${API_TIMEOUT_MS:-1200000}"   # ride out the cold start

# With no args, seed a first message so the model introduces itself and knows to use the Brave MCP.
if [ "$#" -eq 0 ]; then
  set -- "Hey, who are you and what model are you? For web searches, use the Brave Search MCP."
fi

echo "claude-launch: Claude Code -> ${MODEL} @ ${ANTHROPIC_BASE_URL}/v1/messages (workspace via localhost tunnel)" >&2
# No exec: keep this shell alive so the EXIT trap can close the tunnel when Claude Code quits.
claude "$@"
