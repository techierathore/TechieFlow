#!/usr/bin/env python3
"""tests/mirror/dup-check.py — refuse the same rule written in two places (FR-67).

    python3 tests/mirror/dup-check.py            check against the baseline
    python3 tests/mirror/dup-check.py --write    rewrite the baseline from what is there now

WHY THIS EXISTS. On 2026-09-08 the maintainer answered one problem by writing the same
rules into three files — a shared rule, a template's authoring notes and the schemas
document — 825 words of prose where nine checks were the actual fix. The maintenance
contract already said "a new rule is a script or a hook, not a paragraph"; nothing
measured it, so it was ignored (MISS-TechieFlow-20260908-04, sorted `ignored`). The
remedy the four questions prescribe for `ignored` is a hook or a script. This is it.

WHAT IT CHECKS. Every sentence of 12 or more words in the live rule surfaces — the
tasks, the personas, the templates and the framework's own readable documents. A
sentence appearing in more than one file is duplication, and duplication is how a
rule set rots: the copies drift, and a reader who finds one never learns there was
another.

WHAT IT ALLOWS. Some duplication is deliberate — the two day-1 variants are parallel
by design, and the four personas carry the same standing rules on purpose. Those are
baselined in `allowed-duplicates.txt`, so they pass. Anything NEW fails, which is the
whole point: the cost of the next copy is paid at the moment it is written.

Adding to the baseline is a deliberate act. If a new duplicate is genuinely intended,
run --write and the diff shows it in review; if it is not, delete one of the copies
and point at the other.
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BASELINE = os.path.join(HERE, "allowed-duplicates.txt")

# The live rule surfaces. Dated session prompts and the changelog are history: they
# quote each other on purpose and are never read as rules.
SCAN = [
    (".tfcore/tasks", r"\.md$"),
    (".tfcore/agents", r"\.md$"),
    (".tfcore/templates/v4custom", r"\.md$"),
    ("docs", r"^TechieFlow-(?!Session-|Sitting-|.*Restart-Prompt).*\.md$"),
]
MIN_WORDS = 12


def sentences(path):
    """Normalised sentences of MIN_WORDS or more, code blocks and markup removed."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)      # code is not prose
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)    # nor are HTML comments…
    for raw in re.split(r"(?<=[.;:])\s+|\n", text):
        norm = re.sub(r"[`*_>#\[\]()]", "", raw)
        norm = re.sub(r"\s+", " ", norm).strip().lower()
        if len(norm.split()) >= MIN_WORDS:
            yield norm


def scan():
    """{sentence hash: (sentence, {file, …})} for every sentence in the rule surfaces."""
    found = {}
    for folder, pattern in SCAN:
        d = os.path.join(ROOT, folder)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not re.search(pattern, name):
                continue
            rel = os.path.join(folder, name)
            for s in sentences(os.path.join(d, name)):
                key = hashlib.sha1(s.encode("utf-8")).hexdigest()[:12]
                entry = found.setdefault(key, (s, set()))
                entry[1].add(rel)
    return {k: v for k, v in found.items() if len(v[1]) > 1}


def load_baseline():
    allowed = set()
    if os.path.exists(BASELINE):
        with open(BASELINE, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    allowed.add(line.split()[0])
    return allowed


def write_baseline(dups):
    lines = ["# Duplicated sentences that are deliberate. One per line:",
             "#   <hash>  <files>  <the first words>",
             "# Regenerate with: python3 tests/mirror/dup-check.py --write",
             "# Adding a line here is a decision — the copy must be intended, not accidental.",
             ""]
    for key in sorted(dups, key=lambda k: (sorted(dups[k][1]), k)):
        s, files = dups[key]
        lines.append(f"{key}  {','.join(sorted(files))}  {s[:70]}")
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(dups)


def main(argv):
    dups = scan()
    if "--write" in argv:
        n = write_baseline(dups)
        print(f"dup-check: baseline written with {n} deliberate duplicate(s)")
        return 0
    allowed = load_baseline()
    new = {k: v for k, v in dups.items() if k not in allowed}
    if not new:
        print(f"ok   no rule is written twice ({len(dups)} baselined duplicate(s))")
        return 0
    for key in sorted(new, key=lambda k: sorted(new[k][1])):
        s, files = new[key]
        print(f"FAIL the same sentence is in {len(files)} files: {', '.join(sorted(files))}", file=sys.stderr)
        print(f"     \"{s[:100]}\"", file=sys.stderr)
    print(f"FAIL {len(new)} rule(s) written in more than one place. Delete a copy and point at "
          f"the one that stays; if the copy is deliberate, add it with --write.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
