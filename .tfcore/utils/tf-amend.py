#!/usr/bin/env python3
"""tf-amend.py — the check behind `tf-emit.sh --amend <miss_id> <field> <value|none> ["<why>"]` (SCHEMA.md §5.5.7).

    python3 tf-amend.py <misses.jsonl> <miss_id> <field> <value> [<why>]

Prints "OK <the miss-amend record>" or "REFUSED <why>"; tf-emit.sh writes the record through its own
emitter, which checks it again (_amend_ok). Moved out of tf-emit.sh on 2026-11-14, when the class
correction (Sevak TF-036) would have grown that file past its size limit. Never writes anything.
"""
import json, sys
path, mid, fld, val, why = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5].strip()
val = None if why and val == "none" else val   # a correction may clear a value nobody can vouch for

# THE ALLOWLIST (SCHEMA.md §5.5.7): a closed-vocabulary JUDGEMENT a reader can still make later
# (why_missed), never an OBSERVATION (found_gate) nor a field this emitter derives (cost, attribution).
AMENDABLE = {
    "why_missed": ("missing-checklist-item", "insufficient-verify-method",
                   "code-audit-limitation", "ambiguous-acceptance",
                   "dependency-not-declared", "instruction-ignored", "other"),
    "sort": ("spec", "unsaid", "weak-check", "ignored"),
}
# `what` is free text, safe because an amend only fills a null (tf_018); a correction names why.
AMENDABLE_TEXT = ("what",)
# replaced only by a correction, never filled nor cleared (Sevak TF-036: a miss logged with the wrong class)
CORRECT_ONLY = {"miss_class": ("missed-requirement", "partial-implementation", "wrong-behaviour", "regression", "unspecified-gap",
                               "spec-contradiction", "scope-creep", "hallucinated-api", "standards-violation", "other")}
if fld in CORRECT_ONLY:
    if not why or val not in CORRECT_ONLY[fld]:
        print("REFUSED %s is replaced only by a correction with a reason, to one of: %s" % (fld, ", ".join(CORRECT_ONLY[fld]))); raise SystemExit(0)
elif fld not in AMENDABLE and fld not in AMENDABLE_TEXT:
    print("REFUSED %s is not an amendable field (SCHEMA.md §5.5.7)" % fld); raise SystemExit(0)
elif val is None:
    pass
elif fld in AMENDABLE_TEXT:
    if not isinstance(val, str) or not val.strip():
        print("REFUSED %s must be a non-empty sentence" % fld); raise SystemExit(0)
elif val not in AMENDABLE[fld]:
    print("REFUSED %r is not in the closed vocabulary for %s" % (val, fld)); raise SystemExit(0)

parent, current = None, None
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("kind") == "miss" and r.get("miss_id") == mid:
                parent = r
                current = r.get(fld)
            elif (r.get("kind") == "miss-amend" and r.get("miss_id") == mid
                  and r.get("field") == fld):
                current = r.get("value")          # an earlier amend already set it
except FileNotFoundError:
    pass

if parent is None:
    print("REFUSED no miss record %s on this stream" % mid); raise SystemExit(0)
# A CORRECTION (Sevak 2026-11-13: a duplicate check put one miss cause on MISS-Sevak-20261112-21)
# names why the value set is wrong; it replaces the value, and its reason stays on the stream.
if current is not None and not why:
    print("REFUSED %s is already %r on %s — an amend completes a record; to correct a wrong value, add "
          "why: --amend %s %s <value|none> \"<why>\"" % (fld, current, mid, mid, fld)); raise SystemExit(0)
if why and current == val:
    print("REFUSED %s is already %r on %s" % (fld, current, mid)); raise SystemExit(0)
print("OK " + json.dumps({"kind": "miss-amend", "miss_id": mid, "field": fld, "value": val,
                          **({"reason": why} if why else {})}, separators=(",", ":"), ensure_ascii=False))
