<!-- tf-schema
doc: brief
file: docs/{App}-Brief.md
header: App, Date
section: What it is | required | max 150
section: Who it is for | required | max 150
section: Must do | required
section: Out of scope | required | max 150
section: Open questions | optional | max 150
rule: brief-must-do
rule: no-glossary
target-lines: 60
max-lines: 120
-->
<!-- Authoring notes (agent only; never visible text).

     The brief is the input to day-1: `*day1-greenfield` and `*day1-brownfield` read it
     and turn it into the Architecture, the BRD and the mockups. Its whole job is to be
     ONE PAGE the owner can read and correct in two minutes, before anything expensive
     is built on it.

     It replaced a 221-line inherited template (2026-09-08) whose twelve sections —
     executive summary, problem statement, proposed solution, goals and metrics, KPIs,
     post-MVP vision, expansion opportunities — produced a document nobody read and
     nothing checked. What the framework's own review says a brief is: "a one-page
     brief: product, users, must-do, out of scope". That is what this template holds.

     Each "Must do" line becomes one or more BRD items at day-1, so write them as
     things the product does, one per line, numbered. Not features to build: outcomes
     a user gets. If a line needs a paragraph to explain it, it is two lines.

     "Open questions" is where a decision the owner has not taken goes, so day-1 asks
     rather than assumes. An empty brief with three honest open questions is worth more
     than a full one built on guesses. -->

# {App} — Brief

| | |
|---|---|
| App | {App} |
| Date | {YYYY-MM-DD} |

## What it is

{Two or three sentences, at most 150 words. What the product does, in the words you
would use to a person who has never heard of it. No technology.}

## Who it is for

{Who uses it and what they are trying to get done. Name each role. At most 150 words.}

## Must do

1. {One thing the product does, as an outcome a user gets.}
2. {Another.}
3. {Another.}

## Out of scope

{What this is deliberately not doing, so day-1 does not build it. At most 150 words.}

## Open questions

{A decision not yet taken, one per line, so day-1 asks instead of assuming. Delete the
section when there are none.}
