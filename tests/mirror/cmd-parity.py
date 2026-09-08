#!/usr/bin/env python3
"""tests/mirror/cmd-parity.py — every command a persona offers must exist in BOTH harnesses (FR-68).

    python3 tests/mirror/cmd-parity.py

WHY THIS EXISTS. The framework's first rule is that Claude Code and OpenCode behave the
same. The mirror check enforces that for TASK FILES — but a persona can offer a command
that has no task file of its own, and seven did: four on the architect and three on the
analyst, all routing through `create-doc` with a YAML template. They appeared in Claude
Code's command list and in no OpenCode registration, unnoticed through the whole reset,
because nothing ever read the persona command list (MISS-TechieFlow-20260908-06).

HOW A COMMAND RESOLVES. Claude Code reads the persona, so listing it there is enough.
OpenCode has no alias mechanism: it addresses a task by its own registered name. So a
command resolves there only when `techieflow:tasks:<command>` exists in opencode.jsonc.

That strictness is the point. An earlier, looser version of this check accepted any task
the command's line happened to mention — and would have passed all six removed commands,
because each said "use task create-doc", and create-doc is registered. The defect was
never a missing task; it was a command NAME that existed in one harness only.

Built-ins are exempt: they run no task and produce no file (see BUILTIN).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

# Persona behaviour, not commands: each runs no task and writes no file, so there is
# nothing for OpenCode to register. `report` prints checklist rows the persona has
# already read; `doc-out` flushes the document in progress.
BUILTIN = {"help", "exit", "doc-out", "yolo", "report"}
CMD = re.compile(r"^\s{2}-\s([a-z][a-z0-9-]{2,})(?:\s*\{[^}]*\})?\s*:\s*(.*)$")
# The flow-master and the verifier list their commands as a markdown table instead of a
# YAML block: | `*build-phase {App}` | what it does | `build-phase.md` |
ROW = re.compile(r"^\|\s*`\*([a-z][a-z0-9-]{2,})[^`]*`\s*\|(.*)$")
TASK_IN_LINE = re.compile(r"\b([a-z][a-z0-9-]{2,})\.md\b")
RUNS_TASK = re.compile(r"(?:run|runs|execute|use)\s+task\s+([a-z][a-z0-9-]{2,})", re.I)


def personas():
    d = os.path.join(ROOT, ".tfcore", "agents")
    for name in sorted(os.listdir(d)):
        if name.endswith(".md"):
            with open(os.path.join(d, name), encoding="utf-8", errors="replace") as fh:
                yield name[:-3], fh.read()


def commands(body):
    """(command, its description line) for everything under `commands:`."""
    out = []
    inside = False
    for line in body.splitlines():
        if re.match(r"^commands:\s*$", line):
            inside = True
            continue
        if inside and re.match(r"^\S", line):
            break
        if inside:
            m = CMD.match(line)
            if m:
                out.append((m.group(1), m.group(2)))
    for line in body.splitlines():
        m = ROW.match(line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out


def main():
    oc_path = os.path.join(ROOT, "opencode.jsonc")
    oc = open(oc_path, encoding="utf-8", errors="replace").read()
    tasks_dir = os.path.join(ROOT, ".tfcore", "tasks")
    have_task = {f[:-3] for f in os.listdir(tasks_dir) if f.endswith(".md") and not f.startswith("_")}

    bad, checked = [], 0
    for persona, body in personas():
        for cmd, desc in commands(body):
            if cmd in BUILTIN:
                continue
            checked += 1
            named = set(TASK_IN_LINE.findall(desc)) | set(RUNS_TASK.findall(desc))
            named = {t for t in named if t in have_task}
            if f'"techieflow:tasks:{cmd}"' not in oc:
                via = f" (it runs {', '.join(sorted(named))}, but OpenCode cannot alias)" if named else ""
                bad.append(f"*{cmd} (on {persona}) has no \"techieflow:tasks:{cmd}\" entry in opencode.jsonc{via}")
            for t in named:
                if not os.path.exists(os.path.join(tasks_dir, t + ".md")):
                    bad.append(f"*{cmd} (on {persona}) names task {t}.md, which is not there")

    if bad:
        for b in bad:
            print("FAIL " + b, file=sys.stderr)
        print(f"FAIL {len(bad)} command(s) do not resolve in both harnesses. Register the command in "
              f"opencode.jsonc, or remove it from the persona.", file=sys.stderr)
        return 1
    print(f"ok   all {checked} persona command(s) resolve in both harnesses")
    return 0


if __name__ == "__main__":
    sys.exit(main())
