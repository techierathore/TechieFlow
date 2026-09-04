<!-- tf-schema
doc: productguide
file: docs/{App}-ProductGuide.md
header: App, Size, Date
section: Welcome | required | max 150
section: Getting started | required
section: Roles at a glance | optional
section: Using* | required
section: Troubleshooting | optional
entries: Using* |
rule: entry-steps
rule: entry-screenshot
budget: S 2500 3500 | M 4500 6500 | L 4500 6500
-->
<!-- Authoring notes (agent only; never visible text).
     The end user's manual: plain language, task by task, one real screenshot per task, no code and no
     requirement ids. "Roles at a glance" only when there is more than one role. The Using section is
     titled "Using {App}"; one `###` per task in the order a user meets them. -->

# {App} — Product Guide

| | |
|---|---|
| App | {App} |
| Size | Small, Medium or Large |
| Date | {YYYY-MM-DD} |

## Welcome

{What it does and who it is for, at most 150 words.}

## Getting started

1. {Open … and sign in.}
2. {What you see first.}

![Sign in](screenshots/{App}/login.png)

## Roles at a glance

| Role | What you can do |
|---|---|
| {Role} | {one line} |

## Using {App}

### {Task name}

1. {step}
2. {step}
3. {what you should see}

![{Task name}](screenshots/{App}/{screen-slug}.png)

## Troubleshooting

- {problem}: {what to do}
