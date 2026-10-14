#!/usr/bin/env python3
"""tf-yolo-perms.py — switch OpenCode to never ask, and back (owner, 2026-10-14). Run by tf-yolo.sh.

    python3 .tfcore/utils/tf-yolo-perms.py on  <project-root>
    python3 .tfcore/utils/tf-yolo-perms.py off <project-root>

on   OpenCode: the config file it reads LAST (it reads opencode.json, opencode.jsonc,
     .opencode/opencode.json, .opencode/opencode.jsonc, in that order, the last matching rule
     winning; checked on OpenCode 2.0.27) is rewritten with every "ask" made "allow", every "deny"
     kept in its place, and edit, webfetch, external_directory and doom_loop allowed, in the root map
     and in every agent's. In a project that file is the framework's own .opencode/opencode.jsonc.
     Its exact text is saved once, in .tfcore/.session/yolo-perms.json; a second `on` keeps the
     first saving.
     Claude Code is NOT switched here: it ignores permissions.defaultMode "bypassPermissions" in
     project and local settings ("only policy/user/flag settings may grant bypass mode", Claude Code
     2.1.299, 2026-10-14). Its side is the hook .tfcore/hooks/yolo-allow.sh, and for the prompts a
     hook cannot clear (ask rules, safety checks), a session started with
     `claude --permission-mode bypassPermissions` (tf-goal.sh always starts it so).
off  Puts the OpenCode file back as it was (one the updater replaced meanwhile is left as the updater
     wrote it) and removes the saving. Without a saving it does nothing.
Exit 0 always: YOLO never fails a phase.
"""
import json
import os
import re
import sys

MARK = "// tf-yolo.sh on rewrote this file so nothing asks while YOLO is on; tf-yolo.sh off puts the original back"
OPEN_ALLOW = ("edit", "webfetch", "external_directory", "doom_loop")


def jsonc(text):
    """JSON with // and /* */ comments and trailing commas, as opencode.jsonc is written"""
    out, i, n, s = [], 0, len(text), None
    while i < n:
        c = text[i]
        if s:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == s:
                s = None
        elif c == '"':
            s = c; out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        else:
            out.append(c)
        i += 1
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))


def never_ask(perm):
    """a permission map with every "ask" made "allow"; order (and so every deny's place) kept"""
    if perm == "ask":
        return "allow"
    if isinstance(perm, dict):
        out = {k: never_ask(v) for k, v in perm.items()}
        for k in OPEN_ALLOW:
            if k not in out or out[k] == "ask":
                out[k] = "allow"
        return out
    return perm


def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def write(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("on", "off"):
        print(__doc__)
        return 0
    verb, root = argv[1], argv[2]
    saving = os.path.join(root, ".tfcore", ".session", "yolo-perms.json")
    oc = next((os.path.join(root, *p) for p in ((".opencode", "opencode.jsonc"), (".opencode", "opencode.json"),
                                                 ("opencode.jsonc",), ("opencode.json",))
               if os.path.isfile(os.path.join(root, *p))), None)

    if verb == "on":
        if not os.path.isfile(saving):
            write(saving, json.dumps({"opencode_file": oc, "opencode_text": read(oc) if oc else None}, indent=1))
        # OpenCode
        text = read(oc) if oc else None
        if text is not None and MARK not in text:
            try:
                cfg = jsonc(text)
            except ValueError:
                cfg = None
            if isinstance(cfg, dict):
                cfg["permission"] = never_ask(cfg.get("permission") or {})
                for a in (cfg.get("agent") or {}).values():
                    if isinstance(a, dict) and a.get("permission"):
                        a["permission"] = never_ask(a["permission"])
                write(oc, MARK + "\n" + json.dumps(cfg, indent=2) + "\n")
        print("permissions: OpenCode set to never ask; Claude Code: the yolo-allow hook")
        return 0

    # off
    if not os.path.isfile(saving):
        return 0
    try:
        before = json.loads(read(saving) or "{}")
    except ValueError:
        before = {}
    oc_file, oc_text = before.get("opencode_file"), before.get("opencode_text")
    if oc_file and oc_text is not None and MARK in (read(oc_file) or ""):
        write(oc_file, oc_text)
    os.remove(saving)
    print("permissions: OpenCode config put back as it was")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as e:   # never a veto
        print(f"tf-yolo-perms: {e}", file=sys.stderr)
        sys.exit(0)
