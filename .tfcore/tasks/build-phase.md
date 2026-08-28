# build-phase

The single unified build. Implement every open REQ in `docs/{AppName}-Checklist.md` — UI, functional, RAG, and NFR — then self-smoke (data + visual) and chain the verifier automatically.

## Purpose

There is one build phase for the whole app. `build-phase` (driven by **flow-master**) reads the one checklist, clusters ALL open REQs, and fans the work out — **calling the library agents as sub-agents** rather than as separate phase commands:
- `REQ-UI-*` clusters → built by invoking **`/trblazeui`** as a sub-agent, **from the approved mockups** (`docs/{AppName}-UIDesign.md` + `docs/mockups/*.html`).
- `REQ-RAG-*` clusters → built by invoking **`/techierag`** as a sub-agent.
- `REQ-FN-*` / `REQ-NFR-*` clusters → built directly by flow-master's own general-purpose subagents.

There is no separate `build-ui-phase` / `build-rag-phase` command — those were dissolved; trblazeui and techierag are skills this phase calls.

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 0. Stamp the start time

Run `date -u +%Y-%m-%dT%H:%M:%SZ` and keep the value — it is this run's `started` for the §7a telemetry emit. It cannot be reconstructed at the end, and an invented duration is a fabricated measurement.

### 1. Required reading
1. `docs/{AppName}-Coding-Standards.md` — strict compliance (`obj` field prefix where the project uses one, `a`/`v` prefixes, no underscores, file-scoped namespace, XML docs)
2. `docs/{AppName}-Architecture.md` — module boundaries
3. `docs/{AppName}-Checklist.md` — the work list (all REQ classes)
4. **The UI design source** — greenfield: `docs/{AppName}-UIDesign.md` + `docs/mockups/*.html` (build UI to match the approved mockups); brownfield: `docs/{AppName}-DevGuide.md` (or the split set under `docs/devguides/`) for the as-built screen map.
5. The library references when their REQ classes are in scope: `.trblazeui/TrBlazeUI-AI-Reference.md` (if absent, run `dotnet build` once to deploy), `.techierag/TechieRag-AI-Reference.md`.

### 2. Scope filtering — ALL open REQs

Working list = every non-terminal REQ in the checklist, all prefixes (UI / FN / RAG / NFR). No prefix is excluded.

### 2a. Re-entry mode detection (FIX vs FRESH)

Read the **Requirements Status** table in `docs/{AppName}-Checklist.md` (the single source of truth — no separate dated coverage files). **Terminal statuses — never rebuild, never count as open:** `Verified`, `Done (pre-existing)` (migrated from a dev plan; do NOT re-implement), `N/A`.

- Any row `FAIL` / `PARTIAL` / `In Progress` / `Needs re-verify` → **FIX mode**, working list = only those REQ IDs. (`Blocked` rows are library gaps — pass through unless the blocking TR entry is marked resolved.)
- Every row terminal (or terminal + `Blocked`) → nothing to build; say so and update PROJECT-STATUS (§7).
- Otherwise → **FRESH mode**, working list = all non-terminal, non-`Blocked` REQs.

Echo one line: `Mode: FIX — N items: REQ-UI-3, REQ-FN-2` or `Mode: FRESH — N items`.

### 2b. ONE PASS = THE WHOLE WORKING LIST (owner rule 2026-08-21 — non-negotiable)

**A build pass is finished when every REQ on the working list from §2a has reached at least `Implemented` (or a genuine `Blocked`), the verifier has been chained (§6b), and its FAIL rows have been looped (§6c). Not before.** The owner's observed anti-pattern — implement some REQs, update PROJECT-STATUS with "run `*build-phase` again for the remaining REQs", end the turn — is **banned**. The point of the build phase is that *all* checklist items reach the verify stage in one go, so the owner can then call the verifier once over everything.

