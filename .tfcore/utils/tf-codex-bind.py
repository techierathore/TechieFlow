#!/usr/bin/env python3
"""Generate TechieFlow's Codex agents and thin workflow skills."""

from __future__ import annotations

import argparse
import pathlib
import re


PHASES = {
    "day1-brownfield": ("analyst", "Reverse-document and initialize an existing application."),
    "day1-greenfield": ("analyst", "Initialize planning artifacts and mockups for a new application."),
    "amend-docs": ("analyst", "Amend existing requirements and design artifacts in place."),
    "author-brd": ("analyst", "Interactively author or extend numbered business requirements."),
    "mockups": ("analyst", "Create or update the greenfield UI design and HTML mockups."),
    "split-brd": ("analyst", "Convert a BRD into the single implementation checklist."),
    "build-phase": ("flow_master", "Implement the open checklist and chain smoke and verification."),
    "verify-phase": ("verifier", "Independently verify requirements against runtime evidence."),
    "fix-issues": ("flow_master", "Fix reported or verifier-discovered application defects."),
    "triage-issues": ("flow_master", "Analyze and document human-found bugs without fixing source."),
    "devguide": ("flow_master", "Create the developer-facing screen and component guide."),
    "productguide": ("flow_master", "Create the user-facing guide from the running application."),
    "handoff-phase": ("flow_master", "Complete handoff documents, status, and rendered artifacts."),
    "refresh-status": ("flow_master", "Recover truthful project status after an interrupted run."),
    "generate-html": ("flow_master", "Render an arbitrary human-readable Markdown document to HTML."),
    "render-workflow-docs": ("flow_master", "Render the canonical BRD, Architecture, and status HTML files."),
    "metrics-report": ("flow_master", "Report TechieFlow development telemetry without changing code."),
}

PERSONAS = {
    "flow-master": "flow-master.md",
    "analyst": "analyst.md",
    "architect": "architect.md",
    "verifier": "verifier.md",
}

WORKERS = {
    "tf-builder": """Implement one assigned FN/NFR requirement cluster. Read `.tfcore/tasks/_smoke-test-policy.md`. Never run git or gh. Follow project coding standards, smoke the changed behavior, update only the assigned checklist rows, and return structured evidence to the parent.""",
    "tf-test-writer": """Write black-box verification tests for one assigned requirement cluster. Never edit application source and never run git or gh. Follow `.tfcore/tasks/verify-phase.md` and return tests added, tests refreshed, and anything unobservable.""",
    "tf-explorer": """Perform a focused read-only codebase scan. Never edit files and never run git or gh. Return concise evidence with file paths and symbols.""",
    "trblazeui": """Read the NuGet-deployed TrBlazeUI persona and adopt its implementation rules. Resolve it in this order and use the FIRST that exists: `.claude/commands/trblazeui.md` (current deploy target), `.claude/trblazeui.md` (legacy deploy target), `.opencode/command/trblazeui.md`, `.trblazeui/TrBlazeUI-AI-Reference.md` (packaged component reference). Only if NONE exists, report that the TrBlazeUI persona is not deployed (`dotnet build` the app to unpack the package) and stop. Never run git or gh.""",
    "techierag": """Read the NuGet-deployed TechieRag persona and adopt its implementation rules. Resolve it in this order and use the FIRST that exists: `.claude/commands/techierag.md` (current deploy target), `.claude/techierag.md` (legacy deploy target), `.opencode/command/techierag.md`, `.techierag/TechieRag-AI-Reference.md` (packaged service reference). Only if NONE exists, report that the TechieRag persona is not deployed (`dotnet build` the app to unpack the package) and stop. Never run git or gh.""",
}


def routing(path: pathlib.Path) -> dict:
    cfg = {"enabled": False, "tiers": {}, "phases": {}, "subagents": {}, "effort": {}}
    section = tier = None
    if not path.exists():
        return cfg
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            key, _, value = line.partition(":")
            section, tier = key.strip(), None
            if section == "enabled":
                cfg["enabled"] = value.strip() == "true"
        elif section == "tiers":
            if re.match(r"^  [a-z-]+:\s*$", line):
                tier = line.strip()[:-1]
                cfg["tiers"][tier] = {}
            elif tier and line.startswith("    "):
                key, _, value = line.strip().partition(":")
                cfg["tiers"][tier][key] = value.strip()
        elif section in ("phases", "subagents", "effort"):
            key, _, value = line.strip().partition(":")
            cfg[section][key] = value.strip()
    return cfg


