# _yolo-mode (shared rule — YOLO / goal mode: run unattended to completion)

## What YOLO means (owner rule 2026-08-21)

**YOLO = "I have given you all the permissions and all the access. Run until the goal is complete — not until you feel like checking in."** It exists so a whole development pass (build → verify → fix → handoff) can run on a VM with nobody watching. A 3-day run that kept stopping for a delete prompt, a git-read prompt, or a "shall I continue?" is the failure this rule removes.

YOLO is ON when **any** of these holds — you do not need the owner to say it twice:

| Trigger | How you know |
|---|---|
| `*yolo` typed to any TechieFlow agent | you ran `bash .tfcore/utils/tf-yolo.sh on --source yolo` (do this **immediately**, first action, before anything else) |
| The prompt contains `YOLO` / `yolo` / `--yolo` anywhere (e.g. `*build-phase MyApp yolo`, "YOLO: finish the app") | same — run `tf-yolo.sh on` first, then the command |
| A Claude Code goal is active (`/goal <condition>`), or the session was started by `tf-goal.sh` | `tf-goal.sh` sets `TF_YOLO=1` + the flag for you; for a hand-typed `/goal`, run `tf-yolo.sh on --source goal` as your first action |
| The harness is already in a no-prompt mode (Claude Code `bypassPermissions` / `auto`, `opencode run --auto`) | the hook sees `permission_mode` itself; you should still run `tf-yolo.sh on` so the agent-side rules below apply |

`*yolo` again, or `bash .tfcore/utils/tf-yolo.sh off`, turns it off. `tf-yolo.sh status` tells you which. The flag lives at `.tfcore/.session/yolo.json` (never committed) and is read by `.tfcore/hooks/block-git.sh` (both harnesses) and `.opencode/plugin/techieflow.js`.

**The grant ends with the run — it is not a repo setting (2026-08-28).** Three things now close it, so an unnoticed flag cannot go on suppressing delete prompts for days: `tf-yolo.sh off`, **`tf-yolo.sh done`** (the sentinel below clears the flag as well as writing the outcome), and, for a session that is killed or crashes before either, an **expiry** — a flag older than 24 h (`TF_YOLO_TTL_HOURS`, `0` disables) is ignored by the hook and reported as `OFF (flag EXPIRED …)` by `status`. `tf-goal.sh` additionally clears its own flag on every exit path via an `EXIT`/`INT`/`TERM` trap, and exports `TF_YOLO=1` for the duration of the run, which is checked first and **never** expires — so a multi-day supervised run that sleeps through usage-limit windows is unaffected. If you need YOLO back, say `*yolo` again; that is one line, and it is cheaper than a repo that has been silently permissive since last week.

## What changes when YOLO is ON

**Permissions (mechanical — the hook/plugin enforce these, you just stop worrying about them):**

| Action | Normal mode | YOLO |
|---|---|---|
| `rm` / `rmdir` / `find -delete` / `sudo` | prompt (hook `ask`) | **allowed, no prompt** — delete anything the task needs (catastrophic `rm -rf /`, `~` stay denied) |
| Read-only git/gh — `status`, `log`, `diff`, `show`, `blame`, `grep`, `branch`, `tag -l`, `stash list`, `remote -v`, `config --get`, `gh pr list/view` | blocked | **allowed** — use it when it is genuinely the fastest evidence; the checklist table + working tree remain the primary status source |
| Git/gh **writes** — `commit`, `push`, `add`, `reset`, `checkout`, `switch`, `restore`, `stash`, `tag`, `merge`, `rebase`, `branch -d/-m`, `clean`, `pull`, `fetch`, `gh pr/issue create|merge|close` | blocked | **still blocked** — in every mode, forever. The owner commits. Never try a workaround. |
| Edits, writes, builds, test runs, booting the app, Playwright, winrun | allowed | allowed |

**Behaviour (agent-side — these are on you):**

