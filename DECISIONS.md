# TechieFlow — Decisions

Durable decisions taken while building the framework, with the reasoning that would otherwise be lost. Newest first.

---

## 2026-08-20 — Guard bridge implemented; P-0 agent-permission fix; WSL OpenCode is the live path

Implementation of the 2026-08-19 design's *breaks* items, each verified live against the **deployed** WSL OpenCode 1.18.18 binary (the source checkout at `/mnt/c/4RoCode/opencode` is reference-only — nothing depends on it at runtime).

1. **`.opencode/plugin/techieflow.js` (new, tracked)** — the guard bridge from Adapter-Design §2.1, no policy inside: `tool.execute.before` translates `bash`/`edit`/`write` args to the Claude-shaped stdin JSON the unchanged `.tfcore/hooks/*.sh` guards already parse; guard exit 2 → `throw` (blocks the call, guard's stderr becomes the tool result); everything else fails open. `apply_patch` is refused only for `PROJECT-STATUS.md`/`*-Checklist.md` with a redirect to edit/write. `shell.env` injects `TF_HARNESS`/`TF_PROJECT_DIR`/`TF_SESSION_ID`. The `event` hook accumulates `message.updated` tokens+cost, tracks `parentID` from `session.created`, writes the session pointer `.tfcore/.session/opencode.json` (`{session_id, db_path, ts}`, gitignored), and on root `session.idle` emits a cumulative `sessions.jsonl` snapshot with **real `cost_usd`** and `children_sessions` (dedupe rule in SCHEMA.md §4). Live tests: git command blocked with `block-git.sh`'s message; `Verified`-cell write without ledger blocked with `guard-verify.sh`'s message; benign commands unaffected; `TF=opencode` observed in a tool shell. Closes Coupling-Points **H-1, H-2** (and T-1/T-2 partially).
2. **P-0 fix in `opencode.jsonc`** — all six agents' `"bash": "allow"` replaced with the full ordered deny map. Root cause: permission evaluation is `findLast` (last matching rule wins) and agent rules append after root rules, so a bare agent-level allow voided the root git/gh denies. Verified: rule order via `opencode agent list`, behavior via a rejected `git status` under `--agent flow-master`. The config comment now documents both footguns (rule order matters; agent-level `bash` must repeat the map). The compound-form caveat in that comment was deleted — compounds ARE decomposed and matched (probe-verified).
3. **`tf-emit.sh` harness detection honors `TF_HARNESS` first** (values `claude-code|opencode` only). Reason: a process launched from inside the other harness inherits its marker vars — the plugin must pass `CLAUDE_PROJECT_DIR` for the guards, which previously mislabeled OpenCode emits as `claude-code`. Additive: `TF_HARNESS` is unset on the Claude path.
4. **WSL deployment state:** native binary at `~/.opencode/bin/opencode` (owner should PATH it ahead of the Windows npm shim); portable `opencode-go` key copied to `~/.local/share/opencode/auth.json`. Probe evidence and the `/mnt/c`-vs-ext4 large-repo result are in the 2026-08-19 entry §7 and OpenCode-Deployment-Guide §0.

5. **D-1 propagation (same day, second pass):** `update-framework.sh` §3c and both scaffolds' §4b now deploy the OpenCode bridge to apps — `.opencode/plugin/*.js` (always refreshed) and a framework-owned `.opencode/opencode.jsonc` (a transformed copy of the template's root config; always refreshed; **wins over the preserved project root `opencode.jsonc` on conflicting keys** — merge precedence verified §7f). One trap found by live verification: **`{file:...}` refs resolve relative to the config file's own directory** and a bad ref hard-fails the entire config load, so the deploy rewrites `{file:./.tfcore/...}` → `{file:../.tfcore/...}`. The root file stays preserved for project-specific agents/MCP/LSP, with a warning when it still carries the bare agent-level `"bash": "allow"`. Propagated to all 18 `.tfcore`-bearing WSL repos; live-verified in TechieBlog (all six framework agents load; flow-master's `git status` blocked with `block-git.sh`'s message via the deployed plugin; `sessions.jsonl` record with `app:"TechieBlog"`, `harness:"opencode"`, real cost). Apps commit nothing — `.opencode/` is inside the managed `.gitignore` framework block.