def quoted(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def write(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8", newline="\n")


def persona_instructions(root: pathlib.Path, source_name: str) -> str:
    source = root / ".tfcore" / "agents" / source_name
    return f"""Read `{source.relative_to(root)}` completely before acting and follow its persona, core principles, command routing, and dependency rules. Skip only its activation greeting/help/halt ritual because this is a spawned Codex role. Treat `.tfcore/tasks/*.md` as executable workflows. Never run git or gh. Preserve TechieFlow's smoke, verifier, artifact-location, local-only runtime, checklist, and PROJECT-STATUS invariants. Load only dependencies needed for the assigned task."""


def agent_file(name: str, description: str, instructions: str, model: str | None,
               effort: str | None, read_only: bool = False) -> str:
    lines = [f"name = {quoted(name)}", f"description = {quoted(description)}",
             f"developer_instructions = {quoted(instructions)}"]
    if model:
        lines.append(f"model = {quoted(model)}")
    if effort:
        lines.append(f"model_reasoning_effort = {quoted(effort)}")
    if read_only:
        lines.append('sandbox_mode = "read-only"')
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    if not (root / ".tfcore").is_dir():
        parser.error(f"not a TechieFlow repository: {root}")
    cfg = routing(root / ".tfcore" / "routing.yaml")

    persona_tier = {"flow-master": "build-phase", "analyst": "day1-greenfield",
                    "architect": "day1-greenfield", "verifier": "verify-phase"}
    for name, source in PERSONAS.items():
        tier = cfg["phases"].get(persona_tier[name], "inherit")
        model = cfg["tiers"].get(tier, {}).get("codex") if cfg["enabled"] and tier != "inherit" else None
        effort = cfg["effort"].get(tier) if model else None
        write(root / ".codex" / "agents" / f"{name}.toml", agent_file(
            name.replace("-", "_"), f"TechieFlow {name} specialist.",
            persona_instructions(root, source), model, effort))

    for name, instructions in WORKERS.items():
        tier = cfg["subagents"].get(name, "inherit")
        model = cfg["tiers"].get(tier, {}).get("codex") if cfg["enabled"] and tier != "inherit" else None
        effort = cfg["effort"].get(tier) if model else None
        write(root / ".codex" / "agents" / f"{name}.toml", agent_file(
            name.replace("-", "_"), f"TechieFlow {name} role.", instructions,
            model, effort, read_only=name == "tf-explorer"))

    for phase, (owner, description) in PHASES.items():
        skill_name = f"techieflow-{phase.removesuffix('-phase')}"
        task = f".tfcore/tasks/{phase}.md"
        body = f"""---
name: {skill_name}
description: {description} Use when a TechieFlow project needs its `{phase}` workflow.
---

# {skill_name}

1. Read `{task}` completely and follow it as the canonical executable workflow.
2. Read `.tfcore/core-config.yaml` and only the task dependencies required for this run.
3. Operate as the `{owner}` role. Delegate only where the task explicitly calls for independent subagents, using the registered Codex roles and waiting for their results.
4. Preserve interactive elicitation unless `.tfcore/.session/yolo.json` exists or the user explicitly requested YOLO/goal mode.
5. Never run `git` or `gh`. Run required builds, smoke tests, runtime observations, verifier gates, document updates, and telemetry yourself.
6. Treat old `*...` and harness slash-command text in the canonical task as vocabulary aliases; execute the named task or delegate to the named Codex role directly.
"""
        write(root / ".agents" / "skills" / skill_name / "SKILL.md", body)

    yolo = """---
name: techieflow-yolo
description: Enable, disable, or inspect TechieFlow YOLO mode for an explicitly requested unattended workflow.
---

Read `.tfcore/tasks/_yolo-mode.md` completely. Run `bash .tfcore/utils/tf-yolo.sh on|off` as requested. YOLO removes elicitation pauses but does not broaden the user's task, allow git/gh, bypass the Codex workspace sandbox, or waive genuine external blockers. For a supervised long-running goal, use `.tfcore/utils/tf-goal.sh --harness codex`.
"""
    write(root / ".agents" / "skills" / "techieflow-yolo" / "SKILL.md", yolo)
    print(f"tf-codex-bind: generated {len(PERSONAS) + len(WORKERS)} agents and {len(PHASES) + 1} skills")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
