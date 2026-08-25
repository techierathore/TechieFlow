#!/usr/bin/env bash
# TechieFlow PreToolUse hook — blocks repo-root run-artifact directories.
#
# verify-phase.md §1 ARTIFACT-LOCATION RULE: everything a run generates that is
# not a deliverable lands under tests/.artifacts/. Repo-root siblings —
# test-results-<slug>/, scripts-<slug>/ — are BANNED: a suffixed name escapes the
# ignore pattern written for the unsuffixed one, and nothing ever cleans them up.
#
# The prose rule has now failed THREE times: fourteen test-results-* dirs in one
# app, then four scripts-cluster-* dirs in the next fan-out after those were
# banned, then ten test-results-* dirs in TechieBlog (2026-08-23..25, swept
# 2026-08-25). Every one came from an agent passing `--output test-results-<slug>`
# and overriding the config's pinned outputDir. This hook makes the rule
# MECHANICAL, the same way block-git.sh made the git ban mechanical.
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Bash"); Codex via
# .tfcore/hooks/codex-adapter.py pre-tool; OpenCode via .opencode/plugin/techieflow.js.
# Exit 2 + stderr = block the call and feed the message back to the agent.
#
# What it blocks:
#   - --output / --output-dir pointed at a root-level test-results* or scripts-*
#     (bare -o is deliberately NOT matched — see the comment in the Python body)
#   - mkdir of a root-level test-results* or scripts-* directory
# What it deliberately ALLOWS:
#   - --output tests/.artifacts/<slug>        (the sanctioned isolation form)
#   - anything under tests/, and the project's own tracked scripts/ (no hyphen)
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

ti = data.get("tool_input") or {}
cmd = ti.get("command")
if not isinstance(cmd, str) or not cmd.strip():
    sys.exit(0)

errors = []

# A root-relative artifact path: optional ./ then test-results… or scripts-…
# `tests/…` never matches (the 's' in "tests" is followed by '/'), and the
# project's own `scripts/` never matches (requires the hyphen).
ROOT_ARTIFACT = r"(?:\./)?(test-results[\w.-]*|scripts-[\w.-]+)/?"

# Long form ONLY. A bare `-o` is deliberately NOT matched: Playwright has no -o
# shorthand for --output, while `grep -o 'test-results-…'` and `curl -o` are
# legitimate and would false-positive. Cheap specificity beats a clever pattern.
for m in re.finditer(
    r"--output(?:-dir)?[=\s]+(['\"]?)" + ROOT_ARTIFACT,
    cmd,
):
    errors.append(
        f'--output points at repo-root "{m.group(2)}". The single artifact '
        "destination is playwright.config.ts's pinned outputDir "
        "(tests/.artifacts/test-results), which Playwright namespaces per test "
        "AND wipes at the start of every run — that is what keeps the tree from "
        "growing. If a parallel fan-out genuinely needs isolation, the ONLY "
        "permitted override is a subfolder: --output tests/.artifacts/<slug>."
    )

for m in re.finditer(
    r"(?<!\w)mkdir(?:\s+-[\w-]+)*\s+(['\"]?)" + ROOT_ARTIFACT,
    cmd,
):
    errors.append(
        f'mkdir would create repo-root "{m.group(2)}". Run material — tool output '
        "AND the throwaway scripts you write to drive it — lives under "
        "tests/.artifacts/ (harness scripts: tests/.artifacts/harness/<name>.mjs). "
        "Never a root-level <name>-<slug>/ per run or per cluster."
    )

if errors:
    print(
        "BLOCKED by TechieFlow policy: no repo-root run-artifact directory "
        "(verify-phase.md §1 ARTIFACT-LOCATION RULE).",
        file=sys.stderr,
    )
    for e in dict.fromkeys(errors):
        print(" - " + e, file=sys.stderr)
    print(
        "Do NOT reason by the letter of this list: any NEW root-level "
        "<name>-<slug>/ you are about to create for a fan-out is the same defect, "
        "whatever the noun. Re-run writing under tests/.artifacts/ instead. "
        "Note: a script that imports the Playwright LIBRARY does not load "
        "playwright.config.ts at all — it must place its own captures under "
        "tests/.artifacts/ explicitly, resolved relative to the repo root, never "
        "an absolute path.",
        file=sys.stderr,
    )
    sys.exit(2)

sys.exit(0)
PY
exit $?
