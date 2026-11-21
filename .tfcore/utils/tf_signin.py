#!/usr/bin/env python3
"""tf_signin.py — did this run fail to sign in, and is this row one it could not measure for that reason?

Used by tf-verify-verdict.py (TfLens TF-061). When the sign-in itself fails (the account service is down,
the test user is gone), every screen behind Sign in answers with the sign-in page and every test stops
waiting to leave it. That says nothing about the rows: they are not measured, they keep their status,
and no gate record or miss is written for them.

    why(screens, row, scr, t) -> "" or the reason, in plain words

A row is not measured for a failed sign-in when:
  * screens.json says the sign-in failed (login.attempted and not login.ok, the run's "LOGIN failed" line), and
    the row's screen was sent to the sign-in page (or answered 401/403), or its test failed waiting for an address;
  * or the screen check did not sign in at all (no screens.json, or no sign-in tried) and the row's test failed
    waiting for an address while still on the sign-in path.
Never: a row of the sign-in screen itself (its route is the sign-in path), which is graded as it stands, and
a test that waits on the sign-in path in a run whose screen check did sign in (the app let the checker in, so
the test's own failure is real).
"""
import re

URL_WAIT = re.compile(r"waitForURL|toHaveURL|waiting for navigation", re.I)
LOGIN_PATH = re.compile(r"/(?:account/)?(?:log-?in|sign-?in)(?![\w-])", re.I)
WALL = re.compile(r"redirected to the sign-in page|not signed in|answered HTTP 40[13]\b", re.I)


def why(screens, row, scr, t):
    lg = (screens or {}).get("login") or {}
    failed = bool(lg.get("attempted")) and not lg.get("ok")
    if LOGIN_PATH.search((row.get("route") or "").split("?")[0]):
        return ""
    reason = (t.get("reason") or "") if t and t.get("result") == "FAIL" else ""
    waited = bool(URL_WAIT.search(reason))
    wall = bool(scr) and scr.get("render") == "UNREACHABLE" and any(
        WALL.search(f.get("detail", "")) for w in scr.get("widths", []) for f in w.get("findings", []))
    if failed and (wall or waited):
        err = re.sub(r"\s+", " ", str(lg.get("error") or "still on the sign-in page")).replace("|", "/")[:90]
        return (f"sign-in failed ({err}), so "
                + (f"screen {row.get('screen')} was never reached" if wall else "its test never got past Sign in")
                + "; its status is kept, fix the sign-in and verify again")
    if not failed and not lg.get("ok") and waited and LOGIN_PATH.search(reason):
        return "sign-in failed: its test stopped waiting to leave the sign-in page; its status is kept, fix the sign-in and verify again"
    return ""