**Not done yet (deliberately):** vocabulary edits (S-1), routing.yaml, Claude-side session pointer. Claude Code path untouched except the additive tf-emit detection branch.

---

## 2026-08-19 — Harness adapter boundary, per-phase model routing, OpenCode deployment (design only)

Investigation + design session; nothing implemented. Evidence and reasoning live in `docs/Capability-Matrix.md` (facts, source-cited: OpenCode 1.18.18 `file:line`, Claude Code doc URLs), `docs/Coupling-Points.md`, `docs/Adapter-Design.md` (Tasks 3+4), `docs/Telemetry-Hooks.md`, `docs/OpenCode-Deployment-Guide.md`. Constraints: not a rewrite; additive or behind a flag; the Claude Code daily path must not break.

### 1. The adapter boundary — decision

**A "harness profile" of four small pieces, no abstraction layer:** (a) a guard/telemetry *bridge* per harness — the existing `.claude/settings.json` hooks on Claude; a new local plugin `.opencode/plugin/techieflow.ts` on OpenCode that re-creates the Claude hook payload and shells out to the **same** `.tfcore/hooks/*.sh` (policy stays in bash, the plugin translates); (b) a framework-owned harness config per harness — `.claude/settings.json` as today; a new `.opencode/opencode.jsonc` that the scripts force-refresh (the root `opencode.jsonc` stops being the only carrier of framework config and becomes project-owned, mirroring `settings.json` vs `settings.local.json`); (c) `.tfcore/routing.yaml` — phase → tier, tier → model per harness, `enabled: false` by default; (d) a vocabulary rule — tasks name roles ("builder subagent") and resolve harness forms through `.tfcore/utils/tf-harness.sh` instead of Claude tool names (`Agent`, `general-purpose`, `subagent_type=`) — three task lines.

**What stays framework code:** every task, persona, gate, template, the status gate, the guard scripts' logic, the telemetry streams and schema (extended additively). **Deliberately left harness-specific** (Adapter-Design §4): permission syntax, session/TUI UX, headless CLIs, `@`/`$ARGUMENTS` sigils, bash-guard depth, cost display, `*agent` transformation, the Docker launcher, the byte-identical Claude mirror, MCP/LSP/OTel.

**Why this boundary and not another:** the only *breaks* items (Coupling-Points §1) are the two hooks that are unenforced under OpenCode, the config that never propagates, and the Docker runtime; each is a wiring problem at the harness edge, none is a phase-logic problem. The premise that blocked a plugin in the 2026-08-08 decision (§3b below — "npm plugin modules … do not fit the copy-files deployment model") is **wrong for OpenCode 1.18.18**: `.opencode/{plugin,plugins}/*.{ts,js}` are globbed and imported directly (`packages/opencode/src/config/plugin.ts:18-30`, `config/config.ts:462-465`, `plugin/loader.ts:139`); the `.opencode/package.json`/`node_modules` already sitting in this repo are OpenCode's own background type install, not something we did. §3b is superseded on that point; its other two findings (harness detection, root resolution) stand.

### 2. Model routing — decision

**Routing is declared at the harness boundary (command and subagent definitions) and observed by telemetry; it is never enforced mid-turn, because neither harness can change a running turn's model** (Claude: skill `model:` is turn-scoped; OpenCode: model fixed at message creation, `session/prompt.ts:646`, and no plugin hook can change it). Both harnesses bind a model to a subagent and to a command; that is the routing unit. Claude: generated wrapper commands `.claude/commands/tf/<phase>.md` (`model:`, `effort:`) + tier-bound `.claude/agents/tf-*.md`; OpenCode: `command.*.model` + `agent.*.model` in the framework-owned config, `opencode run --command … --model …` headless. Tier names (`frontier/standard/economy`) are abstract; ids are per harness and per machine (`ANTHROPIC_DEFAULT_*_MODEL`, root `opencode.jsonc`).

