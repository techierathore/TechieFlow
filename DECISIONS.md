# TechieFlow — Decisions

Durable decisions taken while building the framework, with the reasoning that would otherwise be lost. Newest first.

---

## 2026-08-08 — Development telemetry

Implemented from `docs/TechieFlow-Telemetry-Runbook.md`. Full maintenance-log entry in `WorkFlow-Context.md` §5; schema in `.tfcore/telemetry/SCHEMA.md`; doctrine in `.tfcore/tasks/_metrics-emit-gate.md`.

### 1. Which streams are live, which were skipped

| Stream | State | Notes |
|---|---|---|
| `gates.jsonl` | **live** | `verify-phase` §6a (one record per REQ graded, first-failing gate) + `triage-issues` §6a (`gate:"escaped"`). The primary stream. |
| `runs.jsonl` | **live** | Emitted by 13 tasks at the status gate. `_status-update-gate.md` item 10 is the trigger for every task that cites the gate; the three light-touch tasks (`devguide`, `productguide`, `mockups`) carry their own explicit step. |
| `sessions.jsonl` | **live** | `SessionEnd` hook. See §2. |
| `commits.jsonl` | **live, owner-side only** | Written by `.git/hooks/pre-commit`, installed as part of a normal framework refresh. The hook runs inside your own `git commit`; no agent path writes it. **Optional** — `tf-metrics.sh --backfill-commits` reconstructs the same data perfectly, so deleting the hook costs nothing. |

**Nothing was skipped.** Two fields are deliberately `null` rather than fabricated:

- **`cost_usd` is always `null`.** Claude Code 2.x transcripts carry token counts but no per-message dollar cost (verified by reading a real transcript, not assumed). Multiplying tokens by a rate card would be an estimate presented as a measurement, and this framework runs on a subscription where marginal per-token cost is not the real unit anyway. Consequence, stated in the schema and the report template: **"cost per verified REQ" is reported in tokens, not dollars.**
- **`gates_run` on backfilled records is `[]`.** The checklist snapshot never recorded which gates ran, and guessing would credit gates that may never have fired.

### 2. The session-hook event name

