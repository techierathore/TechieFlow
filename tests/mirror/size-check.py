#!/usr/bin/env python3
"""tests/mirror/size-check.py — a script may not grow past a size, and one already past it may not grow.

    python3 tests/mirror/size-check.py            check against the ceilings
    python3 tests/mirror/size-check.py --list     print every file and block over a limit, with its size
    python3 tests/mirror/size-check.py --write    rewrite the ceilings from what is there now

WHY THIS EXISTS. The five verify scripts and the mockup check went from 1,888 lines to 4,669 in two
months (docs/TechieFlow-Code-Review-2026-11-10.md): every fix added lines to the same few files and
nothing counted them. The word budgets stopped the task files growing the same way; this is the
same rule for code.

THE LIMITS.
  script   a file in .tfcore/utils or .tfcore/hooks: at most 600 lines AND 40,000 bytes
           (bytes too, because a line limit alone is met with longer lines)
  block    python or node held inside a bash script there (a here-document, or a quoted -c / -e
           program): at most 30 lines
  test     a file under tests/: at most 1,500 lines

WHAT IT ALLOWS. A file or block already over a limit is listed in size-ceilings.txt with its size
on the day it was listed. It passes while it stays at or under that size, so nothing has to be
split before the check can run; a fix that needs 40 more lines in such a file takes 40 out or goes
in a new file. Anything not listed fails the moment it crosses a limit.

Raising a ceiling or adding a line is a deliberate act: run --write and the diff shows it in review.
When a listed file shrinks, --write lowers its ceiling so the room is not grown back into.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CEILINGS = os.path.join(HERE, "size-ceilings.txt")
MAX_LINES, MAX_BYTES, MAX_BLOCK, MAX_TEST = 600, 40_000, 30, 1_500
CODE = (".sh", ".py", ".mjs", ".js", ".cjs", ".ps1")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
PROGRAM = re.compile(r"\b(python3?|node)\b")
QUOTED = re.compile(r"\b(?:python3?\s+(?:-[A-Za-z]+\s+)*-c|node\s+(?:-[A-Za-z-]+\s+)*(?:-e|--eval|--input-type=module\s+-e))\s+(['\"])")
LOOKS_PY = re.compile(r"^\s*(import |from \w+ import |def |const |let |await |async )")


def files(sub, exts=CODE):
    out = []
    for cur, dirs, names in os.walk(os.path.join(ROOT, sub)):
        dirs[:] = [d for d in dirs if d not in ("__pycache__", ".artifacts", "node_modules", ".session")]
        out += [os.path.join(cur, n) for n in names if n.endswith(exts)]
    return sorted(out)


def size(path):
    data = open(path, "rb").read()
    return data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0), len(data)


def blocks(path):
    """line counts of the python or node programs a bash script holds, longest first"""
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    found, i = [], 0
    while i < len(lines):
        line = lines[i]
        if line.lstrip().startswith("#"):
            i += 1
            continue
        m = HEREDOC.search(line)
        if m:
            tag, j = m.group(2), i + 1
            while j < len(lines) and lines[j].strip() != tag:
                j += 1
            body = lines[i + 1:j]
            first = next((b for b in body if b.strip() and not b.lstrip().startswith(("#", "//"))), "")
            if PROGRAM.search(line) or re.search(r"PY|JS|NODE|PROG", tag, re.I) or LOOKS_PY.match(first):
                found.append(len(body))
            i = j + 1
            continue
        q = QUOTED.search(line)
        if q and q.group(1) not in line[q.end():].replace("\\" + q.group(1), ""):
            j = i + 1
            while j < len(lines) and q.group(1) not in lines[j].replace("\\" + q.group(1), ""):
                j += 1
            found.append(j - i - 1)
            i = j + 1
            continue
        i += 1
    return sorted((n for n in found if n > MAX_BLOCK), reverse=True)


def measure():
    """-> {('script'|'test', rel): (lines, bytes), ('blocks', rel): [n, ...]} for everything over a limit"""
    over = {}
    for sub in (".tfcore/utils", ".tfcore/hooks"):
        for p in files(sub):
            rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
            n, b = size(p)
            if n > MAX_LINES or b > MAX_BYTES:
                over[("script", rel)] = (n, b)
            if p.endswith(".sh"):
                bl = blocks(p)
                if bl:
                    over[("blocks", rel)] = bl
    for p in files("tests"):
        rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
        n, b = size(p)
        if n > MAX_TEST:
            over[("test", rel)] = (n, b)
    return over


def read_ceilings():
    out = {}
    if os.path.isfile(CEILINGS):
        for line in open(CEILINGS, encoding="utf-8"):
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            kind, rel = parts[0], parts[-1]
            out[(kind, rel)] = [int(x) for x in parts[1].split(",")] if kind == "blocks" else (int(parts[1]), int(parts[2]))
    return out


def write_ceilings(over):
    head = [l.rstrip("\n") for l in open(CEILINGS, encoding="utf-8") if l.startswith("#")] if os.path.isfile(CEILINGS) else []
    rows = []
    for (kind, rel), v in sorted(over.items(), key=lambda kv: (("script", "blocks", "test").index(kv[0][0]), kv[0][1])):
        rows.append(f"blocks  {','.join(map(str, v))}  {rel}" if kind == "blocks" else f"{kind:<6}  {v[0]} {v[1]}  {rel}")
    open(CEILINGS, "w", encoding="utf-8", newline="\n").write("\n".join(head + rows) + "\n")


def main(argv):
    over = measure()
    if "--write" in argv:
        write_ceilings(over)
        print(f"size-check: ceilings written for {len(over)} file(s) in {os.path.relpath(CEILINGS, ROOT)}")
        return 0
    if "--list" in argv:
        for (kind, rel), v in sorted(over.items()):
            print(f"{kind:<6} {rel}: " + (f"blocks of {', '.join(map(str, v))} lines" if kind == "blocks" else f"{v[0]} lines, {v[1]} bytes"))
        return 0
    allowed, bad, room = read_ceilings(), [], 0
    for (kind, rel), v in sorted(over.items()):
        cap = allowed.get((kind, rel))
        if kind == "blocks":
            cap = cap or []
            if len(v) > len(cap):
                bad.append(f"{rel} holds {len(v)} python or node block(s) over {MAX_BLOCK} lines ({', '.join(map(str, v))}); "
                           f"{len(cap)} are listed. Put the program in its own .py or .mjs file")
            elif any(now > was for now, was in zip(v, cap)):
                bad.append(f"{rel}: a python or node block grew (now {', '.join(map(str, v))} lines; ceilings {', '.join(map(str, cap))}). "
                           "Take lines out of it, or move the program to its own file")
            else:
                room += v != cap
        elif cap is None:
            limit = f"{MAX_TEST} lines" if kind == "test" else f"{MAX_LINES} lines and {MAX_BYTES:,} bytes"
            bad.append(f"{rel} is {v[0]} lines and {v[1]:,} bytes, over the limit of {limit}. Split it, or put the new code in a new file")
        elif v[0] > cap[0] or v[1] > cap[1]:
            bad.append(f"{rel} grew to {v[0]} lines and {v[1]:,} bytes; it was already over the limit and its ceiling is "
                       f"{cap[0]} lines and {cap[1]:,} bytes. Take out as much as the change adds, or put the new code in a new file")
        else:
            room += v != cap
    gone = [rel for (kind, rel) in allowed if (kind, rel) not in over]
    if bad:
        for b in bad:
            print(b)
        return 1
    n = {k: sum(1 for (kind, _r) in over if kind == k) for k in ("script", "blocks", "test")}
    print(f"ok   no script, block or test file grew past its limit ({n['script']} script(s), {n['blocks']} file(s) with long blocks "
          f"and {n['test']} test file(s) are over and listed; none grew"
          + (f"; {room + len(gone)} shrank, run size-check.py --write to lower the ceilings" if room or gone else "") + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