1. **No confirmations, no elicitation, no phase-boundary pauses.** `brd_coverage_protocol`'s "pause and ask the user to CONFIRM the list" → emit the list and continue. `*run-workflow`'s "pauses for confirmation at each phase boundary" → log the boundary and continue. `elicit=true` sections → take the sensible default, mark it `<!-- yolo-default -->` / note it in the checklist Remarks, continue. "Ask once" questions (scope, AppName, which startup project, which BRD variant) → resolve from `core-config.yaml` / `PROJECT-STATUS.md` / the file system; if truly ambiguous, pick the most conservative reading and **record the decision**. The only questions that survive YOLO are the ones the owner has explicitly reserved — creating a **new test user** (`_smoke-test-policy.md`): in YOLO, use an existing documented account; if none exists, create ONE, name it `{AppName}-yolo-tester`, record it in the UsageGuide Test-users table, and move on.
2. **Never end a turn with a question, a plan, a menu, or "shall I…".** Ending a turn is allowed only when (a) the goal/command is complete, or (b) everything remaining is owner-only (see §Completion). Otherwise the next step is yours to take.
3. **Whole-checklist build passes.** `*build-phase` in YOLO (and, honestly, in every mode — build-phase §2b) means every open REQ reaches at least `Implemented` **in this pass**, the verifier is chained inline, and FIX mode loops on its `FAIL` / `Needs re-verify` rows automatically (build-phase §6c) until they pass or are genuinely `Blocked`. "Run build-phase again for the remaining REQs" is a banned ending.
4. **Context pressure is not a reason to stop.** If the working list is large, fan more clusters out to sub-agents (build-phase §3) and keep only the cluster table + results in your own context. Delegating is how a long run survives; stopping is not.
5. **Recover, don't report.** A failed build, a flaky boot, a port in use, a dead service — fix it (build ladder, verify-phase §3a escalation) and continue. Report only what you could not fix after genuinely trying.
6. **Still no self-attestation.** YOLO does not relax `guard-verify.sh`, `guard-status.sh`, the smoke policy, or the status gate. `Verified` still comes only from an executed verify-phase run; PROJECT-STATUS (md + html) is still the last action of every phase.

## Usage limits (5-hour / weekly) — the supervisor waits, you just resume cleanly

When the subscription limit hits mid-run the harness stops the session and prints the reset time ("resets 7pm (Asia/Kolkata)", "resets in 2h 14m", `usage limit reached|<epoch>`). Nothing inside the session can wait that out — so the wait is done **outside** it by `.tfcore/utils/tf-goal.sh`: it parses the reset time, **sleeps until reset + 15 min** (`--buffer-min`), writes `RETRY AT <time>` to `.tfcore/.session/goal.log` / `goal.json`, then **resumes the same session** (`claude -p --resume <id>` / `opencode run -c`). No reset time parseable → it **probes** instead of guessing: a one-turn `claude -p "Reply OK"` every 15 min (`--probe-min`) until the API answers cleanly, then a 15-min buffer and resume (gives up probing after `--probe-max-hours` 8 and resumes anyway). Crashes/API errors → exponential backoff (2 min → 30 min). Your only job on resume: **re-read `PROJECT-STATUS.md` + the checklist Requirements Status table and continue from the weakest open REQ** — the status gate you ran at the end of every phase is what makes the resume lossless. That is one more reason the gate is non-skippable.

If you (the agent) see a `429` / `rate_limit` / `overloaded` **tool** error from a sub-agent or an API you called, that is not the session limit: wait 60 s, retry once, then route around it (another sub-agent, smaller batch). Do not declare the goal blocked over a transient.

## Completion — the sentinel (how an unattended run knows it is over)

The supervisor stops **only** when you write the sentinel. Write it exactly once, as the very last action after the status gate + run record:

```bash
# every in-scope REQ terminal, PROJECT-STATUS.md + .html updated, runs.jsonl emitted:
bash .tfcore/utils/tf-yolo.sh done complete "MyApp: 23 REQs Verified, handoff written"

# everything left needs the OWNER (credentials / physical device / paid account / product decision):
bash .tfcore/utils/tf-yolo.sh done blocked "REQ-FN-7, REQ-NFR-2 need the production SMTP creds"
```

`blocked` is legitimate only when **every** remaining open REQ is owner-gated and you have finished everything else, logged each blocker under PROJECT-STATUS "Known blockers", and pointed the next command at the owner-run step. A `blocked` written because the work was long, the context was full, or you wanted a check-in is the exact failure this rule exists to stop — the supervisor will simply re-prompt you, and the log will show it.

Without a goal/supervisor (plain `*yolo` in an interactive session) the sentinel is harmless; still write it — it records the outcome for `tf-yolo.sh status` **and it is what turns YOLO back off**. An interactive `*yolo` that ends without it leaves the repo permissive until the 24 h expiry catches it.

## Starting an unattended run (owner side — the VM recipe)

```bash
# Claude Code (default). Runs in .tfcore/.session/goal.log; resumes across limit windows.
bash .tfcore/utils/tf-goal.sh /path/to/App "Take MyApp from its current PROJECT-STATUS to Handoff: build every open REQ, verify all, fix until every row is Verified, then *handoff-phase."

# OpenCode
bash .tfcore/utils/tf-goal.sh --harness opencode --model opencode-go/kimi-k3 /path/to/App @goal.md

# after a reboot / to pick up where it left off
bash .tfcore/utils/tf-goal.sh --resume /path/to/App
```

Interactive alternative: start Claude Code with `--permission-mode bypassPermissions` (or `auto`), type `/goal <condition>`, then `/TechieFlow:agents:flow-master *yolo` and the command. That gives you YOLO permissions and the goal loop, but **not** the limit-wait — for that, use `tf-goal.sh`.

Exit codes: `0` complete · `3` blocked (owner input needed — read `goal-done.json`) · `4` max cycles.
