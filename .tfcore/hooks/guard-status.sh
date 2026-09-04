#!/usr/bin/env bash
# TechieFlow PreToolUse hook — blocks convoluted PROJECT-STATUS.md writes.
#
# PROJECT-STATUS is a CRISP, FIXED-SHAPE snapshot agents OVERWRITE — never an
# append-log. See .tfcore/tasks/_status-update-gate.md §"CRISP, FIXED-SHAPE
# snapshot" and .tfcore/templates/v4custom/app-project-status-tmpl.md. The prose
# rule alone kept failing (AstroLyfe's 286-line mess, repeat offenses after);
# this hook makes the shape MECHANICAL, the same way block-git.sh made the git
# ban mechanical.
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Write|Edit|MultiEdit"
# AND matcher "Bash"); OpenCode via .opencode/plugin/techieflow.js.
# Exit 2 + stderr = block the call and feed the message back to the agent.
#
# What it blocks (only for files named PROJECT-STATUS.md):
#   - Any H2 heading outside the template's fixed section set (per-run dated
#     H2s like "## *verify all — coverage matrix (DATE)" are the disease).
#   - Headings that name a command run (*verify / *build-phase / *fix-issues).
#   - A paragraph stuffed into `current_phase:` (must be ONE short line).
#   - A full-file Write longer than 120 lines (template shape is ~60).
#   - (Bash) any shell command that WRITES the file — redirection, tee, cp, mv,
#     sed -i, a Python/Node one-liner — because a shell write is invisible to the
#     Write/Edit checks above (reset Session 3, 2026-09-04). Reading it is fine.
# Content rules (section word limits, the two command blocks, the five-row log)
# are checked by .tfcore/utils/tf-doc-check.sh at the status gate.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

# stdin feeds python the SCRIPT (heredoc), so the payload travels via env var.
TF_HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

ti = data.get("tool_input") or {}

# --- Bash branch: refuse shell writes to PROJECT-STATUS.md -------------------
cmd = ti.get("command")
if isinstance(cmd, str):
    if re.search(r"PROJECT-STATUS\.md", cmd, re.I) and re.search(
        r"(>>?\s*[\"']?[^\s|;&]*PROJECT-STATUS\.md)"      # > / >> redirection
        r"|(\btee\b[^|;&]*PROJECT-STATUS\.md)"            # tee
        r"|(\b(cp|mv|install)\b[^|;&]*PROJECT-STATUS\.md)"  # copy / move onto it
        r"|(\b(sed|perl)\b[^|;&]*\s-[a-zA-Z]*i[a-zA-Z]*\b[^|;&]*PROJECT-STATUS\.md)"  # in-place edit
        r"|(\b(python3?|node)\b[^|;&]*PROJECT-STATUS\.md)"  # a one-liner that opens it
        r"|(\b(truncate|dd)\b[^|;&]*PROJECT-STATUS\.md)",
        cmd, re.I,
    ):
        print(
            "BLOCKED by TechieFlow policy: PROJECT-STATUS.md is written ONLY through "
            "the harness Write/Edit tool, never through the shell (redirection, tee, "
            "cp, mv, sed -i, a script). The shell path bypasses the shape guard, which "
            "is how status files got spoiled. Write the file with the Write tool in the "
            "template shape (.tfcore/templates/v4custom/app-project-status-tmpl.md), "
            "then run: bash .tfcore/utils/tf-doc-check.sh PROJECT-STATUS.md",
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(0)

path = (ti.get("file_path") or "").replace("\\", "/")
if path.rsplit("/", 1)[-1].lower() != "project-status.md":
    sys.exit(0)

# Write carries the whole file in `content`; Edit/MultiEdit carry fragments.
pieces = []
is_full_write = False
if isinstance(ti.get("content"), str):
    pieces.append(ti["content"])
    is_full_write = True
if isinstance(ti.get("new_string"), str):
    pieces.append(ti["new_string"])
for e in ti.get("edits") or []:
    if isinstance(e, dict) and isinstance(e.get("new_string"), str):
        pieces.append(e["new_string"])
new = "\n".join(pieces)
if not new:
    sys.exit(0)

ALLOWED = {
    "where i am",
    "next command to run",
    "open requirements",
    "known blockers",
    "verification log",
    "library feedback summary",
    "standards compliance",
    "deferred / future",
    "recovery note",  # written by *refresh-status, may carry a date
}

errors = []

for m in re.finditer(r"(?m)^##\s+(.+)$", new):
    heading = m.group(1).strip()
    h = heading.rstrip(":").lower()
    base = re.sub(r"\s*[—\-(].*$", "", h).strip()  # drop trailing dates/qualifiers
    if h in ALLOWED or base in ALLOWED:
        continue
    errors.append(
        f'H2 "## {heading}" is not a template section. PROJECT-STATUS has EXACTLY '
        "the fixed sections of app-project-status-tmpl.md — a run NEVER adds a new "
        "H2; it overwrites the existing sections + adds ONE Verification-log row."
    )

if re.search(r"(?m)^#{2,}\s.*\*(verify|build-phase|fix-issues|refresh-status)", new):
    errors.append(
        "A heading naming a command run (*verify / *build-phase / *fix-issues) is "
        "per-run narrative. Record the run as ONE Verification-log table row; "
        "per-REQ detail goes in the checklist Remarks cells."
    )

m = re.search(r"(?m)^current_phase:\s*(.+)$", new)
if m and len(m.group(1).strip()) > 120:
    errors.append(
        "current_phase must be ONE short line (phase name + at most a half-line "
        "qualifier), never a paragraph of run detail."
    )

if is_full_write:
    n_lines = new.count("\n") + 1
    if n_lines > 120:
        errors.append(
            f"This write is {n_lines} lines. PROJECT-STATUS is a one-page snapshot "
            "(~60 lines, hard cap 120). TRIM to the template shape — blow-by-blow "
            "history lives in the checklist Remarks and .verify/ artifacts, never here."
        )

if errors:
    print(
        "BLOCKED by TechieFlow policy: PROJECT-STATUS is a CRISP, FIXED-SHAPE "
        "snapshot you OVERWRITE in place — never append to, never restructure "
        "(.tfcore/tasks/_status-update-gate.md).",
        file=sys.stderr,
    )
    for e in errors:
        print(" - " + e, file=sys.stderr)
    print(
        "Fix and retry: keep ONLY the template sections (Where I am / Next command "
        "to run / Open requirements / Known blockers / Verification log / Library "
        "feedback summary / Standards compliance / Deferred / future), overwrite "
        "their content in place, add ONE Verification-log row for this run, and put "
        "the detail in docs/<APP>-Checklist.md Remarks. Do NOT pad, do NOT narrate.",
        file=sys.stderr,
    )
    sys.exit(2)

sys.exit(0)
PY
exit $?