- **Do not shrink the working list** to "the first cluster", "the UI ones", "what fits this turn". §3 already fans the list out across parallel sub-agents; a long list means **more clusters and more sub-agents**, never a shorter pass. If your own context is filling up, delegate the remaining clusters to fresh sub-agents (each gets its REQ IDs + acceptance + the two standing rules) and keep only the cluster table + returns in your context. **Context pressure is a reason to delegate, not to stop.**
- **Wait for every cluster.** §3 says "wait for ALL sub-agents to return" — that includes clusters you spawned late to replace a failed or partial return. A cluster that comes back `PARTIAL` is re-spawned with the missing REQs before you move to §5.
- **Legitimate reasons for an open REQ to remain below `Implemented` at the end of a pass — and there are only these:** `Blocked` by a logged library gap (TR-NNN entry exists, workaround impossible); a REQ whose acceptance cannot be met without an owner-only asset (credentials, a paid account, a physical device, a product decision) — record it in PROJECT-STATUS "Known blockers" with the exact ask. "Ran out of time/turns", "large scope", "will do in the next pass" are **not** reasons.
- **The next command after a complete pass is the verifier's or the owner's, never "build again for the rest".** `*build-phase` may appear as the next command only for FIX mode (verifier `FAIL` / `Needs re-verify` rows, §6b/§7) or once a `Blocked` library gap is resolved.
- Under YOLO / goal mode (`.tfcore/tasks/_yolo-mode.md`) this section is doubly binding: there is nobody to "run it again".

### 3. Dependency analysis + parallel fan-out (MANDATORY — do not skip)

**Single-agent sequential implementation is a banned anti-pattern.** Group the working list into dependency clusters by feature, then fan out clusters in parallel — **routing each cluster to the right builder by its REQ prefix**.

Clustering rules:
- SAME cluster if REQs touch the same page/component/layout (UI), the same controller/service/DB table (FN), the same `TechieRagBuilder`/embedding/`IConversationMemory` (RAG), or one depends on a type/contract the other defines.
- DIFFERENT clusters if they share no files and no contract dependency.
- A cluster is single-prefix where possible so it routes cleanly to one builder. A mixed feature (e.g. a settings page that saves to DB) splits into a UI cluster (REQ-UI) + an FN cluster (REQ-FN) with the FN one depending on the UI contract.

Emit a one-block cluster table BEFORE fanning out, naming the builder per cluster:
```
Cluster A [trblazeui]: REQ-UI-1, REQ-UI-2  (Login page — mockup: docs/mockups/login.html)
Cluster B [flow-master]: REQ-FN-3, REQ-FN-4  (Order pipeline)
Cluster C [techierag]: REQ-RAG-1            (Doc-search RAG flow)
Cluster D [flow-master]: REQ-NFR-1          (Logging middleware)
```

Then in ONE assistant turn, spawn the clusters in parallel:
- **`[trblazeui]` clusters** — invoke `/trblazeui` as a sub-agent (Claude Code `/trblazeui …`, OpenCode `/trblazeui …`). The prompt MUST include: the cluster's REQ-UI IDs + acceptance verbatim from the checklist; **the mockup file(s) the cluster realizes + their component map** (build the screen to match the mockup — same TrBlazeUI controls, same layout); `docs/{AppName}-Coding-Standards.md` + field-prefix rule; `.trblazeui/TrBlazeUI-AI-Reference.md`; **the two standing rules verbatim (see below)**; tag each REQ's work with `[REQ-UI-N]` in the checklist Remarks (NEVER a git commit); log TrBlazeUI gaps to `docs/{AppName}-TrBlazeUI-Feedback.md` (one file per library); return `{ reqsImplemented[], filesChanged[], libraryIssues[] }`.
- **`[techierag]` clusters** — invoke `/techierag` as a sub-agent. Prompt MUST include: REQ-RAG IDs + acceptance; `.techierag/TechieRag-AI-Reference.md`; coding standards; wire via `TechieRagBuilder` / `ITechieRag` (`IngestAsync`/`SearchAsync`/`AskAsync`/`ChatWithRagAsync`), `ITokenTracker` if an NFR needs it; unit tests in `tests/unit/Rag/`; **the two standing rules verbatim (see below)**; tag work `[REQ-RAG-N]` in the checklist Remarks (NEVER a git commit); log gaps to `docs/{AppName}-TechieRag-Feedback.md` (one file per library); return contract as above + `testsAdded[]`.
- **`[flow-master]` clusters** — spawn one **builder subagent** per cluster: `tf-builder` if the harness registers it, otherwise the harness's general subagent (Claude Code: the `Agent` tool, `subagent_type=tf-builder|general-purpose`; OpenCode: the `task` tool, `subagent_type=tf-builder|general`). Prompt MUST include: REQ-FN/NFR IDs + acceptance; coding standards + field-prefix rule; architecture boundaries; **the two standing rules verbatim (see below)**; tag work `[REQ-FN-N]`/`[REQ-NFR-N]` in the checklist Remarks (NEVER a git commit) + unit tests in `tests/unit/`; log library gaps to the owning library file; return contract.

