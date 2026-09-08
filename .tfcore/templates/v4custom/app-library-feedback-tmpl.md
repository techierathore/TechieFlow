<!-- tf-schema
doc: feedback
file: docs/{App}-{Upstream}-Feedback.md
header: App, Upstream, Updated
section: Summary | required | max 200
section: Entries | required
section: Replies from* | optional
section: Resolution status* | optional
entries: Entries |
per-entry: 120 250
rule: entry-feedback-fields
rule: entry-blocks-line
rule: feedback-blocking-count
rule: no-glossary
-->
<!-- Authoring notes (agent only; never visible text).

     ONE FEEDBACK FILE PER UPSTREAM — never a combined file. Each upstream owns a
     separate codebase and receives only its own file:

       docs/{App}-TrBlazeUI-Feedback.md    ids TR-NNN        (the UI library)
       docs/{App}-TechieRag-Feedback.md    ids TR-RAG-NNN    (the RAG library)
       docs/{App}-TechieFlow-Feedback.md   ids TF-NNN        (the framework itself)

     A future library {LibName} gets docs/{App}-{LibName}-Feedback.md with its own
     prefix. Create the file on the FIRST entry for that upstream.

     REPORTING IS NEVER REFUSED. If something upstream is wrong, file it — whatever
     the severity, whatever the day. What this schema constrains is the SHAPE, not
     the right to report:

     1. Every entry says whether it BLOCKS the work, in one word. That is the field
        the owner reads first, and it decides whether the run stops.
     2. A non-blocking entry is filed and the work CONTINUES. Never stop, never ask,
        never write a page of analysis about it mid-run. One entry, then carry on.
     3. 250 words for the REPORT, hard: the eight fields, and nothing else. An entry is
        a bug report, not an essay. Evidence goes in a code block, not in prose.
        Working-out that is genuinely worth keeping goes under a `#### Detail` heading
        inside the entry, and is not counted — so a thorough analysis costs nothing and
        an unreadable entry is still refused.
     4. Plain English. No coined terms, no framework shorthand, no word the reader
        would have to look up. If you find yourself writing a glossary, the words
        are wrong — change the words. `rule: no-glossary` refuses the section.
     5. A decision for the owner does NOT go in this file. It goes in a Decision
        Request (`app-decision-request-tmpl.md`), which is written for the owner and
        carries the prompt to paste back.

     "Replies from {Upstream}" holds the upstream team's answers, newest block first.
     Ids are append-only and never renumbered. A fixed entry keeps its body and gains
     a resolution line; the record of what was wrong is the point. -->

# {Upstream} feedback — found while building {App}

| | |
|---|---|
| App | {App} |
| Upstream | {Upstream} |
| Updated | {YYYY-MM-DD} |

## Summary

{N} entries: {n} blocking now, {n} filed and not blocking, {n} fixed upstream.

{One sentence naming what is blocked right now, or the sentence "Nothing is blocked."}

## Entries

### {TF-001} — {one line saying what is wrong}

- **Severity:** blocker | major | minor
- **Blocks:** yes — {the row or command that cannot proceed} | no — {what was done instead, and the work carried on}
- **Repro:** {the shortest command or snippet that shows it}
- **Expected:** {what should have happened}
- **Actual:** {what happened}
- **Encountered in:** {REQ-UI-013, or the command that was running}
- **Workaround:** {what was done in this project, or "none"}
- **Suggested fix:** {one concrete change for the upstream team}

#### Detail

{Optional, and not counted against the 250 words: the root cause, the reasoning, the
longer version of the fix. Everything above must stand on its own without it.}

## Replies from {Upstream}

<!-- The upstream team's answers, newest block first. Left in full: this is the record. -->
