#!/usr/bin/env python3
"""Audit an app's ROOT opencode.jsonc against the framework template.

Prints ONE verdict line on stdout:
  current                 byte-identical to the template — nothing to do
  refresh                 carries no project-only content — safe to replace wholesale
  project|<k1,k2,...>     carries project-only keys — must be preserved, keys listed
  unknown|<reason>        could not be parsed — caller falls back to preserving

Also prints, after the verdict, zero or more DIAG lines the caller echoes:
  DIAG|dead-ref|<ref>     a {file:...} reference that does not resolve in the app
  DIAG|bare-bash-allow|<where>   a genuine agent-level "bash": "allow" string value

"Project-only" means a key the framework template does not define, excluding the
framework's own `techieflow:` command namespace (retired framework commands are
framework litter, not project content, and must NOT block a refresh).
"""
import json
import os
import re
import sys


def strip_jsonc(text):
    """Remove // line comments and trailing commas. Quote-aware: a // inside a
    string literal (e.g. a URL) is left alone."""
    out, in_str, esc, i = [], False, False, 0
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < len(text) and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = len(text) if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    s = "".join(out)
    return re.sub(r",(\s*[}\]])", r"\1", s)


def load(path):
    raw = open(path, encoding="utf-8").read()
    return json.loads(strip_jsonc(raw)), raw


def main():
    tmpl_path, app_path = sys.argv[1], sys.argv[2]
    app_dir = os.path.dirname(os.path.abspath(app_path)) or "."

    try:
        tmpl, tmpl_raw = load(tmpl_path)
    except Exception as e:
        print("unknown|template unreadable: %s" % e)
        return
    try:
        app, app_raw = load(app_path)
    except Exception as e:
        print("unknown|app config does not parse: %s" % e)
        return

    diags = []

    # --- genuine bare agent-level "bash": "allow" -------------------------
    # Checked on the PARSED tree, never on raw text: the template's own comment
    # contains the literal string `"bash": "allow"`, so a grep over the raw file
    # matches its own documentation and fires on every correct config.
    for name, block in (app.get("agent") or {}).items():
        if not isinstance(block, dict):
            continue
        perm = block.get("permission")
        if isinstance(perm, dict) and perm.get("bash") == "allow":
            diags.append("DIAG|bare-bash-allow|agent.%s" % name)
    root_perm = app.get("permission")
    if isinstance(root_perm, dict) and root_perm.get("bash") == "allow":
        diags.append("DIAG|bare-bash-allow|permission")

    # --- dead {file:...} refs (hard-fails OpenCode's whole config load) ----
    for ref in sorted(set(re.findall(r"\{file:([^}]*)\}", app_raw))):
        rel = ref[2:] if ref.startswith("./") else ref
        if not os.path.isfile(os.path.join(app_dir, rel)):
            diags.append("DIAG|dead-ref|%s" % ref)

    # --- project-only content ---------------------------------------------
    project = []
    for k in app:
        if k not in tmpl:
            project.append(k)
    for k in (app.get("agent") or {}):
        if k not in (tmpl.get("agent") or {}):
            project.append("agent.%s" % k)
    for k in (app.get("command") or {}):
        if k in (tmpl.get("command") or {}):
            continue
        if k.startswith("techieflow:"):
            continue  # retired FRAMEWORK command — litter, not project content
        project.append("command.%s" % k)

    if app_raw == tmpl_raw:
        print("current")
    elif project:
        print("project|%s" % ",".join(sorted(project)))
    else:
        print("refresh")
    for d in diags:
        print(d)


main()
