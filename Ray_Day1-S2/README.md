# Ray Summit 2026 — Self-Host a Coding-Agent LLM (Training)

Hands-on: deploy `qwen3.6-27b` in your own Anyscale workspace, then drive it from **Claude Code** and
**Codex** running on your laptop.

`qwen3.6-27b` is a 27B FP8 hybrid-reasoning, tool-calling model that
[Qwen positions as comparable to Claude Opus 4.5](https://qwen.ai/blog?id=qwen3.6-27b). With **direct
streaming** enabled, one Ray Serve LLM deployment exposes the native APIs each agent expects — no proxy.

## Session flow

| Step | What you do | Where it runs | Folder |
|---|---|---|---|
| 1 | Your agent writes the Ray Serve app from a prompt, then `serve run` deploys it | in your **workspace** | [`part1-deploy-naive/`](./part1-deploy-naive/) |
| 2 | Connect Claude Code and Codex to it over an SSH tunnel | on your **laptop** | [`part2-connect-clients-workspace/`](./part2-connect-clients-workspace/) |

[`part3-optimize/`](./part3-optimize/) is **reference only** — the optimized single-GPU deployment. We don't
run it in the session; browse it if you're curious.

## What's already set up

- **Your workspace** (Part 1): the required image, the two direct-streaming env vars, your coding agent and
  the `/anyscale-workload-llm-serving` skill, and this repo — all pre-provisioned. One workspace per person.
- **Your laptop** (Part 2): you'll need the Anyscale CLI (`anyscale login`) and Claude Code and/or Codex —
  the Brave web-search key is baked into the launchers. See [Part 2](./part2-connect-clients-workspace/README.md).

## Direct streaming

Direct streaming lets one deployment expose each agent's native API path, no separate proxy:

| Path | Used by |
|---|---|
| `POST /v1/messages` | Claude Code |
| `POST /v1/responses` | Codex |
| `POST /v1/chat/completions` | Cursor |

It's enabled by two cluster-level env vars (`RAY_SERVE_ENABLE_HA_PROXY=1`,
`RAY_SERVE_LLM_ENABLE_DIRECT_STREAMING=1`), already set on your workspace. Part 1 explains the details.

## After the session

The full public version of this material — the Anyscale **Service** deploy path, **Cursor**, the Part 3
optimization prompt, and the cost analysis — lives at
**[anyscale/llm-serving-for-coding-agents](https://github.com/anyscale/llm-serving-for-coding-agents)**.
Clone it and play.
