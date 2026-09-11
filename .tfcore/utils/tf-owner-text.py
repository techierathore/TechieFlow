#!/usr/bin/env python3
"""tf-owner-text.py — check text written for the owner (MISS-TechieFlow-20260911-03).

    bash .tfcore/utils/tf-owner-text.sh [--root <dir>] [--final] <file> ...
    bash .tfcore/utils/tf-owner-text.sh [--root <dir>] [--final] --stdin      # the closing message

Four checks, one per mistake that reached the owner in TfLens's hand-off of 2026-09-11
(MISS-TfLens-20260911-01 to -03, and a fourth: two problems fixed upstream reported as open):

  words     a word from .tfcore/standards/owner-words.txt, or a script's internal name such as
            duration_s or PHASES_TOP_KEYS, in a sentence the owner reads
  upstream  an upstream problem (an entry id in docs/*-Feedback.md: TF-022, TR-010 …) that is
            still open sits in a table saying what it affects and whether it blocks or breaks
            anything, and appears in a code block, which is the prompt that gets it fixed; one the
            feedback file records as fixed upstream or closed is described as fixed or closed
  commands  a framework command named in a sentence (*verify) appears in a code block holding
            the line to paste
  final     with --final, the text is a command's closing message and carries a code block: the
            next prompt

Text inside ``` blocks is what the owner pastes, so the words check skips it. A document that has
its own template (BRD, checklist, feedback file …) is skipped: tf-doc-check.sh owns its shape.
Exit 0 clean, 1 a FAIL, 2 could not run. Python 3 standard library only.
"""
from __future__ import annotations

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ANY_ID = re.compile(r"(?<![\w-])([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-\d+)\b")
SCRIPT_NAME = re.compile(r"(?<![\w/.\-])([A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+)(?![\w/\-]|\.\w)")
COMMAND = re.compile(r"(?<![\w*])\*([a-z][a-z0-9]*(?:-[a-z0-9]+)*)\b")
# a sentence that puts a command in front of the owner as work still to do
TO_RUN = re.compile(r"(?i)\b(run|rerun|re-run|pending|next|not (?:yet )?(?:been )?run|still|should|must|"
                    r"needs?|to do|waiting|before|then)\b")
COMMANDS = {"verify", "build-phase", "fix-issues", "triage-issues", "triage-and-fix", "amend-docs",
            "refresh-status", "handoff-phase", "log-miss", "deploy-checklist", "day1-greenfield",
            "day1-brownfield", "devguide", "productguide", "metrics", "split-brd", "mockups", "yolo"}
TEMPLATED = re.compile(
    r"(?i)(?:-P\d+)?-(BRD|Architecture|UIDesign|Checklist|Deployment-Checklist(?:-[\w]+)?|Coding-Standards|"
    r"UsageGuide|Usage-Guide|DevGuide|ProductGuide|Phases|Brief|Decision-Request|[\w.]+-Feedback|Misses)\.md$"
    r"|(?:^|/)PROJECT-STATUS\.md$")


def load_words(root):
    for base in (os.path.join(root, ".tfcore", "standards"), os.path.join(HERE, "..", "standards")):
        p = os.path.join(base, "owner-words.txt")
        if os.path.isfile(p):
            out = {}
            for line in open(p, encoding="utf-8"):
                if line.strip() and not line.lstrip().startswith("#") and "|" in line:
                    w, say = (x.strip() for x in line.split("|", 1))
                    out[w.lower()] = say
            return out
    return {}


def upstream_state(root):
    """Every entry id in the project's feedback files -> (state, where), from the one reader
    every script uses (tf_feedback.py), so this check and PROJECT-STATUS can never disagree."""
    sys.path.insert(0, HERE)
    import tf_feedback
    return tf_feedback.state_map(root)


