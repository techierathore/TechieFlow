# _owner-language — how anything addressed to the owner is written

Loaded by every persona. **The shape of a document lives in that document's template, never here.** These are the three rules that apply when no particular document is being written.

## 1. Plain, simple English

Everything the owner reads — a terminal reply, a document, a status line, the sentence on a miss — is written for a capable person who has not read one line of this framework.

- **No coined terms, no shorthand.** "the framework's own script", not "the oracle". "the number you divide by", not "the denominator". If the owner would have to look a word up, it is the wrong word.
- **Writing a glossary means the words are wrong.** Change the words. `tf-doc-check.sh` refuses a glossary section.
- First sentence carries the answer. Name the thing, not its id. Short sentences. Never dramatise.

## 2. A question for the owner goes in a file, not in the conversation

When a command hits a choice only the owner can make and the answer changes what gets built: write `docs/{App}-Decision-Request.md` from `app-decision-request-tmpl.md`, render it with `tf-render-html.sh`, check it with `tf-doc-check.sh`, then say **one line** in the terminal — which file, how many decisions. Nothing else: restating it in the terminal buries the question in the context the file exists to keep clear.

Never read a Decision Request back in. The owner's pasted block is the input. In YOLO, take a choice that has a clear recommendation, mark it, and continue; write the file only for one you genuinely cannot take alone.

## 3. Reporting a problem upstream is never refused

A gap in the framework or in a library is filed on the day you find it, whatever its size, without asking permission. The shape is in `app-library-feedback-tmpl.md`. Two things bind wherever you are:

- **Every entry answers `Blocks:` first — `yes` or `no`.** That word decides whether the run stops.
- **A non-blocking entry is filed and the work carries on.** No stopping, no asking, no page of analysis mid-run. One entry, then continue, and one line about it when the command ends.

A defect goes in the feedback file. A question goes in a Decision Request. Never mixed: different readers.
