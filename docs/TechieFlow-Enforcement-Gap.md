# TechieFlow — Rules Without Hooks

**Framework defect report + implementation spec**
Filed from: TechieBlog · Date: 2026-08-25 · For: framework team

---

## Summary

Two TechieFlow policies have no mechanical enforcement. Both failed again this week in
TechieBlog. The artifact-location rule has now failed **three times** across three separate
strengthenings of its prose.

Every TechieFlow rule that *does* have a hook held. Both rules without one failed, repeatedly,
despite prose that is if anything more forceful than the rules that held.

| Metric | Value |
|---|---|
| Litter found | 10 root `test-results-*` dirs |
| Disk | 14 MB, invisible to `git status` |
| Recurrence | 3rd, after two prose fixes |
| Status-page drift | 4 h 40 m (owner read stale HTML) |
| Installs affected | 5 vendored `.tfcore` of 22 local projects |

---

## 1. The two failures

### A. Repo-root artifact directories

Ten `test-results-*` directories accumulated at the TechieBlog repo root between 23 and 25
August — `test-results-uat025`, `-uat026`, `-uat027-post`, `-uat027-width`, `-uat029`,
`-final`, `-final29`, `-prod`, `-fixissues`, `-blogapp` — one per fix-issues or verify pass.
14 MB total.

Each was created by an agent passing `--output test-results-<slug>`, overriding the `outputDir`
that `playwright.config.ts` correctly pins to `tests/.artifacts/test-results`.

They were gitignored by `test-results-*/`, so they never surfaced in the owner's `git status` —
which is why they accumulated unnoticed for three days. The ignore rule hid the symptom the
prose rule was written to prevent.

**The rule already exists, and is emphatic.** `.tfcore/tasks/verify-phase.md:93` (framework
copy, modified 2026-08-20):

> "NEVER create a repo-root sibling directory for run material… Per-run/per-cluster directories
> at the root are BANNED… **Do not reason by the letter of this list**: any new root-level
> `<name>-<slug>/` you are about to create for a fan-out is the same defect, whatever the noun."

The same paragraph documents its own two prior failures:

> "This has actually happened twice — one app ended up with fourteen `test-results-*` dirs, and
> after those were banned the next fan-out produced four `scripts-cluster-*` dirs instead."

TechieBlog is the third.

### B. Stale `PROJECT-STATUS.html`

The owner reads the rendered HTML. On 25 August he was reading a page rendered at 05:16 while
the markdown had been rewritten at 09:56. The stale page still listed `REQ-FN-062` as blocked on
his credentials, still told him to deploy the site, and still asked him to load speaking data and
enter `UserStats` — three tasks he had already completed and which had been retracted in the
markdown that morning. It also pointed at the wrong next command.

`_status-update-gate.md` §8 is unambiguous:

> "If you edited `PROJECT-STATUS.md` you re-render `PROJECT-STATUS.html` in the same turn, full stop."

Two consecutive status writes skipped it. Nothing checked.

---

## 2. The pattern

| Rule | Stated in prose | Mechanical hook | Outcome |
|---|---|---|---|
| Git is manual — agents never commit | Yes | `block-git.sh` | **Holds** |
| PROJECT-STATUS keeps a fixed shape | Yes | `guard-status.sh` | **Holds** |
| `Verified` requires a real verify run | Yes | `guard-verify.sh` | **Holds** |
| Artifacts live under `tests/.artifacts/` | Yes — strengthened twice | *none* | **Failed ×3** |
| Re-render `PROJECT-STATUS.html` | Yes — "full stop" | *none* | **Failed ×2** |

The artifact rule has been strengthened twice and broken three times, which is strong evidence
that a fourth rewording would not change the outcome either.

The mechanism is simple: a rule in a task file only binds if the agent loads that file, reaches
the relevant line, and complies. A hook binds unconditionally. `verify-phase.md` is a 56 KB
document and the artifact rule sits at line 93 of it.

---

## 3. Why this cannot be fixed in the consuming project

Both hooks were written and tested in TechieBlog first. They work — but they cannot survive
there. This is why it is a framework ticket, not a project one.

| Project file | Treatment on `update-framework.sh` | Fate of a local change |
|---|---|---|
| `.tfcore/hooks/` | `rsync --delete` — `hooks` is in `FRAMEWORK_SUBDIRS` | Deleted |
| `.claude/settings.json` | "Refreshed by default" from a block hardcoded in `update-framework.sh` | Overwritten |
| `.tfcore/tasks/*.md` | `rsync --delete` | Overwritten |

`.tfcore/` is gitignored in consuming projects precisely because it is vendored. Anything written
there is scratch until it exists upstream.

---

## 4. Proposed changes

Three discrete patches, in order. **Changes 1 and 2 must ship together** — a hook script with no
settings entry is inert, and a settings entry with no script logs an error on every matching tool
call.

### Change 1 — Add the two hook scripts

