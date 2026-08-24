---
name: techieflow-refresh-status
description: Recover truthful project status after an interrupted run. Use when a TechieFlow project needs its `refresh-status` workflow.
---

# techieflow-refresh-status

1. Read `.tfcore/tasks/refresh-status.md` completely and follow it as the canonical executable workflow.
2. Read `.tfcore/core-config.yaml` and only the task dependencies required for this run.
3. Operate as the `flow_master` role. Delegate only where the task explicitly calls for independent subagents, using the registered Codex roles and waiting for their results.
4. Preserve interactive elicitation unless `.tfcore/.session/yolo.json` exists or the user explicitly requested YOLO/goal mode.
5. Never run `git` or `gh`. Run required builds, smoke tests, runtime observations, verifier gates, document updates, and telemetry yourself.
6. Treat old `*...` and harness slash-command text in the canonical task as vocabulary aliases; execute the named task or delegate to the named Codex role directly.
