# Miss telemetry — AI-First Playbook (the team edition)

**Status:** DESIGN — nothing in the Playbook is implemented yet. **The solo edition shipped its half on 2026-08-28**, so this design now has a working reference implementation to copy from rather than a sibling design document: `.tfcore/telemetry/SCHEMA.md` §5.5, `.tfcore/utils/tf-emit.sh`, `.tfcore/telemetry/tf-metrics.sh`.
**Target repo:** `/mnt/c/3AIGenCode/AI-First-Playbook` (public team edition; source of truth is the private source repo).
**Siblings:** `docs/Miss-Telemetry-TechieFlow.md` (the solo edition's version — read it first, especially its §0 implementation status) · `docs/Miss-Telemetry-TfLens.md`.

---

## 0. Requirement updates from the shipped solo edition (2026-08-28)

Seven things the TechieFlow implementation settled that change what this document asks for. All seven are cheap to adopt now and expensive to retrofit.

**0.1 — `why_missed` shipped, and the port back was not verbatim.** SCHEMA §5.5.6 carries the Playbook's six values **plus a seventh, `instruction-ignored`** — a written rule existed, in a file the agent had loaded, and was not honoured. **The decision this document reserved in §7 is still open and is now the Playbook's to make.** Two things to weigh, both learned since:

- The value earns its keep in the solo edition because a lone agent skipping a step in a long markdown task is that framework's dominant failure mode. A team edition has the same failure mode *and* a human one — a person not following the process — and those must not collapse into one label, because the second is a performance judgement about a named `actor` (see §6.1). If `instruction-ignored` is adopted here, its definition must be explicitly **agent-only**, or it will quietly become the field that ranks people.
- The other six values are identical in both editions and the field is comparable across them either way, so declining the seventh costs nothing in poolability.

**0.2 — `why_missed` is optional, and that has a reporting consequence this document did not state.** `null` means *not assessed*, never a zero in some category, so **every distribution over the field is denominated on records that carry it** and prints `n of N assessed`. The shipped reporter (`tf-metrics.sh`) does this and also surfaces `escapes_missing_why` — escapes that arrived with no `why_missed`, which are the most valuable records in the stream arriving incomplete. Phase 9 already produces this judgement in prose, so the Playbook should be able to hold the miss rate near zero; measure it rather than assume it. Add both to `playbook-validate.mjs`.

**0.3 — Confidence is derived, not authored — move it out of the agent-authored category.** §2.2's third category lists the agent-authored fields; `origin_confidence` is **not** one of them, and neither is `origin_model`. The solo edition's emitter resolves all three from the run record and **forces the model to `null` when the lookup fails, overwriting whatever the caller supplied.** `playbook-miss.mjs open` must do the same rather than trusting the caller: an agent naming its own confidence is the same hazard as an agent naming its own model, one level up. The honesty rule in §2.2 stands — *an agent may classify, but may never report a number* — with "or a provenance verdict" added.

**0.4 — "Open" needs two predicates that deliberately disagree.** The solo edition splits the lifecycle three ways and found the two questions must not be reconciled:

| Question | Predicate | Used by |
|---|---|---|
| How much work is outstanding? | latest `verdict_after ∉ {pass, abandoned}` | the backlog figure a team reads |
| Is this defect still live? | latest `verdict_after != pass` — **`abandoned` is still live** | `open --if-new`, the collapse check |

A deliberately-abandoned defect is not backlog, but the next `FAIL` on that item is still the *same* defect and must not open a second record. `deferred` is outstanding work and stays open in both. Map this onto `templates/checklist-metadata.yml`'s status vocabulary (`pass` · `fail` · `data-gap` · `blocked` · `deferred` · `abandoned`) when implementing §8.2's collapse rule, and comment the divergence in the code — a reviewer will otherwise "fix" the two to agree and break one of them.

**0.5 — Add the Playbook's equivalent of `*log-miss`, and treat it as load-bearing rather than a convenience.** The solo edition shipped a 20-second front door — a command that classifies a one-sentence report, writes the record and the checklist line, and **never boots the app, never reproduces, never touches `src/`**. The reasoning transfers to a team unchanged and gets stronger: §5's front doors all sit inside a phase, so a miss noticed *between* phases — in review, in standup, by someone who is not running the process at that moment — has nowhere to go and becomes a message in a channel. The friction of "first, reproduce it" is precisely what stops a miss being recorded, and **an unrecorded miss is the whole problem.** Suggested shape: `playbook-miss.mjs open` already exists as the primitive; wrap it in a harness command in both `harness/opencode/command/` and `harness/claude-code/commands/`, with the same hard scope rule (records and docs only) and the same `--fixed` mode for a miss reported after it was already repaired.

**0.55 — Adopt a third record kind, `miss-amend`, from day one — the two-kind design has a hole.** TechieFlow shipped with `miss` and `miss-fix` only, and the first outside user hit the gap within a day (TfLens TF-005): the append-only doctrine says *"if a record is wrong, the correction is a new record, never an edit"*, and neither kind can carry a correction. A field left `null` — most sharply a `why_missed` on a record written before the field existed — was **unreachable**: leave it empty forever, or break the rule. `misses.ndjson` inherits that hole exactly, and this document's §3 says nothing about it.

The fix, now shipped in the solo edition as SCHEMA §5.5.7, transfers unchanged:

```json
{"kind":"miss-amend","ts":"…","schema":1,"miss_id":"MISS-20260828-03","field":"why_missed","value":"insufficient-verify-method"}
```

- It may set a field that is `null`; it may **never** overwrite one that is not, including a value an earlier amend set. It completes a record rather than altering a fact, so append-only survives intact and a reader that ignores amendments sees nothing false, only less.
- **Only closed-vocabulary judgements are amendable.** The boundary is the load-bearing part: *a judgement may be completed, an observation may not.* `why_missed` is a classification the Phase 9 analyst can still make honestly next week; a phase verdict is a fact about a run that is over. Everything the joiner derives — `origin_model`, `origin_confidence`, `cost_attribution`, tokens, dollars — is excluded outright, which also keeps §2.2's honesty rule intact.
- `playbook-miss.mjs amend <miss_id> <field> <value>` is the only door, it validates the invariant itself, and it **prints its refusal** rather than failing quietly. `playbook-validate.mjs` counts orphan amends (no parent) exactly as it counts orphan `miss-fix` records, and the joiner folds amendments into the parent before computing anything — re-checking the null rule while folding, because a team's stream is merged across machines and can carry an amend and a later-written value in either order.
- **Team-edition extra:** an amend is a second person's judgement landing on someone else's record. Record it as ordinary data — never as an `actor`-attributed correction rate, per §6.1. "Who amended whom" is precisely the metric that stops people logging misses.

**Also worth carrying: a record written before a field existed is not "unassessed".** The solo edition keeps a `FIELD_SINCE` table beside its late-gates table and drops such records from that field's denominator, printing how many. Without it, adding any optional field makes the practice look worse the day it ships.

**0.6 — `fix_run_id` is omitted, never approximated.** In `--fixed` mode the solo edition omits `fix_run_id` when the repairing run cannot be identified, so the record costs `none`. Stated as a rule because the temptation is real: **do not point at a plausible-looking phase window to make a number appear.** One fabricated measurement discredits every honest cost figure beside it — the same position §4.3 already takes, applied to the one path that invites breaking it.

---

## 1. The Playbook is already most of the way there

TechieFlow had to invent the *concept* of a miss. The Playbook already has it, in prose, in the right place. Phase 9 (`/analyze-fix`, `phases/09-post-verification-bugs.md`) states the defining move outright:

> "Don't just fix the bug — **fix the checklist that let it escape.**" … For each bug it produces: the root cause; **why the Verifier missed it** — missing checklist item? insufficient Verify method? code-audit limitation?; a checklist patch…

That is the analysis. What is missing is that it stays **prose in a checklist and then the Issues file is deleted**. It cannot be counted, grouped by phase or model, or priced.

So the Playbook's version of this work is smaller and better-founded than TechieFlow's: **turn an analysis the process already performs into a durable record**, and join it to the token and cost data the plugin already captures.

## 2. Two facts that make the Playbook's version simpler than TechieFlow's

**2.1 — Cost is unambiguous.** Telemetry capture is OpenCode-only by design (`docs/Telemetry-Guide.md` §5: *"The Playbook is OpenCode-first; the Claude Code path is documented for parity but no Claude transcript parser is built or planned"*). OpenCode reports **real provider cost per message**. So unlike TechieFlow — where Claude Code and Codex yield tokens with `cost_usd: null` forever — every Playbook miss can carry a genuine dollar figure. The awkward three-harness table in the TechieFlow document has no counterpart here.

The one caveat that already exists carries over unchanged: the v2-engine cost caveat in `docs/Telemetry-Hooks.md` (`cost_usd` may read 0 on some engine versions; tokens are correct everywhere). Same caveat, same workaround, no new one.

**2.2 — The framework/harness split is already drawn.** `docs/Telemetry-Guide.md` §1 states the principle this design just extends:

> "**attempt and verdict are framework data, not harness data** — they are parsed deterministically from the checklist … Only phase, model and tokens are harness-sourced, which shrinks the fragile surface to three fields."

Miss records slot straight into that split, with one addition — a third category:

| Category | Fields | Source |
|---|---|---|
| **Harness-sourced** | `model`, `tokens_*`, `cost_usd`, `tokens_scope`, `subagents` | The plugin's turn rows. **Never self-reported** |
| **Framework-parsed** | `item_id`, `attempt`, `status`, `phase`, `actor` | Deterministic parse of the checklist metadata comments and the Verifier Run Log |
| **Agent-authored** (new) | `miss_class`, `artifact`, `severity`, `origin_phase`, `origin_agent`, `why_missed` | The Phase 9 analyst's classification, constrained to closed vocabularies |
| **Emitter-derived** (§0.3) | `origin_model`, `origin_confidence`, `cost_attribution`, every token/cost field | Resolved from the run record by `playbook-miss.mjs` / the joiner — **never accepted from the caller** |

The third category is new and needs its own honesty rule: **an agent may classify, but may never report a number.** A classification is a judgement the analyst is already making; a token count is a fact only the harness holds. Keeping that line sharp is what makes the whole stream trustworthy — the same reasoning that makes TechieFlow's `failure_class` a closed enum while `harness` is detected.

## 3. Where the records live — and why not in `events.ndjson`

The obvious move is a new `kind` on the existing stream: `events.ndjson` is already an event log with a `kind` discriminator (`phase-start` / `turn` / `phase-end`), and `scripts/playbook-telemetry.mjs` already latches phase context across it.

**Do not do that.** `docs/Telemetry-Guide.md` §6 says of `events.ndjson`: *"It's safe … but usually noise — most teams gitignore `verification/telemetry/` and keep the joined per-phase records instead."* A miss record is the opposite kind of object: it is the durable finding, it outlives the run that produced it, and it is the thing a team looks back at in three months. Putting it in a file the guidance tells people to gitignore and rotate would destroy the data by design.

**Decision: a second, durable file — `verification/telemetry/misses.ndjson`.**

- **Committed**, and explicitly carved out of the "gitignore `verification/telemetry/`" advice in §6 of the Telemetry Guide. That advice needs rewording to name the two files separately rather than the directory.
- **Never rotated.** `events.ndjson` stays transient.
- **Append-only.** A miss is opened by one record and closed by another; nothing is ever edited. Corrections are new records.
- **Written by a small CLI, not by the plugin** — the plugin only sees OpenCode events, and these records are authored during a phase. `scripts/playbook-miss.mjs` is the Playbook's counterpart to TechieFlow's `tf-emit.sh`: one append primitive, one code path, exits 0 unconditionally.

Because the file is committed, it carries a stronger privacy obligation than `events.ndjson` — see §6.

## 4. The record kinds

*(Two as designed; §0.55 adds a third, `miss-amend`.)*

### 4.1 `miss` — opened

```json
{"kind":"miss","ts":"2026-08-28T11:04:19Z","schema":1,
 "miss_id":"MISS-20260828-03","item_id":"REQ-014","feature":"CostReport",
 "miss_class":"partial-implementation","artifact":"checklist","severity":"major",
 "why_missed":"insufficient-verify-method",
 "origin_phase":"plan","origin_agent":"planner","origin_run_id":"…","origin_confidence":"linked",
 "origin_model":null,"actor":"a3f1",
 "found_by":"human","found_phase":"post-verification-bugs","found_phase_gate":"PASS",
 "project_type":"dotnet-react","harness":"opencode"}
```

**Vocabularies — closed, no free text.**

| Field | Values |
|---|---|
| `miss_class` | `missed-requirement` · `partial-implementation` · `wrong-behaviour` · `regression` · `unspecified-gap` · `spec-contradiction` · `scope-creep` · `hallucinated-api` · `standards-violation` · `other` |
| `artifact` | `plan` · `checklist` · `mockup` · `src` · `tests` · `docs` · `config` · `deployment-steps` · `other` |
| `severity` | `blocker` · `major` · `minor` |
| **`why_missed`** | `missing-checklist-item` · `insufficient-verify-method` · `code-audit-limitation` · `ambiguous-acceptance` · `dependency-not-declared` · `other`. **Optional — `null` is *not assessed*, so distributions are denominated on records that carry it (§0.2).** Whether to adopt the solo edition's seventh value `instruction-ignored` is still open — §0.1 and §7 |
| `origin_phase` | The Playbook's own ten phases: `plan` · `plan-review-gate` · `build` · `self-review` · `verify` · `verification-results-gate` · `fix` · `human-acceptance` · `post-verification-bugs` · `production-bugs` |
| `found_by` | `verifier` · `self-review` · `human` · `production` · `agent-review` |
| `found_phase_gate` | One of the allowed verification outcomes: `PASS` · `FAIL` · `PASS (code-audit)` · `FAIL (code-audit)` · `DATA-GAP` · `BLOCKED` |
| `origin_confidence` | `linked` · `inferred` · `unknown` |

**`why_missed` is the Playbook's best contribution to the shared design** — so much so that TechieFlow ported it on 2026-08-28, ahead of this document being implemented (see §7). Phase 9 already produces exactly this judgement — *missing checklist item? insufficient Verify method? code-audit limitation?* — and those three options plus a couple more are the whole vocabulary. It is the field that tells a team whether their *specification practice* or their *verification practice* is the weak one, which is a more actionable answer than any per-model count.

**Cross-edition naming — this is a rule, not a preference.** `SCHEMA.md` §11 reserves **`gate` for assertion gates** (TechieFlow: build/acceptance/render/visual/perf/standards) and **`phase_gate` for process gates** (the Playbook's ten phases and their verdicts). They are different axes and must never share a field name. Hence `found_phase_gate` here and `found_gate` in TechieFlow. Getting this wrong would make the two editions' data silently un-poolable in a way no reader could detect — the exact failure §11 was written to prevent.

**`origin_model` is looked up, never written.** `scripts/playbook-miss.mjs` resolves it from the turn rows of `origin_run_id` in `events.ndjson` if that file still exists; otherwise `null`. It is not the agent's to state, and a stale `events.ndjson` is a normal, expected condition — a null here is honest.

### 4.2 `miss-fix` — closed

```json
{"kind":"miss-fix","ts":"2026-08-28T14:52:07Z","schema":1,
 "miss_id":"MISS-20260828-03","item_id":"REQ-014",
 "fix_phase":"fix","fix_run_id":"…","fix_attempt":2,
 "verdict_after":"pass","reopened":false,
 "cost_attribution":"shared:3",
 "tokens_in":48213,"tokens_out":9120,"cost_usd":0.41,
 "tokens_scope":"tree","subagents":{"count":2,"tokens_out":1840,"cost_usd":0.06},
 "model":"anthropic/claude-sonnet-5","tier":"standard","actor":"a3f1"}
```

`verdict_after` uses the checklist's own status vocabulary from `templates/checklist-metadata.yml` — `pass` · `fail` · `data-gap` · `blocked` · `deferred` · `abandoned` — rather than inventing a parallel one.

The token, cost, `tokens_scope`, `subagents`, `model` and `tier` fields are **produced by the joiner, not typed by anyone**: `scripts/playbook-miss.mjs close` writes the identity and outcome fields, and `scripts/playbook-telemetry.mjs` fills the cost half from the turn rows in the fix phase's window. Same architecture as the existing per-phase records, so `subagents` rolls up child sessions exactly as it does today.

### 4.3 `cost_attribution` — the same guard as the solo edition

A `/fix` run that repairs three misses has one cost window.

- **`sole`** — the fix phase addressed one miss. The window is that miss's cost. A measurement.
- **`shared:<n>`** — *n* misses in one phase. Divided equally **and labelled as divided**.
- **`none`** — no window (no `events.ndjson`, telemetry not enabled, phase boundaries unresolvable).

**Reporting rule:** a headline cost-per-miss figure is computed over `sole` records only; apportioned figures appear in a separate labelled column. The Playbook's whole trust position rests on *"never estimated — a missing signal produces `null`, not a guess"* (`docs/Telemetry-Guide.md` §4), and an equal division across unequal work is a guess wearing a decimal point.

## 5. Where it gets wired

| Phase / file | Change |
|---|---|
| `phases/09-post-verification-bugs.md` | **The primary front door.** Step 2 already produces root cause + why-the-Verifier-missed-it + a checklist patch. Add step 2b: emit one `miss` per issue via `playbook-miss.mjs open`, carrying the classification the analyst just made. Step 5's "delete the transient Issues file" rule gains a precondition: **the file may only be deleted once every issue has a `miss` record** — today the rule is that its content is copied into the checklist; this adds the machine-readable half |
| `phases/10-production-bugs.md` | Same, with `found_by:"production"` |
| `phases/06-verification-results-gate.md` | Every `FAIL` / `DATA-GAP` verdict emits a `miss` with `found_by:"verifier"`. This is the high-volume, low-effort source and needs no extra judgement from anyone |
| `phases/07-fix.md` | Emits `miss-fix` for each `miss_id` the run addressed |
| `phases/03-build.md` | When the builder finds the plan or checklist incomplete: `miss_class:"unspecified-gap"`, `origin_phase:"plan"`, `found_by:"agent-review"`. **This is the design-phase capture** — the case that has no home at all today |
| `phases/04-self-review.md` | Optional: self-caught misses with `found_by:"self-review"`. Genuinely useful — a rising self-catch share is the clearest sign the build phase is improving |
| `templates/checklist-item-template.md` | The metadata comment gains `"misses":[]` beside the existing `"evidence":[]` — an array of `miss_id`s, so an item's history is legible from the checklist alone. Document it in `templates/checklist-metadata.yml` (`required` list and a `misses` block) |
| `templates/issues-file-template.md` | Note that each issue becomes a `miss` record, and that deletion is now gated on that |
| `scripts/playbook-miss.mjs` | **New.** `open` / `close` / **`amend`** (§0.55) / `next-id` / `list`. Fire-and-forget, error-isolated, exits 0 unconditionally, opt-in under the same `PLAYBOOK_TELEMETRY=1` flag |
| `scripts/playbook-telemetry.mjs` | Join miss records to phase windows; fill the `miss-fix` cost half; a `--misses` output mode |
| `scripts/playbook-validate.mjs` | Validate the vocabularies and the `miss_id` ↔ `miss-fix` linkage; report orphans. Also (§0.2): the `why_missed` assessed-count `n of N`, and escapes arriving with no `why_missed` |
| **A log-a-miss harness command** (§0.5) | **New, recommended.** The between-phases front door — one sentence in, one record + one checklist line out; never boots, never reproduces, never touches `src/`. Wraps `playbook-miss.mjs open`, carries a `--fixed` mode. Both harness trees |
| `harness/opencode/command/{analyze-fix,fix,verify,implement}.md` and the `harness/claude-code/commands/` counterparts | The emit steps. **Both harness trees must stay in step** even though only OpenCode captures cost — the classification half of a record is harness-independent and degrades to `cost_usd:null` on Claude, which is exactly how `granularity:"session"` already degrades |
| `scripts/install.mjs`, `scripts/harness-install.mjs` | Ship the new script; ensure `verification/telemetry/misses.ndjson` is **not** caught by any generated ignore rule |
| `docs/Telemetry-Guide.md` | New section; **rewrite §6's gitignore advice** to name `events.ndjson` (rotatable) and `misses.ndjson` (durable, committed) separately |
| `docs/Telemetry-Hooks.md` | The capture-point evidence for the new records |
| `docs/Model-Routing-Guide.md` | Miss rate per tier is a stronger routing signal than attempt-count alone — §3's "is the tier map right?" question gains a second axis |
| `docs/Adoption-Metrics.md` | Its weekly review list already names *escaped defects* and *rework*; both become measured rather than eyeballed |
| `docs/Decisions.md` | Record the two decisions that will be re-litigated: the separate durable file (and why not `events.ndjson`), and agent-authored classification (and why it does not breach "never self-reported") |

## 6. Team-edition concerns the solo edition does not have

**6.1 — `actor`, and the line it must not cross.** `SCHEMA.md` §11 already reserves `actor` as the team edition's one extra field. A miss stream is where that field becomes dangerous: a per-person miss count is a performance metric, and a performance metric changes behaviour — people stop logging misses. That destroys the data and the practice at the same time.

**Rule: `actor` is aggregate-only.** It exists so a team can see whether misses cluster around an unfamiliar area of the codebase or an under-documented service — never to rank people. No report, export or dashboard may present a miss figure broken down by `actor`. Write this into the Telemetry Guide as a stated policy, not a convention, because the field is trivially groupable and someone will try.

**6.2 — Privacy is stricter here than in `events.ndjson`.** That file carries only counts and ids and is usually gitignored. `misses.ndjson` is **committed to an employer's repository**, so the closed vocabularies are not stylistic — they are the control. No issue title, no reproduction steps, no expected/actual text, no file contents. `item_id` and file paths are the ceiling, matching `templates/checklist-metadata.yml`'s `prohibited` list (credentials, tokens, secrets, unredacted PII) and its `allowed_classes`.

**6.3 — Retention.** `checklist-metadata.yml` sets `evidence.retention_days: 180`. Miss records are aggregate history and should outlive that, but the decision belongs to the team, not to this document. Recommendation: keep `miss` records indefinitely (they carry no content) and let the pointer into any evidence expire on the existing schedule.

## 7. Cross-edition compatibility with TechieFlow

The two editions emit **related but deliberately non-identical** miss records, and the differences must be intentional and documented rather than accidental:

| Concern | TechieFlow | Playbook |
|---|---|---|
| File | `docs/metrics/misses.jsonl` | `verification/telemetry/misses.ndjson` |
| Record kinds | `miss` · `miss-fix` · `miss-amend` (§0.55) | same three, if §0.55 is adopted |
| Work item | `req_id` | `item_id` |
| Process axis | `found_gate` (assertion gates) | `found_phase_gate` (process gates) — **SCHEMA.md §11** |
| Phase enum | `runs.jsonl.cmd` values | the ten Playbook phase names |
| Dollars | OpenCode only; `null` on Claude/Codex | real everywhere |
| `why_missed` | **ported and shipped 2026-08-28** (SCHEMA §5.5.6), plus `instruction-ignored` | six values; the seventh is an open decision (§0.1) |
| Front door for a one-line report | `*log-miss` — shipped; no boot, no repro (§0.5) | **no counterpart yet** — recommended |
| `actor` | absent (solo) | present, aggregate-only |

**`why_missed` was ported into TechieFlow on 2026-08-28 and is now shipped and collecting there** (SCHEMA §5.5.6) — ahead of this document being implemented, because the vocabulary proved itself immediately: TechieFlow's own first miss records had nowhere to say that a written rule went unfollowed. `miss_class` says *what* was missed; `why_missed` says *which practice failed*, and it is the most decision-changing field in either design.

The port is **not verbatim**. TechieFlow adds a seventh value, **`instruction-ignored`** — a written framework rule existed and was not honoured — because an agent skipping a step in a long markdown task is that framework's dominant failure mode, and none of the Playbook's six values covers it (it is not a spec gap, not a weak verify method, and no gate change fixes it). The other six are identical, so the field stays comparable across editions. **When this document is implemented, decide deliberately whether `instruction-ignored` belongs here too** — a team edition may want to name the person-facing version of that differently, or not carry it at all. Do not assume it transfers.

Shared, non-negotiable across both editions: append-only · closed vocabularies, no free text · numbers never self-reported · attribution looked up or `null` · apportioned cost never blended with measured cost · telemetry never blocks a run.

## 8. Decisions taken (owner-approved 2026-08-28)

**8.1 — `misses.ndjson` is committed by default.** A record a team has to opt into keeping is a record that does not exist by the time anyone wants it. The privacy control is the closed vocabulary, not the gitignore — which is why §6.2's vocabulary discipline is not negotiable.

**8.2 — Phase 6 auto-emits on every `FAIL` / `DATA-GAP`, and `found_by` does the separating.** It is the highest-volume source and needs no human judgement. The stream being dominated by ordinary in-cycle failures is not a problem — an in-cycle `FAIL` and a production escape are both misses, and **the interesting number is the ratio between them**, which only exists if both are recorded. Reports segment on `found_by`; they never filter one out.

The same collapse rule as the solo edition applies (`Miss-Telemetry-TechieFlow.md` §8.1): before emitting, check for an **open** miss on the same `item_id` with the same `miss_class` and emit nothing if one exists. `playbook-miss.mjs open --if-new` performs the check, so the phase command never has to. **Use the *still-live* predicate here, not the backlog one** — `abandoned` collapses, `pass` does not; see §0.4.

**8.3 — No rendered report inside the Playbook.** The Telemetry Guide deliberately stops at *"ready for `jq`, a spreadsheet, or your dashboard of choice"*, and that line holds. TfLens is the dashboard. A second report built inside the Playbook would fork the metric definitions between two codebases, and the first time the two disagreed neither would be trusted again.