**`SessionEnd`** — verified against the installed Claude Code version (`2.1.226`) by reading the local hook schema (`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/hook-development/`, whose `validate-hook-schema.sh` lists `VALID_EVENTS` including `SessionEnd`), **not** assumed from memory. The payload shape (`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `reason`) was confirmed from the same source, and the hook was executed against a real transcript before being wired in.

It is registered with **no matcher** — `SessionEnd` has no tool to match on — in the canonical `.claude/settings.json` block, **in all three scripts identically** plus the framework's own settings. That identity matters: `update-framework.sh` force-refreshes `settings.json`, so a block present in only two of the three would silently revert on the next update.

The hook emits **only** into a repo that already has `docs/metrics/`. A session in an unrelated directory writes nothing.

### 3. Constraints from §1 that forced a design compromise

**Constraint 1 (agents never run git) → the one-commit lag is permanent.** `post-commit` fires after the commit is sealed, so its record rides in the *next* commit. The obvious fix — `pre-commit` + staging the file — was rejected: it puts version control inside an automated path, and the entire design depends on commits staying manual and owner-driven. Documented in `SCHEMA.md` §5, the app-side `docs/metrics/README.md`, and WORKFLOW §17.

**Revised 2026-08-11 (a) — the lag was permanent, the data loss was not.** The hook now *reconciles*: it writes a record for every commit reachable from HEAD that the stream lacks, skipping on `sha`. That removed what actually hurt — a portfolio worked on from a Mac and from Windows/WSL, where the trailing record was never pushed, a clone with no hook recorded nothing, and the other machine's commits were invisible. `git log` is already replicated by push/pull, so the stream reduced to a projection of it. Paired with `merge=union` so two machines never conflict, `eol=lf` so a machine-appended log never acquires mixed line endings, and de-duplication on `sha` at read time so the union merge cannot inflate a count.

**Revised 2026-08-11 (b) — REVERSED: it is a `pre-commit` hook now, and it stages one file.** The decision above rejected exactly this. The owner rejected the rejection, and the reasoning that overturned it is worth keeping:

*The stated cost of post-commit was "metrics lag by one commit." The real cost was different and larger: `commits.jsonl` was **dirty the instant every commit finished, permanently**, because a record of commit N cannot exist before N does.* There is no reachable clean state — committing the pending line creates a new commit whose record is then pending in turn. The advice that follows from the old design ("commit the one-line diff, then pull") is circular. On a repo worked from more than one machine it also blocked `git pull` every time the file had changed upstream. A design whose steady state is "your tree is never clean" is not a lag; it is a defect that was mislabelled as a caveat.

What the original decision got right is the *risk*, and it is not waived — it is bounded:

- The hook stages **exactly one path**, `docs/metrics/commits.jsonl`. Never `-A`, never a directory. It cannot pull source changes into a commit.
- On a **partial commit** (`git commit -- <paths>`, detected via `GIT_INDEX_FILE`) it writes the record and does **not** stage — it can never add a file to a commit you deliberately scoped down.
- It **cannot fail a commit**. A pre-commit hook exiting non-zero aborts the commit, so every path ends `exit 0`. Telemetry keeps its no-veto property (constraint 9).
- Everything it skips — merges, `--no-verify`, rebase, cherry-pick, partial commits — is picked up by the next ordinary commit's reconcile. Skipping is never losing.

Constraint 1 (*agents* never run git) is untouched: this is the owner's own `git commit`, no agent path reaches it, and `block-git.sh` is unchanged. What moved is the narrower rule that the framework's git usage stays read-only — which was never a stated constraint, only an inherited habit of the post-commit design.

**Constraint 1 also split `tf-metrics.sh` by mode.** `--backfill-commits` and `--backfill-gates` are **owner-run only**; `--report` and `--rollup` are read-only, invoke no git, and are what the `*metrics` task calls. Making the agent do the arithmetic by hand over raw JSONL was considered and rejected — see §Provenance below.

**Constraint 1 did NOT justify a separate install command — corrected 2026-08-08.** The first cut put telemetry setup behind an owner-run `install-metrics.sh`, on the reasoning that installing a git hook must stay out of an automated path. That reasoning was wrong twice over: `update-framework.sh` is the owner's command, and more importantly **installing a hook is a file copy, not a git operation**. The setup now locates `.git/hooks` by reading the filesystem (`.git/` as a directory, or the `gitdir:` pointer when `.git` is a file) and never invokes the git binary, so it runs identically whoever triggers the refresh, needs no permission prompt, and leaves `block-git.sh` untouched. Telemetry setup is now part of `update-framework.sh` and both scaffolds. `install-metrics.sh` survives only as the reclassification helper (`--type`), auto-invoked by all three scripts so the logic has one source of truth rather than being copy-pasted three ways.

**Constraint 7 (telemetry never blocks) → `tf-emit.sh` exits 0 unconditionally,** and on a failure it *drops the event silently*. That means a genuinely broken emitter loses data with no visible signal. Accepted deliberately: a telemetry bug must never cost a working session. `TF_METRICS_DEBUG=1` is the escape hatch, and the streams are inspectable at any time.

**Constraint 8 (no content) → `failure_class` is a closed enum** rather than a description, and commit **subjects** are discarded inside the commit hook, keeping only a `feat|fix|docs|chore|refactor|test|build` prefix. This costs real diagnostic richness — you cannot ask "what actually broke" from telemetry alone — and that is the correct trade for data that could become public.

**Constraint 9 (provenance never merges) → `attempt` counts live records only,** which creates a known hole: on a backfilled app, the first *live* verify of an old REQ records `attempt: 1` even though it is not that REQ's first attempt. Rather than silently correcting it, **`*metrics` excludes any REQ carrying backfilled history from the live first-pass rate entirely**, and names the excluded REQs. The exclusion is the fix; the field is never quietly patched.

**Provenance is enforced in code, not in prose.** `tf-metrics.sh` has no code path that produces a combined first-pass rate, gate distribution, or escape rate across live/backfilled or across `project_type`. This was the deciding reason for letting the agent call `--report --json` instead of computing by hand: an agent that must *resist* producing a tempting number will eventually produce it, especially when a reader asks for "just the overall figure". The tool cannot.

### 3b. Harness portability — Claude Code and OpenCode

The framework ships to **two harnesses** from byte-identical task files (`.claude/commands/TechieFlow/` and `.opencode/command/TechieFlow/`). The first cut of telemetry was Claude-Code-shaped in three places. Two were bugs and are fixed; one is a genuine gap and is documented rather than papered over.

**Fixed — `harness` was hard-coded.** Every emit template literally contained `"harness":"claude-code"`, so an OpenCode agent copying the snippet would have stamped the wrong harness on every record — silently, forever, on the one field that exists to tell the two apart. `tf-emit.sh` now **detects** it (harness env vars, then the parent process chain bounded to 12 levels, since OpenCode sets no `OPENCODE_*` variables) and the literal was stripped from all 14 task files. Undeterminable becomes `null`, deliberately: a wrong harness label corrupts every comparison built on it, a missing one is merely missing. Verified by forcing all three detection branches.

**Fixed — root resolution assumed `CLAUDE_PROJECT_DIR`.** It is still preferred when set, but the walk-up fallback (looking for `.tfcore/` or `docs/`) is what actually runs under OpenCode, and it works.

**Gap, documented — `sessions.jsonl` is Claude-Code-only.** It is written by a `SessionEnd` settings hook. OpenCode's extension point is **npm plugin modules** (`opencode plugin <module>`), not a settings block, which does not fit this framework's copy-files deployment model; and the hook parses Claude Code's transcript format regardless. Under OpenCode that stream simply stays empty. `runs`, `gates`, and `commits` — including the entire primary stream and all three headline metrics — are harness-agnostic and work identically.

**Worth knowing: OpenCode can measure the one thing Claude Code cannot.** `opencode stats` reports sessions, input/output/cache tokens **and real dollar cost**, with `--days` and `--project` filters; `opencode export <sessionID>` gives per-session JSON, which would make ingestion append-safe by de-duplicating on session id. That is the obvious route to making `cost_usd` a real number instead of `null` (see 1 above). Not built — it is a new ingestion path, not a bug fix, and nobody has asked for it yet.

**Observation, not acted on — the guard hooks are Claude-Code-only, and this predates telemetry.** `block-git.sh`, `guard-status.sh` and `guard-verify.sh` are wired in `.claude/settings.json`; `opencode.jsonc` has no hook or permission mechanism at all. So under OpenCode the git ban and the mechanical "no `Verified` without a run ledger" gate are **prose rules only, not enforced**. That matters for telemetry integrity specifically: a `Verified` self-attested under OpenCode would produce a `gates.jsonl` record indistinguishable from an earned one. Flagged here per the runbook's "note it and leave it"; closing it is separate work and may not be possible without an OpenCode plugin.

### 4. The install command the owner runs, per app repo

There isn't one. Telemetry rides the normal refresh:

```bash
# WSL/Linux
/mnt/c/3AIGenCode/TechieFlow/update-framework.sh /path/to/YourApp

# macOS
/Volumes/MacD/MyCode/TechieFlow/update-framework.sh /path/to/YourApp
```

That creates `docs/metrics/`, seeds the four streams, writes the README, installs the `pre-commit` hook, and warns if an ignore rule would swallow the data. The scaffolds do the same on a fresh project. Idempotent, so every later refresh keeps it current, and `--dry-run` previews it.

**`project_type` is auto-detected once** — a packable `.csproj` → `library`; `.razor`/`.xaml` present → `app`; no source → `docs`; this repo → `framework` — printed loudly, written to the preserved `core-config.yaml`, and never re-guessed afterwards. Correct a wrong guess with the one command you may ever need to type by hand:

```bash
.tfcore/telemetry/install-metrics.sh . --type app|library|docs|framework
```

### 5. App repos this still needs to be installed into

Found on the WSL machine (each has a `docs/<App>-Checklist.md`, so each is a live TechieFlow project). **None has been refreshed yet** — `update-framework.sh` is yours to run and was not executed against any app repo in this session. Running it is now the whole of the setup; the `project_type` column below is what the auto-detector will choose, so most rows need no action at all.

| Repo | Suggested `project_type` | Why |
|---|---|---|
| `/mnt/c/3AIGenCode/TrSetup` | `app` | MAUI desktop app, runtime screens. Auto-detector confirmed `app` on a dry run. |
| `/mnt/c/3AIGenCode/TrStudio` | `app` | runtime screens |
| `/mnt/c/3AIGenCode/AppManager` | `app` | runtime screens |
| `/mnt/c/3AIGenCode/AppStudio` | `app` | runtime screens |
| `/mnt/c/1MyCode/AstroLyfe` | `app` | runtime screens |
| `/mnt/c/3AIGenCode/TrBlazeUI` | `library` | NuGet UI library — the §4b visual gate never fires on the package itself. Auto-detector confirmed `library` on a dry run. |
| `/mnt/c/3AIGenCode/TechieRag` | `library` | NuGet RAG/LLM library, no screens |
| `/mnt/c/3AIGenCode/Lekhak` · `/mnt/c/3AIGenCode/XVault` · `/mnt/c/1MyCode/TechieBlog` | owner's call | have checklists; classify on install |
| this repo (`TechieFlow`) | `framework` | optional — it is not built by its own pipeline |

The `project_type` matters: it is why gate-catch numbers stay comparable. Classifying a library as `app` would make the visual gate look like it never catches anything — so check the line the refresh prints, and correct it with `--type` if the heuristic guessed wrong.

### 6. Backfill — what ran, and what the data is worth

**`--backfill-gates` was validated in `--dry-run` against three real app repos and wrote nothing.** Synthesising a project's history is the owner's call, not an agent's, and no app repo has been refreshed yet.

| Repo | Records the parser would write | Rows skipped (status is not a verify verdict) |
|---|---|---|
| TrSetup | 49 | `N/A` ×6 |
| TrBlazeUI | 33 | — |
| AstroLyfe | 85 | `Done` ×4, `Implemented (re-verify pending …)` ×6, `In Progress` ×5, `PARTIAL` ×1 |

Every record carries `backfilled: true` and an `inferred[]` list. Fields inferred: **`attempt` always**, plus `gates_run` and `prior_verdict` always, `gate` and `failure_class` whenever they came from remark prose, and `ts` where the remark carried no date. Because none of these repos has `metrics.project_type` set yet, every record also carries `project_type_inferred: true` and reports as **unclassified** — running `update-framework.sh` on the repo *before* backfilling avoids that.

> **Stated plainly: the backfilled set cannot support a published first-pass rate.** The Requirements Status table is a mutated-in-place snapshot, not a log. A REQ that failed three times and then passed is indistinguishable from one that passed first try unless every failure happened to leave a dated remark — and they did not. `attempt`, the field first-pass rate depends on entirely, is not recoverable and is being assumed. Backfilled gate data is **context and volume only**.

`--backfill-commits` is a different matter and genuinely reliable: the commit log is a real append-only log, so those records are as trustworthy as live ones and need no separation in reporting. It has not been run — it invokes version control, so it is owner-only.

**Which makes the commit hook optional, and worth saying out loud.** It is the weakest component in the design: it is the only piece with a known limitation (the one-commit lag), the only piece that writes to your index, and the only piece whose data can be reconstructed perfectly without it. If a hook in `.git/hooks/` is unwelcome, delete it and run `--backfill-commits` before you want a report — you lose nothing. That is the opposite of `gates.jsonl`, whose history genuinely cannot be recovered and is why the rest of the telemetry has to be written as it happens.

**Observation, not acted on** (per "do not refactor unrelated parts of the framework while in here"): AstroLyfe's checklist carries free-text status variants such as `Implemented (re-verify pending formal pass)` that are outside the documented Status vocabulary. The backfill reports them as skipped rather than guessing. Worth normalising in that checklist at some point; not a telemetry problem.

### 7. Verified during implementation

- `tf-emit.sh`: valid JSON appends one line; `garbage` exits 0 and appends nothing; unknown stream drops silently; `--next-attempt` counts live records only and skips backfilled ones.
- `metrics-session.sh`: run against a real transcript, produced a correct record; malformed payload and non-opted-in repo both exit 0 writing nothing.
- `tf-metrics.sh --report`: correctly segments live vs backfilled, prints the excluded-REQ list, and prints `insufficient data (n=…)` below n=3.
- Telemetry setup: `scaffold-brownfield.sh` run twice against a sandbox repo — streams seeded, `project_type` auto-detected as `app` from a `.razor` file, `post-commit` installed and `chmod +x`, second run correctly reported "already current" / "streams present". `install-metrics.sh . --type library` then reclassified in place. Separately re-run **with the version-control binary removed from `PATH`** to prove nothing version-control-related ever executes: identical result, hook step degraded with a clear warning.
- `update-framework.sh --dry-run` against TrSetup and TrBlazeUI: auto-detector chose `app` and `library` respectively, and found `.git/hooks` without invoking git.
- **Constraint 2 checked mechanically:** no entry in either managed `.gitignore` block matches `docs/metrics/…`, and all three scripts now assert it at deploy time.
- `update-framework.sh --dry-run` against TrSetup: all new `.tfcore/` files land (`telemetry/`, `utils/tf-emit.sh`, `hooks/metrics-session.sh`, both new tasks, the new template) and **nothing under `docs/` is overwritten**.
- Harness mirrors byte-identical (`diff -rq` clean) to both `.claude/commands/TechieFlow/` and `.opencode/command/TechieFlow/`.

### 8. Not done in this session

- No `update-framework.sh` run against any app repo — that is yours (`WORKFLOW.html` §17, runbook §5). It is now the only step: there is no separate telemetry install.
- No live end-to-end `*build-phase` → `*verify all` → `*metrics` cycle: that requires a scaffolded app with the framework refreshed, which is the owner's step.
- `sessions.jsonl` will stay empty in every repo until open Claude Code sessions are restarted, so the new `SessionEnd` hook loads.

---

## 2026-08-08 — Cross-edition schema: the AI-First-Playbook team edition

Recorded now, though implementation is months out. [`AI-First-Playbook`](https://github.com/techierathore/AI-First-Playbook) is public, ships as documentation, and is intended to become a spec-driven, agent-based framework — the team-scale sibling of TechieFlow, same Apache-2.0, publicly positioned as one philosophy at two scales.

**The cost of deciding this now is one table. The cost of deciding it later is reconciling two incompatible schemas across two public frameworks that advertise themselves as one system.**

### The decision

When the Playbook grows agents, it emits **this same schema** — same four streams, same field names, same `project_type` and `backfilled` discipline. Team-edition records add exactly one field, **`actor`** (who ran it), which the solo edition has no use for.

### Verdict vocabulary mapping — the vocabularies have already diverged

| Playbook verdict | TechieFlow verdict | Notes |
|---|---|---|
| `PASS` | `Verified` | execution-proven |
| `PASS (code-audit)` | `Implemented` | **not** `Verified` — TechieFlow's `guard-verify.sh` already refuses `Verified` without an executed run ledger. Same principle; enforce it identically. |
| `FAIL` / `FAIL (code-audit)` | `FAIL` | |
| `BLOCKED` | `Blocked` | |
| — | `Needs re-verify` | Playbook has no equivalent; a re-opened item re-enters as `FAIL` |

### `gate` must not be reused across editions without disambiguation

TechieFlow's `gate` names an **assertion** that failed: `build` / `acceptance` / `render` / `visual` / `standards`. The Playbook's four gates are **process** gates: plan review, verify, gap report, post-verification bugs. These are different axes and must not share a field name.

**`gate` is reserved for assertions. `phase_gate` is reserved for the process gate.** Recorded in `SCHEMA.md` §11 so a future session cannot collapse them by accident.

### One metric the Playbook produces that TechieFlow cannot

**Execution-proven rate** — `PASS ÷ (PASS + PASS (code-audit))`. Code audit is the Playbook's explicit last resort, so this ratio measures whether the team is honouring "verify by executing, not by reading" or quietly degrading to reading. It is also a **leading indicator of adoption decay**: rising code-audit fallback is what process abandonment looks like before anyone says so out loud.

It is already in the shared schema as the optional field **`proof: "executed" | "code-audit" | null`** (`SCHEMA.md` §3.4), so the solo edition can carry it if a runtime bridge is ever unreachable and a run stamps `⚠ STATIC-ONLY`. TechieFlow never converts a `code-audit` proof into a `Verified` verdict — `guard-verify.sh` already refuses that, and the field changes nothing about the gate.

**Nothing Playbook-side was implemented.** Writing the decision and the mapping down was the whole task.
