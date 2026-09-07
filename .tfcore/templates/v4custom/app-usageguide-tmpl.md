<!-- tf-schema
doc: usageguide
file: docs/{App}-UsageGuide.md
header: App, Kind, Size, Date
section: Test users | required
section: Execution guide | required
section: How to test, screen by screen | required
section: Automated tests | required
section: Known limitations | required
section: Platform notes | optional
section: How to call it | library
entries: How to test, screen by screen |
per-entry: 90 120
budget: S 2500 3500 | M 4000 6000 | L 4000 6000
rule: test-users-table
rule: execution-code
rule: entry-steps
rule: entry-expected
-->
<!-- Authoring notes (agent only; never visible text).
     The owner's test plan. Every agent (smoke, verify) and the owner's UAT use the SAME test users and
     the SAME walkthrough; nobody invents accounts. One `###` per screen in navigation order, at most
     120 words: who to sign in as, numbered steps, the expected result, the REQ ids covered.
     The Execution guide is copy-pasteable commands, one per line, no narrative. Hosting and production
     deployment are not here; they are in the Deployment Checklist after UAT.
     For a library, "How to call it" says how a consumer installs and registers the package and gives one call
     example per public service or component; the maintainer's map of each service is the DevGuide's. -->

# {App} — Usage Guide

| | |
|---|---|
| App | {App} |
| Kind | app or library |
| Size | Small, Medium or Large |
| Date | {YYYY-MM-DD} |

## Test users

| # | User | Password source | Role | Exists |
|---|---|---|---|---|
| 1 | {admin@app.test} | {user secrets key, seed script} | {Admin} | {yes, no} |

## Execution guide

Prerequisites: {runtime and version, database, anything else, one line}.

```
{restore command}
{database setup or migration command}
{build command}
{run command, with the URL it serves}
```

Open {http://localhost:port} and sign in as user 1.

## How to test, screen by screen

### {Screen name}
- **Sign in as:** {user # from the table}
- **Steps:** 1) {action} 2) {action} 3) {action}
- **Expected:** {what proves it works}
- **Covers:** {REQ ids}

## Automated tests

```
{test command}
```
{One line: what the suite covers.}

## Known limitations

- {one line each, with the REQ or feedback id}

## Platform notes

{Only when the app runs on more than one platform.}

## How to call it

{Libraries only. How to install and register the package, then one call example per public service or component. The maintainer's map of each service is in the DevGuide.}
