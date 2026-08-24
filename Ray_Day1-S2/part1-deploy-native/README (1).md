# Part 1 — Deploy `qwen3.6-27b` in your workspace

Your coding agent writes the Ray Serve LLM app and deploys it with `serve run`, right here in your
workspace. This is the naive baseline — 4× L4, single replica, no optimization — enough to get a working
endpoint for Part 2. (Part 3 has the optimized version.)

## Deploy

The workspace already has the right image and env vars. Just:

1. Install the Anyscale agent skills (this provides `/anyscale-workload-llm-serving`), picking the
   platform you'll use — **Claude Code** or **Codex**, since Part 2 needs one of those:

   ```bash
   anyscale skills install
   ```

2. Run the prompt in [`PROMPT.md`](PROMPT.md) with your agent. It writes `serve_qwen3_6_27b_naive.py` and
   deploys it:

   ```bash
   serve run serve_qwen3_6_27b_naive:app     # serves at http://localhost:8000
   ```

   Leave it running — Part 2 connects to this endpoint.

3. **Stuck?** If the generated app won't deploy, run the doctor — it restores a known-good app, clears
   any running deployment, and serves it:

   ```bash
   bash .doctor.sh
   ```

## Verify

```bash
# second terminal — client.py defaults to http://localhost:8000, no token:
python client.py
```

The first call cold-starts for ~2–3 min (weight download + compile), then it's warm.

→ Next: **[Part 2 — connect Claude Code / Codex](../part2-connect-clients-workspace/README.md)**
