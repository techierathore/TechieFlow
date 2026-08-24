#!/usr/bin/env python3
"""Emit authoritative Codex exec JSONL usage into TechieFlow sessions telemetry."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tf-codex-telemetry.py <project-root> <codex-jsonl>", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    source = pathlib.Path(sys.argv[2])
    thread_id = None
    model = None
    totals = {"input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
              "reasoning_output_tokens": 0}
    try:
        for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                event = json.loads(line)
            except Exception:
                continue
            if event.get("type") == "thread.started":
                thread_id = event.get("thread_id") or thread_id
            if event.get("model"):
                model = event.get("model")
            if event.get("type") == "turn.completed" and isinstance(event.get("usage"), dict):
                usage = event["usage"]
                totals["input_tokens"] += int(usage.get("input_tokens") or 0)
                totals["output_tokens"] += int(usage.get("output_tokens") or 0)
                totals["cache_read_tokens"] += int(usage.get("cached_input_tokens") or 0)
                totals["reasoning_output_tokens"] += int(usage.get("reasoning_output_tokens") or 0)
    except Exception:
        return 0
    if not thread_id or not any(totals.values()):
        return 0
    record = {
        "kind": "session", "session_id": thread_id, "model": model,
        "duration_s": None, **totals, "cache_creation_tokens": None,
        "cost_usd": None, "children_sessions": None,
    }
    emit = root / ".tfcore" / "utils" / "tf-emit.sh"
    env = os.environ.copy()
    env.update(TF_HARNESS="codex", TF_PROJECT_DIR=str(root), CLAUDE_PROJECT_DIR=str(root))
    try:
        subprocess.run(["bash", str(emit), "sessions"], input=json.dumps(record), text=True,
                       timeout=10, env=env, check=False)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
