#!/usr/bin/env bash
set -euo pipefail

# Self-contained launcher — copy this WHOLE file to your laptop (save as codex-launch.sh) and run:
#   bash codex-launch.sh
# It creates a local ./part2-connect-clients-workspace/ folder with the Brave web-search MCP config,
# opens an SSH tunnel to your Anyscale workspace, and starts Codex against the qwen LLM served there
# (direct streaming → /v1/responses on localhost:8000). Nothing else to set up.
#
# Laptop prereqs: Anyscale CLI (`anyscale login`), Codex (npm i -g @openai/codex), Node.js.
# Prompts for your workspace's console URL (or set WORKSPACE_URL=… to skip the prompt).
#   bash codex-launch.sh "explain this repo"   # positional args pass straight through to codex

BASE="${WORKSPACE_LLM_URL:-http://localhost:8000}/v1"   # ends in /v1
MODEL="${WORKSPACE_MODEL:-}"   # empty → auto-detected from the served endpoint below
PROVIDER="workspace-local"
CTX="${CODEX_MODEL_CONTEXT_WINDOW:-32768}"
MAXOUT="${CODEX_MODEL_MAX_OUTPUT_TOKENS:-8192}"
WS_URL="${WORKSPACE_URL:-}"   # empty → prompted for below (only if a tunnel is actually needed)
export WORKSPACE_API_KEY="local"                                          # dummy; localhost serve has no auth
export BRAVE_API_KEY="${BRAVE_API_KEY:-BSADFwvqJAoqW-579Ip_UozyGoPP2lx}"  # baked-in Brave key (internal training)

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

command -v codex >/dev/null 2>&1 || { echo "codex-launch: codex CLI not on PATH (npm i -g @openai/codex)." >&2; exit 1; }

# Open the tunnel ourselves unless localhost:8000 already answers (e.g. reusing claude-launch's tunnel).
if ! curl -sf --max-time 3 "${BASE}/models" >/dev/null 2>&1; then
  command -v anyscale >/dev/null 2>&1 || { echo "codex-launch: anyscale CLI not on PATH." >&2; exit 1; }
  if [ -z "$WS_URL" ]; then
    read -rp "codex-launch: paste your workspace URL from the Anyscale console: " WS_URL || true
  fi
  # The console URL carries the workspace id. Resolve by id, not name: `ssh -n <name>` only
  # searches your default project, so a workspace in any other project comes back "not found".
  WS_ID=$(printf '%s' "$WS_URL" | grep -oE 'expwrk_[A-Za-z0-9]+' | head -1 || true)
  [ -n "$WS_ID" ] || { echo "codex-launch: no workspace id (expwrk_…) in that input — paste the full console URL." >&2; exit 1; }
  # Talk to whichever console the URL came from, unless the caller already pinned a host.
  if [ -z "${ANYSCALE_HOST:-}" ]; then
    WS_HOST=$(printf '%s' "$WS_URL" | grep -oE 'https://console[A-Za-z0-9.-]*' | head -1 || true)
    [ -n "$WS_HOST" ] && export ANYSCALE_HOST="$WS_HOST"
  fi
  echo "codex-launch: opening SSH tunnel to ${WS_ID} (localhost:8000) …" >&2
  anyscale workspace_v2 ssh --id "$WS_ID" -- -N -L 8000:localhost:8000 &
  TUNNEL_PID=$!
  trap 'kill "$TUNNEL_PID" 2>/dev/null || true' EXIT INT TERM
  for _ in $(seq 1 60); do
    curl -sf --max-time 3 "${BASE}/models" >/dev/null 2>&1 && break
    kill -0 "$TUNNEL_PID" 2>/dev/null || { echo "codex-launch: tunnel exited early — is the workspace RUNNING, and does your 'anyscale login' match ${ANYSCALE_HOST:-the prod console}?" >&2; exit 1; }
    sleep 1
  done
  curl -sf --max-time 3 "${BASE}/models" >/dev/null 2>&1 || { echo "codex-launch: ${BASE} still not reachable after 60s — is the serve app up in the workspace?" >&2; exit 1; }
  echo "codex-launch: tunnel up." >&2
else
  echo "codex-launch: localhost:8000 already reachable — reusing the open tunnel." >&2
fi

# Read the served model id straight from the endpoint — no hardcoding (override with WORKSPACE_MODEL).
if [ -z "$MODEL" ]; then
  MODEL="$(curl -sf --max-time 5 "${BASE}/models" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null || true)"
  [ -n "$MODEL" ] || { echo "codex-launch: couldn't auto-detect the model id from ${BASE}/models — set WORKSPACE_MODEL." >&2; exit 1; }
fi

echo "codex-launch: Codex -> ${MODEL} @ ${BASE}/responses (workspace via localhost tunnel)" >&2

# Hosted tools (web_search / image gen / plugins) hit routes the custom provider doesn't serve — off;
# web search comes from the local Brave MCP in .codex/config.toml. requires_openai_auth=false so a clean
# ~/.codex needs no OpenAI login. Your ~/.codex auth/trust are untouched.
# No exec: keep this shell alive so the EXIT trap can close the tunnel when Codex quits.
# With no args, seed a first message so the model introduces itself and knows to use the Brave MCP.
if [ "$#" -eq 0 ]; then
  set -- "Hey, who are you and what model are you? For web searches, use the Brave Search MCP."
fi
codex \
  -c model="${MODEL}" \
  -c model_provider="${PROVIDER}" \
  -c "model_providers.${PROVIDER}.name=Workspace-local" \
  -c "model_providers.${PROVIDER}.base_url=${BASE}" \
  -c "model_providers.${PROVIDER}.env_key=WORKSPACE_API_KEY" \
  -c "model_providers.${PROVIDER}.wire_api=responses" \
  -c "model_providers.${PROVIDER}.requires_openai_auth=false" \
  -c model_context_window="${CTX}" \
  -c model_max_output_tokens="${MAXOUT}" \
  -c tools.web_search=false \
  -c features.image_generation=false \
  -c features.plugins=false \
  -c features.apps=false \
  -c features.browser_use=false \
  -c features.computer_use=false \
  -c features.multi_agent=false \
  "$@"
