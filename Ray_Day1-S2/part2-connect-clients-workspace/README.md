# Part 2 — connect Claude Code / Codex

From **your laptop**, point Claude Code or Codex at the qwen LLM you deployed in Part 1. The launcher is
self-contained — it writes the Brave MCP config, asks for your workspace's console URL and opens an SSH
tunnel to it, then starts the agent against `localhost:8000` with a first prompt so the model introduces
itself. No repo checkout needed.

**Prereqs (laptop):** Anyscale CLI (`anyscale login`), Claude Code and/or Codex, Node.js.

## Run it

Use `claude-launch.sh` for Claude Code, or `codex-launch.sh` for Codex.

1. On your laptop, create a new file with that name.
2. Copy the full contents of the matching script ([`claude-launch.sh`](claude-launch.sh) / [`codex-launch.sh`](codex-launch.sh)) from your workspace into it.
3. Run it:
   ```bash
   bash claude-launch.sh
   ```

**Shortcut** — instead of copying by hand, ask the agent you used in Part 1 to pull it from the workspace:

> create a local script on my laptop named claude-launch.sh and copy over the content of part2-connect-clients-workspace/claude-launch.sh from the workspace llm-post-training-serving

Then exit the agent and relaunch it with `bash claude-launch.sh`. (For Codex, swap in `codex-launch.sh`.)

It asks for your workspace's console URL on launch — copy it from your browser's address bar while viewing
the workspace (set `WORKSPACE_URL=…` to skip the prompt). Launch Claude Code first; Codex reuses the same
tunnel, so it won't ask again. The first turn is slow (reasoning model cold
start), not a hang.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "tunnel exited early" | The workspace isn't RUNNING, or your `anyscale login` points at a different console than the URL. |
| "still not reachable after 60s" | The serve app isn't up — see [Part 1](../part1-deploy-naive/README.md). |
| Brave tools don't appear | Install Node.js (the MCP runs via `npx`). |

Back: [Part 1](../part1-deploy-naive/README.md)