**The one place routing touches phase wording** — `build-phase` §6b chains the verifier *inline*, so it inherits the build tier. Options recorded: (a) accept (both are `standard` in the starting map — chosen for now); (b) delegate §6b to a `tf-verifier` subagent with its own model (one paragraph, owner's call, only if telemetry shows verify dominating cost); (c) invoke build and verify as separate routed commands. Per-tool-call routing does not exist in either harness and is not a loss: deterministic steps should become scripts, not cheaper prompts.

**Starting tier map** (Adapter-Design §5.6): frontier = day-1 ×2, author-brd, amend-docs, fix-issues (the *diagnosis* half); standard = build orchestrator **and builders**, verify (gates deterministic, test generation + screenshot judgement on the model), mockups, split-brd, triage, devguide; economy = productguide, handoff, refresh-status, render/generate-html, metrics, explorer. This *challenges* the working hypothesis in one place: builders should be standard, not economy — a cheap builder that ships a blank table costs a full verify cycle; the rework ratio (`runs.mode:"fix"`) by tier is the test that will confirm or overturn it.

### 3. Telemetry — decision

Add optional fields to `runs.jsonl`/`gates.jsonl`: `tier`, `tier_model`, `model`, `models[]`, `routed`, `tokens_in/out/cache_read/cache_write`, `cost_usd` (real on OpenCode, `null` on Claude), `tokens_scope` (`main|tree|none`). Source: a per-run **time window** over the harness's store — Claude transcript JSONL via a session pointer written by a `SessionStart`/`UserPromptSubmit` hook (subagent transcripts UNVERIFIED → `tokens_scope`), OpenCode SQLite `opencode.db` (root + children by `parent_id`) plus the plugin's `event` hook for `sessions.jsonl` with real cost. `attempt` stays per REQ on `gates`; a per-run retry counter was rejected (would require agent self-report). Dollars are never pooled across harness (provenance rule applied once more). No hook payload on Claude carries tokens — stated, not worked around.

### 4. OpenCode deployment — decision

**Run OpenCode in the WSL distro, as Claude Code is run; demote Docker to a fallback.** OpenCode's docs recommend WSL; the entire runtime harness (winrun/cmd.exe interop, headless Chromium, Appium on localhost) is already there; the Docker path had reconstructed a subset of it through an SSH bridge. The Bun-on-large-repos crash is UNVERIFIED in WSL; `watcher.ignore`, LSP off, `ulimit`, `.wslconfig` are the mitigations; the Docker image stays on disk. Ladder §E and `TF_OPENCODE_DOCKER` branches remain, dormant.

### 5. Alternatives rejected, and why

| Alternative | Rejected because |
|---|---|
| Prose-only ("OpenCode agents, follow the rules") | The 2026-07-09 self-attested-`Verified` incident is the counter-example; a rule called mechanical must be mechanical or it poisons `gates.jsonl`. |
| A generic harness-abstraction layer / DSL generating both configs | More code than both harness configs combined, a third dialect to maintain, and it would have to model hooks vs plugins, which are genuinely different shapes. |
| YAML frontmatter with `model:`/`tier:` on `.tfcore/tasks/*.md` | Breaks the byte-identical Claude mirror rule (§7 of WorkFlow-Context) and leaks frontmatter text into OpenCode prompts (`{file:}` inlines raw content). |
| Relying on the user's `/model` switches for per-phase tiers | Manual, unrecorded, and the owner's stated pain is that the session model governs everything. |
| Per-phase sessions as the only routing unit | Works but costs the owner an extra prompt per phase; kept as option (c), not the design. |
| Subagents as the *only* routing unit (orchestrator stays frontier, everything delegated) | Would force every phase through a delegation step the phase logic does not have today — a restructuring; commands-with-models achieve the same without it. |
| OTel collector for Claude token attribution | Exact, but a collector process for a solo WSL setup; transcript window is sufficient and degrades honestly (`tokens_scope:"none"`); OTel documented as the upgrade path. |
| Reading OpenCode tokens only via `opencode stats` (owner-run) | Coarse (per project/day), not per run; kept as the reconciliation fallback. |
| Keeping Docker as the OpenCode path and hardening the bridge further | Every hardening step (2026-08-15 log) was re-creating a capability WSL already has; the root cause was topology, not configuration. |
| Deleting the Docker artefacts now | The WSL crash hypothesis is unverified; a fallback that costs nothing to keep is worth keeping. |

### 6. UNVERIFIED items that gate implementation (each with its test)

OpenCode: `tool.execute.before` fires for subagent sessions and `throw` blocks without killing the session (scratch repo, `opencode run`); `.opencode/opencode.jsonc` precedence over root `opencode.jsonc` (merge two keys, `opencode debug config`); compound `cd . && git status` denied by `permission.bash` (one prompt); TUI re-sends its own model after a routed command (type a follow-up, check `runs.model`); `shell.env` reaches child processes. Claude Code: `SubagentStop` payload's `transcript_path` is the subagent's (print the payload once); WSL OpenCode on the largest repo does not reproduce the Bun crash (run `*build-phase` on TechieBlog).

### 7. Probe results (2026-08-20, WSL, OpenCode 1.18.18 native Linux binary, scratch project, `opencode run --model opencode-go/kimi-k3`)

**VERIFIED at runtime:** (a) local `.opencode/plugin/*.js` auto-loads with zero npm install; (b) `throw` in `tool.execute.before` blocks the tool call — the shell never executes, the error text becomes the tool result, the session continues; (c) the hook also fires inside `task`-tool **subagent** sessions (child sessionID observed, child bash call blocked) and fires *before* the permission check (it runs even for calls permission later denies); (d) `shell.env` injects env vars that reach the bash child (`TF_HARNESS` observed in command output); (e) the plugin `event` hook receives `message.updated` with real `tokens{input,output}` and `cost` per message; (f) `.opencode/opencode.jsonc` **overrides** the root `opencode.jsonc` on conflicting keys and merges with it on the rest — framework-owned config is viable; (g) compound `echo hello && git status` **is** denied by `"git *": "deny"` — the tree-sitter decomposition is real; the "compound forms not matched" comment in `opencode.jsonc` is wrong.

**NEW FINDING — the git ban was void for every TechieFlow OpenCode agent (BREAKS class; FIXED 2026-08-20 — each agent's `permission.bash` now repeats the full deny map with `"*": "allow"` first; verified via `opencode agent list` rule order and a rejected `git status` under `--agent flow-master`).** Permission evaluation is `findLast` — the *last* matching rule wins (`packages/opencode/src/permission/index.ts:28-38`), and agent-level `permission` rules are appended *after* the global ruleset. All six agents in `opencode.jsonc` declare `"permission": {"edit": "allow", "bash": "allow"}`, so their effective ruleset ends with `bash * allow`, which beats the global `git`/`gh` denies. Proven behaviorally (`git status` executed under `--agent` with that shape) and structurally (`opencode agent list` shows the allow as the last rule for `flow-master`). Only the default `build` agent is protected. Fix options: repeat the deny map inside each agent's `permission.bash`, or drop `bash` from agent-level permission so the global map applies — and the guard-bridge plugin enforces regardless (its `throw` is upstream of permission). Corollary footgun: **rule order in the config object is significant** — a `"*": "allow"` written after the denies silently disables them.

**Deployment probes:** WSL boot on TechieFlow from `/mnt/c` works (18.7s cold run incl. model call; all 6 agents + commands load, `{file:}` refs resolve). The large-repo failure is **real but is a 9p-filesystem pathology, not a Bun-in-WSL crash**: the OpenCode monorepo on `/mnt/c` timed out at 5 min stuck in the snapshot subsystem ("removing gitignored files from snapshot"), while the same repo on ext4 (`~/`) completed in 30s. Consequence for the deployment guide: moderate repos may stay on `/mnt/c`; large repos need ext4 (or snapshot/watcher tuning). Also: the WSL native binary at `~/.opencode/bin/opencode` must be put on PATH ahead of the Windows npm shim (`/mnt/c/Users/srkra/AppData/Roaming/npm/opencode`), which WSL interop otherwise resolves first — that shim is the crash-prone native-Windows Bun build. Portable `opencode-go` API key copied from the Windows `auth.json` works in WSL; no interactive login was needed. Still UNVERIFIED: TUI model re-send after a routed command; Claude `SubagentStop` transcript_path.

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
