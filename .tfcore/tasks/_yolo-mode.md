# _yolo-mode (shared rule — YOLO / goal mode: run unattended to completion)

YOLO means all permissions and all access are granted: run one command to completion and never stop to check in. It never crosses an owner review into the next phase; `*day1-greenfield` runs one stage, and stage 2 needs `--stage2`. `*build-phase` and `*verify` are in YOLO by default; every other command honours it when it is on.

## When it is on

| Trigger | What you do first |
|---|---|
| `*yolo` typed, or `YOLO` / `yolo` anywhere in the prompt | `bash .tfcore/utils/tf-yolo.sh on --source yolo` |
| The session was started by `tf-goal.sh`, or a `/goal` is active | the supervisor sets it; for a hand-typed `/goal`, `bash .tfcore/utils/tf-yolo.sh on --source goal` |
| The harness is in a no-prompt mode (`bypassPermissions`, `opencode run --auto`) | `bash .tfcore/utils/tf-yolo.sh on`, so the rules below apply |

`tf-yolo.sh off`, `tf-yolo.sh done`, or a flag older than 24 hours ends it. `tf-yolo.sh status` says which.

## What changes

- Deletes and `sudo` run without a prompt. Read-only git is allowed. Git writes stay refused in every mode; the owner commits.
- No question, confirmation or pause: take the documented default and record it in the checklist Remarks. The one question that survives is a new test user (`_smoke-test-policy.md`): use a documented account; if none exists, create one named `{App}-yolo-tester`, record it in the UsageGuide, and continue.
- Never end a turn with a question, a plan or "shall I". End only when the command is complete or everything left is owner-only.
- A failed build, a dead port, a stopped service: fix it and continue. A `429` from a sub-agent or an API: wait 60 seconds, retry once, then route around it.
- Nothing is relaxed: the status gate, the smoke policy, the guard hooks, and `Verified` only from an executed verify.

## The sentinel

When the goal is met, after the status gate and the run record, exactly once:

```bash
bash .tfcore/utils/tf-yolo.sh done complete "<one line>"
```

When every remaining row needs the owner (credentials, a device, a paid account, a product decision), everything else is finished, and each blocker is listed under PROJECT-STATUS "Known blockers":

```bash
bash .tfcore/utils/tf-yolo.sh done blocked "<what the owner must do>"
```

A `blocked` written because the work was long or the context was full is the failure this rule exists to stop; the supervisor re-prompts and the log shows it. Without a supervisor the sentinel still turns YOLO off.

Usage limits are handled outside the session by `tf-goal.sh`, which waits and resumes the same session; on resume, re-read PROJECT-STATUS and the checklist and continue from the weakest open row. How the owner starts an unattended run: `docs/TechieFlow-How-It-Works.md` §3.10.
