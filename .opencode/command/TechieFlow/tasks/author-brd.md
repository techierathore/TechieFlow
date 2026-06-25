# author-brd

Author or extend a Business Requirements Document (BRD) with stable BRD-N requirement IDs, using interactive elicitation. The analyst NEVER assumes a requirement — each candidate is confirmed by the user before it lands in the BRD.

> **When to use:** this is the INTERACTIVE alternative for extending an existing BRD requirement-by-requirement. For creating a project's BRD, the default path is `*day1-brownfield` / `*day1-greenfield` (bulk draft, no per-item confirmation).

## Purpose

Produce a BRD where every business/functional requirement has a unique, stable, append-only ID (`BRD-1`, `BRD-2`, …) that downstream agents (UI agent, orchestrator, verifier) can declare and verify against. Eliminate the "implicit requirement" problem by forcing per-item user confirmation.

## elicit

elicit=true — this task REQUIRES user interaction. Never skip elicitation for efficiency.

## Inputs

- `{AppName}` argument (required for the canonical filename; ask once if missing).
- `{topic}` argument (optional) — the product/feature area. If absent, ask once: "What's the topic / product area for this BRD?"
- Existing BRD path. Resolve in this order: `core-config.yaml → customTechnicalDocuments`, then `docs/{AppName}-BRD.md` (legacy fallbacks: `docs/brd.md`, `docs/BRD.md`). If found, OPEN it and continue from the highest existing BRD-N. If not found, create `docs/{AppName}-BRD.md` from `.tfcore/templates/v4custom/app-brd-tmpl.md` (feature catalog + §10 BRD-N ledger shape — NOT ad-hoc "Phase N" sections).

## SEQUENTIAL Execution

### 1. Read or scaffold the BRD

- If the resolved BRD exists: read it, parse all existing `BRD-{N}` IDs, and record the highest N. New requirements continue from N+1.
- If absent: scaffold `docs/{AppName}-BRD.md` from `.tfcore/templates/v4custom/app-brd-tmpl.md` (leave unconfirmed sections empty; confirmed requirements land in the §10 ledger).
- Ask the user which areas they want to scope today.

### 2. Drive elicitation per area, one at a time

For each area the user wants to cover (UI, data, workflow, NFRs, etc.):

1. Generate a numbered list of CANDIDATE requirements for that area — 3 to 7 items, written as one-line "user can X" / "system shall Y" statements. Do NOT assign BRD-N IDs yet.
2. Present the list and ask the user to (a) accept, (b) reject, (c) refine, or (d) add their own — one item at a time. Use this exact prompt format:
   ```
   Candidate requirements for {area}:
   1. {candidate}
   2. {candidate}
   ...
   For each, reply: keep / drop / refine: <new text>. Or add a new one with: add: <text>.
   ```
3. After the user processes each item, assign the next BRD-N to every KEPT or REFINED item, in the order they were confirmed. Show the assignments back:
   ```
   Assigned:
   - BRD-{N}: {final text}
   - BRD-{N+1}: {final text}
   ```
4. Append the assigned requirements to the §10 Functional-requirements ledger of the resolved BRD file (and flesh out / create the owning feature-catalog entry).

Repeat for each area until the user says they're done with this BRD pass.

### 3. NFRs and acceptance criteria (optional pass)

If the user wants NFRs (performance, accessibility, browser support, etc.) or acceptance criteria for any BRD-N, run the same elicitation pattern. NFRs get their own BRD-N IDs (do NOT use a separate `NFR-N` series — keep one ID space so the verifier can grade everything uniformly).

### 4. Final output

Append/refresh the footer block of the BRD:
```
---
Last updated: {YYYY-MM-DD}
Highest BRD ID: BRD-{N}
```

Print a compact summary to the user:
```
BRD updated → docs/{AppName}-BRD.md
Added: BRD-{a}..BRD-{b} ({count} requirements)
Phases touched: {list}
```

HALT.

## Hard rules

- elicit=true — never batch-confirm; one item at a time.
- BRD-N IDs are append-only — never renumber an existing ID even if the user removes a requirement later (mark it `~~BRD-N~~ (removed)` instead).
- Requirements are written as observable outcomes, not implementation hints. The verifier needs to be able to test them.
- The analyst writes the BRD; the analyst does NOT implement anything.
