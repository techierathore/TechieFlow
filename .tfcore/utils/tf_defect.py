"""tf_defect.py — the defect marks the framework's own writers put in a checklist row's Remarks.

devguide.md writes `⚠ DevGuide`, tf-checklist-edit's demote `⚠ UAT bug` / `⚠ prod bug` / `⚠ miss`,
tf-verify-verdict one mark per failing check, the smoke policy `⚠ visual`, security findings
`⚠ SECURITY`. A bare ⚠ is not a defect: hand-written remarks use it for "not verifiable here".

Imported by tf-status-facts.py (TF-019), tf-build-list.py (TF-020) and tf-verify-verdict.py (TF-021).
tests/regression/run.sh am_019, am_020, am_021.
"""
import re

# found by a verify check: a new verify grades it again, so its verdict replaces the old mark
VERIFY = r"acceptance|build|render|assets|visual|mockup-parity|perf"
# found by another step (guide, owner's testing, production, a miss, a review): no verify sees it
OTHER = r"DevGuide|UAT bug|prod bug|miss \d{4}-|SECURITY"
DEFECT = re.compile(rf"⚠\s*(?:{OTHER}|{VERIFY})\b")
UNSEEN = re.compile(rf"⚠\s*(?:{OTHER})\b")


def clauses(remarks, pattern=DEFECT):
    """The defect clauses of a Remarks cell: each runs from its ⚠ mark to the next ⚠ or the end."""
    return [c.strip().rstrip(";").strip() for c in re.split(r"(?=⚠)", remarks or "") if pattern.match(c)]


def unseen(remarks):
    """The clauses a verify cannot see, so a verify must neither erase them nor pass over them."""
    return clauses(remarks, UNSEEN)
