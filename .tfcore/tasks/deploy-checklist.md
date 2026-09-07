# deploy-checklist

`*deploy-checklist {App} {pipeline-document}` writes `docs/{App}-Deployment-Checklist.md`: the steps to put the application on its host, one document per hosting target, produced after UAT from the owner's pipeline guidance document and the Stack answers about hosting and production secrets. It never deploys anything and never edits code. Running the application locally is not in it; the UsageGuide's Execution guide owns that.

First: `bash .tfcore/utils/tf-phase.sh start deploy-checklist {App}` prints the start time and marks the command running.

## Inputs

- `{App}`, or read it from `core-config.yaml`.
- `{pipeline-document}`: the path of the owner's pipeline guidance document. If missing, ask once: "Which document describes the pipeline and the host? A path, or `none` to write the checklist from the Stack answers alone."

## Steps

1. Read the pipeline document, the Architecture's Stack decisions, and the UsageGuide's Execution guide (so nothing local is repeated). If the Stack decisions have no Q9 (hosting) or Q10 (production secrets and pipeline) row, ask those two questions now, once, and add the rows to the Architecture, citing the owner.
2. If `docs/{App}-Deployment-Checklist.md` already exists for this target, `bash .tfcore/utils/tf-day1-files.sh --archive docs/{App}-Deployment-Checklist.md` moves it to `docs/OldDocs/` first; read it for facts, never copy its shape. Write `docs/{App}-Deployment-Checklist.md` from `.tfcore/templates/v4custom/app-deployment-checklist-tmpl.md`, in the template's order, for one hosting target. Every item in "Before the first deploy", "Deploy", "After the deploy" and "Rollback" is a checkbox with one action and the result that shows it worked; every secret or setting is one row in "Secrets and settings" and is named nowhere else; "Proven" lists what has been executed for real, and the header says `never` until a real deploy has run. A second hosting target is a second document, `docs/{App}-Deployment-Checklist-{Target}.md`.
3. Where the pipeline document contradicts itself (a variable it says was deleted and still uses, a pipeline called settled on one page and never run on another), write the checklist from what the code and configuration say, and list each contradiction under "Troubleshooting" as a symptom with its fix. Log the contradiction as a miss when the document is the framework's own output.
4. `bash .tfcore/utils/tf-doc-check.sh docs/{App}-Deployment-Checklist.md`; fix every FAIL.
5. Run the status gate (`.tfcore/tasks/_status-update-gate.md`) with `"cmd":"deploy-checklist"`. The next command is the one the gate printed.
6. Report: the hosting target, the number of steps per section, the secrets named, the contradictions found, and that nothing has been proven until the owner executes a deploy and updates "Proven".
