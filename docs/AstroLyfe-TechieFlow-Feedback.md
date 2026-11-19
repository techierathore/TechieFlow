# TechieFlow feedback — found while building AstroLyfe

| | |
|---|---|
| App | AstroLyfe |
| Upstream | TechieFlow |
| Updated | 2026-11-14 (file started by the TechieFlow team: TF-001 from the owner's report of the run of 13 Nov, fixed upstream, in `.tfcore/`) |

Defects found in the **TechieFlow framework itself** (`.tfcore/`) while building AstroLyfe. `.tfcore/` is the TechieFlow team's and `update-framework.sh` overwrites it, so nothing in it is fixed here; this file is the hand-off. `bash .tfcore/utils/tf-feedback.sh AstroLyfe` reads it.

## Summary

1 entry: 0 open, 1 fixed upstream and not yet re-checked (TF-001), 0 closed. 0 blocking.

## Entries

### TF-001 — The booted app's address reaches the browser tests only as an environment variable, and the test-users check does not read the TestNUsageDoc

- **Status:** fixed upstream 2026-11-14, fixed in AstroLyfe's `.tfcore/` by the framework update of 2026-11-14; not yet re-checked here.
- **Filed by:** the TechieFlow team, from the owner's report of AstroLyfe's run of 13 Nov.
- **Blocks:** no — `_settings.ts` falls back to `process.env.BASE_URL`, so the tests reach the app; the owner rule of 11 Nov (every test setting from the settings files, never the environment) cannot be met fully.
- **Severity:** minor
- **Repro:** `bash .tfcore/utils/tf-verify-tests.sh --base <boot address>` hands the address to `npx playwright test` as `BASE_URL` (and `CDP_URL`) only. AstroLyfe's tests read every setting from `tests/verify/testsettings.json` with `testsettings.Local.json` laid over it. Separately, `tf-test-users-check.py` reads the Test users of `docs/<App>-UsageGuide.md` only; AstroLyfe keeps them in `docs/AstroLyfe-TestNUsageDoc.md` under "## 2. Test User Accounts", so the check found 0 test users.
- **Expected:** the address arrives through `tests/verify/testsettings.Local.json`, with the old variable still set for one release so no project breaks; the check reads the TestNUsageDoc's Test users too.
- **Reply (TechieFlow team, 2026-11-14):** Fixed upstream in `tf-verify-tests.sh`, a new `tf-verify-settings.py` and `tf-test-users-check.py`. For each browser run the address is written into `tests/verify/testsettings.Local.json` as `Verify:BaseUrl` (and `Verify:CdpUrl` for a desktop head); after the run the two keys are put back as they were (a file the run created is removed), and nothing else in the file is read out or printed. `BASE_URL` and `CDP_URL` are still set, for one release (until v1.5), so a suite that reads them keeps working; a suite that reads `BaseUrl` from its settings is no longer refused as "nothing reads BASE_URL". The test-users check now also reads `docs/<App>-TestNUsageDoc.md`, and a "Test users" or "Test User Accounts" section runs to the next heading of its own level, so the table under "### Account Setup" counts: on this project's documents it now finds the 9 accounts (before: 0) and its verdict is unchanged. Case `as_001` in `tests/faults/run.sh` fails on the scripts you had and passes now. Its control halves: the Local file is the same after the run, its own BaseUrl and sign-in kept; an address built at run time is still a finding. Proved on a fixture, not on the AstroLyfe app. **Fixed in AstroLyfe's `.tfcore`:** deployed with `update-framework.sh` on 2026-11-14, when no AstroLyfe run was in progress. **Check it here:** the next verify's browser run reads `Verify:BaseUrl` = the boot address, and `testsettings.Local.json` is unchanged afterwards; `python3 .tfcore/utils/tf-test-users-check.py --app AstroLyfe` says `9 test user(s) in docs/AstroLyfe-TestNUsageDoc.md`. When the env fallback in `_settings.ts` is no longer needed, it can go before v1.5.

## Replies from TechieFlow

### Resolution status (TechieFlow team, 2026-11-19)

From `/mnt/c/1MyCode/AstroLyfe/docs/AstroLyfe-TechieFlow-Feedback.md`, read on 2026-11-19. **No entry is open.** TF-001 is fixed upstream and waits for your re-check; `as_001` still passes on tonight's scripts, so nothing about them changed. TechieFlow v1.4.0 (in this project's `.tfcore/` from the framework update of 2026-11-19 (morning)) changes the screen and mockup checks, the token counts of Claude Code runs and the estimates; its notes are `docs/TechieFlow-Release-Notes-v1.4.0.md` in TechieFlow.

**One change that reaches your verify (TfLens TF-060).** A row of a later phase that no screen of its own phase owns is now resolved against the earlier phases' screens. On your documents (read only), 7 rows gain a screen (phase 3: 6, phase 4: 1), for example REQ-UI-060 on `/ShowKundali/{id}`.

**The table** (`measure-projects.py --base v1.3.1`), your row: rows whose verdict moves: 0 of 96 (the last verify covered 96 of the project's 157 rows; the others are not measured); tests a phase verify stops running: 0 of 67 stop (32 left out in all, in 21 file(s)); 12 file(s) name no row id at all; findings that appear or go: none; build list and next command: same. The screen and mockup checks changed, so a row with a screen reads "not measured" there: the saved records were written by the old checks. What they now do is in the cases above, and the earlier-phase screens (TfLens TF-060) are counted from your documents, not from a verify.

### Resolution status (TechieFlow team, 2026-11-14)

**Fixed in AstroLyfe's `.tfcore`** through the framework update of 2026-11-14.

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. The address goes through `testsettings.Local.json`; `BASE_URL` stays one release; the TestNUsageDoc's test users are read. The reply is under the entry. | the next verify's browser run; `tf-test-users-check.py --app AstroLyfe` finds 9 test users. |
