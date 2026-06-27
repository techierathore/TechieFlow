# {AppName} — UI Design Spec (Mockups)

> **What this is.** The approved visual design for {AppName}, produced at day-1 (greenfield) before any UI is built. Each screen has a **rendered mockup** (`docs/mockups/{screen}.html`, styled to look like TrBlazeUI) and a **component map** that ties every region to a real **TrBlazeUI control**, so the build (`/trblazeui`) reproduces it 1:1 and the verifier's visual-truth gate (`verify-phase.md §4b`) can diff the live screen against it. This is a HUMAN document → rendered to HTML. The owner APPROVES it (alongside the BRD + Architecture) before build.

## Table of Contents

<!-- Auto-maintained. Slug rule: .tfcore/templates/v4custom/html-render-shell.md §1. List each `### Screen: ...` under "Screens". -->

1. [How to use](#how-to-use)
2. [Design system (TrBlazeUI)](#design-system-trblazeui)
3. [Screens](#screens)

## How to use

- Every screen below links to its rendered mockup in `docs/mockups/`. Open those `.html` files in a browser to see the intended layout.
- The **Component map** is the build contract: `region → TrBlazeUI control`. Only controls that actually exist in the TrBlazeUI library are used (the analyst read the component catalog first). If a screen needs something the library lacks, it is flagged here and logged to `docs/{AppName}-TrBlazeUI-Feedback.md`.
- To change a screen after approval: run `*mockups {AppName} --update` (or `*amend-docs` for a requirement change that adds screens).

## Design system (TrBlazeUI)

- **Source:** TrBlazeUI component library (`.trblazeui/TrBlazeUI-AI-Reference.md`). Mockups use its components and design language (spacing, color tokens, typography) so they are replicable in Blazor.
- **Layout shell:** {top nav / sidebar / both — name the TrBlazeUI layout components}.
- **Theme:** light/dark per the shared shell; warm off-white light default.
- **Controls inventory used:** {list the TrBlazeUI controls this app's screens rely on — e.g. `TrNavMenu`, `TrCard`, `TrDataGrid`, `TrForm`, `TrButton`, `TrChart`, `TrDialog`}.

## Screens

<!-- One `### Screen: ...` per key screen from the BRD §9 feature catalog. Each has its mockup link,
     a component map (region → TrBlazeUI control + the data it shows), and state notes. -->

### Screen: Dashboard (`/dashboard`)

**Mockup:** [docs/mockups/dashboard.html](./mockups/dashboard.html) · **Role(s):** {who reaches it} · **BRD:** BRD-X · **REQ:** REQ-UI-001

**Layout (one line):** top nav fixed; 3-card KPI row; full-width chart below; recent-activity table at the bottom.

**Component map:**

| Region | TrBlazeUI control | Shows / binds | States |
|--------|-------------------|---------------|--------|
| Top nav | `TrNavMenu` | logo, user menu, theme toggle | — |
| KPI row | 3× `TrCard` | {metric} each | loading skeleton; zero-state |
| Trend chart | `TrChart` (line) | {series} | empty: "no data yet" |
| Activity | `TrDataGrid` | {columns} | empty row message; paged |

**Notes / interactions:** {sort, filter, drill-through, responsive behavior — what collapses/stacks at mobile width}.

**Empty / loading / error:** {what each control shows when there's no data, while loading, on error — the verifier checks these aren't blank-but-broken}.
