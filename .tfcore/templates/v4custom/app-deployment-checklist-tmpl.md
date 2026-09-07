<!-- tf-schema
doc: deployment-checklist
file: docs/{App}-Deployment-Checklist.md
header: App, Hosting target, Pipeline document, Date, Proven
section: Who does what | required
section: Secrets and settings | required
section: Before the first deploy | required
section: Deploy | required
section: After the deploy | required
section: Rollback | required
section: Routine operations | required
section: Troubleshooting | required
section: Proven | required
budget: S 2500 4000 | M 2500 4000 | L 2500 4000
rule: deploy-who-table
rule: deploy-secrets-once
rule: deploy-checkboxes
rule: deploy-proven
-->
<!-- Authoring notes (agent only; never visible text).
     One document per hosting target, produced after UAT from the owner's pipeline guidance document
     and the Stack answers Q9 (hosting) and Q10 (production secrets and pipeline). Running the
     application locally is NOT in it; that is the UsageGuide's Execution guide.
     Every item in sections 3 to 6 is a checkbox ("- [ ]") with one action and one observable result;
     no narrative paragraphs anywhere. Each secret or setting name appears in exactly one row of the
     Secrets and settings table and is never re-described elsewhere. Proven says "never" until a real
     deploy has been executed, then the date. Schema: docs/TechieFlow-Document-Schemas.md §3.10. -->

# {App} — Deployment Checklist

| | |
|---|---|
| App | {App} |
| Hosting target | {one target: VPS, Docker host, IIS, Azure App Service, …} |
| Pipeline document | {path of the owner's pipeline guidance document} |
| Date | {YYYY-MM-DD} |
| Proven | never |

## 1. Who does what

| Step | Done by |
|---|---|
| {Build and publish the artefact} | pipeline |
| {Approve the release} | owner |

## 2. Secrets and settings

| Name | Where it is set | What breaks without it |
|---|---|---|
| {CONNECTION_STRING} | {host environment variable} | {the application cannot start} |

## 3. Before the first deploy

- [ ] {One action} — {the result that shows it worked}

## 4. Deploy

- [ ] {One action} — {the result that shows it worked}

## 5. After the deploy

- [ ] {The command to run} — {the output that proves it worked}

## 6. Rollback

- [ ] {One action} — {the result that shows it worked}

A rollback does not undo: {database migrations; …}.

## 7. Routine operations

| Task | Command |
|---|---|
| {Restart the service} | `{command}` |

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| {…} | {…} | {…} |

## 9. Proven

| What | Executed for real | When |
|---|---|---|
| {Deploy to the target} | no | — |
