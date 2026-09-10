<!-- tf-schema
doc: decision-request
file: docs/{App}-Decision-Request.md
header: App, Written, Waiting on
section: What happened | required | max 250
section: What I need you to decide | required
section: What I do when you answer | required | max 200
section: Copy this back to me | required | max 250
entries: What I need you to decide |
per-entry: 150 300
rule: entry-decision-options
rule: entry-recommendation
rule: paste-back-block
rule: no-glossary
target-lines: 120
max-lines: 260
-->
<!-- Authoring notes (agent only; never visible text).

     WHEN TO WRITE ONE. A command has hit a choice only the owner can make and the
     answer changes what gets built. Write this file, render it to HTML, and say one
     line in the terminal: which file to open, and that it holds N decisions. Never
     argue the decision out in the terminal — that fills the context and buries the
     question. Everything the owner needs is in the file.

     WHO READS IT. The owner, and nobody else. No task ever loads a Decision Request
     as input, and it is never named in core-config.yaml. The way the answer comes
     back is the owner pasting the block from §"Copy this back to me" — that pasted
     prompt is the input, and the file's job is done the moment it is answered.

     HOW IT IS WRITTEN. Plain, simple English, the way you would explain it to
     someone who has not read a line of the framework. No coined terms. No framework
     shorthand. No requirement ids in the question itself — name the thing, not its
     number. If a word needs defining, it is the wrong word: change it. A glossary
     section is refused by `rule: no-glossary`, because a document that has to teach
     its own vocabulary before it can ask its question was written for the wrong
     reader.

     WHAT IT IS NOT. Not a defect report — that is the feedback file. Not an
     architecture decision record — that is DECISIONS.md, written after the fact.
     This file asks a question and then stops existing: when it is answered, it moves
     unchanged to docs/OldDocs/ and the live name is free for the next one.

     ONE LIVE FILE. All open decisions go in this one file as separate entries. Never
     a dated copy, never a -v2. -->

# {App} — decisions I need from you

| | |
|---|---|
| App | {App} |
| Written | {YYYY-MM-DD} |
| Waiting on | {N} decisions. Nothing has been changed yet. |

## What happened

{Two short paragraphs, at most 250 words. What was being done, what stopped it, and
why the choice is yours rather than something to be worked out. Plain words.}

## What I need you to decide

### {1. The short name of the choice}

{One paragraph: what the choice actually is, in plain words.}

| Option | What happens | What it costs |
|---|---|---|
| **A — {name}** | {what the project looks like afterwards} | {work, and what is given up} |
| **B — {name}** | {what the project looks like afterwards} | {work, and what is given up} |

**My recommendation: {A}** — {one sentence saying why.}

## What I do when you answer

{The steps, in order, one line each. What gets edited, what gets re-checked, roughly
how long. So the answer is given with the consequences in view.}

## Copy this back to me

{One fenced block per decision. Each block is a complete instruction that stands on
its own — the owner pastes it and nothing else needs saying.}

```
{App}: decision 1 — go with option A. {The one thing that changes.}
```