def split_text(text):
    """-> (prose lines [(n, line)], the text inside code blocks)."""
    prose, fenced, fence = [], [], None
    for n, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^\s*(```|~~~)", line)
        if m:
            fence = None if fence == m.group(1) else (fence or m.group(1))
            continue
        (fenced if fence else prose).append((n, line) if not fence else line)
    return prose, "\n".join(fenced)


def units(prose):
    """Group prose lines into the unit a sentence is read in: a table row (with its table's
    header) or a paragraph. -> [(first line no, text, header or None)]"""
    out, para, header, in_table = [], [], None, False

    def flush():
        if para:
            out.append((para[0][0], "\n".join(t for _n, t in para), None))
            para.clear()

    for n, line in prose:
        if line.lstrip().startswith("|"):
            flush()
            if not in_table:
                header, in_table = line, True
            elif not re.match(r"^\s*\|?\s*:?-{2,}", line):
                out.append((n, line, header))
            continue
        in_table = False
        if line.strip():
            para.append((n, line))
        else:
            flush()
    flush()
    return out


def next_command(root):
    p = os.path.join(root, "PROJECT-STATUS.md")
    if not os.path.isfile(p):
        return ""
    m = re.search(r"(?ms)^##\s+Next command to run.*?```[^\n]*\n(.*?)```", open(p, encoding="utf-8").read())
    return m.group(1).strip().splitlines()[0] if m and m.group(1).strip() else ""


def check(text, label, root, final=False, words=None, ups=None):
    fails = []
    fail = lambda n, msg: fails.append(f"FAIL {label}{':' + str(n) if n else ''}: {msg}")
    words = load_words(root) if words is None else words
    ups = upstream_state(root) if ups is None else ups
    prose, fenced = split_text(text)

    # 1. words
    seen = set()
    for n, line in prose:
        plain = re.sub(r"`[^`]*`", " ", re.sub(r"https?://\S+|\]\([^)]*\)", " ", line))
        plain = re.sub(r'"[^"\n]{1,30}"|“[^”\n]{1,30}”', " ", plain)   # a word quoted to name it is not used
        for w, say in words.items():
            if w not in seen and re.search(rf"(?i)(?<![\w-]){re.escape(w)}s?(?![\w-])", plain):
                seen.add(w)
                fail(n, f'"{w}" is a word the owner has to look up; say "{say}"')
        for name in SCRIPT_NAME.findall(re.sub(r"https?://\S+|\]\([^)]*\)", " ", line)):
            if name not in seen:
                seen.add(name)
                fail(n, f'"{name}" is a name inside a script; say in words what it is')

    # 2. upstream problems. A fixed or closed one must read as such wherever it is named; an open
    # one must be explained once, in a table row saying what it affects and whether it blocks or
    # breaks anything, and must appear in the prompt that gets it fixed.
    us = units(prose)
    mentions = {}
    for n, txt, header in us:
        for rid in dict.fromkeys(ANY_ID.findall(txt)):
            if rid in ups:
                mentions.setdefault(rid, []).append((n, txt, header))
    for rid, ms in sorted(mentions.items(), key=lambda kv: kv[1][0][0]):
        st, where = ups[rid]
        if st in ("fixed", "closed"):
            # read the sentence that names it, or its table row: "TF-901 is filed. X is fixed." is wrong
            said = lambda txt, h: [txt] if h is not None else [s for s in re.split(r"(?<=[.!?])\s+", txt) if rid in s]
            wrong = next((n for n, txt, h in ms
                          if not all(re.search(r"(?i)\b(fixed|closed)\b", s) for s in said(txt, h))), None)
            if wrong is not None:
                fail(wrong, f"{rid} is written about as an open problem, but {where} records it as "
                            f"{'fixed upstream' if st == 'fixed' else 'closed'}; say so, and say what re-checks it here")
            continue
        explained = any(h is not None and "affect" in h.lower() and re.search(r"(?i)block|break", h)
                        for _n, _t, h in ms)
        if not explained:
            fail(ms[0][0], f"{rid} is named without saying what it affects and whether it blocks or breaks "
                           f"anything: put it in a table with the columns Problem | What it affects | Does it block or break anything")
        elif not re.search(rf"(?<![\w-]){re.escape(rid)}\b", fenced):
            fail(ms[0][0], f"{rid} is open and no code block gives the prompt that gets it fixed")

    # 3. commands: one presented as something to run needs the line to paste. Naming a command
    # to say what it did ("*build-phase means build every unfinished row") needs nothing.
    known = COMMANDS | {os.path.splitext(os.path.basename(p))[0]
                        for p in glob.glob(os.path.join(root, ".tfcore", "tasks", "*.md"))
                        if not os.path.basename(p).startswith("_")}
    named = {}
    for n, txt, _h in us:
        plain = re.sub(r"`[^`]*`", " ", txt)                 # `run-void` is a name, not a cue
        plain = re.sub(r"(?i)\b(?:do not|don't|never|no need to|need not)\s+run\b", " ", plain)
        if not TO_RUN.search(plain):
            continue
        for c in COMMAND.findall(txt):
            if c in known:
                named.setdefault(c, n)
    for c, n in sorted(named.items(), key=lambda kv: kv[1]):
        if not re.search(rf"\*{re.escape(c)}\b", fenced):
            fail(n, f"*{c} is named, but no code block holds the line to paste for it "
                    f"(tf-status-facts.sh prints it in both harness forms)")

    # 4. a command's closing message ends by handing over the next prompt
    if final and not fenced.strip():
        nc = next_command(root)
        fail(0, "the closing message gives no next prompt; end with a code block holding the line to paste"
                + (f" — PROJECT-STATUS.md says: {nc}" if nc else ""))
    return fails


def main(argv):
    root, final, stdin, files = os.getcwd(), False, False, []
    it = iter(argv)
    for a in it:
        if a == "--root":
            root = os.path.abspath(next(it, "."))
        elif a == "--final":
            final = True
        elif a == "--stdin":
            stdin = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            files.append(a)
    if not stdin and not files:
        print(__doc__)
        return 2
    words, ups, fails, checked = load_words(root), upstream_state(root), [], 0
    if stdin:
        fails += check(sys.stdin.read(), "the closing message", root, final, words, ups)
        checked += 1
    for f in files:
        rel = os.path.relpath(os.path.abspath(f), root)
        if TEMPLATED.search(rel.replace("\\", "/")):
            print(f"SKIP {rel}: it has a template; tf-doc-check.sh checks it")
            continue
        if not os.path.isfile(f):
            fails.append(f"FAIL {rel}: file not found")
            continue
        # a document handed over is held to the first three checks; ending on the next prompt is
        # the closing message's job
        fails += check(open(f, encoding="utf-8", errors="replace").read(), rel, root, False, words, ups)
        checked += 1
    for line in fails:
        print(line)
    print(f"tf-owner-text: {len(fails)} FAIL in {checked} text(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
