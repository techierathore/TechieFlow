#!/usr/bin/env python3
"""heredoc-scan.py FILE... — here-documents that bash 3.2 cannot parse.

Bash 3.2 (the /bin/bash of every Mac) finds the end of a $( ) or <( ) by scanning its text for
quotes and brackets, and a here-document inside it is part of that text. So a program embedded as

    out="$(python3 - <<'PY'
    # the file's name        <- an apostrophe: bash 3.2 looks for the closing quote
    PY
    )"

breaks on a Mac although bash 4 and 5 read it fine. This emulates bash 3.2's scan over each
such here-document body and prints "path:line: <why>" for every body that does not leave the
scan where it started. Used by tests/portability/run.sh.
"""
import re
import sys


def scan(text):
    """None when bash 3.2's matched-pair scan passes over text unchanged, else the reason."""
    i, n, depth, stack, mode = 0, len(text), 0, [], None  # mode: None, "'", '"', '`'
    while i < n:
        c = text[i]
        if mode == "'":
            if c == "'":
                mode = stack.pop()
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if mode == '"':
            if c == '"':
                mode = stack.pop()
            elif c == "`":
                stack.append(mode); mode = "`"
            i += 1
            continue
        if mode == "`":
            if c == "`":
                mode = stack.pop()
            elif c in "'\"":
                stack.append(mode); mode = c
            i += 1
            continue
        if c in "'\"`":
            stack.append(mode); mode = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth < 0:
                return "a ')' in the body ends the substitution early"
        i += 1
    if mode:
        return "an unmatched %s in the body" % {"'": "apostrophe", '"': 'double quote', "`": "backquote"}[mode]
    if depth:
        return "an unmatched '(' in the body"
    return None


START = re.compile(r"""(\$\(|<\()[^)]*?<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2""")


def main(paths):
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
        i = 0
        while i < len(lines):
            m = START.search(lines[i])
            if m and not lines[i].lstrip().startswith("#"):
                tag, body, j = m.group(3), [], i + 1
                while j < len(lines) and lines[j].strip() != tag:
                    body.append(lines[j]); j += 1
                why = scan("\n".join(body))
                if why:
                    print("%s:%d: here-document %s inside a substitution: %s" % (path, i + 1, tag, why))
                i = j
            i += 1


if __name__ == "__main__":
    main(sys.argv[1:])
