#!/usr/bin/env python3
"""tf-verify-settings.py — hand the booted app's address to the browser tests through their settings file.

    python3 .tfcore/utils/tf-verify-settings.py put <base-url> [<cdp-url>]
    python3 .tfcore/utils/tf-verify-settings.py back

Run by tf-verify-tests.sh around each browser run (AstroLyfe, 2026-11-13). A project whose tests take
every setting from tests/verify/testsettings.json with testsettings.Local.json laid over it, never from
the environment, got the boot address only as BASE_URL. `put` writes Verify:BaseUrl (and Verify:CdpUrl
for a desktop head) into tests/verify/testsettings.Local.json, the machine's own git-ignored file, and
notes what those two keys held before; `back` puts them back as they were (a file `put` created is
removed). Nothing else in the file is read out or printed: it holds this machine's passwords.

BASE_URL and CDP_URL are still set for the tests as before, for one release (until v1.5), so a suite
that reads them keeps working; `--base` reaching neither is refused as before.
Prints one line. Never fails the run: a file that is not plain JSON is left alone and the line says so.
"""
import json, os, sys

LOCAL = os.path.join("tests", "verify", "testsettings.Local.json")
NOTE = os.path.join("tests", ".artifacts", "verify", "settings-handoff.json")
KEYS = ("BaseUrl", "CdpUrl")


def load():
    with open(LOCAL, encoding="utf-8-sig") as fh:
        d = json.load(fh)
    if not isinstance(d, dict):
        raise ValueError("not a JSON object")
    return d


def save(d):
    with open(LOCAL, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def verify_block(d):
    k = next((k for k in d if str(k).lower() == "verify"), "Verify")
    if not isinstance(d.get(k), dict):
        d[k] = {}
    return d[k]


def put(base, cdp):
    if not os.path.isdir(os.path.dirname(LOCAL)):
        return "settings: no tests/verify folder; the address goes as BASE_URL only"
    created = not os.path.exists(LOCAL)
    try:
        d = {} if created else load()
    except (OSError, ValueError) as e:
        return f"settings: {LOCAL} is not plain JSON ({type(e).__name__}); left alone, the address goes as BASE_URL only"
    v = verify_block(d)
    was = {k: v[k] for k in KEYS if k in v}
    for k, val in (("BaseUrl", base), ("CdpUrl", cdp)):
        if val:
            v[k] = val
    save(d)
    os.makedirs(os.path.dirname(NOTE), exist_ok=True)
    json.dump({"created": created, "was": was, "set": [k for k, val in zip(KEYS, (base, cdp)) if val]}, open(NOTE, "w"))
    return f"settings: Verify:BaseUrl {base}" + (f" and Verify:CdpUrl {cdp}" if cdp else "") + f" written to {LOCAL} for this run"


def back():
    try:
        note = json.load(open(NOTE))
    except (OSError, ValueError):
        return "settings: nothing to put back"
    os.remove(NOTE)
    if note.get("created"):
        if os.path.exists(LOCAL):
            os.remove(LOCAL)
        return f"settings: {LOCAL} removed again (this run created it)"
    try:
        d = load()
    except (OSError, ValueError):
        return f"settings: {LOCAL} changed during the run; not touched"
    v = verify_block(d)
    for k in note.get("set", []):
        if k in note.get("was", {}):
            v[k] = note["was"][k]
        else:
            v.pop(k, None)
    save(d)
    return f"settings: {LOCAL} put back as it was before the run"


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["put"] and len(a) >= 2 and a[1]:
        print(put(a[1], a[2] if len(a) > 2 else ""))
    elif a[:1] == ["back"]:
        print(back())
    else:
        print("settings: nothing to hand over")
