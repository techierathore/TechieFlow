# TechieFlow feedback — found while building Sevak

| | |
|---|---|
| App | Sevak |
| Upstream | TechieFlow |
| Updated | 2026-10-02 |

## Summary

1 entry: 0 blocking now, 0 open, 1 fixed upstream and waiting to be re-checked here (TF-001, fixed 2026-10-02).

Nothing is blocked. TF-001 is fixed upstream: raising the size changes only the size and the phases file.

## Entries

### TF-001 — Raising a project's size overwrites AGENTS.md and CLAUDE.md with blank templates

- **Severity:** major
- **Blocks:** no — the two files were copied back from `docs/OldDocs/` and the document list in `core-config.yaml` was restored from a copy; the amendment carried on.
- **Repro:** run the step `*amend-docs` names for growing past Medium:
  ```text
  bash .tfcore/utils/tf-day1-files.sh Sevak --size L --kind app
  -> archived AGENTS.md -> docs/OldDocs/AGENTS.md ; wrote AGENTS.md
  -> archived CLAUDE.md -> docs/OldDocs/CLAUDE.md ; wrote CLAUDE.md
  ```
- **Expected:** only `appSize` in `core-config.yaml` changes, and `docs/Sevak-Phases.md` is created.
- **Actual:** AGENTS.md and CLAUDE.md were replaced by the generic templates (".NET 9, Blazor Server", an `obj` field prefix, no hard rule 5 on stored identifiers). `customTechnicalDocuments` was rewritten to name a coding standards file that does not exist, and the UI design, usage guide and checklist were dropped from it.
- **Encountered in:** `*amend-docs Sevak` of 2026-10-02, step 4 (raising the size to Large).
- **Workaround:** restored by hand from `docs/OldDocs/` and a copy of `core-config.yaml` taken before the run; `appSize: L` and `appPhase: 2` added by hand.
- **Suggested fix:** make `--size` change only the size and the phases file; write AGENTS.md, CLAUDE.md and the document list only when `--prefix` (day-1 stage 2) is given.

## Resolution status (TechieFlow team, 2026-10-02)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. In `tf-day1-files.sh`, `--size`, `--kind` and `--phase` now set only `appSize`, `appKind` and `appPhase`, plus `docs/<App>-Phases.md` for Large. AGENTS.md, CLAUDE.md, `.editorconfig` and the document list are written only with `--prefix` (day-1 stage 2). Even then, the document list only gains missing entries and keeps every entry already there. Run with no flag, the script refuses rather than rewriting everything. | Copy `.tfcore/core-config.yaml`, then run `bash .tfcore/utils/tf-day1-files.sh Sevak --size L --kind app`. The output names only `appSize L, appKind app` (and the Phases file, which is left as is because it exists). AGENTS.md and CLAUDE.md are unchanged, nothing new is in `docs/OldDocs/`, and the config differs from the copy in `appSize` only. |
