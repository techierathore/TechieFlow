<!-- tf-schema
doc: uidesign
file: docs/{App}-P{n}-UIDesign.md
header: App, Kind, Size
section: Screens | required
section: Where the rest lives | required
entries: Screens | Screen:
per-entry: 250 400
rule: entry-mockup
rule: entry-regions-table
rule: entry-fields-table
rule: entry-states
rule: mockup-links
rule: phase-pointer
-->
<!-- Authoring notes (agent only; never visible text).
     A phase UIDesign is phase 2 onward of a Large project. Phase 1 is docs/{App}-UIDesign.md, written
     from app-uidesign-tmpl.md, and it holds everything the whole application shares: the UI library
     and theme in its header, the Design system, the one Click-through flow across every phase (the
     mockup folder is one set), and the Branding guide. A phase UIDesign never repeats them — two
     copies become two answers the day one changes (owner, 2026-09-11, after TfLens TF-024). It holds
     one `### Screen: Name (/route)` per screen in this phase's row of docs/{App}-Phases.md, written
     exactly as in phase 1, and a "Where the rest lives" table linking back to the phase-1 UIDesign.
     A new screen that changes the flow is added to phase 1's Click-through flow, not drawn here.
     The header carries "| Phase | n of m |" (the checker refuses the file without it). -->

# {App} — UI Design — Phase {n}: {Phase name}

| | |
|---|---|
| App | {App} |
| Kind | app or library |
| Size | Small or Medium (this phase on its own) |
| Phase | {n} of {m} |

## Screens

### Screen: {Name} (`/route`)

**Mockup:** [mockups/{screen-slug}.html](mockups/{screen-slug}.html) · **Roles:** {who reaches it} · **BRD:** BRD-{N}

| Region | Control | Shows or binds |
|---|---|---|
| {Main list} | {control} | {…} |

| Field | Type | Required | Validation |
|---|---|---|---|
| {Title} | text | yes | {1 to 120 characters} |

**Dialogs opened here:** {Dialog name: fields …; or "none"}

**States:** empty: {…} · loading: {…} · error: {…}

## Where the rest lives

| What | Where |
|---|---|
| UI library, theme and the design system | [phase 1 UI design]({App}-UIDesign.md) |
| The click-through flow across every phase | [phase 1 UI design]({App}-UIDesign.md) |
| This phase's requirements | [{App}-P{n}-BRD.md]({App}-P{n}-BRD.md) |
