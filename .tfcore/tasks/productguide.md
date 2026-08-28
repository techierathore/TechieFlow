# productguide

Generate (or incrementally refresh) the **end-user Product Guide** — the screenshot-illustrated, task-oriented manual that teaches an *external user* how to use the app, screen by screen. It is the user-facing sibling of the DevGuide: same screen inventory and the **same captured screenshots**, but re-told as "what this is for / how to do it" instead of code lineage.

Output: `docs/{AppName}-ProductGuide.md` (single doc, small apps) **or** a `docs/productguides/` subfolder with an index + one `docs/productguides/{AppName}-ProductGuide-{Role}.md` per role (large apps) — **always with a sibling `.html`** (it is a human-facing doc, so MD + HTML are both mandatory, every time). Template: `.tfcore/templates/v4custom/app-productguide-tmpl.md`.

## When to use

- **Whenever you need user-facing documentation** — for onboarding, a help site, a manual, app-store/marketing copy, or handing the product to non-technical users. On-demand by design (`*productguide {AppName}`).
- **Re-runnable**: `--update` refreshes only changed screens (and re-shoots their screenshots) — cheap to keep current as the UI evolves.
- It is purely a documentation task — it **never edits source code**.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Scope}` — OPTIONAL: `all` (default) · a role name · a screen/route · a comma-list. Limits which screens are (re)written.
- `--update` — OPTIONAL: incremental refresh — only re-write screens whose UI changed since the guide's last generation (or only `{Scope}`), preserving every unchanged section verbatim.
- `--single` / `--split` — OPTIONAL: force the structure instead of auto-deciding (same rule as devguide §3).

## SEQUENTIAL Execution

### 1. Confirm there is a built, runnable UI

The Product Guide documents the real running app. If the repo is doc-only / not yet built (e.g. greenfield before any build), HALT: "No built UI yet — the Product Guide documents the running app with real screenshots. Build first, then run `*productguide {AppName}`." (A greenfield app gets its Product Guide AFTER it is built, exactly like its DevGuide.)

### 2. Gather the screen inventory + screenshots (reuse, don't reinvent)

The DevGuide already did the hard discovery work — reuse it:
- Read the **DevGuide** (`docs/{AppName}-DevGuide.md`, or the split set under `docs/devguides/`) for the role→menu map, the screen list, the real post-login landing per role (LANDING-TRUTH), and each screen's purpose.
- Use the **screenshots** the DevGuide's OBSERVE pass captured under `docs/screenshots/{AppName}/` (`{role}-{screen-slug}.png`, + `-mobile` where present). These are the images the guide embeds.
- Read the **BRD** §9 feature catalog (feature purpose/benefit, personas) and the **UsageGuide** (user flows + known limitations) for the plain-language "what it's for" and "tips".

**If screenshots are missing or stale** (no DevGuide ran OBSERVE, or the UI changed): capture them yourself before writing — boot the app and screenshot each in-scope screen via the **verifier render sweep** (`.tfcore/tasks/verify-phase.md §4a`, the same mechanism devguide §5a uses), saving to `docs/screenshots/{AppName}/`. Follow `.tfcore/tasks/_smoke-test-policy.md` (you run it yourself; bring up multi-service stacks; documented test users; "can't run on Linux" is banned). If the app genuinely cannot be booted after the full escalation, HALT and tell the user to bring the stack up — a Product Guide with no real screenshots is not acceptable (do NOT fabricate images or ship a screenshot-less guide silently).

### 3. Decide structure — single doc vs per-role split

Same rule as devguide §3: **split per role** when `roles ≥ 3` OR `screens > 12` OR any role has `> 8` screens; else single. Honor `--single`/`--split`. A split guide lives in `docs/productguides/` (index + per-role files co-located, so relative links resolve); a single guide is `docs/{AppName}-ProductGuide.md`. On a structure switch (single↔split), move/delete the stale-location copy so only one canonical copy survives.

### 4. Write the guide — END-USER voice, screenshot per screen (FAN OUT per role)

Fan out one subagent per role (or screen-cluster) to bound tokens, each scoped to its slice. From the template, for each in-scope screen write a `### {Feature / Screen}` block:
- **What it's for** — the user benefit in plain language (from the BRD feature catalog), NOT code or architecture.
- **How to use it** — numbered, task-oriented steps a real user follows (click X, enter Y, see Z), in navigation order.
- **The real screenshot** — embed `![{screen}](<rel>/screenshots/{AppName}/{role}-{screen-slug}.png)` (path relative to where the guide lives: `screenshots/...` from `docs/`, `../screenshots/...` from `docs/productguides/`).
- **Tips & notes** — gotchas/limits in plain language (translate any UsageGuide "known limitation" into user terms; never expose REQ/defect IDs or internal jargon).