**The two standing rules — paste into EVERY sub-agent prompt (library agents don't read `.tfcore/` tasks, so the rules reach them only through you):**
1. *GIT IS MANUAL:* "NEVER run `git` or `gh` for any purpose — no commit, no `status`/`log`/`diff`/`grep`/`blame`. The harness denies it. Record your REQ IDs in the checklist Remarks, not in commits. Evidence for 'what changed' = the working-tree files you edited."
2. *SMOKE IT YOURSELF:* "Before you return, run your changed feature once against the running app yourself — headless Playwright (WSL) / the Windows-MAUI bridge / the Appium bridge are already set up; 'can't run on Linux/WSL', 'it's MAUI', 'needs a GUI' are banned excuses (`.tfcore/tasks/_smoke-test-policy.md`). Confirm the data renders AND the screen looks right; use a documented test user from the UsageGuide/DB, never an invented one. Never ask the owner to run anything."

A sub-agent that git-commits or returns un-smoked code is the orchestrator's failure — reject its return and re-prompt with the rules.

**Head naming is fixed at scaffold time — the primary head carries the PRODUCT name.** The product's primary executable head project is named exactly `{AppName}` (`src/{AppName}/{AppName}.csproj`) — **NEVER `{AppName}.App`** (a meaningless suffix; banned, owner rule 2026-07-10). A single-head product's one head IS `{AppName}`. Secondary heads of a multi-head product take a *descriptive* dotted suffix (`{AppName}.Api`, `{AppName}.Desktop`); satellites keep their conventional names (`{AppName}.Core`, `{AppName}UI` RCL, `{AppName}.Core.Tests`). If the working tree already contains a `{AppName}.App`, do not propagate the name into new code/docs — log a rename REQ in the checklist (dir + `.csproj` + sln + namespaces) and build it.

**Serilog is wired at scaffold time, not on request.** Whenever a cluster CREATES a new executable head (a web/API host, MAUI app, desktop app, console/CLI, background service), it wires Serilog file-based logging as part of the scaffold per coding-standards §Logging (rolling file sink under `logs/`, startup + unhandled-exception logging, `ILogger<T>` in app code) — even if no open REQ names logging. Day-1 BRDs carry a standing Observability NFR that split-brd turns into a `REQ-NFR-*` row; if this app's checklist predates that rule and has no logging REQ, wire it anyway and note it in the cluster's checklist Remarks. The owner never has to ask for logging.

Wait for ALL sub-agents to return, then aggregate. The orchestrator owns the build + smoke + verifier handoff (§6–§7); sub-agents own per-cluster implementation only. **Cluster of size 1 still fans out.** Skip parallelism only if the entire working list is a single tight cluster — then do it inline and note "Single-cluster — implemented sequentially."

### 4. Library issue logging (continue with workaround, do not stop)

Gaps in TrBlazeUI → `docs/{AppName}-TrBlazeUI-Feedback.md` (TR-NNN); gaps in TechieRag → `docs/{AppName}-TechieRag-Feedback.md` (TR-RAG-NNN). Create from `.tfcore/templates/v4custom/app-library-feedback-tmpl.md` on first issue. One file PER library (separate teams — never combine). Schema: Severity / Repro / Expected / Actual / Encountered in / Workaround / Suggested fix. Workaround + log + continue — never stop the build for a library gap, never silently swallow it.

### 4a. Specification-gap logging — the DESIGN miss (do not skip, do not stop)

Library gaps go in the feedback files (§4). **Specification gaps go in `misses.jsonl`.** When a REQ you are building turns out to be unbuildable as written — no acceptance criteria, a screen with no mockup, two REQs that contradict each other, a behaviour the BRD plainly needed and never named — that is a **miss made in the design phase**, and this is the only place in the framework that can see it. The verifier cannot: by the time it runs, the gap has either been papered over or built wrongly.

Do what you already do — pick the sensible reading, note it in the checklist Remark, and keep building. Then record it:

```bash
MID=$(bash .tfcore/utils/tf-emit.sh --next-miss-id)
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss","miss_id":"$MID","req_id":"REQ-FN-014","req_class":"FN",
 "miss_class":"unspecified-gap","artifact":"brd","severity":"minor",
 "why_missed":"missing-checklist-item",
 "origin_phase":"split-brd","origin_agent":"analyst",
 "origin_run_id":"<started of the split-brd/day1 run, from runs.jsonl>",
 "found_by":"agent-review","found_phase":"build-phase",
 "found_gate":null,"found_run_id":"<the §0 timestamp>","failure_class":null}
JSON
```

- **`artifact`** names the deficient document: `brd` · `architecture` · `uidesign` (a screen with no mockup) · `checklist` (a REQ with no acceptance bullet).
- **`miss_class`** is `unspecified-gap` for something never specified, `spec-contradiction` for two requirements that cannot both hold. If the spec was fine and the *previous build* got it wrong, that is `missed-requirement` / `partial-implementation` with `origin_phase:"build-phase"` instead.
- **`req_id:null` is correct** when the gap is behaviour no REQ ever covered. Do not attach it to the nearest REQ to make the record look tidier — an unowned gap is a different and more interesting finding than a thin REQ.
- **`why_missed`** (SCHEMA §5.5.6) — from this phase it is nearly always `missing-checklist-item` (nothing covered the behaviour) or `ambiguous-acceptance` (the criteria admitted two honest readings and you had to pick one). `dependency-not-declared` where the REQ needed something no document stated.
- **`severity`** here is about the *product*, not about how much it slowed you down.
- Run the `--open-miss` check first when the gap attaches to a REQ; skip it when `req_id` is `null`.

This does not change what you do next: **log and continue.** A spec gap never stops a build, never becomes a question to the owner mid-pass, and never blocks the working list (§2b). It is a record, not a gate.

### 5. Build (must PASS before self-smoke)

Run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. MANDATORY:
- **Platform probe first** — read ladder §0. In OpenCode Docker, confirm `/usr/local/bin/winrun`, `TF_WINDOWS_APP_PATH`, and the mounted `/root/.nuget/NuGet/NuGet.Config`; prove the bridge with `winrun "dotnet --info"`. Do not probe direct `cmd.exe` in the container.
- **Solution-scan second** — in OpenCode Docker, a solution containing a Windows MAUI head uses `winrun "dotnet build ..."`; a solution containing only standard .NET projects uses container `dotnet build`. Never install/check for `maui-tizen`; this image intentionally has no MAUI workloads.
- **Workload errors are wrong-rung signals, not project blockers** — `NETSDK1178`, `Microsoft.iOS.Sdk missing`, `Workload ID … not recognized` → on WSL switch to rung #4; in OpenCode Docker use `winrun` for a Windows MAUI head, and never install a workload in the container. Do NOT log these as failures.
- **Real compile errors** (CS####, missing source references) → fan out fix subagents (group by file) and retry.
- Never accept "command not found" as a stop condition — that means wrong rung, not missing dotnet.

### 6. Self-smoke — data + visual (MANDATORY — do not skip)

**Follow `.tfcore/tasks/_smoke-test-policy.md` for this whole section.** Non-negotiables from it: (1) you run the smoke yourself — "can't run on Linux / it targets Windows / it's MAUI / Playwright needs a GUI / it's multi-service / data is present so it's fine" are BANNED excuses; the headless-Playwright + Windows/MAUI bridge are already set up (use rung #4 and verify-phase §3a before ever asking the user). (2) For any smoke needing a login, use a test account from `docs/{AppName}-UsageGuide.md` or the database — NEVER auto-create random smoke users; if none exists, ask the user to confirm before creating, then record it in the UsageGuide. (3) **"it runs" means the controls RENDER THEIR DATA *and* the screen LOOKS RIGHT** — a blank table is a failed smoke (RENDER-TRUTH) and so is a screen whose controls overlap / clip / sit off-viewport (VISUAL-TRUTH).

**A green compiler is not proof the code works.** Self-smoke before chaining the verifier:

1. Boot the app yourself via the build invocation ladder (local-only — never propose cloud deploy; see verify-phase.md §Local-only deployment policy). Bring up dependent services (DB/LLM/API) yourself in dependency order if it's a multi-service stack.
2. Poll until ready (HTTP 200 or "Now listening on", up to 60s).
3. For EACH REQ implemented this phase, run a **minimal smoke**, fanned out across parallel subagents (one per cluster):
   - UI / page REQ → Playwright: page reachable AND its top-level control **renders its data** (rows present and non-empty, chart non-empty) AND the screen passes the **visual check** — no sibling-control bounding-box overlap, every control in-viewport and non-zero size, at desktop + a mobile width; capture a screenshot and eyeball it; where a mockup exists, it should match the mockup's layout.
   - API REQ → request the endpoint, expect `ok()`; for RAG: ingest→200, search→non-empty, chat→non-empty answer.
   - Pure backend REQ → run its unit test (`~/.dotnet/dotnet test --filter "FullyQualifiedName~{TypeName}"`).
4. Kill the boot process; confirm the port is free.
5. **Write the smoke results into the Requirements Status table** of `docs/{AppName}-Checklist.md` — do NOT create a `docs/qa/*-smoke-*.md` file. Per REQ set Status (`Implemented` if smoke PASS pending verifier; `FAIL`/`PARTIAL`/`Needs re-verify` otherwise), `%`, and a dated Remark (visual failures prefixed `⚠ visual:`). Playwright screenshots stay in `tests/.artifacts/`, and any throwaway smoke script you wrote stays in `tests/.artifacts/harness/` (both gitignored — **never** a repo-root `test-results/`, `test-results-<slug>/` or `scripts-<slug>/`, and never inside the project's own tracked `scripts/`; see `verify-phase.md` §1 artifact-location rule, which binds self-smokes too); only the one-line outcome goes in Remarks.

**If any smoke FAILed (data or visual):** loop back into FIX mode (§2a) on the failed REQs — route layout/overlap failures back to the `[trblazeui]` builder. Do NOT chain to the verifier with known smoke failures.

**If app failed to boot:** apply the local-fallback flow from verify-phase.md §3a (escalate, bring services up yourself, ask the user to run it only as a last resort) — never propose cloud deploy.

### 6b. Chain verifier (only after smoke is clean)

- **How to chain:** read `.tfcore/tasks/verify-phase.md` and execute it inline in THIS session with scope `all` — the scope is known, so skip its §0 question. (Do not hand back to the user; the chain is automatic.)
- **Chaining = EXECUTING, not summarizing.** "Execute verify-phase inline" means actually performing its §1–§7 steps in this session — boot per the ladder, generate + run the scoped tests, apply §4a data-render + §4b visual-truth, write the run ledger `docs/.last-verify.json` (verify-phase §6), THEN record verdicts. Your §6a self-smoke is NOT a substitute, however thorough it felt — smoke results cap at `Implemented`. **The build orchestrator NEVER writes `Verified` from its own observations**; a `Verified` status exists only downstream of an executed verify-phase run. This is enforced mechanically: the PreToolUse hook `.tfcore/hooks/guard-verify.sh` blocks any checklist write that introduces `Verified` without a same-day run ledger. If you are about to set a REQ to `Verified` and you have not executed verify-phase this session, STOP — you are self-attesting (the exact 2026-07-09 TrSetup failure this rule exists to prevent).
- Output: the verifier writes each REQ's verdict (Status / % / Remarks) **into the Requirements Status table** of `docs/{AppName}-Checklist.md` — no dated coverage file. It applies BOTH the data render gate (§4a) AND the visual-truth gate (§4b); a REQ is `Verified` only if acceptance passes AND its controls render data AND the screen looks right.
- The verifier ALSO runs the standards-compliance grep checks from `docs/{AppName}-Coding-Standards.md` §"Enforcement". Violations get noted in the offending REQ's Remarks (or a standards row) and reflected in PROJECT-STATUS standards-compliance.
- The verifier reads the current Status table as its baseline — REQs already `Verified` re-confirm fast; it prioritizes the rest.

### 6c. FIX loop after the verifier

If the verifier reports `FAIL` / `Needs re-verify` rows:

- **YOLO / goal mode ON** (`bash .tfcore/utils/tf-yolo.sh is-on` exits 0, or `TF_YOLO=1`, or the session is a `/goal` / `tf-goal.sh` run): **do not hand back.** Re-enter §2a — it detects FIX mode on exactly those rows — fan the repairs out (§3; layout/overlap → `[trblazeui]`), rebuild (§5), re-smoke (§6), re-chain the verifier (§6b) on the same scope. Repeat until every row is terminal or `Blocked`, **up to 5 FIX cycles per pass**; each cycle emits its own `runs.jsonl` record with `"mode":"fix"` (§7a). A row that is still failing after 5 cycles is marked `FAIL` with a Remark naming the cycle count and the last observed defect, and goes into PROJECT-STATUS "Known blockers" — that is the only way a FAIL row survives a YOLO pass.
- **YOLO OFF:** return to the user with the matrix + message: "Fix the flagged REQ-* items by re-running `*build-phase {AppName}` — it detects FIX mode and fans out repair subagents (layout fixes route to trblazeui). `Blocked` (library-gap) items pass through." (This — FIX mode on verifier failures — is the **only** situation where "run build-phase again" is a legitimate next step; see §2b.)

### 7. FINAL GATE — update PROJECT-STATUS.md (MANDATORY, non-skippable)

**You are NOT done until this is written. Updating PROJECT-STATUS — BOTH `PROJECT-STATUS.md` AND re-rendered `PROJECT-STATUS.html` — is the LAST action of every phase, every time; a markdown-only update is incomplete (the owner reads the HTML). Never report completion without both.** (Hard framework rule; see `.tfcore/tasks/_status-update-gate.md`.)

- **Build status (always update):** `last_verified_build: PASS` and `last_verified_date: {today YYYY-MM-DD}`. If the build failed and you somehow advanced anyway, set `FAIL` and add to "Known blockers".
- **Open requirements:** sync the checkbox list to the checklist Status table — anything not `Verified` stays open.
- **Next command — the Build → Verify → Handoff ladder, gated on the weakest open REQ** (per `_status-update-gate.md` item 5; do NOT freelance to `*verify all` just because you built something this pass):
  - **Any REQ still unbuilt** (`Planned`/`In Progress`/`PARTIAL`/`NOT-IMPLEMENTED`, or open + not implemented) → keep phase `Build`, next command = `/TechieFlow:agents:flow-master *build-phase {AppName}` (OpenCode: `/flow-master *build-phase {AppName}`) naming the open REQ IDs. Building isn't finished, so **build is next — not verify**, even if other REQs you just wired now want verification. This includes REQs that are built but **`NOT-OBSERVABLE` for lack of a test/harness** — writing that test is build work (`*build-phase` adds unit tests), so build still leads until the verifier has something to assert. **But read §2b before you write this line:** if the unbuilt REQs are unbuilt because *this pass stopped early*, you are not at the gate yet — go back to §3 and build them. This bullet describes a state the owner finds after a `Blocked`/owner-gated remainder or a crashed session, not an ending you choose.
  - **All REQs built AND observable (≥ `Implemented`, with a test/route the verifier can exercise) but some not `Verified`** → phase `Verify`, next command = `/TechieFlow:agents:verifier *verify all {AppName}` (OpenCode: `/flow-verifier *verify all {AppName}`) (or narrowest scope).
  - **All agent-verifiable REQs terminal, but open rows remain that are documented OWNER-RUN UAT** (external/host-bound/destructive — the verifier cannot exercise them from this machine) → phase `UAT`, next command = the owner-run pointer at `docs/{AppName}-UsageGuide.md §"UAT plan"` naming the open REQ IDs. **Do NOT suggest `*handoff-phase` — not even as "optional" —** if a READY-FOR-UAT handoff already ran this cycle (check the Verification log); it only leads (once) when it has never run for this cycle, because it produces the UAT bundle. Never say "nothing left" / "done" / propose `Released` while non-terminal rows remain — `Released` is the OWNER's call after UAT (_status-update-gate.md item 5).
  - **All REQs terminal** (`Verified`/`Done (pre-existing)`/`N/A`; `Blocked`-by-library counts as pass-through) → phase `Handoff`, next command = `/TechieFlow:agents:flow-master *handoff-phase {AppName}` (OpenCode: `/flow-master *handoff-phase {AppName}`) — or, if handoff already ran, the project waits on the owner to set `Released`.
- Log a verification-log row (Status table column → `docs/{AppName}-Checklist.md#requirements-status`).
- Update "Library feedback summary" counts and "Standards compliance".

### 7a. Emit the run record

Same turn as the status gate, right after it. Doctrine + the ten constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"build-phase","mode":"build",
 "started":"<the §0 timestamp>","ended":"<now>","duration_s":<n>,
 "reqs_touched":["REQ-UI-004","REQ-FN-011"],"reqs_count":2,
 "subagents":["trblazeui"],"files_written":14,"build_result":"pass"}
JSON
```

- **`mode` is the rework metric — get it right.** `"fix"` when §2a detected FIX mode (re-entry over `FAIL`/`Needs re-verify` rows), `"build"` on a FRESH pass. The ratio of the two is how the framework measures how much work is rework; a mislabelled run corrupts it silently.
- `subagents` = which of `trblazeui` / `techierag` / `general-purpose` you actually fanned out to this pass. Empty array if you built everything yourself.
- `files_written` is a count you already know — **do not shell out to compute it.**
- `build_result` = `pass` / `fail` / `not-run` — honestly, including when the phase ended badly.
- `reqs_touched` carries **REQ IDs only**. Never requirement text (constraint 7).

The verify pass chained in §6b emits its own `gates.jsonl` records **and its own `misses.jsonl` records** (verify-phase §6a) — do not emit those yourself; the verifier owns both, exactly as it owns the `Verified` verdict. The only misses this task writes are the §4a **specification gaps**, which the verifier structurally cannot see.

**In FIX mode (§2a), also close the misses you repaired.** For each REQ you re-entered that had an open miss, emit a `miss-fix` after this run record exists — it is the run record's `started` that carries the token window the fix cost is read from:

```bash
MID=$(bash .tfcore/utils/tf-emit.sh --open-miss REQ-UI-009 | cut -d' ' -f1)
[ -n "$MID" ] && FA=$(bash .tfcore/utils/tf-emit.sh --next-fix-attempt "$MID") && \
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss-fix","miss_id":"$MID","req_id":"REQ-UI-009",
 "fix_run_id":"<the §0 timestamp — this run's started>","fix_cmd":"build-phase",
 "fix_attempt":$FA,"verdict_after":"<the verifier's verdict for this REQ>","reopened":false}
JSON
```

`verdict_after` is **the verifier's verdict, not your opinion of the fix** — `Verified` only if §6b actually produced it. A miss closed on a builder's self-assessment is the same failure as a self-attested `Verified`, one stream over. Write no token or cost fields: the emitter copies them from the run you just named (constraint 10).

**Telemetry has no veto.** If the emit fails, the phase still succeeded: do not retry, do not diagnose, do not mention it.

## Output Checklist

- [ ] **ALL open `REQ-UI/FN/RAG/NFR-*` from the checklist implemented in THIS pass (§2b) — no "run build-phase again for the remaining REQs" ending; every working-list row ≥ `Implemented` or a logged `Blocked`/owner-gated blocker** (terminal rows untouched)
- [ ] Work tagged `[REQ-*]` in the checklist Remarks (never a commit — git is manual); unit tests added
- [ ] **YOLO / goal mode: FIX loop ran automatically on verifier FAIL rows (§6c, ≤5 cycles); sentinel `tf-yolo.sh done` written only if this was the goal's last phase**
- [ ] `dotnet build` passes
- [ ] **Cluster table emitted naming the builder per cluster; sub-agents (trblazeui / techierag / flow-master) fanned out in parallel** (or single-cluster note)
- [ ] UI clusters built to match the approved mockups
- [ ] **Self-smoke ran (agent ran it — no excuses); DATA-render AND VISUAL checks applied; results in the checklist Status table** (no `docs/qa/*.md` file) — per `_smoke-test-policy.md`
- [ ] Smoke used a documented/existing test user (UsageGuide table or DB) — NO random smoke-user auto-created
- [ ] **Verifier verdicts written into the checklist Status table** (Status / % / Remarks per REQ)
- [ ] Library issues (if any) logged to the owning per-library file
- [ ] Standards-compliance greps clean (or violations noted)
- [ ] **PROJECT-STATUS.md updated — FINAL GATE (phase, next command, open reqs, log row) + re-rendered HTML**
- [ ] **`runs.jsonl` record emitted (§7a) with the correct `mode` (build vs fix)**
- [ ] Specification gaps hit during the pass logged as `misses.jsonl` `unspecified-gap` records (§4a) — logged and continued, never a stop
- [ ] FIX mode only: a `miss-fix` emitted per re-entered REQ that had an open miss, carrying the **verifier's** verdict (§7a)
