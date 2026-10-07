# TechieFlow — decisions I need from you

| | |
|---|---|
| App | TechieFlow |
| Written | 2026-10-07 |
| Waiting on | 1 decision. Nothing has been changed for Blazor Hybrid apps yet. |

## What happened

I built the verifier's check for Mac apps. It works for Mac apps made of native MAUI controls: it starts the app, clicks to each screen, checks that every control the mockup names is there and shows something, checks for overlaps, and saves a picture of the app's window. Its self-test passes.

Lekhak's Mac app is different: it is Blazor Hybrid, so its screens are web pages shown inside the app. The check finds each control by the `data-testid` the mockup gives it, and on a Mac that name never leaves the web page. I tested a small Blazor Hybrid app three ways: Appium as normal, Appium with the web view's extra accessibility mode switched on, and macOS accessibility read directly. All three saw every text, field and button with its position, but no `data-testid` and no HTML `id`. Only an `aria-label` came through. Which way to go changes what gets built, and one option adds code to every app, so it is your call. Until you answer, a Blazor Hybrid Mac app is recorded as "not verified", never graded.

## What I need you to decide

### 1. How to check Blazor Hybrid apps on a Mac

The Mac cannot show the verifier the names of the controls inside a Blazor Hybrid page. Pick how much checking the Mac version should get.

| Option | What happens | What it costs |
|---|---|---|
| **A — Check without names** | The Mac check still runs: the window is not blank, no error bar, nothing overlaps or sits outside the window, and a picture of every screen. It does not check control by control; the Windows version, which uses the same pages, still does. | About a day of framework work, no app changes. A fault that hides one control only on the Mac would get through. |
| **B — A test-only bridge in each app** | In Debug builds, the app measures its own page with the same script the Windows check uses, and hands the result over. The Mac gets the full check by `data-testid`. | About two days of work, plus a small file in every Blazor Hybrid app. |
| **C — Name controls with aria-label** | Every named control also gets an `aria-label` equal to its test id, and the check matches on that. | Edits in every page of every app; screen readers would read names like "post-list" aloud. |
| **D — Leave it** | Blazor Hybrid Mac rows stay "not verified", with the reason written down. | Nothing to build. Lekhak's rule that a row is verified only on both versions can never be met for its Mac rows. |

**My recommendation: A** — the pages are the same on both versions and Windows already checks every name, so what is left to catch on the Mac is how the page is drawn, which A checks with no change to any app.

## What I do when you answer

1. A: add a "no names" mode to the Mac check, let the boot start Blazor Hybrid Mac apps, and mark the skipped name check as "not measured" in the verdict. About a day.
2. B: write the Debug-only file, add it to the scaffold, and have the Mac check read its results. About two days, then deploy to each Blazor Hybrid app.
3. C or D: C is spread across every app's pages; D needs only a note in Lekhak's feedback file.
4. In every case: run the Mac self-test and a real run on Lekhak's Mac app, then reply to Lekhak's feedback item about the Mac driver.

## Copy this back to me

```
TechieFlow: decision 1 — go with option A. Check Blazor Hybrid Mac apps without control names (blank, error bar, overlap, off-window, screenshots), and record the name check as not measured.
```