Order screens the way a user would actually move through them (the DevGuide menu map). Omit pure-plumbing/internal screens an external user never sees (unless writing the admin-role guide). Fill the template header (Welcome, Getting started with the sign-in shot, Roles at a glance) from the BRD + DevGuide.

**Voice rule:** this is for someone who has never seen the code and may not be technical. No file paths, no service/proc names, no REQ IDs, no architecture. If a sentence would only make sense to a developer, it belongs in the DevGuide, not here.

For `--update`: locate the existing guide (either layout), re-write only changed/in-scope screens (re-shoot their screenshots), preserve the rest verbatim.

### 5. Render to HTML (MANDATORY — both MD and HTML, every time)

Render every produced markdown to a sibling `.html` via `.tfcore/tasks/generate-html.md` (shared shell — light/dark theme, TOC). The Product Guide is a human-facing doc, so **MD + HTML are both required**; a markdown-only Product Guide is an incomplete deliverable. For a split guide, render the index + every role file in place inside `docs/productguides/`. (The checklist is the only doc that stays markdown-only; this is not that.)

### 6. Note it in PROJECT-STATUS (light touch — NOT the full gate)

Add/refresh one line under "Where I am" / artifacts: `Product Guide generated {date}: docs/{AppName}-ProductGuide.md (single) or docs/productguides/ (split) (+ .html); {M} screens, {S} screenshots`. This task does not change build/verify state — do not touch `current_phase` or `last_verified_build`. Re-render `PROJECT-STATUS.html` only if you edited it.

### 6a. Emit the run record (telemetry)

Same turn as the status/PROJECT-STATUS write. Doctrine + the ten constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"productguide","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":[],"reqs_count":0,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`reqs_touched` carries REQ IDs only — never requirement text — and `[]` is correct when this task touched no specific REQ. **Telemetry has no veto:** if the emit fails, the phase still succeeded; do not retry, do not diagnose, do not mention it.

### 7. HALT — report

```
# Product Guide — {AppName}
Structure: {single | split per role (R files)}
Roles: {list}   Screens documented: {M}   Screenshots used/captured: {S} (existing {e} / newly captured {c})
Files: docs/{AppName}-ProductGuide.md (single) — or docs/productguides/{AppName}-ProductGuide.md + -{Role}.md ... — and sibling .html (always)
Next: open the .html in a browser; run `*productguide {AppName} --update` after UI changes.
```

## Hard rules

- **End-user voice, never developer.** No code paths, service/proc names, REQ/defect IDs, or architecture. If it only makes sense to a developer, it's not Product-Guide content.
- **Every screen carries a REAL screenshot** (reused from the DevGuide's `docs/screenshots/{AppName}/`, or freshly captured via the verifier render sweep). Never fabricate an image; never ship a screenshot-less guide silently — HALT and ask for the app to be booted if capture genuinely fails.
- **MD + HTML always.** This is a human-facing doc; both versions are mandatory on every run (unlike the checklist, which is markdown-only).
- **Never edit source code.** Documentation only.
- **Reuse the DevGuide's discovery + screenshots** rather than re-deriving the screen map — they share the same screen inventory (developers' view vs users' view of the same screens).
- **Incremental by default on `--update`.** Preserve unchanged screens verbatim; only re-write + re-shoot what changed.
- **Boot the app yourself if screenshots are missing** (incl. multi-service stacks; documented test users) per `_smoke-test-policy.md`; asking the user is the last resort. Never run git.

## Output Checklist

- [ ] Built UI confirmed (HALT if doc-only / not yet built)
- [ ] Screen inventory + screenshots reused from the DevGuide (`docs/screenshots/{AppName}/`), or freshly captured via the render sweep where missing/stale
- [ ] Structure decided (single vs split per role) with stated reason / honored `--single`/`--split`
- [ ] Each screen block: plain-language "what it's for" + numbered "how to use it" + a REAL screenshot + tips — END-USER voice (no code/proc/REQ-ID/architecture)
- [ ] Header sections (Welcome, Getting started w/ sign-in shot, Roles at a glance) filled from BRD + DevGuide
- [ ] **Both MD and HTML produced** (index + role files if split) — HTML is mandatory, not optional
- [ ] PROJECT-STATUS got the one-line Product Guide note (no full status gate)
- [ ] Report printed with structure, counts, screenshots used/captured
