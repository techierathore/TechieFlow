#!/usr/bin/env python3
"""tf_looks.py — which investigation a finding belongs to, and what that investigation cost in time.

One rule, used by tf-triage.py (demote, new, close) and tf-log-miss.py (Chatur TF-036, Sevak TF-039).
Until 2026-11-15 each script had its own: both took "the latest look mark with a time at or before the
finding", read from the clock. A mark set in the same second as the last finding took that finding's
time (0 s), and a cause logged after the next investigation had begun got that later one's time.

THE RULE. `tf-triage.sh <App> look "<problem>"` opens an investigation and prints its number. The
actions of a command are read in the ORDER THEY WERE MADE (their place in the list), never by their
times: two calls in one second keep their order.
  which mark   the one the finding names (--look <number, time or words of its text>); else the latest
               mark made before it. When no mark is named and two or more marks are still unanswered
               (no finding and no note since they were set), nobody can say which one the finding
               answers: it is "not measured" and the reason names the marks, never a guess.
  the time     from the mark to the finding; or to the next mark, when one was set before the finding
               was logged (the investigation ended when the next one began).
  one mark, several findings   the first finding carries the time. Findings logged right after it (each
               within 120 s of the one before) answer the same problem: each says it was found in the same
               investigation and names the first, so the time is counted once. A finding logged later than
               that, with no mark of its own, keeps the older rule: its time starts at the previous finding,
               and two such findings within 120 s of each other were found together, both "not measured"
               (TechieBlog TF-004). tf-triage.py applies that at the close, to all of a run's rows at once.
A finding is a demote, a new row or a miss logged by tf-log-miss.sh (which writes itself into the list
as verb "miss"). A note answers the latest mark. With no mark before a finding the callers keep their
own older rule (the previous finding or the command's start). Python 3 standard library only.
"""
import datetime

FOUND = ("demote", "new", "miss")
BURST = 120
LATER = False   # window()'s answer for a finding logged long after its mark's first one: the older rule
SAME = "found in the same investigation as"   # tf-discovery-gate.py does not ask for these again


def number(acts, k):
    """the number of the mark at position k: the one stored when it was set, else its place among the marks"""
    return acts[k].get("n") or sum(1 for a in acts[:k + 1] if a.get("verb") == "look")


def _name(a):
    return a.get("miss_id") or a.get("req_id") or "an earlier finding"


def _find(acts, marks, named):
    named = str(named).strip()
    for k in marks:
        if named in (str(number(acts, k)), acts[k].get("ts")):
            return k
    hits = [k for k in marks if named.lower() in (acts[k].get("symptom") or "").lower()]
    return hits[0] if len(hits) == 1 else None


def said(acts, marks):
    return ", ".join(f'{number(acts, k)} "{(acts[k].get("symptom") or "")[:40]}"' for k in marks)


def _s(t):
    return datetime.datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ").timestamp()


def later(acts, i):
    """the older rule for one finding logged on its own (tf-log-miss.sh): from the previous finding, or
    "found together" when that was at most 120 s ago. -> (start, end, why)"""
    prev = [a for a in acts[:i] if a.get("verb") in FOUND]
    p, t = prev[-1], acts[i]["ts"]
    if _s(t) - _s(p["ts"]) <= BURST:
        return None, None, f"found together with {_name(p)}: logged within {BURST} s of it with no `tf-triage.sh look` between them"
    return p["ts"], t, None


def window(acts, i):
    """acts: this command's actions, in the order made. i: the position of the finding.
    -> None when no mark was made before it; LATER when its mark's first findings were logged more than
    120 s before it (the caller's older rule); else (start, end, why): the two times, or the reason
    there are none. The mark a finding names is acts[i]["look"]."""
    if not any(a.get("verb") == "look" for a in acts[:i]):
        return None
    open_, first, last, out = [], {}, {}, None   # marks unanswered so far; mark -> its first finding, and the latest of its first burst
    for j, a in enumerate(acts[:i + 1]):
        verb = a.get("verb")
        marks = [k for k in range(j) if acts[k].get("verb") == "look"]
        if verb == "look":
            open_.append(j)
        elif verb == "note" and open_:
            open_.pop()
        elif verb in FOUND and marks:
            named = a.get("look")
            if named:
                k = _find(acts, marks, named)
                if k is None:
                    out = (None, None, f"--look {named} names no mark of this command (marks: {said(acts, marks)})")
                    continue
            elif len(open_) > 1:
                out = (None, None, f"{len(open_)} investigations were open ({said(acts, open_)}) and this finding named none: "
                                   f"say which with --look <number>")
                open_ = []                # said once: the next finding is measured from the latest mark
                continue
            else:
                k = marks[-1]
            open_ = [m for m in open_ if m != k]
            if k in first:
                if last[k] is not None and _s(a["ts"]) - _s(acts[last[k]]["ts"]) <= BURST:
                    last[k] = j
                    out = (None, None, f"{SAME} {_name(acts[first[k]])} (mark {number(acts, k)}), whose record carries the time")
                else:
                    last[k] = None            # the burst is over: every later finding is on the older rule
                    out = LATER
                continue
            first[k] = last[k] = j
            later = [m for m in marks if m > k]
            start = acts[k]["ts"]
            out = (start, max(start, acts[later[0]]["ts"] if later else a["ts"]), None)
    return out
