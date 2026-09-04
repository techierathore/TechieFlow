# TechieFlow — Distribution Pipeline: Session Prompt

| | |
|---|---|
| Purpose | A prompt for one Claude Code session that gives TechieFlow the same distribution the AI-First Playbook already has: an npm package, a one-shot installer, pre-publish checks, and a GitHub Actions release pipeline. |
| Where to run | On the **main** branch, on a separate machine or clone, in parallel with the reset work on the **dev** branch. The two do not conflict: the installer copies whatever `.tfcore/` and mirrors contain, so the reset's content changes flow through it later without changes to the pipeline. |
| Requirements met | FR-48 to FR-52 in `TechieFlow-Requirements.md`; defect D-22 in `TechieFlow-How-It-Works.md`. |
| Reference implementation | `/mnt/c/3AIGenCode/AI-First-Playbook`: `package.json`, `scripts/install.mjs`, `scripts/npm-lifecycle.mjs`, `scripts/test-install.mjs`, `.github/workflows/release.yml` and `validate.yml`, `docs/Installation.md`, `docs/Npm-Release-Guide.md`, `docs/Npm-Publishing-Guide.md`. Read them before writing anything; reuse their shape, not their content. |

---

## Before starting

1. Be on `main`, with the reset's document commits already in. Create a branch `pipeline` from it. Agents never run git; the owner does.
2. Confirm Node 22.14 or later and npm 11.5 or later are installed (`node -v`, `npm -v`).
3. The owner has an npm account with the `@techierathore` scope and two-factor authentication on, and the GitHub repository can hold an `NPM_TOKEN` secret. If either is missing, follow `docs/Npm-Publishing-Guide.md` in the Playbook first; do not improvise the account setup.

---

## The prompt

Copy from here to the end of the block into a fresh Claude Code session opened in the TechieFlow repository on the `pipeline` branch.

```
You are adding npm distribution to TechieFlow, a spec-driven development framework for AI coding agents that works in two harnesses, Claude Code and OpenCode. Today it is installed by cloning this repository and running scaffold-brownfield.sh, scaffold-greenfield.sh or update-framework.sh from the clone. The goal is that anyone can instead run one command in their project and get exactly the same result.

Read first, in this order:
1. docs/TechieFlow-How-It-Works.md, sections 2 and 3, for what the framework is and what the three shell scripts deploy.
2. docs/TechieFlow-Requirements.md, group I (FR-48 to FR-52). These are the acceptance criteria. Nothing else is in scope.
3. The three shell scripts at the repository root. Note exactly what each copies, what it preserves on re-run, what it writes into .gitignore, and what it does for each harness.
4. The reference implementation in /mnt/c/3AIGenCode/AI-First-Playbook: package.json, scripts/install.mjs, scripts/npm-lifecycle.mjs, scripts/test-install.mjs, .github/workflows/release.yml, .github/workflows/validate.yml, docs/Installation.md, docs/Npm-Release-Guide.md. This is how the sibling framework is already published and it works. Reuse its structure: one-shot npx install, hidden folders only, managed .gitignore entries, no application dependency left behind, version set by GitHub release, CI publishes.

Rules for this session:
- Plain English in every document and every message. The owner is a .NET developer, not an npm or GitHub Actions expert, and will reject text they cannot repeat to a colleague.
- Do not change anything under .tfcore/, .claude/commands/, .opencode/ or opencode.jsonc. The installer ships those folders as they are. Content is the reset's job, on another branch.
- Do not edit the reset documents (docs/TechieFlow-*.md) except to add the Installation document named below.
- Never run git. Tell the owner what to commit and when.
- Both harnesses, always. An install that sets up Claude Code and not OpenCode is not done.
- Codex is frozen: ship its files if the shell scripts ship them today, add nothing for it.

Deliverables:
1. package.json for @techierathore/techieflow: bin pointing at the installer, an explicit files whitelist (everything the shell scripts deploy, plus the installer and its tests, plus LICENSE, README and the Installation document), engines, publishConfig access public, and a prepublishOnly script that runs every check in item 4.
2. scripts/install.mjs: commands install, update, uninstall; flags --target=, --dry-run, --force, --no-gitignore. It must produce, on a clean target, exactly the file set scaffold-brownfield.sh produces, and on an existing target exactly what update-framework.sh produces, including the preserve rules and the .gitignore block. The greenfield scaffold's extra steps (solution skeleton) are a flag, --greenfield, not the default. It must leave no node_modules, package.json or lock file in the target. Install the telemetry streams the way install-metrics.sh does.
3. scripts/test-install.mjs: on a temporary directory, run the installer and the matching shell script, diff the two results, fail on any difference. Run it for brownfield, greenfield and update. Also assert the Claude mirror is byte-identical to .tfcore/ and every {file:} reference in the installed opencode.jsonc resolves.
4. scripts/validate.mjs: mirror parity, opencode.jsonc reference resolution, bash -n on every .sh under the repository, and npm pack --dry-run. Exit non-zero on any failure.
5. .github/workflows/validate.yml (on every push and pull request: run item 4 and item 3) and .github/workflows/release.yml (on a published GitHub release: set the package version from the tag, run prepublishOnly, publish with the NPM_TOKEN secret). Copy the Playbook's approach for how the version is taken from the release rather than committed.
6. docs/TechieFlow-Installation.md: for a person on a fresh machine with Node installed. Sections: what gets installed; install into an existing project; start a new project; update; uninstall; what it does not touch; how the shell scripts from a clone remain an alternative. Under ten minutes to a working *day1-greenfield. Short sentences, one command per step.
7. docs/TechieFlow-Release-Guide.md: how the owner cuts a release, in the same shape as the Playbook's Npm-Release-Guide, adapted.
8. A short paragraph proposed for README section 3, replacing "copy, don't npm-install" with the two routes. Propose it in the chat; do not edit the README. The README is trimmed in the reset's Session 6 and the owner decides where this goes.

Order of work: items 3 and 4 first, so every later change is checked; then 2; then 1; then 5; then 6 and 7; then 8. After each item, run the tests and show the result.

Finish with: the exact commands the owner runs to commit, push, create the first GitHub release, and confirm the package appears on npm; and a list of anything that could not be verified from this machine.
```

---

## After the session

- Merge `pipeline` into `main` once `validate.yml` is green on GitHub.
- When the reset's `dev` branch later merges into `main`, the pipeline needs no change: it ships whatever `.tfcore/` and the mirrors contain. Re-run `npm run validate` after that merge to confirm mirror parity still holds.
- The requirement checks FR-48 to FR-52 are run against the MyDiary fixture as part of Session 6 (deploy to every repo), replacing `update-framework.sh <repo>` with `npx @techierathore/techieflow@latest update` for at least one repo.
