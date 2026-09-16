"""tf_roadmap.py — which checklist rows are roadmap items, out of this phase's scope.

A row is a roadmap item when its acceptance line in the checklist's detail section carries
"Roadmap — not in this phase's scope" (any dash, any case). Such a row is not work for this
phase: it stays off the build list and out of the "not built yet" count, and it never makes
*build-phase the next command. Only the owner moves it, through *amend-docs.

AppManager's REQ-NFR-008 carried the marker at In Progress; tf-build-list.py put it on the
working list with a builder prompt, a builder built it against the owner's decision, and
tf-status-facts.py named *build-phase as the next command for it forever (TF-017).
tests/regression/run.sh am_017. Imported by tf-build-list.py and tf-status-facts.py.
"""
import re

MARK = re.compile(r"roadmap\s*[—–-]+\s*not in this phase['’]?s scope", re.I)
ACCEPTANCE = re.compile(r"\*Acceptance:?\*|^\s*[-*]\s*Acceptance:", re.I)
OWNER = re.compile(r"<a id=['\"]d-(req-[a-z]+-\d+)['\"]|\*\*`?(REQ-[A-Z]+-\d+)`?\*\*", re.I)


def ids(text):
    """The set of REQ ids whose acceptance line carries the roadmap marker.

    The owner of an acceptance line is the nearest REQ anchor or bold REQ id above it, in the
    detail section; status-table rows (lines starting with `|`) are never read."""
    out, owner = set(), None
    for line in text.splitlines():
        if line.lstrip().startswith("|"):
            continue
        if re.match(r"^#{1,2}\s", line):
            owner = None
        for m in OWNER.finditer(line):
            owner = (m.group(1) or m.group(2)).upper()
        if owner and ACCEPTANCE.search(line) and MARK.search(line):
            out.add(owner)
    return out
