# {AppName} — Product Guide

> **Audience: end users (not developers).** This is the how-to-use-the-app manual — task-oriented, screenshot-illustrated, plain language. It explains *what each screen is for* and *how to do each thing*, not how the code works (that's the DevGuide). It is a HUMAN document → always written as markdown AND rendered to HTML.

## Table of Contents

<!-- Auto-maintained. Slug rule: .tfcore/templates/v4custom/html-render-shell.md §1. List each `## <Role/Area>` and its `### <Feature/Screen>` sub-entries. -->

1. [Welcome](#welcome)
2. [Getting started](#getting-started)
3. [Roles at a glance](#roles-at-a-glance)
4. [Using {AppName}](#using-appname)

## Welcome

<one short paragraph: what {AppName} is and who it's for, in product language drawn from the BRD §1/§9 — no jargon, no architecture.>

## Getting started

- **Sign in:** {how to reach the app + log in; the sign-in screen with its screenshot}.
- **What you'll see first:** {the landing screen per role — keep it accurate to the real post-login landing, the same one the DevGuide's LANDING-TRUTH established}.

![Sign in](./screenshots/{AppName}/{anon}-login.png)

## Roles at a glance

<one row per user role/persona, plain-language "what this role can do" — derived from the BRD personas + the DevGuide's role→menu map.>

| Role | What you can do |
|------|-----------------|
| {Role} | {one line} |

## Using {AppName}

<!-- One `## {Role or Area}` section, then one `### {Feature / Screen}` block per screen, in the order a
     user would naturally use them (navigation order from the DevGuide's menu map). Each block is
     task-oriented and carries the REAL screenshot captured by the DevGuide OBSERVE pass. For a large
     app this section is split per role into docs/productguides/ (see the task). -->

### {Feature / Screen name}

**What it's for:** {one or two plain sentences — the user benefit, from the BRD feature catalog.}

**How to use it:**
1. {step — what the user clicks/enters}
2. {step}
3. {what they should see / the result}

![{Screen name}](./screenshots/{AppName}/{role}-{screen-slug}.png)

**Tips & notes:** {gotchas, limits, anything from the UsageGuide's known-limitations that a user should know — plain language, no defect IDs.}

<!-- Repeat the ### block for every user-facing screen/feature. Omit purely internal/admin-plumbing
     screens that an external user never touches, unless the role section is the admin guide. -->
