"""tf-req-ids.py — which rows a test's name claims (Chatur TF-012). Imported by tf-verify-tests.sh.

A test proves the ids its name STARTS with, nothing else. An xUnit theory reported as
`REQ-UI-048 requirement ids are found in test names(aName: "REQ-FN-053 …")` passed REQ-FN-053 and
REQ-FN-055, which no test had ever touched. The ids are read from the leading run of REQ tokens
(separated by spaces, commas, slashes, "and" …, after at most one short capital tag such as FIX or
UAT), before any argument list. An id named later in the name is the test's subject matter, not its
claim. A theory whose argument is NAMED for the row it proves (`row: "REQ-RAG-125"`, also req, reqId,
requirement) claims that row: TechieRag's per-row cases.
"""
import re

ID = re.compile(r"(REQ-(?:UI|FN|NFR|RAG)-\d{3})", re.I)
LEAD_SEP = re.compile(r"(?:[\s,;/&+|·:\[\]–—-]|\band\b)*", re.I)
TAG = re.compile(r"\s*\[?[A-Z][A-Z0-9]{1,5}\]?:?\s+(?=REQ-)")
ROW_ARG = re.compile(r"\b(?:row|req|reqid|req_id|requirement)\s*[:=]\s*[\"']?(REQ-(?:UI|FN|NFR|RAG)-\d{3})\b", re.I)


def ids_of(name):
    """the ids one name claims, in order"""
    name = str(name or "")
    head, out = name.split("(", 1)[0], [x.upper() for x in ROW_ARG.findall(name)]
    t = TAG.match(head)
    p = t.end() if t else 0
    while True:
        p = LEAD_SEP.match(head, p).end()
        m = ID.match(head, p)
        if not m:
            return out
        out.append(m.group(1).upper())
        p = m.end()


def mentioned(name):
    """every id the name carries anywhere"""
    return {x.upper() for x in ID.findall(str(name or ""))}