**Target:** `/mnt/c/3AIGenCode/TechieFlow/.tfcore/hooks/`

Both follow the conventions already established by `guard-status.sh`: read the hook JSON from
stdin, pass it to `python3` through an environment variable (stdin is occupied by the heredoc),
**fail open** if `python3` or valid JSON is unavailable, and exit `2` with an explanatory stderr
message to block and inform the agent.

#### `guard-artifacts.sh` — PreToolUse, matcher `Bash`

Blocks any command pointing `--output` / `--output-dir` at a root-level `test-results*` or
`scripts-*`, or `mkdir`-ing one. The whole matcher is two regexes over one shared path fragment:

```python
# A root-relative artifact path: optional ./ then test-results… or scripts-…
# `tests/…` never matches (the 's' in "tests" is followed by '/'), and the
# project's own `scripts/` never matches (requires the hyphen).
ROOT_ARTIFACT = r"(?:\./)?(test-results[\w.-]*|scripts-[\w.-]+)/?"

re.finditer(r"--output(?:-dir)?[=\s]+(['\"]?)" + ROOT_ARTIFACT, cmd)
re.finditer(r"(?<!\w)mkdir(?:\s+-[\w-]+)*\s+(['\"]?)" + ROOT_ARTIFACT, cmd)
```

**One deliberate omission — please keep it.** A bare `-o` short form is **not** matched.
Playwright has no `-o` shorthand for `--output`, while `grep -o "test-results-…"` and
`curl -o test-results-report.json` are both legitimate and were false-positived by an earlier
draft that included it. Cheap specificity beat the more clever pattern here.

Full source: `.tfcore/hooks/guard-artifacts.sh` in this repo (see §7 for how to retrieve it
before the next framework update deletes it).

#### `guard-status-html.sh` — Stop hook

Refuses to end a turn while `PROJECT-STATUS.html` is older than `PROJECT-STATUS.md`, or missing
entirely.

**Stop, not PostToolUse.** The rule is about the turn, not the edit: an agent legitimately writes
the markdown and renders the HTML several tool calls later, and a PostToolUse hook would fire a
false alarm on every correct sequence. Stop fires only when the turn actually ends with the two
files out of sync — precisely the condition §8 describes. The hook honours `stop_hook_active` so
a turn that genuinely cannot render still terminates rather than looping.

Full source: `.tfcore/hooks/guard-status-html.sh` in this repo.

### Change 2 — Wire both into the canonical settings block

**Target:** `/mnt/c/3AIGenCode/TechieFlow/update-framework.sh`, heredoc at ~line 387

The canonical `settings.json` that `update-framework.sh` writes into every project currently
declares `PreToolUse` (line 388), `SessionStart` (412), `UserPromptSubmit` (422) and `SessionEnd`
(432). **There is no `Stop` key** — this change introduces one.

Append `guard-artifacts.sh` to the existing `Bash` matcher, beside `block-git.sh`:

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/block-git.sh\""
    },
    {
      "type": "command",
      "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-artifacts.sh\""
    }
  ]
},
```

Add the new `Stop` key as a sibling of `PreToolUse`:

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-status-html.sh\""
      }
    ]
  }
],
```

Note the escaping: these lines live inside a shell heredoc, so `\"$CLAUDE_PROJECT_DIR/…\"` must
keep its backslashes exactly as the neighbouring entries do.

### Change 3 — Record the enforcement in the rule docs

**Targets:** `.tfcore/tasks/verify-phase.md` §1 · `.tfcore/tasks/_status-update-gate.md` §8

Not cosmetic. `block-git.sh` and `guard-status.sh` are both announced in the prose they enforce,
and that announcement does real work: it tells an agent that a block is *the policy operating
correctly* rather than an obstacle to route around. Without it, a blocked agent's instinct is to
reword the command until it passes.

Into `verify-phase.md` §1, before the "Never pass `--output test-results-…`" bullet:

```markdown
- **The harness enforces this MECHANICALLY** (added 2026-08-25, after TechieBlog
  accumulated ten root `test-results-*` dirs on top of the two prior recurrences this
  rule already records): the `.tfcore/hooks/guard-artifacts.sh` PreToolUse hook blocks
  any Bash command that points `--output` / `--output-dir` at a root-level
  `test-results*` or `scripts-*`, or `mkdir`s one. A blocked call is **the policy
  working** — re-run writing under `tests/.artifacts/`, never reword the command to
  slip past it. `--output tests/.artifacts/<slug>` is allowed by design, as are
  `tests/`, `docs/screenshots/` and the project's own tracked `scripts/`.
```

Into `_status-update-gate.md` §8, after "…in the same turn, full stop.":

```markdown
**The harness enforces this MECHANICALLY** (same treatment as the git ban and the
status shape): the `.tfcore/hooks/guard-status-html.sh` **Stop** hook refuses to end
your turn while `PROJECT-STATUS.html` is older than `PROJECT-STATUS.md`, or missing.
A blocked stop means *the render is genuinely outstanding* — re-render it, do not look
for a way around the hook.
```

