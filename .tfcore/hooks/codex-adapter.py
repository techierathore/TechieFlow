#!/usr/bin/env python3
"""Translate Codex hooks to TechieFlow's existing guard and telemetry contracts."""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone


def read_event() -> dict:
    try:
        value = json.load(sys.stdin)
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def project_root(event: dict) -> pathlib.Path:
    start = pathlib.Path(str(event.get("cwd") or os.getcwd())).resolve()
    for candidate in (start, *start.parents):
        if (candidate / ".tfcore").is_dir():
            return candidate
    return start


def environment(root: pathlib.Path, event: dict) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        TF_HARNESS="codex",
        TF_PROJECT_DIR=str(root),
        CLAUDE_PROJECT_DIR=str(root),
        TF_SESSION_ID=str(event.get("session_id") or ""),
    )
    if (root / ".tfcore" / ".session" / "yolo.json").exists():
        env["TF_YOLO"] = "1"
    return env


def deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


def run_guard(root: pathlib.Path, event: dict, script: str, payload: dict) -> str | None:
    path = root / ".tfcore" / "hooks" / script
    if not path.exists():
        return None
    try:
        result = subprocess.run(
            ["bash", str(path)], input=json.dumps(payload), text=True,
            capture_output=True, timeout=10, env=environment(root, event), check=False,
        )
    except Exception as exc:
        # Policy checks fail closed. Telemetry is handled separately and fails open.
        return f"TechieFlow could not execute {script}: {exc}"
    if result.returncode == 2:
        return result.stderr.strip() or f"Blocked by TechieFlow guard {script}"
    if result.returncode not in (0,):
        return f"TechieFlow guard {script} failed unexpectedly (exit {result.returncode})."
    return None


def pre_tool(event: dict) -> None:
    root = project_root(event)
    tool = str(event.get("tool_name") or "")
    raw = event.get("tool_input")
    args = raw if isinstance(raw, dict) else {}
    scripts: list[str] = []
    if tool == "Bash":
        payload = {"tool_name": "Bash", "tool_input": {"command": str(args.get("command") or "")}}
        scripts = ["block-git.sh"]
    elif tool == "apply_patch":
        patch = str(args.get("command") or args.get("patch") or "")
        # Run the existing guards once per file using actual paths and separated
        # added/removed lines. This avoids treating context or removed Verified
        # cells as newly introduced content.
        headers = list(re.finditer(r"(?m)^\*\*\* (?:Update|Add) File: (.+)$", patch))
        for index, header in enumerate(headers):
            end = headers[index + 1].start() if index + 1 < len(headers) else len(patch)
            section = patch[header.end():end]
            added = []
            removed = []
            for line in section.splitlines():
                if line.startswith("+") and not line.startswith("+++"):
                    added.append(line[1:])
                elif line.startswith("-") and not line.startswith("---"):
                    removed.append(line[1:])
            payload = {
                "hook_event_name": "PreToolUse", "cwd": str(root),
                "session_id": event.get("session_id"), "tool_name": "Edit",
                "tool_input": {"file_path": header.group(1).strip(),
                               "old_string": "\n".join(removed),
                               "new_string": "\n".join(added)},
            }
            for script in ("guard-status.sh", "guard-verify.sh"):
                reason = run_guard(root, event, script, payload)
                if reason:
                    deny(reason)
                    return
        return
    elif tool in ("Edit", "Write"):
        payload = {"tool_name": tool, "tool_input": args}
        scripts = ["guard-status.sh", "guard-verify.sh"]
    else:
        return
    payload.update(hook_event_name="PreToolUse", cwd=str(root), session_id=event.get("session_id"))
    for script in scripts:
        reason = run_guard(root, event, script, payload)
        if reason:
            deny(reason)
            return


def write_pointer(root: pathlib.Path, event: dict) -> None:
    session_id = str(event.get("session_id") or "")
    if not session_id:
        return
    target = root / ".tfcore" / ".session" / "codex.json"
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps({
            "session_id": session_id,
            "transcript_path": event.get("transcript_path"),
            "model": event.get("model"),
            "ts": datetime.now(timezone.utc).isoformat(),
        }) + "\n", encoding="utf-8")
    except Exception:
        pass


def session_end(root: pathlib.Path, event: dict) -> None:
    # Transcript format is explicitly not a stable Codex hook interface. Record
    # honest session metadata; codex exec --json telemetry is enriched separately.
    emit = root / ".tfcore" / "utils" / "tf-emit.sh"
    if not emit.exists() or not event.get("session_id"):
        return
    record = {
        "kind": "session",
        "session_id": event.get("session_id"),
        "model": event.get("model"),
        "duration_s": None,
        "input_tokens": None,
        "output_tokens": None,
        "cache_read_tokens": None,
        "cache_creation_tokens": None,
        "cost_usd": None,
        "children_sessions": None,
        "harness": "codex",
    }
    try:
        subprocess.run(["bash", str(emit), "sessions"], input=json.dumps(record), text=True,
                       capture_output=True, timeout=2, env=environment(root, event), check=False)
    except Exception:
        pass


def main() -> int:
    event = read_event()
    root = project_root(event)
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "pre-tool":
        pre_tool(event)
    elif mode == "session-start":
        write_pointer(root, event)
    elif mode == "session-end":
        write_pointer(root, event)
        session_end(root, event)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
