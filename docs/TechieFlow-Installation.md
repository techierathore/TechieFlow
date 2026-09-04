# TechieFlow — Installation

| | |
|---|---|
| Purpose | Get TechieFlow into a project with one command, on a machine that has never seen it. |
| Audience | A developer on a fresh machine. No knowledge of npm or of this repository is assumed. |
| Package | [`@techierathore/techieflow`](https://www.npmjs.com/package/@techierathore/techieflow) on npm |
| Time | Under ten minutes to a working `*day1-greenfield`. |

---

## Before you start

You need four things on the machine.

| Tool | Why | Check |
|---|---|---|
| Node.js 20 or newer | Runs the installer. Nothing is added to your project. | `node --version` |
| bash | The framework's guard hooks and helper scripts run under bash. macOS and Linux have it. On Windows, work inside WSL or Git Bash. | `bash --version` |
| Python 3.10 or newer | Powers the HTML renderer, the telemetry writer and the guard hooks. An older Python 3 works but skips the Codex files. | `python3 --version` |
| Claude Code or OpenCode | The harness that runs the agents. Either one. Both work from the same install. | `claude --version` or `opencode --version` |

For a .NET project you also need the .NET SDK. Run `dotnet --version` to check.

You do not need rsync, git on the command line, or a clone of this repository.

---

## 1. What gets installed

The installer copies the framework into hidden folders inside your project. It never adds the framework as a dependency of your application. After it runs there is no `node_modules`, no `package.json` and no lock file that was not there before.

| Path | What it is | On update |
|---|---|---|
| `.tfcore/` | The framework: personas, tasks, templates, hooks, helper scripts. | Refreshed. Two files inside are yours and are kept: `core-config.yaml` and `routing.yaml`. |
| `.claude/commands/TechieFlow/` | The Claude Code mirror of the personas and tasks. Claude Code only reads this folder. | Refreshed. |
| `.claude/commands/generate-html.md` | The short `/generate-html` command for Claude Code. | Refreshed. |
| `.claude/settings.json` | Claude Code permissions: everything allowed except git writes, plus the guard hooks. | Refreshed, with the old file kept as `settings.json.bak`. Pass `--keep-permissions` to keep yours. |
| `.opencode/plugin/techieflow.js` | The OpenCode plugin that runs the same guard hooks Claude Code runs. | Refreshed. |
| `.opencode/opencode.jsonc` | The framework's OpenCode configuration. OpenCode reads the personas and tasks straight from `.tfcore/` through it. | Refreshed. |
| `.opencode/command/generate-html.md` | The short `/generate-html` command for OpenCode. | Added on update only. |
| `opencode.jsonc` | The root OpenCode configuration, for your own additions. | Refreshed only when it holds nothing of yours, with the old file kept as `opencode.jsonc.bak`. |
| `.codex/` and `.agents/skills/` | The Codex adapter, generated from the same personas and tasks. | Refreshed. `config.toml` is yours and is kept. |
| `WORKFLOW.html` | The human workflow guide. Open it in a browser. | Refreshed. |
| `.tf-scaffold-note.txt` | A note with your next command. Delete it when read. | Left alone. |
| `docs/metrics/` | Five empty telemetry files and a README. This is your project's history: commit it. | Left alone. |
| `.gitignore` | Lines that keep the copies above out of your commits. Appended, never rewritten. | Appended. |
| `.gitattributes` | Line-ending rules and a merge rule for the telemetry files. Appended, never rewritten. | Appended. |
| `.git/hooks/pre-commit` | Records each commit in `docs/metrics/commits.jsonl`. Only when `.git/` exists. | Refreshed if it is ours. |

Both harnesses are set up by the one command. There is no separate step for Claude Code or for OpenCode.

---

## 2. Install into an existing project

Open a terminal in the project folder.

Step 1. Preview what will happen. Nothing is written.

```bash
npx @techierathore/techieflow@latest install --dry-run
```

Step 2. Install.

```bash
npx @techierathore/techieflow@latest install
```

Step 3. Read the note it left.

```bash
cat .tf-scaffold-note.txt
```

Step 4. Start your harness in this folder and run the brownfield day-1 command.

Claude Code:

```text
/TechieFlow:agents:analyst *day1-brownfield MyApp
```

OpenCode:

```text
/flow-analyst *day1-brownfield MyApp
```

Replace `MyApp` with your application's name in PascalCase.

The installer warns if it finds no `.csproj` or `.sln` within four folder levels and asks whether to continue. Add `--force` to skip the question.

If the project already has `.tfcore/`, install fills in missing files only. Use `update` to refresh.

---

## 3. Start a new project

This is the ten-minute path. Use `MyDiary` as the example name.

Step 1. Make the folder and step into it.

```bash
mkdir MyDiary && cd MyDiary
```

Step 2. Start the git repository. The framework never runs git for you; this is the one git command you run yourself now, so the commit-telemetry hook has somewhere to live.

```bash
git init
```

Step 3. Install the framework with the greenfield flag. It also creates `src/`, `tests/playwright/` and `tests/unit/`.

```bash
npx @techierathore/techieflow@latest install --greenfield
```

Step 4. Create the .NET solution.

```bash
dotnet new sln -n MyDiary
```

```bash
dotnet new blazor -n MyDiary.Web -o src/MyDiary.Web
```

```bash
dotnet sln add src/MyDiary.Web
```

Step 5. Add the component library and build once. The build deploys the library's own agent files.

```bash
dotnet add src/MyDiary.Web package TrBlazeUI
```

```bash
dotnet build
```

Step 6. Start your harness in this folder. When Claude Code asks whether to trust the folder, answer yes. That accepts the `.claude/settings.json` the installer wrote.

```bash
claude
```

or

```bash
opencode
```

Step 7. Run day-1.

Claude Code:

```text
/TechieFlow:agents:analyst *day1-greenfield MyDiary
```

OpenCode:

```text
/flow-analyst *day1-greenfield MyDiary
```

The analyst asks for the concept once. Answer in a sentence or a few bullets. It then writes the BRD, the architecture, the coding standards, the UI mockups, the checklist and the status file, and renders each document to HTML.

Step 8. Commit. The framework does not commit for you.

```bash
git add -A && git commit -m "Day 1"
```

The hidden framework folders are already in `.gitignore`. What you commit is your documents, your code and `docs/metrics/`.

---

## 4. Update

When a new version of the package is released, refresh the framework in each project.

Step 1. Preview. Nothing is written.

```bash
npx @techierathore/techieflow@latest update --dry-run
```

Step 2. Apply.

```bash
npx @techierathore/techieflow@latest update
```

Step 3. Restart Claude Code or OpenCode so the new task and persona files are loaded.

Update overwrites framework files and deletes framework files that no longer ship. It never touches the files listed in section 6.

If you have edited `.claude/settings.json` on purpose and want to keep it:

```bash
npx @techierathore/techieflow@latest update --keep-permissions
```

A project that still has the old `.bmad-core/` folder is migrated in place first. Your `core-config.yaml` is kept and patched.

---

## 5. Uninstall

Step 1. See what would be removed. Nothing is deleted without `--force`.

```bash
npx @techierathore/techieflow@latest uninstall
```

Step 2. Remove.

```bash
npx @techierathore/techieflow@latest uninstall --force
```

Uninstall removes the framework folders, the framework's `.gitignore` lines and the telemetry commit hook. It keeps `docs/metrics/`, every file it can see you changed, the NuGet-deployed library personas and `.gitattributes`.

`.tfcore/core-config.yaml` and `.tfcore/routing.yaml` live inside the framework folder. Copy them out first if you want to keep them.

---

## 6. What it does not touch

The installer and the updater never write to:

- `src/`, `tests/` and any code folder
- `docs/`, apart from creating `docs/metrics/` once
- `PROJECT-STATUS.md`, `CLAUDE.md`, `.editorconfig`
- `.tfcore/core-config.yaml` and `.tfcore/routing.yaml` after the first install
- `.claude/settings.local.json`
- `.claude/commands/trblazeui.md`, `.claude/commands/techierag.md` and the same names under `.opencode/command/`. These come from the NuGet packages.
- `.codex/config.toml` after the first install
- `opencode.jsonc` at the root when it holds a key of your own

Existing lines in `.gitignore` and `.gitattributes` are never rewritten. The managed lines are appended once and recognised on every later run.

---

## 7. Flags

| Flag | Meaning |
|---|---|
| `--target=<folder>` | Work on another folder instead of the current one. |
| `--dry-run` | Print what would happen. Write nothing. |
| `--force` | install: skip the "no .csproj found" question. uninstall: really delete. |
| `--no-gitignore` | Do not edit `.gitignore` or `.gitattributes`. |
| `--greenfield` | install only: also create `src/`, `tests/playwright/`, `tests/unit/`. |
| `--keep-permissions` | update only: leave `.claude/settings.json` as it is. |

---

## 8. The shell scripts are still there

The three shell scripts at the root of the repository still work from a clone. They need rsync, bash and python3.

```bash
git clone https://github.com/techierathore/TechieFlow.git
```

```bash
/path/to/TechieFlow/scaffold-brownfield.sh /path/to/existing-app
```

```bash
/path/to/TechieFlow/scaffold-greenfield.sh /path/to/new-app
```

```bash
/path/to/TechieFlow/update-framework.sh /path/to/app
```

The installer and the scripts produce the same files. A test in the repository, `scripts/test-install.mjs`, runs both on the same folders and fails on any difference. Choose the route you like. The package route needs no clone and always gives you the released version. The clone route gives you whatever is on the branch you checked out.

Do not run `npm install @techierathore/techieflow`. That would add the package to your application. Use `npx`, which runs the installer once and keeps nothing.

---

## 9. If something goes wrong

| What you see | What to do |
|---|---|
| `bash was not found` | On Windows, run the command inside WSL or Git Bash. |
| `python3 was not found` | Install Python 3 and run the command again. On macOS: `brew install python3`. On Ubuntu or WSL: `sudo apt-get install -y python3`. |
| `Codex bindings could not be generated` | Your Python is older than 3.10. Everything except the Codex files is installed. Upgrade Python and run `update` to add them. |
| `Refusing to install into the framework itself` | You ran the command inside a clone of this repository. Pass `--target=<your project>`. |
| `does not look installed` on update | The folder has no `.tfcore/`. Run `install` first. |
| Claude Code does not show the `/TechieFlow:agents:analyst` command | Restart Claude Code in the project folder. Check that `.claude/commands/TechieFlow/agents/analyst.md` exists. |
| OpenCode does not show `/flow-analyst` | Restart OpenCode. Check that `.opencode/opencode.jsonc` exists and that `.tfcore/agents/analyst.md` exists. |
