# TechieFlow — Permissions and YOLO mode

| | |
|---|---|
| Purpose | Why the harness stops asking you for permission, how the git ban is enforced, and what YOLO mode changes. Includes the shipped `settings.json` and every guard hook with the incident that produced it. |
| Audience | The owner, and anyone who has to explain why an agent was refused. |
| Status | Moved out of `README.md` on 2026-09-07 (Session 6 of the reset), unedited. Written before the reset: the hook list grew afterwards to eleven, adding the database, build and metrics guards. `docs/TechieFlow-How-It-Works.md` §2 carries the current list. |
| Companion | `README.md`, `docs/TechieFlow-How-It-Works.md`, `.tfcore/tasks/_yolo-mode.md`. |

---

## 12. Permissions (yolo-except-git-writes)

The pre-built config **auto-allows** Read/Glob/Grep/Edit/Write/MultiEdit and **all Bash** (bare `"Bash"`) — so create/update/**move** run with zero prompts. **Deletes and `sudo`** (`rm`, `rmdir`, `find -delete`, `sudo`) **ask — via the hook, not via a settings `ask` rule** (see the YOLO box below for why). **Denies** catastrophic `rm -rf` root/home paths **and every git/gh WRITE subcommand** (`git commit|push|add|reset|checkout|switch|restore|merge|rebase|stash|clean|pull|fetch|…`, `gh pr|issue|repo|release create|merge|close|…`) — git is manual in TechieFlow; agents never write it, so it is a hard deny, in **every** permission mode including bypass. Permission precedence is `deny → ask → hook → allow`. *(Cross-project tip: to let a session work in another app's folder without per-path prompts, add that root to `permissions.additionalDirectories` in this project's settings.json — keep those machine-specific paths out of any shared template.)*

**The git ban is TWO layers, because prefix rules alone leak.** `Bash(git commit*)` is a literal prefix match — it never sees `cd src && git commit` or `echo done; git add -A`, which the bare `"Bash"` allow would wave straight through. That is exactly how agents kept "accidentally" running git during status updates. So the config also wires a **PreToolUse hook** — `.tfcore/hooks/block-git.sh` — that parses every Bash call (compound forms, `bash -c "…"`, `eval`, `$(…)`, wrappers like `sudo`/`env`/`xargs`) and classifies each `git`/`gh` node as **read** (`status`/`log`/`diff`/`show`/`blame`/`grep`/`branch`/`tag -l`/`stash list`/`remote -v`/`config --get`, `gh pr list|view`…) or **write** (everything else). Writes are blocked always; reads are blocked outside YOLO and allowed in YOLO. The block message carries the local-evidence recipe (checklist tables + working-tree files + fresh build) so the agent continues correctly instead of flailing. You still run git yourself: in a separate terminal, or by typing `!git …` in the session (user-typed bang commands bypass agent tool permissions).

### 12a. YOLO / goal mode — "I've given you all the permissions; run until it's done" (2026-08-21)

`*yolo` used to be agent-side only (skip elicitation) and the owner still got prompted for every delete and blocked on every git read — which is how a VM goal run took **3 days**, mostly waiting for a human. Now `*yolo`, the word **YOLO** anywhere in a command, an active Claude Code **`/goal`**, or a `tf-goal.sh` run all mean the same thing, defined in **`.tfcore/tasks/_yolo-mode.md`**:

| | Normal | YOLO |
|---|---|---|
| `rm` / `rmdir` / `sudo` | hook asks | **allowed, no prompt** (catastrophic `rm -rf /`/`~` still denied) |
| git/gh **reads** (`status`/`log`/`diff`/`blame`, `gh pr view`) | blocked | **allowed** |
| git/gh **writes** (`commit`/`push`/`add`/`reset`/`checkout`/`stash`/`tag`, `gh pr create|merge`) | blocked | **blocked — always** |
| Elicitation, phase-boundary pauses, "confirm the BRD-N list", "ask once" questions | pause | **decide the default, record it, continue** |
| Build pass scope | whole checklist (§2b) | whole checklist **+ automatic FIX loop** on verifier FAIL rows (build-phase §6c, ≤5 cycles) |
| Turn ending | may hand back | **only** when the goal is complete (`tf-yolo.sh done complete`) or every remaining REQ is owner-gated (`done blocked`) |

**Mechanics.** The flag is `.tfcore/.session/yolo.json` (`bash .tfcore/utils/tf-yolo.sh on|off|status`; never committed). `block-git.sh` reads it (plus `TF_YOLO=1` and the hook payload's `permission_mode` — Claude Code's `bypassPermissions`/`auto` count as YOLO); the OpenCode plugin reads the same flag and auto-approves its `rm */sudo *` asks via `permission.ask`. **Why the delete prompt moved out of `settings.json`:** Claude Code honours a settings `ask` rule *even in `bypassPermissions` mode and even when a hook says allow* — so as long as `Bash(rm *)` sat in `ask`, no mode could stop the prompt. A hook-issued `ask` can be withheld; a settings `ask` cannot.

**Usage limits (5-hour / weekly).** Nothing inside a session can wait a limit out, so the wait lives in a supervisor: `bash .tfcore/utils/tf-goal.sh <app-dir> "<goal>"` runs the goal headless (`claude -p --permission-mode bypassPermissions`, or `--harness opencode` → `opencode run --auto`), parses the reset time from the limit message (`resets 7pm (Asia/Kolkata)`, `resets in 2h 14m`, `usage limit reached|<epoch>`, weekly `resets Tue 3pm`), **sleeps until reset + 15 min** (`--buffer-min`), logs `RETRY AT …` to `.tfcore/.session/goal.log`, and **resumes the same session** (`--resume <id>`). Crashes back off 2 → 30 min; an agent that stops without finishing is re-prompted; it exits only on the agent's sentinel (`0` complete, `3` owner-blocked, `4` max cycles). `--resume <app-dir>` picks up after a reboot. The agent's part of the bargain is the status gate: every phase ends with PROJECT-STATUS + checklist written, so a resume is lossless.

**Build passes are whole-checklist, YOLO or not.** The other 3-day culprit: build-phase runs that implemented a few REQs, wrote "next command: `*build-phase` for the remaining REQs" and stopped. `build-phase.md §2b` now bans that ending — a pass is done when **every** working-list REQ is ≥ `Implemented` (or a logged `Blocked`/owner-gated blocker), the verifier has been chained, and (in YOLO) its FAIL rows have been looped. Long list ⇒ more sub-agent clusters, never a shorter pass. `_status-update-gate.md` item 5 carries the matching rule for the next-command line.

**Codex permission difference.** `.codex/hooks.json` routes shell and file changes through `.tfcore/hooks/codex-adapter.py`, while `.codex/rules/techieflow.rules` provides the command policy. Codex keeps every agent-issued `git` and `gh` command blocked in normal and YOLO modes (including reads); this is intentionally stricter than the Claude/OpenCode YOLO table above. Trust the repository and inspect `/hooks` after scaffold/update. `$techieflow-yolo` changes TechieFlow pause/delete behavior, but never relaxes Codex's version-control boundary.

**Q: Config (canonical version in scaffold-brownfield.sh / scaffold-greenfield.sh)**

```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash",
      "Edit", "Write", "MultiEdit", "NotebookEdit",
      "Read", "Glob", "Grep", "TodoWrite", "WebFetch", "WebSearch", "Task"
    ],
    "ask": [],
    "deny": [
      "Bash(rm -rf /)", "Bash(rm -rf /*)", "Bash(rm -rf ~)", "Bash(rm -rf ~/*)",
      "Bash(git commit*)", "Bash(git push*)", "Bash(git add*)", "Bash(git reset*)",
      "Bash(git checkout*)", "Bash(git switch*)", "Bash(git restore*)", "Bash(git merge*)",
      "… every other git WRITE subcommand (rebase, cherry-pick, revert, clean, pull, fetch, init, clone, …) …",
      "Bash(gh pr create*)", "Bash(gh pr merge*)", "Bash(gh issue create*)", "… every gh WRITE verb …"
    ]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command",
                     "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/block-git.sh\"" },
                   { "type": "command",
                     "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-artifacts.sh\"" } ] },
      { "matcher": "Write|Edit|MultiEdit",
        "hooks": [ { "type": "command",
                     "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-status.sh\"" },
                   { "type": "command",
                     "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-verify.sh\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command",
                     "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-status-html.sh\"" } ] }
    ]
  }
}
```

**Repo-root artifact directories are blocked mechanically (2026-08-25).** A fourth PreToolUse hook — `.tfcore/hooks/guard-artifacts.sh`, matcher `Bash` — blocks any command that points `--output` / `--output-dir` at a root-level `test-results*` or `scripts-*` directory, or `mkdir`s one. The prose rule in `verify-phase.md` §1 had been strengthened twice and broken three times (fourteen `test-results-*` dirs in one app, four `scripts-cluster-*` in the next fan-out, ten `test-results-*` in TechieBlog) — every time from an agent passing `--output test-results-<slug>` and overriding the config's pinned `outputDir`. The sanctioned isolation form `--output tests/.artifacts/<slug>` passes, as do `tests/`, `docs/screenshots/` and the project's own tracked `scripts/`. A bare `-o` is deliberately *not* matched (Playwright has no `-o`; `grep -o` / `curl -o` are legitimate).

**A stale `PROJECT-STATUS.html` blocks the end of the turn (2026-08-25).** The first **Stop** hook — `.tfcore/hooks/guard-status-html.sh` — refuses to let a turn end while `PROJECT-STATUS.html` is older than `PROJECT-STATUS.md`, or missing. `_status-update-gate.md` §8 ("re-render in the same turn, full stop") had failed twice in a row; the owner spent 4h40m reading a page that still listed retracted owner-actions. Stop, not PostToolUse, because the rule is about the turn — an agent legitimately renders the HTML several tool calls after writing the markdown. It honours `stop_hook_active` so a turn that genuinely cannot render still terminates. mtime only: content parity stays an agent responsibility.

**Expired run material is deleted automatically (2026-08-26).** Pinning artifacts under `tests/.artifacts/` fixed *where* they land but not that they ever leave — Playwright wipes only its own `outputDir`, so per-cluster subfolders, harness scripts and multi-hundred-MB host logs piled up (TechieBlog: 1.1 GB under `tests/.artifacts/` + 101 MB of `.verify/*.log`, mostly two weeks stale). A **SessionStart** hook — `.tfcore/hooks/sweep-artifacts.sh`, no veto, exit 0 always — deletes files under `tests/.artifacts/` and `.verify/` older than the retention window (default **7 days**; `artifactRetentionDays: N` in `.tfcore/core-config.yaml` or `TF_ARTIFACT_RETENTION_DAYS=N`; `0` disables the age sweep), prunes emptied dirs, and removes banned repo-root legacy dirs (`test-results*/`, `scripts-*/`, `playwright-report/`) regardless of age. Files newer than the window are untouched, so a run in flight is never disturbed and a mixed-age `harness/` keeps its recent scripts. Never follows symlinks, never leaves the project root, never touches tracked `tests/verify/` or the project's own `scripts/`. Throttled to once per hour per project (`.tfcore/.session/sweep.stamp`); `TF_SWEEP_DRY_RUN=1` previews. Codex runs it from `codex-adapter.py session-start`; OpenCode from the plugin on the first root `session.created`. The one-line summary of what was removed is surfaced into the session.

Both new guards run in every harness: Codex through `codex-adapter.py` (`pre-tool` and the new `stop` mode wired in `.codex/hooks.json`), OpenCode through `.opencode/plugin/techieflow.js` (the bash guard in `tool.execute.before`; the Stop check as a one-shot follow-up prompt on root `session.idle`, since OpenCode has no blocking Stop hook). Hooks load at session start — neither takes effect in an already-running session.

**PROJECT-STATUS shape is enforced mechanically too (2026-07-09).** A second PreToolUse hook — `.tfcore/hooks/guard-status.sh`, matcher `Write|Edit|MultiEdit` — blocks any write to `PROJECT-STATUS.md` that violates the crisp fixed-shape snapshot rule: an H2 outside the template's section set (per-run dated sections like `## *verify all — coverage matrix (DATE)` are the classic disease), a heading naming a command run, a paragraph stuffed into `current_phase:`, or a full-file write past ~120 lines. The block message tells the agent exactly how to reshape (overwrite the template sections in place, ONE Verification-log row per run, detail into the checklist Remarks). Same philosophy as the git ban: prose rules kept failing, so the harness enforces it. See `.tfcore/tasks/_status-update-gate.md`.

**`Verified` verdicts are enforced mechanically too (2026-07-10).** A third PreToolUse hook — `.tfcore/hooks/guard-verify.sh`, matcher `Write|Edit|MultiEdit` — blocks any write to a `*-Checklist.md` that *introduces* a `Verified` status cell unless a same-day run ledger `docs/.last-verify.json` exists, which only an *executed* `verify-phase` run writes (verify-phase §6: boot → scoped tests → §4a data-render + §4b visual-truth gates → ledger → verdicts). This exists because a build orchestrator did its own smoke and wrote the `Verified` verdicts itself (TrSetup, 2026-07-09) — self-attestation the "chain the verifier" prose didn't stop. A self-smoke's ceiling is `Implemented` (`_smoke-test-policy.md §"Smoke is NOT verify"`); `*refresh-status` may reconcile a lagging Status column to a row's *pre-existing* dated verdict by writing the ledger with `"mode":"reconcile"`. Demotions (e.g. `Verified → Needs re-verify`) are never blocked.

**WSL (Windows):**

```bash
/mnt/c/3AIGenCode/TechieFlow/update-framework.sh /path/to/app
```

**macOS:**

```bash
/Volumes/MacD/MyCode/TechieFlow/update-framework.sh /path/to/app
```