---

## 5. Test matrices

Both hooks were run against these inputs in TechieBlog. Every blocked case is paired with a
legitimate near-miss, because a silently unmatchable regex returns zero hits and reads exactly
like a pass — a failure mode this codebase has hit three separate times with hand-written greps.

### `guard-artifacts.sh` — 5/5 blocked, 8/8 allowed

| Exit | Command | Why |
|---|---|---|
| 2 | `npx playwright test --output test-results-uat032` | root artifact dir |
| 2 | `npx playwright test --output=./test-results-foo` | `./` prefix, `=` form |
| 2 | `npx playwright test --output-dir test-results/` | unsuffixed form |
| 2 | `mkdir -p test-results-cluster-a` | direct creation |
| 2 | `mkdir scripts-cluster-b` | the second recurrence's shape |
| 0 | `npx playwright test --output tests/.artifacts/uat032` | sanctioned isolation form |
| 0 | `command grep -o "test-results-[a-z0-9-]*/x" docs/…` | `-o` is grep's, not Playwright's |
| 0 | `curl -o test-results-report.json https://…` | same |
| 0 | `find . -name 'a' -o -name 'test-results-x'` | same |
| 0 | `mkdir -p tests/.artifacts/harness` | correct destination |
| 0 | `bash scripts/release.sh` | project's own tracked `scripts/` |
| 0 | `mkdir -p docs/screenshots/TechieBlog` | DevGuide-owned, tracked |
| 0 | `dotnet build TechieBlog.slnx` | unrelated |

### `guard-status-html.sh` — 6/6 correct

| Exit | Condition | Behaviour |
|---|---|---|
| 0 | HTML newer than markdown | allow — the normal correct case |
| 2 | Markdown newer than HTML | block, reporting drift (`4h 40m newer`) |
| 0 | Stale but `stop_hook_active` | allow — loop guard |
| 2 | HTML missing entirely | block with render instructions |
| 0 | No `PROJECT-STATUS.md` in project | allow — not a TechieFlow project |
| 0 | Live TechieBlog repo, post-fix | allow |

---

## 6. Rollout

1. **Hooks load at session start.** Neither hook takes effect in an already-running session. This
   was confirmed the hard way: after wiring both correctly in TechieBlog, `mkdir -p
   test-results-hooktest` still went straight through. Any verification of this ticket must happen
   in a fresh session.
2. **Sweep before enforcing.** `verify-phase.md` §1 already carries a legacy-sweep step; existing
   installs will have accumulated litter that the new hook prevents but does not remove.
   TechieBlog's ten were swept manually on 2026-08-25.
3. **Blast radius is small.** Five vendored `.tfcore` installs across 22 local projects. Worth a
   read-only scan of the other four for existing `test-results-*` / `scripts-*` litter before
   rollout, to size the sweep.
4. **Fail-open is deliberate.** Both hooks exit 0 if `python3` is missing or the payload will not
   parse. A guard that hard-fails on a malformed payload would block every Bash call in the
   project — a worse failure than the one being prevented.

---

## 7. Where the working code currently lives

Both scripts exist and pass their matrices in TechieBlog's **vendored** copy:

- `/mnt/c/1MyCode/TechieBlog/.tfcore/hooks/guard-artifacts.sh`
- `/mnt/c/1MyCode/TechieBlog/.tfcore/hooks/guard-status-html.sh`

They will be **deleted by the next `update-framework.sh` run** — that deletion is expected, and is
the reason this ticket exists. Copy them upstream before running an update in this project.

---

## 8. Known gaps — not addressed here

Stated so they are not mistaken for covered ground.

- **Playwright-library scripts stay unguarded.** `guard-artifacts.sh` matches command lines. A
  standalone script doing `import { chromium } from 'playwright'` never loads
  `playwright.config.ts`, so `outputDir` does not apply to it and no flag appears on the command
  line to match. §1 already covers this in prose — and a script written during this very
  investigation wrote its screenshot to an absolute path outside the repo, so the gap is live.
  Guarding it properly would mean inspecting `Write` payloads for capture paths, a larger change.
- **`--output` is not the only escape.** A shell redirect, a `cp`, or a Node `fs.writeFileSync`
  into a root-level directory all evade this matcher. The two regexes cover the forms that have
  actually caused all three recurrences; broadening them raises false-positive risk faster than it
  raises coverage.
- **The Stop hook checks mtime, not content.** A touched-but-unmodified HTML satisfies it. Content
  parity between the two files remains an agent responsibility — the hook's message asks for it
  explicitly, but nothing verifies it.

---

*All findings verified in `/mnt/c/1MyCode/TechieBlog` and `/mnt/c/3AIGenCode/TechieFlow` on
2026-08-25.*
