<!-- build-subagent-prompt.md — the prompt build-phase gives every cluster sub-agent.
     Filled by tf-build-list.sh --prompts: {App} {Cluster} {Builder} {Section} {Rows} {Mockups} {Checklist}.
     Library agents (trblazeui, techierag) never read .tfcore/ tasks, so the two standing rules
     reach them only through this text. Keep it short; the rows carry the detail. -->
You are building cluster {Cluster} of {App} ({Section}) as the {Builder}. Implement exactly these rows, nothing else:

{Rows}

Read first: `docs/{App}-Coding-Standards.md` (and the standard files it names under `.tfcore/standards/`), `docs/{App}-Architecture.md` for module boundaries, and the mockups: {Mockups}. Build a UI row to match its mockup control for control, with the same `data-testid` anchors. Use only controls the UI library's reference lists (`.trblazeui/TrBlazeUI-AI-Reference.md`, `.techierag/TechieRag-AI-Reference.md`); a control or feature the library lacks goes as an entry into `docs/{App}-<Library>-Feedback.md` and the row becomes `Blocked`, never a workaround.

Two standing rules:
1. Git is manual. Never run `git` or `gh` for any purpose. Record your row ids in the checklist Remarks (`[REQ-…]`), not in commits.
2. Smoke it yourself before you return: `bash .tfcore/utils/tf-build.sh` must PASS, then boot the app and open every screen you touched with headless Playwright (or the native driver the ladder names); the data must show and nothing may overlap; use a test user from `docs/{App}-UsageGuide.md`, never an invented one. A green compiler is not a smoke.

Unit tests for every FN, RAG and NFR row go under `tests/unit/`. Run-generated files go under `tests/.artifacts/`, never at the repository root.

When done, set each row in `{Checklist}` to `Implemented` (smoke passed) or `PARTIAL` / `FAIL` with a one-line Remark, and return: rows implemented, files changed, tests added, library gaps logged, and the exact smoke you ran.
