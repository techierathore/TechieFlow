---
name: techieflow-day1-greenfield
description: Initialize planning artifacts and mockups for a new application. Use when a TechieFlow project needs its `day1-greenfield` workflow.
---

# techieflow-day1-greenfield

1. Read `.tfcore/tasks/day1-greenfield.md` completely and follow it as the canonical executable workflow.
2. Read `.tfcore/core-config.yaml` and only the task dependencies required for this run.
3. Operate as the `analyst` role. Delegate only where the task explicitly calls for independent subagents, using the registered Codex roles and waiting for their results.
4. Preserve interactive elicitation unless `.tfcore/.session/yolo.json` exists or the user explicitly requested YOLO/goal mode.
5. Never run `git` or `gh`. Run required builds, smoke tests, runtime observations, verifier gates, document updates, and telemetry yourself.
6. Treat old `*...` and harness slash-command text in the canonical task as vocabulary aliases; execute the named task or delegate to the named Codex role directly.
