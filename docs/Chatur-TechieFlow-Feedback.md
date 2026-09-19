# TechieFlow feedback — found while building Chatur

| | |
|---|---|
| App | Chatur |
| Upstream | TechieFlow |
| Updated | 2026-09-19 |

## Summary

1 entry: 0 blocking now, 0 open, 1 fixed upstream and waiting to be re-checked here (TF-001, fixed 2026-09-19).

Nothing is blocked. TF-001 is fixed upstream: a feedback file is no longer turned into a web page.

## Resolution status (TechieFlow team, 2026-09-19)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. The render rules no longer list a feedback file as a human document; `tf-render-html.py` refuses `{App}-{Upstream}-Feedback.md` as it refuses the checklist and the miss log, and the status gate says so in step 4. | After the framework update, run `bash .tfcore/utils/tf-render-html.sh docs/Chatur-TrBlazeUI-Feedback.md` — it prints REFUSED and writes no HTML. |

## Entries

### TF-001 — The render rules still list a feedback file as a document to turn into HTML

- **Severity:** minor
- **Blocks:** no — the HTML copy was deleted, feedback files are no longer rendered in this project, and the work carried on.
- **Repro:** Read the output contract in the render shell:
  ```
  .tfcore/templates/v4custom/html-render-shell.md  §0
  "Only human-readable docs are ever rendered to HTML (BRD, Architecture, … a Decision Request, a feedback file)"
  ```
- **Expected:** Feedback files are read by the upstream library's agent, not by a person, so they are never rendered. `tf-render-html.py` refuses them as it refuses the checklist and the miss log.
- **Actual:** The shell names a feedback file as renderable and the script renders it. An agent following the status gate ("every human document this command wrote") produced `Chatur-TrBlazeUI-Feedback.html`; the owner had to ask for it to be deleted, and said this had been asked several times before.
- **Encountered in:** `*day1-greenfield Chatur`, status gate step 4.
- **Workaround:** none needed in the project; the agent skips feedback files when rendering.
- **Suggested fix:** Remove "a feedback file" from §0 of `html-render-shell.md`, add `*-Feedback.md` to the names `tf-render-html.py` refuses, and say so in `_status-update-gate.md` step 4.
