#!/usr/bin/env python3
"""tf-doc-check.py — check a TechieFlow human document against its template schema.

Every template under .tfcore/templates/v4custom/ opens with a `<!-- tf-schema ... -->`
block: required sections in order, word budgets per size, per-entry limits, and the
named row rules. This script reads that block and checks a generated document
against it. One line per problem, in plain words:

    FAIL docs/MyApp-BRD.md: section "Scope" is missing
    WARN docs/MyApp-BRD.md: 6,410 words; the Small target is 6,000 (maximum 8,000)

Exit 0 when nothing FAILs, 1 when something does, 2 when it could not run.
`--warn` prints every finding as WARN and exits 0 (report mode for existing projects).

Called through tf-doc-check.sh. Python 3 standard library only.
Readable description of the same rules: docs/TechieFlow-Document-Schemas.md.

Schema grammar (one `key: value` per line inside the comment):
    doc: brd                         file: docs/{App}-BRD.md
    header: App, Kind, Size          fields that must be present and filled in
    section: Name | flag | max N     flag = required | optional | optional-small (required for M/L)
                                     | app (required when Kind=app) | library (required when Kind=library)
                                     a trailing * on the name matches any heading with that prefix
    budget: S 6000 8000 | M …        target and maximum words per size (code blocks and comments excluded)
    entries: Section | Prefix:       the section holding one ### entry per screen/task; optional H3 prefix
    per-entry: 250 400               target and maximum words per entry
    max-lines: 120  target-lines: 60
    rule: name                       a named check implemented below (rules starting entry- run per entry)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

SELF_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.normpath(os.path.join(SELF_DIR, "..", "templates", "v4custom"))

# file-name suffix (lower-case) -> (doc id, template file)
DOC_KINDS = [
    ("-brd.md", "brd", "app-brd-tmpl.md"),
    ("-architecture.md", "architecture", "app-architecture-tmpl.md"),
    ("-uidesign.md", "uidesign", "app-uidesign-tmpl.md"),
    ("-deployment-checklist.md", "deployment-checklist", "app-deployment-checklist-tmpl.md"),   # before -checklist.md
    ("-checklist.md", "checklist", "app-checklist-tmpl.md"),
    ("coding-standards.md", "coding-standards", "app-coding-standards-tmpl.md"),
    ("project-status.md", "project-status", "app-project-status-tmpl.md"),
    ("-usageguide.md", "usageguide", "app-usageguide-tmpl.md"),
    ("-usage-guide.md", "usageguide", "app-usageguide-tmpl.md"),
    ("-devguide.md", "devguide", "app-devguide-tmpl.md"),
    ("-productguide.md", "productguide", "app-productguide-tmpl.md"),
    ("-phases.md", "phases", "app-phases-tmpl.md"),
    ("-brief.md", "brief", "app-brief-tmpl.md"),
    ("-decision-request.md", "decision-request", "app-decision-request-tmpl.md"),
    ("-feedback.md", "feedback", "app-library-feedback-tmpl.md"),
]
SIZED_DOCS = {"brd", "architecture", "uidesign", "checklist", "usageguide", "devguide", "productguide"}
# Large projects: these four split by phase. Phase 1 keeps the plain name (App-BRD.md);
# phase 2 onward are App-P2-BRD.md and so on. docs/TechieFlow-Document-Schemas.md §2.
PHASED_DOCS = {"brd", "checklist", "uidesign", "devguide"}
PHASED_SUFFIX = {"brd": "BRD", "checklist": "Checklist", "uidesign": "UIDesign", "devguide": "DevGuide"}
# A feedback entry's heading opens with its id: TF-016, TR-010, TR-RAG-002.
ENTRY_ID = re.compile(r"^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-\d+\b")
# A closed entry carries its resolution banner near the top of its body. The banner is not
# always first: an entry may open with a renumbering or scope note, so the window is generous.
FEEDBACK_CLOSED = re.compile(r"(?i)(✅|\bfixed upstream\b|\bwill not fix\b|\bwont-fix\b|is \*\*closed\*\*)")
DOC_NAME = re.compile(
    r"^(.+?)(?:-P(\d+))?-(BRD|Deployment-Checklist(?:-[\w]+)?|Checklist|UIDesign|DevGuide|Architecture|Coding-Standards|UsageGuide|Usage-Guide|ProductGuide|Phases)\.md$",
    re.I)
PHASE_FORM = re.compile(r"^(\d+)\s+of\s+(\d+)$", re.I)
PHASE_STATUS = {"planned", "building", "done"}
BRD_RANGE = re.compile(r"(?:BRD-)?(\d+)\s*(?:to|-|–|—)\s*(?:BRD-)?(\d+)", re.I)

SIZE_NAMES = {"s": "S", "small": "S", "m": "M", "medium": "M", "l": "L", "large": "L"}
SIZE_LONG = {"S": "Small", "M": "Medium", "L": "Large"}
REQ_CAP = {"S": 50, "M": 100, "L": 100}

CHECKLIST_HEADER = "| ID | Requirement | Status | % | Remarks | Details |"
STATUS_VALUES = {
    "not started", "in progress", "implemented", "verified", "done (pre-existing)",
    "needs re-verify", "partial", "fail", "blocked", "n/a", "owner-uat",
}
NOT_PRESENT = re.compile(r"\b(not|never)\s+(present|found|installed|available)\b|does not exist|no such file", re.I)
NAMES_PATH = re.compile(r"(?:\.tfcore|\.claude|\.opencode|docs|src|tests)/[\w./-]+|[\w-]+\.(?:sh|py|md|json|yaml|razor|cs)\b")
PERF_BUDGET = re.compile(
    r"perf-budget:\s*(p50|p95|max)\s+(ttfb|load)\s*<=\s*\d+\s*ms(\s*@\s*concurrency\s+\d+)?", re.I
)
ACCEPT_LINE = re.compile(r"\*Acceptance:?\*|^\s*[-*]\s*Acceptance:", re.I)
ACCEPT_FORM = re.compile(
    r"^\s*[-*]\s*\*?Acceptance:?\*?:?\s*(?:Given\b[^,]*,\s*)?When\b.+?,\s*then\b.+", re.I
)
NAMES_SCREEN = re.compile(r"\b(on|opens?|from|in)\b", re.I)


def acceptance_words(line: str) -> int:
    """Words in an acceptance line, without the "Acceptance:" label and without a perf-budget tail."""
    t = re.sub(r"^\s*[-*]\s*\*?Acceptance:?\*?:?\s*", "", line)
    t = re.split(r"perf-budget:", t, flags=re.I)[0]
    return len(re.findall(r"\S+", t))


ACC_TARGET, ACC_MAX = 20, 30   # owner, 2026-09-06 (miss 13): a line a person can read at a glance


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def norm_heading(text: str) -> str:
    """'## 3. Users and roles (all)' -> 'users and roles'."""
    h = text.strip().rstrip(":")
    h = re.sub(r"^[#\s]*", "", h)
    h = re.sub(r"^(?:§\s*)?\d+(?:\.\d+)*[.)]?\s+", "", h)  # leading numbering
    h = re.sub(r"[\U0001F300-\U0001FAFF☀-➿]", "", h)  # emoji
    h = re.sub(r"\s*[—(].*$", "", h)  # trailing qualifiers: "— …" or "(…)"
    h = re.sub(r"\s+", " ", h).strip().lower()
    return h


def key_matches(declared_key: str, present_key: str) -> bool:
    if declared_key.endswith("*"):
        return present_key.startswith(declared_key[:-1].rstrip())
    return declared_key == present_key


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def strip_noise(text: str) -> str:
    """Remove HTML comments and fenced code blocks (they are not prose)."""
    return re.sub(r"```.*?```", "", strip_comments(text), flags=re.S)


def word_count(text: str) -> int:
    return len(re.findall(r"\S+", strip_noise(text)))


def split_sections(body: str, level: int = 2):
    """Return [(heading_text or None, section_text)] split on headings of `level`."""
    pat = re.compile(rf"(?m)^{'#' * level}\s+(.+)$")
    out, last, last_head = [], 0, None
    for m in pat.finditer(body):
        out.append((last_head, body[last:m.start()]))
        last_head, last = m.group(1).strip(), m.end()
    out.append((last_head, body[last:]))
    return out


def parse_header(body: str) -> dict:
    """Header fields from YAML frontmatter and from the first `| Key | Value |` table."""
    fields = {}
    text = strip_comments(body).lstrip()
    fm = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.S)
    if fm:
        for line in fm.group(1).splitlines():
            m = re.match(r"^\s*([A-Za-z_][\w -]*):\s*(.*?)\s*$", line)
            if m:
                fields[m.group(1).strip().lower()] = m.group(2).strip()
    head = text.split("\n## ", 1)[0]
    for m in re.finditer(r"(?m)^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*$", head):
        key, val = m.group(1).strip().lower(), m.group(2).strip()
        if key and not set(key) <= set("-: ") and key not in fields:
            fields[key] = val
    return fields


def is_placeholder(val: str) -> bool:
    v = val.strip()
    return v == "" or v.startswith("{") or v.startswith("<") or v in ("…", "...")


def tables_in(text: str):
    """Yield (header_cells, rows) for every markdown table in text."""
    lines = strip_noise(text).splitlines()
    i = 0
    while i < len(lines) - 1:
        if lines[i].lstrip().startswith("|") and re.match(r"^\s*\|?\s*:?-{2,}", lines[i + 1]):
            header = [c.strip() for c in lines[i].strip().strip("|").split("|")]
            rows, j = [], i + 2
            while j < len(lines) and lines[j].lstrip().startswith("|"):
                rows.append([c.strip() for c in lines[j].strip().strip("|").split("|")])
                j += 1
            yield header, rows
            i = j
        else:
            i += 1


def has_table_with(text: str, *cols: str) -> bool:
    want = [c.lower() for c in cols]
    for header, _rows in tables_in(text):
        low = " | ".join(h.lower() for h in header)
        if all(w in low for w in want):
            return True
    return False


def links_to(text: str, folder: str):
    """All paths in the text that point into `folder` (mockups, screenshots)."""
    return {m.group(1).rstrip(".,;:") for m in re.finditer(rf"((?:\./|\.\./|docs/)?{folder}/[^\s)\]\"'`>|]+)", text)}


def resolve(root: str, doc_path: str, link: str) -> bool:
    link = link.split("#", 1)[0]
    cands = [os.path.join(root, link), os.path.join(os.path.dirname(doc_path), link), os.path.join(root, "docs", link)]
    return any(os.path.exists(os.path.normpath(c)) for c in cands)


# ----------------------------------------------------------------------------
# schema
# ----------------------------------------------------------------------------
class Schema:
    def __init__(self, text: str):
        self.doc = self.file = None
        self.header = []
        self.sections = []  # (name, flag, max_words)
        self.budget = {}  # size -> (target, max)
        self.entries = None  # (section name, h3 prefix)
        self.per_entry = None  # (target, max)
        self.max_lines = self.target_lines = None
        self.rules = []
        m = re.search(r"<!--\s*tf-schema\s*\n(.*?)-->", text, re.S)
        if not m:
            raise ValueError("no tf-schema block")
        for raw in m.group(1).splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or ":" not in line:
                continue
            key, val = line.split(":", 1)
            key, val = key.strip().lower(), val.strip()
            if key == "doc":
                self.doc = val
            elif key == "file":
                self.file = val
            elif key == "header":
                self.header = [h.strip() for h in val.split(",") if h.strip()]
            elif key == "section":
                parts = [p.strip() for p in val.split("|")]
                flag = parts[1].lower() if len(parts) > 1 and parts[1] else "required"
                mx = None
                for p in parts[2:]:
                    mm = re.match(r"max\s+(\d+)", p, re.I)
                    if mm:
                        mx = int(mm.group(1))
                self.sections.append((parts[0], flag, mx))
            elif key == "budget":
                for part in val.split("|"):
                    bits = part.split()
                    if len(bits) == 3:
                        self.budget[bits[0].upper()] = (int(bits[1]), int(bits[2]))
            elif key == "entries":
                parts = [p.strip() for p in val.split("|")]
                self.entries = (parts[0], parts[1] if len(parts) > 1 else "")
            elif key == "per-entry":
                bits = val.split()
                self.per_entry = (int(bits[0]), int(bits[1]))
            elif key == "max-lines":
                self.max_lines = int(val)
            elif key == "target-lines":
                self.target_lines = int(val)
            elif key == "rule":
                self.rules.append(val.lower())

    def declared(self, present_key: str):
        for name, flag, mx in self.sections:
            if key_matches(norm_heading(name), present_key):
                return name, flag, mx
        return None


def load_schema(template_file: str) -> Schema:
    with open(os.path.join(TEMPLATE_DIR, template_file), encoding="utf-8") as fh:
        return Schema(fh.read())


# ----------------------------------------------------------------------------
# reporting and context
# ----------------------------------------------------------------------------
class Report:
    def __init__(self, warn_only: bool):
        self.warn_only = warn_only
        self.fails = self.warns = 0
        self.lines = []

    def fail(self, path, msg):
        if self.warn_only:
            self.warns += 1
            self.lines.append(f"WARN {path}: {msg}")
        else:
            self.fails += 1
            self.lines.append(f"FAIL {path}: {msg}")

    def warn(self, path, msg):
        self.warns += 1
        self.lines.append(f"WARN {path}: {msg}")


def detect_kind(path: str):
    name = os.path.basename(path).lower()
    if re.search(r"-deployment-checklist(-[\w]+)?\.md$", name):
        return "deployment-checklist", "app-deployment-checklist-tmpl.md"
    # phase 2 onward of a Large project: still a BRD to every cross-check, but it carries only
    # its own screens and requirements and points back at phase 1 for the rest (TF-024)
    if re.search(r"-p\d+-brd\.md$", name):
        return "brd", "app-phase-brd-tmpl.md"
    if re.search(r"-p\d+-uidesign\.md$", name):
        return "uidesign", "app-phase-uidesign-tmpl.md"
    for suffix, doc, tmpl in DOC_KINDS:
        if name.endswith(suffix):
            return doc, tmpl
    return None, None


def find_root(path: str) -> str:
    d = os.path.dirname(os.path.abspath(path))
    while True:
        if os.path.isdir(os.path.join(d, ".tfcore")) or os.path.isdir(os.path.join(d, "docs")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.dirname(os.path.abspath(path))
        d = parent


def read_core_config(root: str) -> dict:
    out = {}
    p = os.path.join(root, ".tfcore", "core-config.yaml")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^(appSize|appKind|appPhase):\s*(\S+)", line)
                if m and m.group(2) not in ("null", "~", "''", '""'):
                    out[m.group(1)] = m.group(2).strip("'\"")
    return out


def split_name(path: str):
    """'docs/MyApp-P2-BRD.md' -> ('MyApp', 2); 'docs/MyApp-BRD.md' -> ('MyApp', 1); other -> (None, 1)."""
    m = DOC_NAME.match(os.path.basename(path))
    if not m:
        return None, 1
    return m.group(1), int(m.group(2) or 1)


def phase_file(app: str, phase: int, suffix: str) -> str:
    return f"{app}-{suffix}.md" if phase <= 1 else f"{app}-P{phase}-{suffix}.md"


def sibling_brd_header(path: str) -> dict:
    """Size/Kind from docs/<App>-BRD.md when another document of the app lacks them."""
    base = os.path.basename(path)
    m = re.match(r"(.+?)-(Architecture|UIDesign|Checklist|Coding-Standards|UsageGuide|Usage-Guide|DevGuide|ProductGuide)\.md$", base, re.I)
    if not m:
        return {}
    brd = os.path.join(os.path.dirname(path), f"{m.group(1)}-BRD.md")
    if not os.path.exists(brd):
        return {}
    with open(brd, encoding="utf-8") as fh:
        return parse_header(fh.read())


def resolve_size(header, brd_header, cfg, cli_size, rep, rel, need):
    raw = header.get("size") or brd_header.get("size") or cfg.get("appSize") or cli_size
    if raw:
        size = SIZE_NAMES.get(str(raw).strip().lower())
        if size:
            return size
        if need:
            rep.warn(rel, f'Size "{raw}" is not Small, Medium or Large; Small assumed')
    elif need:
        rep.warn(rel, "no Size recorded (document header, the BRD header, or appSize in core-config.yaml); Small assumed")
    return "S"


def resolve_kind(header, brd_header, cfg) -> str:
    raw = (header.get("kind") or brd_header.get("kind") or cfg.get("appKind") or "app").strip().lower()
    return "library" if raw.startswith("lib") else "app"


def section_text(present, name):
    key = norm_heading(name)
    return next((txt for k, _h, txt in present if key_matches(key, k)), None)


# ----------------------------------------------------------------------------
# the checker
# ----------------------------------------------------------------------------
def check_document(path: str, rep: Report, cli_size=None, root=None):
    doc, tmpl = detect_kind(path)
    if not doc:
        rep.warn(path, "not a TechieFlow document name; skipped")
        return None
    try:
        schema = load_schema(tmpl)
    except (OSError, ValueError) as e:
        rep.warn(path, f"template {tmpl} has no usable tf-schema block ({e}); skipped")
        return None
    with open(path, encoding="utf-8") as fh:
        body = fh.read()
    root = root or find_root(path)
    rel = os.path.relpath(path, root)
    cfg = read_core_config(root)
    header = parse_header(body)
    brd_header = sibling_brd_header(path) if doc != "brd" else {}
    size = resolve_size(header, brd_header, cfg, cli_size, rep, rel, doc in SIZED_DOCS)
    kind = resolve_kind(header, brd_header, cfg)
    clean = strip_noise(body)
    nocomment = strip_comments(body)

    # 1. header fields
    for field in schema.header:
        val = header.get(field.lower())
        if val is None:
            rep.fail(rel, f'header field "{field}" is missing')
        elif is_placeholder(val):
            rep.fail(rel, f'header field "{field}" is still a placeholder')

    # 1b. the Phase field of a phased document (Large projects; Schemas §2)
    app, phase = split_name(path)
    if doc in PHASED_DOCS and app:
        phases_doc = os.path.join(os.path.dirname(path), f"{app}-Phases.md")
        pval = header.get("phase")
        if pval is not None and is_placeholder(pval):
            rep.fail(rel, 'header field "Phase" is still a placeholder; write "1 of 3", or delete the row when the project has no phases')
        elif pval is not None:
            m = PHASE_FORM.match(pval.strip("`* "))
            if not m:
                rep.fail(rel, f'header field "Phase" reads "{pval}"; it must read "<n> of <m>", for example "2 of 3"')
            elif int(m.group(1)) != phase:
                rep.fail(rel, f'header field "Phase" says {m.group(1)} but the file name says phase {phase} (phase 1 is {app}-{PHASED_SUFFIX[doc]}.md; phase n is {app}-Pn-{PHASED_SUFFIX[doc]}.md)')
        elif phase > 1:
            rep.fail(rel, f'a phase-{phase} file needs the header row "Phase | {phase} of <m>"')
        elif os.path.exists(phases_doc):
            rep.fail(rel, f'the project has phases ({os.path.relpath(phases_doc, root)}); this file needs the header row "Phase | 1 of <m>"')

    # 2. sections: strangers, order, presence
    present = [(norm_heading(h), h, txt) for h, txt in split_sections(clean, 2) if h is not None]
    always_ok = {"table of contents"} | ({"recovery note"} if doc == "project-status" else set())
    for key, h, txt in present:
        if schema.declared(key) or key in always_ok:
            continue
        if doc == "checklist" and re.search(r"<a id=['\"]d-req-", txt, re.I):
            continue  # a page group holding detail entries
        if doc == "feedback" and ENTRY_ID.match(h.strip()):
            continue  # an entry written at ## level: the layout every feedback file shipped
                      # with before this schema existed. Read as an entry, not a stranger.
        extra = "; bugs and feedback go to the misses stream, not the checklist" if doc == "checklist" else ""
        rep.fail(rel, f'section "{h}" is not in the template{extra}')

    order_of = {norm_heading(n): i for i, (n, _f, _m) in enumerate(schema.sections)}
    last_idx, last_name = -1, None
    for key, h, _txt in present:
        d = schema.declared(key)
        if not d:
            continue
        if doc == "feedback" and d[1] != "required":
            continue    # correspondence blocks are appended over time and sit either side
                        # of the entries; where they land carries no meaning
        idx = order_of[norm_heading(d[0])]
        if idx < last_idx:
            rep.fail(rel, f'section "{h}" comes after "{last_name}"; the template order is the other way round')
        else:
            last_idx, last_name = idx, h

    present_keys = [k for k, _h, _t in present]
    for name, flag, _mx in schema.sections:
        key = norm_heading(name)
        needed = (flag == "required" or (flag == "optional-small" and size in ("M", "L"))
                  or (flag == "app" and kind == "app") or (flag == "library" and kind == "library"))
        if needed and not any(key_matches(key, k) for k in present_keys):
            why = "" if flag == "required" else f" (required for {SIZE_LONG[size] if flag == 'optional-small' else kind})"
            rep.fail(rel, f'section "{name.rstrip("*")}" is missing{why}')

    # 3. budgets
    total = word_count(body)
    if size in schema.budget:
        target, mx = schema.budget[size]
        if total > mx:
            rep.fail(rel, f"{total:,} words; the {SIZE_LONG[size]} maximum is {mx:,} (target {target:,}). Shorten prose; never drop a screen, field or requirement to fit")
        elif total > target:
            rep.warn(rel, f"{total:,} words; the {SIZE_LONG[size]} target is {target:,} (maximum {mx:,})")
    for key, h, txt in present:
        d = schema.declared(key)
        if d and d[2]:
            # A `####` block inside a section is detail the reader chooses to open, and is not
            # counted — the same rule as a feedback entry's `#### Detail` (owner, 2026-09-08).
            n = word_count(re.split(r"(?m)^####\s", txt)[0])
            if n > d[2]:
                rep.fail(rel, f'section "{h}" is {n} words; at most {d[2]}')
    if schema.max_lines:
        n_lines = nocomment.strip().count("\n") + 1
        if n_lines > schema.max_lines:
            rep.fail(rel, f"{n_lines} lines; at most {schema.max_lines}")
        elif schema.target_lines and n_lines > schema.target_lines:
            rep.warn(rel, f"{n_lines} lines; the target is {schema.target_lines} (maximum {schema.max_lines})")

    # 4. per-entry checks (screens, tasks, components)
    entry_names = []
    if schema.entries:
        sec_txt = section_text(present, schema.entries[0])
        prefix = schema.entries[1]
        pairs = list(split_sections(sec_txt, 3)) if sec_txt is not None else []
        if doc == "feedback":
            # Entries may sit under "Entries" as ###, or stand at ## level as every
            # feedback file wrote them before this schema. Both are read the same way.
            pairs += [(h, t) for _k, h, t in present if ENTRY_ID.match(h.strip())]
            sec_txt = sec_txt if sec_txt is not None else ""
        if sec_txt is not None:
            for h3, etxt in pairs:
                if h3 is None:
                    continue
                if prefix and not h3.lower().startswith(prefix.lower()):
                    rep.fail(rel, f'entry "{h3}" must start with "{prefix}"')
                    continue
                ename = h3[len(prefix):].strip() if prefix else h3
                ename = re.sub(r"\s*\(.*$", "", ename).strip("` ").strip()
                entry_names.append(ename)
                if doc == "feedback" and FEEDBACK_CLOSED.search(etxt[:2500]):
                    continue    # a closed entry is the record of what was wrong and why.
                                # History may be as long as it needs to be; the shape and the
                                # word cap bind the LIVE ones, which are what the owner reads.
                if schema.per_entry:
                    # The cap binds the REPORT, not the working-out. Anything under a `####`
                    # heading inside the entry is detail a reader chooses to open, and is not
                    # counted: a thorough analysis is worth having, an entry the owner cannot
                    # read at a glance is not (owner, 2026-09-08).
                    n = word_count(re.split(r"(?m)^####\s", etxt)[0])
                    if n > schema.per_entry[1]:
                        rep.fail(rel, f'entry "{ename}" is {n} words; maximum {schema.per_entry[1]} (target {schema.per_entry[0]})')
                    elif n > schema.per_entry[0]:
                        rep.warn(rel, f'entry "{ename}" is {n} words; target {schema.per_entry[0]} (maximum {schema.per_entry[1]})')
                for rule in schema.rules:
                    if rule.startswith("entry-"):
                        check_entry_rule(rule, ename, etxt, rel, root, path, rep)
            if not entry_names and kind == "app":
                rep.fail(rel, f'section "{schema.entries[0].rstrip("*")}" has no "###" entries')

    # 5. document rules
    ctx = dict(doc=doc, body=body, clean=clean, nocomment=nocomment, present=present, header=header,
               size=size, kind=kind, root=root, path=path, rel=rel, entry_names=entry_names,
               app=app, phase=phase)
    for rule in schema.rules:
        if not rule.startswith("entry-"):
            check_doc_rule(rule, ctx, rep)
    return ctx


def check_entry_rule(rule, ename, etxt, rel, root, path, rep):
    if rule == "entry-mockup":
        links = links_to(etxt, "mockups")
        if not links:
            rep.fail(rel, f'screen "{ename}" has no mockup link (docs/mockups/<screen>.html)')
        for l in sorted(links):
            if not resolve(root, path, l):
                rep.fail(rel, f'screen "{ename}" links mockup {l}, which does not exist')
    elif rule == "entry-screenshot":
        imgs = re.findall(r"!\[[^\]]*\]\(([^)]+)\)", etxt)
        if not imgs:
            rep.fail(rel, f'entry "{ename}" has no screenshot image')
        for l in imgs:
            if not resolve(root, path, l):
                rep.fail(rel, f'entry "{ename}" screenshot {l} does not exist')
    elif rule == "entry-fields-table":
        if not has_table_with(etxt, "field", "type"):
            rep.fail(rel, f'screen "{ename}" has no fields table (Field, Type, Required, Validation)')
    elif rule == "entry-regions-table":
        if not has_table_with(etxt, "region", "control"):
            rep.fail(rel, f'screen "{ename}" has no regions-to-controls table')
    elif rule == "entry-states":
        low = etxt.lower()
        missing = [s for s in ("empty", "loading", "error") if s not in low]
        if missing:
            rep.fail(rel, f'screen "{ename}" does not say what it shows when {", ".join(missing)}')
    elif rule == "entry-break-table":
        if not has_table_with(etxt, "file", "function", "watch", "expected"):
            rep.fail(rel, f'entry "{ename}" has no where-to-break table (File and line, Function, Watch, Expected value)')
    elif rule == "entry-call-chain":
        if not re.search(r"(?im)^\**call chain:?\**", etxt):
            rep.fail(rel, f'entry "{ename}" has no "Call chain:" line')
    elif rule == "entry-steps":
        if not re.search(r"(?mi)^\s*(?:[-*]\s*[*_]*steps?[*_:]*\s*)?1[.)]\s+\S", etxt):
            rep.fail(rel, f'entry "{ename}" has no numbered steps')
    elif rule == "entry-expected":
        if not re.search(r"(?im)^\s*[-*]?\s*\**expected", etxt):
            rep.fail(rel, f'entry "{ename}" has no "Expected:" line')
    elif rule == "entry-feedback-fields":
        # A feedback entry is a bug report, not an essay. Same eight fields every time,
        # so the upstream team reads them in one shape and the owner reads "Blocks" first.
        for field in ("Severity", "Blocks", "Repro", "Expected", "Actual",
                      "Encountered in", "Workaround", "Suggested fix"):
            if not re.search(r"(?im)^\s*[-*]?\s*\**%s\**\s*:" % re.escape(field), etxt):
                rep.fail(rel, f'entry "{ename}" has no "{field}:" line')
    elif rule == "entry-blocks-line":
        # The one word that decides whether the run stops. "no" also has to say what was
        # done instead, because a non-blocking entry is filed and the work carries on.
        m = re.search(r"(?im)^\s*[-*]?\s*\**Blocks\**\s*:\s*(.+)$", etxt)
        if m:
            val = m.group(1).strip().strip("*` ").lower()
            if not re.match(r"^(yes|no)\b", val):
                rep.fail(rel, f'entry "{ename}" says "Blocks: {m.group(1).strip()[:40]}"; it must start "yes" or "no"')
            elif val.startswith("no") and len(val) < 8:
                rep.fail(rel, f'entry "{ename}" says "Blocks: no" and stops; say what was done instead and that the work carried on')
    elif rule == "entry-decision-options":
        if not has_table_with(etxt, "option", "what happens"):
            rep.fail(rel, f'decision "{ename}" has no options table (Option, What happens, What it costs)')
    elif rule == "entry-recommendation":
        if not re.search(r"(?im)^\s*\**My recommendation", etxt):
            rep.fail(rel, f'decision "{ename}" has no "My recommendation:" line — the owner is owed one, with the reason in a sentence')


def check_doc_rule(rule, c, rep):
    rel, root, path, body, clean, nocomment, present, size = (
        c["rel"], c["root"], c["path"], c["body"], c["clean"], c["nocomment"], c["present"], c["size"])

    if rule == "brd-ledger":
        ids = re.findall(r"\*\*BRD-(\d+)\*\*", clean)
        # the Non-functional table carries ids too (| BRD-31 | Performance | … |); they count,
        # they need checklist rows, and they must sit inside the phase's range
        nfr = section_text(present, "Non-functional requirements") or ""
        ids += re.findall(r"(?m)^\s*\|\s*`?\**BRD-(\d+)", nfr)
        if not ids:
            rep.fail(rel, "no **BRD-N** items found in the Requirements section")
            return
        seen, dupes = set(), set()
        for i in ids:
            (dupes if i in seen else seen).add(i)
        if dupes:
            rep.fail(rel, "duplicate requirement ids: " + ", ".join(f"BRD-{d}" for d in sorted(dupes, key=int)))
        if len(seen) > REQ_CAP[size]:
            rep.fail(rel, f"{len(seen)} requirements; the {SIZE_LONG[size]} cap is {REQ_CAP[size]}. Split into phases (each phase its own BRD) instead of growing this one")
        c["brd_ids"] = seen
        req = section_text(present, "Requirements") or ""
        cur = None
        for line in req.splitlines():
            m = re.search(r"\*\*BRD-(\d+)\*\*", line)
            if m:
                cur = m.group(1)
            if cur and ACCEPT_LINE.search(line):
                n_acc = acceptance_words(line)
                if n_acc > ACC_MAX:
                    rep.fail(rel, f"BRD-{cur} acceptance line is {n_acc} words; at most {ACC_MAX} (target {ACC_TARGET}). One behaviour per item: split it, do not bundle steps")
                elif n_acc > ACC_TARGET:
                    rep.warn(rel, f"BRD-{cur} acceptance line is {n_acc} words; the target is {ACC_TARGET} (maximum {ACC_MAX})")

    elif rule == "phase-pointer":
        # a phase BRD leaves scope, users, the whole-app non-functionals, constraints and risks to
        # phase 1, and a phase UIDesign the design system and the click-through flow; this section is
        # how a reader finds them, so it must actually lead to the phase-1 document of the same kind
        txt = section_text(present, "Where the rest lives")
        if txt is None or not c.get("app"):
            return
        want = phase_file(c["app"], 1, PHASED_SUFFIX[c["doc"]])
        hits = [l for l in re.findall(r"\]\(([^)\s]+)\)", txt)
                if os.path.basename(l.split("#", 1)[0]).lower() == want.lower()]
        if not hits:
            rep.fail(rel, f'the "Where the rest lives" section does not link to the phase-1 document ({want}), '
                          f'where everything the whole application shares lives')
        elif not any(resolve(root, path, l) for l in hits):
            rep.fail(rel, f'the "Where the rest lives" link to {hits[0]} points at a file that does not exist')

    elif rule == "mockup-links":
        for l in sorted(links_to(clean, "mockups")):
            if not resolve(root, path, l):
                rep.fail(rel, f"mockup link {l} points at a file that does not exist")

    elif rule == "screens-table":
        txt = section_text(present, "Screens and flow")
        if txt is None:
            return
        if not has_table_with(txt, "screen", "route", "mockup"):
            rep.fail(rel, 'the "Screens and flow" table needs the columns Screen, Route, Role, Mockup, Fields')
            return
        names = []
        for header, rows in tables_in(txt):
            low = [h.lower() for h in header]
            if "screen" in low and "route" in low:
                sc, rc = low.index("screen"), low.index("route")
                for r in rows:
                    if len(r) <= max(sc, rc) or not r[sc] or r[sc].startswith("{"):
                        continue
                    if "dialog" in r[sc].lower() or r[rc].strip("` ").lower().startswith("on "):
                        continue
                    names.append(r[sc])
        c["brd_screens"] = names

    elif rule == "stack-table":
        txt = section_text(present, "Stack decisions")
        if txt is not None and not any(True for _ in tables_in(txt)):
            rep.fail(rel, 'the "Stack decisions" section needs a table (one row per stack question)')

    elif rule == "solution-table":
        txt = section_text(present, "Solution structure")
        if txt is not None and not has_table_with(txt, "project", "kind"):
            rep.fail(rel, 'the "Solution structure" table needs the columns Project, Kind, Purpose')

    elif rule == "stack-rows":
        # one row per stack question; Q9 and Q10 (hosting, production secrets) are decided after UAT
        txt = section_text(present, "Stack decisions")
        if txt is None:
            return
        have = set()
        for _h, rows in tables_in(txt):
            for r in rows:
                m = re.match(r"q\s*(\d+)", r[0].strip("`* ").lower()) if r else None
                if m:
                    have.add(int(m.group(1)))
        missing = [q for q in (1, 2, 3, 4, 5, 6, 7, 8, 11) if q not in have]
        if missing:
            rep.fail(rel, "the Stack decisions table has no row for " + ", ".join(f"Q{q}" for q in missing)
                     + "; one row per stack question, citing its source (Q9 and Q10 are decided after UAT)")

    elif rule == "head-project":
        # an app's primary head project is named exactly <App>; <App>.App is refused (Stack Q7, owner 2026-09-06)
        txt = section_text(present, "Solution structure")
        app = c.get("app")
        if txt is None or c["kind"] != "app" or not app:
            return
        names = [r[0].strip("`* ") for _h, rows in tables_in(txt) for r in rows if r and r[0].strip()]
        names = [n for n in names if not is_placeholder(n)]
        bad = [n for n in names if re.fullmatch(rf"{re.escape(app)}\.App", n, re.I)]
        if bad:
            rep.fail(rel, f'project "{bad[0]}" is named <App>.App; the primary head is named exactly "{app}" (Stack Q7)')
        elif names and not any(n.lower() == app.lower() for n in names):
            rep.fail(rel, f'no project named exactly "{app}" in the Solution structure; the primary head carries the product name (Stack Q7)')

    elif rule == "er-diagram":
        if section_text(present, "Data model") is not None and not re.search(r"```mermaid\s*\n\s*erDiagram", nocomment):
            rep.fail(rel, 'the "Data model" section needs a mermaid erDiagram')

    elif rule == "decisions-log":
        txt = section_text(present, "Decisions log")
        if txt is not None and not has_table_with(txt, "date", "decision", "why", "status"):
            rep.fail(rel, 'the "Decisions log" table needs the columns Date, Decision, Why, Status')

    elif rule == "request-flow":
        txt = section_text(present, "Component map")
        if txt is not None and not re.search(r"(?im)^\**how a request travels", txt):
            rep.fail(rel, 'the "Component map" section needs a "How a request travels" numbered list')

    elif rule == "execution-code":
        seg = re.search(r"(?ms)^##\s+(?:\d+[.)]\s+)?Execution guide.*?\n(.*?)(?=^## |\Z)", nocomment)
        if seg and "```" not in seg.group(1):
            rep.fail(rel, 'the "Execution guide" needs the start commands in a code block')

    elif rule == "test-users-table":
        txt = section_text(present, "Test users")
        if txt is not None and not has_table_with(txt, "user", "role"):
            rep.fail(rel, 'the "Test users" section needs a table with User and Role columns')

    elif rule == "next-command-blocks":
        seg = re.search(r"(?ms)^## Next command to run\s*\n(.*?)(?=^## |\Z)", nocomment)
        if not seg:
            return
        txt = seg.group(1)
        blocks = re.findall(r"```[^\n]*\n(.*?)```", txt, re.S)
        if len(blocks) != 2:
            rep.fail(rel, f'"Next command to run" must hold exactly two code blocks, Claude Code then OpenCode; found {len(blocks)}')
            return
        for label, blk in zip(("Claude Code", "OpenCode"), blocks):
            lines = [l for l in blk.splitlines() if l.strip()]
            if len(lines) != 1:
                rep.fail(rel, f"the {label} command block must be one line; found {len(lines)}")
        parts = txt.split("```")
        if "claude code" not in parts[0].lower():
            rep.fail(rel, 'the first command block must be labelled "Claude Code" on the line before it')
        if len(parts) > 2 and "opencode" not in parts[2].lower():
            rep.fail(rel, 'the second command block must be labelled "OpenCode" on the line before it')

    elif rule == "verification-log":
        txt = section_text(present, "Verification log")
        if txt is None:
            return
        for _h, rows in tables_in(txt):
            if len(rows) > 5:
                rep.fail(rel, f"the Verification log holds {len(rows)} rows; keep the last five, the rest lives in gates.jsonl and runs.jsonl")
            for r in rows:
                for cell in r:
                    n = len(re.findall(r"\S+", cell))
                    if n > 20:
                        rep.fail(rel, f"a Verification log cell is {n} words; at most 20, a result is a count not a story")
                        break

    elif rule == "open-requirements-max-10":
        txt = section_text(present, "Open requirements")
        if txt is not None:
            n = len(re.findall(r"(?m)^\s*[-*]\s*\[?[ x]?\]?\s*REQ-", txt))
            if n > 10:
                rep.fail(rel, f"Open requirements names {n} rows; show counts by status and at most ten named rows")

    elif rule == "checklist-rows":
        check_checklist(c, rep)

    elif rule == "standards-pointer":
        if ".tfcore/standards/" not in body:
            rep.fail(rel, "must name the framework standard files it applies (.tfcore/standards/...)")

    elif rule == "deploy-who-table":
        txt = section_text(present, "Who does what")
        if txt is not None and not has_table_with(txt, "step", "done by"):
            rep.fail(rel, 'the "Who does what" section needs a table with the columns Step and Done by')

    elif rule == "deploy-secrets-once":
        txt = section_text(present, "Secrets and settings")
        if txt is None:
            return
        names = []
        for header, rows in tables_in(txt):
            low = [h.lower() for h in header]
            if "name" in low:
                names += [r[low.index("name")].strip("`* ") for r in rows if r and r[low.index("name")].strip()]
        if not names:
            rep.fail(rel, 'the "Secrets and settings" table needs the columns Name, Where it is set, What breaks without it, and at least one row')
            return
        dupes = sorted({n for n in names if names.count(n) > 1})
        if dupes:
            rep.fail(rel, "a secret or setting is listed more than once: " + ", ".join(dupes))
        # named again as the first cell of a row in any other table: re-described elsewhere
        for key, h, other in present:
            if key_matches(norm_heading("Secrets and settings"), key):
                continue
            for _hdr, rows in tables_in(other):
                for r in rows:
                    if r and r[0].strip("`* ") in names:
                        rep.fail(rel, f'"{r[0].strip("`* ")}" is described again under "{h}"; each secret or setting appears in exactly one row of Secrets and settings')

    elif rule == "deploy-checkboxes":
        for name in ("Before the first deploy", "Deploy", "After the deploy", "Rollback"):
            txt = section_text(present, name)
            if txt is None:
                continue
            boxes = 0
            for line in txt.splitlines():
                t = line.strip()
                if not t or t.startswith("|") or t.startswith("<"):
                    continue
                if re.match(r"^[-*]\s*\[[ xX]\]\s+\S", t):
                    boxes += 1
                elif name == "Rollback" and re.match(r"^A rollback does not undo", t, re.I):
                    continue
                else:
                    rep.fail(rel, f'"{name}" holds a line that is not a checkbox: "{t[:60]}"; every item is "- [ ] action — result", no narrative')
            if boxes == 0:
                rep.fail(rel, f'"{name}" has no checkbox items')
            if name == "Rollback" and not re.search(r"(?im)^A rollback does not undo", txt):
                rep.fail(rel, 'the "Rollback" section needs the line "A rollback does not undo: …"')

    elif rule == "deploy-proven":
        val = (c["header"].get("proven") or "").strip("`* ")
        if val and not (val.lower() == "never" or re.fullmatch(r"\d{4}-\d{2}-\d{2}", val)):
            rep.fail(rel, f'header field "Proven" reads "{val}"; write "never" or the date of the last real deploy')
        txt = section_text(present, "Proven")
        if txt is not None and not has_table_with(txt, "what", "executed", "when"):
            rep.fail(rel, 'the "Proven" section needs a table with the columns What, Executed for real, When')
        tgt = (c["header"].get("hosting target") or "")
        if re.search(r"\b(and|or)\b|,|/", tgt):
            rep.fail(rel, f'Hosting target "{tgt}" names more than one target; one document per hosting target')

    elif rule == "brief-must-do":
        txt = section_text(present, "Must do")
        if txt is None:
            return
        n = len(re.findall(r"(?m)^\s*\d+[.)]\s+\S", txt))
        if n == 0:
            rep.fail(rel, 'the "Must do" section is not a numbered list; day-1 turns each line into requirements, so one line is one thing the product does')
        elif n > 25:
            rep.fail(rel, f'the "Must do" section has {n} lines; a brief that long is a BRD. Keep the page, and let day-1 expand it')

    elif rule == "no-glossary":
        # A document written for the owner explains itself in plain words or it is
        # written wrong. A section that defines the document's own vocabulary before it
        # can ask its question is the tell: the fix is to change the words, never to
        # teach them (owner, 2026-09-08).
        for _key, h, _txt in present:
            if re.search(r"(?i)\b(glossary|terminology|words this document uses|"
                         r"terms? (used|you)|what these words mean|definitions)\b", h):
                rep.fail(rel, f'section "{h}" defines this document\'s own vocabulary; '
                              f'write it in plain English instead — if a word needs a glossary, use a different word')

    elif rule == "feedback-blocking-count":
        txt = section_text(present, "Summary")
        if txt is None:
            return
        if not re.search(r"(?i)\bblocking\b|\bnothing is blocked\b", txt):
            rep.fail(rel, 'the Summary must say how many entries are blocking right now, '
                          'or "Nothing is blocked" — it is the first thing the owner reads')
        # ... and its counts must be the entries' own. TfLens's read "20 entries, 8 open" over 27
        # entries with 7 fixed upstream, and a TrBlazeUI file "all 28 open, none fixed upstream"
        # under the library's own reply fixing 24 of them (MISS-TechieFlow-20260911-04).
        sys.path.insert(0, SELF_DIR)
        import tf_feedback
        es = tf_feedback.entries(path)
        n = {s: [e["id"] for e in es if e["state"] == s] for s in ("open", "fixed", "closed")}
        truth = (f"{len(es)} entries: {len(n['open'])} open, {len(n['fixed'])} fixed upstream and not yet "
                 f"re-checked, {len(n['closed'])} closed")
        head = re.split(r"(?m)^####\s", txt)[0]
        said_total = re.search(r"(?i)\b(\d+)\s+entries\b", head)
        said_open = re.search(r"(?i)\b(?:all\s+)?(\d+)\s+(?:filed and\s+)?open\b", head)
        wrong = ((said_total and int(said_total.group(1)) != len(es))
                 or (said_open and int(said_open.group(1)) != len(n["open"])))
        if wrong:
            rep.fail(rel, f"the Summary's counts are not the entries' — the file holds {truth}; "
                          f"rewrite it from: bash .tfcore/utils/tf-feedback.sh {os.path.basename(path).split('-')[0]}")
        elif n["fixed"] and not re.search(r"(?i)fixed upstream|re-?check", head):
            rep.fail(rel, f"{len(n['fixed'])} entries are fixed upstream and not yet re-checked here "
                          f"({', '.join(n['fixed'][:5])}{' …' if len(n['fixed']) > 5 else ''}); the Summary must say so")

    elif rule == "paste-back-block":
        # `present` is built from the prose-only copy, which drops fenced blocks — and a
        # fenced block is exactly what this rule looks for. Re-split the uncommented source.
        raw_present = [(norm_heading(h), h, t) for h, t in split_sections(nocomment, 2) if h is not None]
        txt = section_text(raw_present, "Copy this back to me")
        if txt is None:
            return
        blocks = re.findall(r"^```", txt, re.M)
        if len(blocks) < 2:
            rep.fail(rel, 'the "Copy this back to me" section has no fenced block; '
                          'the owner answers by pasting it, so it must be there to paste')
        n_dec = len(c.get("entry_names") or [])
        if n_dec and len(blocks) // 2 < n_dec:
            rep.fail(rel, f'{n_dec} decisions but {len(blocks) // 2} paste-back block(s); one per decision')

    elif rule == "phases-table":
        txt = section_text(present, "Phases")
        if txt is None:
            return
        if not has_table_with(txt, "phase", "name", "screens", "brd range", "status"):
            rep.fail(rel, 'the "Phases" table needs the columns Phase, Name, Screens, BRD range, Status')
            return
        rows_out = []
        for header, rows in tables_in(txt):
            low = [h.lower() for h in header]
            if not all(k in low for k in ("phase", "name", "screens", "brd range", "status")):
                continue
            ip, iname, iscr, irng, ist = (low.index(k) for k in ("phase", "name", "screens", "brd range", "status"))
            for r in rows:
                if len(r) <= max(ip, iname, iscr, irng, ist):
                    continue
                pnum = r[ip].strip("`* ")
                if not pnum.isdigit():
                    rep.fail(rel, f'Phases row "{r[ip]}": the Phase cell must be a number')
                    continue
                n = int(pnum)
                if is_placeholder(r[iname]):
                    rep.fail(rel, f"phase {n} has no name")
                screens = [s.strip("`* ") for s in r[iscr].split(",") if s.strip()]
                if not screens or any(is_placeholder(s) for s in screens):
                    rep.warn(rel, f"phase {n} lists no screens")
                    screens = [s for s in screens if not is_placeholder(s)]
                # one range, or several separated by commas when items were added to an earlier phase
                # after a later one existed ("BRD-1 to BRD-73, BRD-111 to BRD-118"): ids run on, never renumber
                ranges = [(int(x), int(y)) for x, y in BRD_RANGE.findall(r[irng])] if not is_placeholder(r[irng]) else []
                lo = hi = None
                if not ranges:
                    rep.fail(rel, f'phase {n} BRD range "{r[irng]}" must read "BRD-<a> to BRD-<b>" (several ranges separated by commas are allowed)')
                else:
                    lo, hi = ranges[0]
                    for x, y in ranges:
                        if x > y:
                            rep.fail(rel, f"phase {n} BRD range runs backwards ({x} to {y})")
                st = r[ist].strip("`* ").lower()
                if st not in PHASE_STATUS:
                    rep.fail(rel, f'phase {n} status "{r[ist]}" must be planned, building or done')
                rows_out.append(dict(n=n, name=r[iname].strip("`* "), screens=screens, lo=lo, hi=hi, ranges=ranges, status=st))
        nums = [p["n"] for p in rows_out]
        if nums != list(range(1, len(nums) + 1)):
            rep.fail(rel, f"phases must be numbered 1, 2, 3 … in order; found {', '.join(str(x) for x in nums) or 'none'}")
        for a in rows_out:
            for b in rows_out:
                if a["n"] >= b["n"]:
                    continue
                for x1, y1 in a["ranges"]:
                    for x2, y2 in b["ranges"]:
                        if x1 <= y2 and x2 <= y1:
                            rep.fail(rel, f"phase {a['n']} (BRD-{x1} to BRD-{y1}) and phase {b['n']} (BRD-{x2} to BRD-{y2}) overlap; ids run on across phases and are never reused")
        seen = {}
        for p in rows_out:
            for s in p["screens"]:
                key = s.lower()
                if key in seen and seen[key] != p["n"]:
                    rep.fail(rel, f'screen "{s}" is in phase {seen[key]} and phase {p["n"]}; a screen sits in exactly one phase')
                seen[key] = p["n"]
        if not rows_out:
            rep.fail(rel, 'the "Phases" table has no rows')
        c["phases"] = rows_out


def check_checklist(c, rep):
    rel, root, path, body, clean, present, size = (
        c["rel"], c["root"], c["path"], c["body"], c["clean"], c["present"], c["size"])
    txt = section_text(present, "Requirements Status")
    if txt is None:
        return
    if not any(re.sub(r"\s+", " ", l.strip()) == CHECKLIST_HEADER for l in clean.splitlines()):
        rep.fail(rel, f"the Requirements Status table header must be exactly {CHECKLIST_HEADER}")
    rows = [l for l in txt.splitlines() if re.match(r"^\s*\|\s*REQ-", l)]
    ids = []
    row_status = {}
    for l in rows:
        cells = [x.strip() for x in l.strip().strip("|").split("|")]
        if len(cells) < 6:
            rep.fail(rel, f"row {cells[0] if cells else '?'} has {len(cells)} cells; six are needed")
            continue
        rid, _req, status, pct, remarks, details = cells[:6]
        rid = rid.strip("`* ")
        ids.append(rid)
        row_status[rid] = status.strip("`* ").lower()
        if not re.fullmatch(r"REQ-(UI|FN|RAG|NFR)-\d{3}", rid):
            rep.fail(rel, f'id "{rid}" is not REQ-UI/FN/RAG/NFR- plus three digits')
        if status.strip("`* ").lower() not in STATUS_VALUES:
            rep.fail(rel, f'{rid} status "{status}" is not one of the fixed values')
        if pct.strip("`* ").rstrip("%").strip() not in ("0", "25", "50", "75", "100"):
            rep.fail(rel, f'{rid} % "{pct}" must be 0, 25, 50, 75 or 100')
        n = len(re.findall(r"\S+", remarks))
        if n > 60:
            rep.fail(rel, f"{rid} Remarks is {n} words; at most 60, current state only (history lives in the telemetry streams)")
        if NOT_PRESENT.search(remarks) and not NAMES_PATH.search(remarks):
            rep.fail(rel, f"{rid} Remarks says something is not present without naming the path that was tried; search tools skip .tfcore/, so read the literal path first")
        m = re.search(r"\(#([^)]+)\)", details)
        if not m:
            rep.fail(rel, f"{rid} Details cell has no link to its detail entry")
        elif not re.search(rf"<a id=['\"]{re.escape(m.group(1))}['\"]", body):
            rep.fail(rel, f"{rid} Details link #{m.group(1)} has no matching anchor in this file")
    if not ids:
        rep.fail(rel, "the Requirements Status table has no REQ- rows")
    if len(ids) > REQ_CAP[size]:
        rep.fail(rel, f"{len(ids)} rows; the {SIZE_LONG[size]} cap is {REQ_CAP[size]}. Split into phases instead of growing this checklist")
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        rep.fail(rel, "duplicate rows: " + ", ".join(dupes))

    brd_refs = set()
    for rid in ids:
        # a row logged from UAT by *triage-issues or *log-miss has no BRD item until *amend-docs
        # gives it one; it carries the marker BRD-pending and stays Not Started (Sitting 4c, 2026-09-06)
        m = re.search(rf"<a id=['\"]d-{re.escape(rid.lower())}['\"]", body)
        if not m:
            continue  # reported above through the Details link
        pos = m.start()
        nxt = re.search(r"\n\s*(?:[-*]\s*)?<a id=|\n## |\n### ", body[pos + 1:])   # an entry is a list item: the dash precedes the anchor (miss 21)
        entry = body[pos: pos + 1 + nxt.start()] if nxt else body[pos:]
        acc = [l for l in entry.splitlines() if ACCEPT_LINE.search(l)]
        if len(acc) != 1:
            rep.fail(rel, f"{rid} must have exactly one acceptance line; found {len(acc)}")
        elif not ACCEPT_FORM.match(acc[0]):
            rep.fail(rel, f'{rid} acceptance line does not read "When <actor> <does what> on <screen>, then <observable result>"')
        elif rid.startswith(("REQ-UI", "REQ-FN")) and not NAMES_SCREEN.search(acc[0].split(", then", 1)[0]):
            rep.fail(rel, f'{rid} acceptance line must name the screen ("… on <screen>, then …")')
        if len(acc) == 1:
            n_acc = acceptance_words(acc[0])
            if n_acc > ACC_MAX:
                rep.fail(rel, f"{rid} acceptance line is {n_acc} words; at most {ACC_MAX} (target {ACC_TARGET}). One behaviour per row: split it, do not bundle steps")
            elif n_acc > ACC_TARGET:
                rep.warn(rel, f"{rid} acceptance line is {n_acc} words; the target is {ACC_TARGET} (maximum {ACC_MAX})")
        for l in entry.splitlines():
            if "perf-budget:" in l.lower() and not PERF_BUDGET.search(l):
                rep.fail(rel, f"{rid} perf-budget line is not in the form perf-budget: <p50|p95|max> <ttfb|load> <= <N>ms [@ concurrency <N>]")
        refs = re.findall(r"BRD-(\d+)", entry)
        if not refs and "brd-pending" in entry.lower() and row_status.get(rid) == "not started":
            rep.warn(rel, f"{rid} is a Not Started row logged from UAT with BRD-pending; *amend-docs gives it its BRD item")
        elif not refs:
            rep.fail(rel, f"{rid} detail entry does not name its BRD-N item")
        brd_refs.update(refs)
        if rid.startswith("REQ-UI"):
            links = links_to(entry, "mockups")
            if not links:
                rep.fail(rel, f"{rid} is a UI row without a mockup link")
            for l in sorted(links):
                if not resolve(root, path, l):
                    rep.fail(rel, f"{rid} mockup {l} does not exist")
    c["checklist_brd_refs"] = brd_refs
    c["checklist_ids"] = ids


# ----------------------------------------------------------------------------
# cross-document rules
# ----------------------------------------------------------------------------
def _screen_key(s):
    s = re.sub(r"\s*[—(].*$", "", s.strip("`* "))   # "Profile (planned)" -> "Profile"
    return re.sub(r"\s+", " ", s).strip().lower()


def cross_checks(ctxs: dict, rep: Report, root: str):
    """ctxs is keyed by (doc, phase). Single documents sit at phase 1."""
    phases = sorted({p for (_d, p) in ctxs})
    for p in phases:
        brd, ui, cl = ctxs.get(("brd", p)), ctxs.get(("uidesign", p)), ctxs.get(("checklist", p))
        if brd and ui and brd.get("brd_screens") is not None and ui["kind"] == "app":
            b = {_screen_key(s) for s in brd["brd_screens"]}
            u = {_screen_key(s) for s in ui["entry_names"]}
            for s in sorted(b - u):
                rep.fail(brd["rel"], f'screen "{s}" is in the BRD but has no "### Screen:" entry in the UIDesign')
            for s in sorted(u - b):
                rep.fail(ui["rel"], f'screen "{s}" is in the UIDesign but not in the BRD screens table')
        if brd and cl and brd.get("brd_ids") is not None and cl.get("checklist_brd_refs") is not None:
            missing = sorted(brd["brd_ids"] - cl["checklist_brd_refs"], key=int)
            if missing:
                shown = ", ".join(f"BRD-{m}" for m in missing[:20]) + (" …" if len(missing) > 20 else "")
                rep.fail(cl["rel"], f"BRD items with no checklist row ({len(missing)}): {shown}")
    uis = [ctxs[k] for k in sorted(ctxs) if k[0] == "uidesign"]
    if uis:
        mock_dir = os.path.join(root, "docs", "mockups")
        if os.path.isdir(mock_dir):
            linked = set()
            for ui in uis:
                linked |= {os.path.basename(l.split("#")[0]) for l in links_to(ui["clean"], "mockups")}
            for f in sorted(os.listdir(mock_dir)):
                if f.lower().endswith(".html") and f not in linked:
                    rep.warn(uis[0]["rel"], f"mockup {f} is not linked from any screen")
            check_mockups(root, rep)
    cross_phase_checks(ctxs, rep, root, phases)


def cross_phase_checks(ctxs, rep, root, phases):
    """Large projects: ids never reused across phases, every screen in exactly one phase,
    every phase row backed by its files (docs/TechieFlow-Document-Schemas.md §2, §3.11)."""
    ph = ctxs.get(("phases", 1))
    brds = {p: c for (d, p), c in ctxs.items() if d == "brd"}
    cls = {p: c for (d, p), c in ctxs.items() if d == "checklist"}
    uis = {p: c for (d, p), c in ctxs.items() if d == "uidesign"}
    app = next((c["app"] for c in ctxs.values() if c.get("app")), None)

    seen = {}
    for p in sorted(brds):
        for i in sorted(brds[p].get("brd_ids") or (), key=int):
            if i in seen:
                rep.fail(brds[p]["rel"], f"BRD-{i} is also in phase {seen[i]}'s BRD; ids run on across phases and are never reused")
            seen[i] = p
    seen = {}
    for p in sorted(cls):
        for i in cls[p].get("checklist_ids") or ():
            if i in seen and seen[i] != p:
                rep.fail(cls[p]["rel"], f"{i} is also in phase {seen[i]}'s checklist; REQ ids run on across phases and are never reused")
            seen.setdefault(i, p)

    if not ph:
        if len(phases) > 1 and app:
            rep.fail(f"docs/{app}-Phases.md", f"phase files exist ({', '.join(f'P{p}' for p in phases if p > 1)}) but the Phases document does not; write it from app-phases-tmpl.md")
        return
    rows = ph.get("phases") or []
    if not rows:
        return
    docs = os.path.dirname(ph["path"])
    app = app or ph["app"]
    for r in rows:
        n = r["n"]
        brd_name = phase_file(app, n, "BRD")
        if not os.path.exists(os.path.join(docs, brd_name)):
            rep.fail(ph["rel"], f"phase {n} has no BRD: docs/{brd_name} does not exist")
        cl_name = phase_file(app, n, "Checklist")
        if not os.path.exists(os.path.join(docs, cl_name)):
            rep.warn(ph["rel"], f"phase {n} has no checklist yet (docs/{cl_name}); day-1 stage 2 writes it")
        b = brds.get(n)
        if b and b.get("brd_ids") and r.get("ranges"):
            out = sorted((i for i in b["brd_ids"] if not any(x <= int(i) <= y for x, y in r["ranges"])), key=int)
            if out:
                shown = ", ".join(f"BRD-{i}" for i in out[:10]) + (" …" if len(out) > 10 else "")
                rng = ", ".join(f"BRD-{x} to BRD-{y}" for x, y in r["ranges"])
                rep.fail(b["rel"], f"{len(out)} requirement(s) outside phase {n}'s range {rng}: {shown}; add a second range to the Phases row for items added later")
        u = uis.get(n)
        if u and u["kind"] == "app":
            want = {_screen_key(s) for s in r["screens"]}
            have = {_screen_key(s) for s in u["entry_names"]}
            for s in sorted(have - want):
                rep.fail(ph["rel"], f'screen "{s}" is in phase {n}\'s UIDesign but not in its Phases row')
            for s in sorted(want - have):
                rep.fail(ph["rel"], f'screen "{s}" is listed under phase {n} but has no "### Screen:" entry in {os.path.basename(u["path"])}')
    listed = {n for n in (p for p in phases) if any(r["n"] == n for r in rows)}
    for p in sorted(phases):
        if p not in listed and (p in brds or p in cls or p in uis):
            rep.fail(ph["rel"], f"phase {p} has files but no row in the Phases table")


ENTRY_NAMES = ("login", "signin", "sign-in", "onboarding", "welcome", "splash", "lock", "index", "home", "dashboard", "landing", "start")
ANCHOR_HREF = re.compile(r"""<a\b[^>]*\bhref\s*=\s*["']([^"'#?]+)""", re.I)
LINK_TAG = re.compile(r"<link\b[^>]*>", re.I)
TAG_HREF = re.compile(r"""\bhref\s*=\s*["']([^"'#?]+)""", re.I)
FORM_ACTION = re.compile(r"""<form\b[^>]*\baction\s*=\s*["']([^"'#?]+)""", re.I)
BUTTON = re.compile(r"<button\b[^>]*>", re.I)
# navigation done by script instead of a link: works only where scripts run, so a viewer
# without them (a preview pane, a rendered-doc iframe) shows a dead page (owner, 2026-09-05)
SCRIPT_NAV = re.compile(r"""onclick\s*=\s*["'][^"']*(?:location\.href|window\.location|location\.(?:assign|replace)|history\.(?:back|go))[^"']*["']""", re.I)
SCRIPT_NAV_TARGET = re.compile(r"""(?:location\.href|window\.location(?:\.href)?|location\.(?:assign|replace))\s*(?:=|\()\s*["']([^"'#?]+)""", re.I)
NAV_BLOCK = re.compile(r"<nav\b[^>]*>(.*?)</nav>", re.I | re.S)
NAV_ITEM = re.compile(r"""<(div|li|span|button)\b[^>]*\bclass\s*=\s*["'][^"']*(?:item|link|tab)[^"']*["'][^>]*>(.*?)</\1>""", re.I | re.S)


def _mock_target(mock_dir: str, t: str):
    """Resolve a link the way a browser opening docs/mockups/<file> would. Returns the file
    name when it lands on an existing file inside the mockup folder, else None."""
    if re.match(r"^(https?:|mailto:|tel:|javascript:|data:)", t, re.I) or t.startswith("/"):
        return None
    p = os.path.normpath(os.path.join(mock_dir, t))
    if os.path.dirname(p) != os.path.normpath(mock_dir) or not os.path.isfile(p):
        return None
    return os.path.basename(p)


def check_mockups(root: str, rep: Report):
    """A mockup set is a click-through: every link resolves, every screen is reachable from
    the entry screen, every screen has a way out, every button does something, and every
    file carries data-testid anchors the verifier can grade (FR-53, owner rule 2026-09-05).
    Since Sitting 4b: navigation is an <a href>, never a script; a menu item goes somewhere;
    a link is resolved from the mockup's own folder, not by its file name; stylesheets exist."""
    mock_dir = os.path.join(root, "docs", "mockups")
    files = sorted(f for f in os.listdir(mock_dir) if f.lower().endswith((".html", ".htm")))
    if not files:
        return
    rel_dir = "docs/mockups"
    out_links = {}
    for f in files:
        try:
            with open(os.path.join(mock_dir, f), encoding="utf-8", errors="replace") as fh:
                html = fh.read()
        except Exception:
            continue
        rel = f"{rel_dir}/{f}"
        if "data-testid" not in html:
            rep.fail(rel, "mockup has no data-testid anchors; the verifier cannot compare the built screen to it")
        targets = []
        for m in list(ANCHOR_HREF.finditer(html)) + list(FORM_ACTION.finditer(html)):
            t = m.group(1).strip()
            if not t or re.match(r"^(https?:|mailto:|tel:|javascript:|data:)", t, re.I):
                continue
            if not t.lower().endswith((".html", ".htm")):
                continue
            name = _mock_target(mock_dir, t)
            if name is None:
                hint = "write the file name alone, not a folder or a leading slash" if ("/" in t) else "the file does not exist"
                rep.fail(rel, f'links to "{t}", which does not open from docs/mockups/ ({hint})')
            else:
                targets.append(name)
        for m in LINK_TAG.finditer(html):
            tag = m.group(0)
            if not re.search(r"""rel\s*=\s*["']stylesheet["']""", tag, re.I):
                continue
            h = TAG_HREF.search(tag)
            if h and not re.match(r"^https?:", h.group(1), re.I) and _mock_target(mock_dir, h.group(1).strip()) is None:
                rep.fail(rel, f'stylesheet "{h.group(1)}" does not open from docs/mockups/; the mockup renders unstyled')
        nav_by_script = SCRIPT_NAV.findall(html)
        if nav_by_script:
            rep.fail(rel, f'{len(nav_by_script)} element(s) navigate by script (onclick location.href); write <a href="screen.html"> so the link works in every viewer')
            for m in SCRIPT_NAV_TARGET.finditer(html):
                name = _mock_target(mock_dir, m.group(1).strip())
                if name:
                    targets.append(name)   # keep the graph honest, the file is still refused above
        for block in NAV_BLOCK.findall(html):
            for m in NAV_ITEM.finditer(block):
                tag_and_body = m.group(0)
                if re.search(r"<a\b[^>]*\bhref", tag_and_body, re.I) or re.search(r"\bonclick\s*=", tag_and_body, re.I):
                    continue
                if re.search(r"""\b(active|current|selected)\b""", re.match(r"<[^>]*>", tag_and_body).group(0), re.I):
                    continue   # the item for the page itself
                label = re.sub(r"<[^>]+>", " ", m.group(2))
                label = re.sub(r"\s+", " ", label).strip()[:40] or "(unnamed)"
                rep.fail(rel, f'menu item "{label}" goes nowhere; every menu item is an <a href> to its screen')
        out_links[f] = set(targets) - {f}
        inert = 0
        for m in BUTTON.finditer(html):
            tag = m.group(0)
            if re.search(r"\bonclick\s*=", tag, re.I):
                continue
            if re.search(r"""type\s*=\s*["']submit["']""", tag, re.I) and FORM_ACTION.search(html):
                continue
            inert += 1
        if inert:
            rep.fail(rel, f"{inert} button(s) do nothing: give each an onclick that shows a message, make it a form submit with an action, or make it a link")
    if len(files) < 2:
        return
    for f in files:
        if not out_links.get(f):
            rep.fail(f"{rel_dir}/{f}", "has no link to any other mockup; every screen needs a way out (a menu, a back link or a logout)")
    entry = next((f for n in ENTRY_NAMES for f in files if f.lower().startswith(n)), files[0])
    seen, todo = {entry}, [entry]
    while todo:
        cur = todo.pop()
        for t in out_links.get(cur, ()):
            if t not in seen:
                seen.add(t)
                todo.append(t)
    unreachable = [f for f in files if f not in seen]
    if unreachable:
        rep.fail(rel_dir, f"{len(unreachable)} mockup(s) cannot be reached by clicking from {entry}: " + ", ".join(unreachable[:10]) + (" …" if len(unreachable) > 10 else ""))


# ----------------------------------------------------------------------------
def app_files(root: str, app: str):
    docs = os.path.join(root, "docs")
    names = [f"{app}-Brief.md", f"{app}-Phases.md", f"{app}-BRD.md", f"{app}-Architecture.md", f"{app}-UIDesign.md", f"{app}-Checklist.md",
             f"{app}-Coding-Standards.md", f"{app}-UsageGuide.md", f"{app}-DevGuide.md", f"{app}-ProductGuide.md"]
    # later phases of a Large project: App-P2-BRD.md, App-P2-Checklist.md, … in phase order
    extra = []
    if os.path.isdir(docs):
        for f in os.listdir(docs):
            m = re.match(rf"^{re.escape(app)}-P(\d+)-(BRD|Checklist|UIDesign|DevGuide)\.md$", f)
            if m:
                extra.append((int(m.group(1)), ["BRD", "UIDesign", "Checklist", "DevGuide"].index(m.group(2)), f))
    names += [f for _p, _o, f in sorted(extra)]
    if os.path.isdir(docs):
        names += sorted(f for f in os.listdir(docs) if re.match(rf"^{re.escape(app)}-Deployment-Checklist(-[\w]+)?\.md$", f))
        # the two documents written for a reader outside this project: the owner's open
        # decisions, and whatever this project has reported upstream (one file per upstream)
        names += sorted(f for f in os.listdir(docs)
                        if re.match(rf"^{re.escape(app)}-Decision-Request\.md$", f)
                        or re.match(rf"^{re.escape(app)}-[\w.]+-Feedback\.md$", f))
    out = [os.path.join(docs, n) for n in names if os.path.exists(os.path.join(docs, n))]
    ps = os.path.join(root, "PROJECT-STATUS.md")
    if os.path.exists(ps):
        out.append(ps)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Check TechieFlow documents against their template schemas.")
    ap.add_argument("files", nargs="*", help="document paths")
    ap.add_argument("--app", help="check every human document of this app under <root>/docs plus PROJECT-STATUS.md")
    ap.add_argument("--root", help="project root (default: found from the first file, or the current directory)")
    ap.add_argument("--size", help="Small|Medium|Large when no header or core-config carries it")
    ap.add_argument("--warn", action="store_true", help="report only: every finding is WARN and the exit code is 0")
    ap.add_argument("--quiet", action="store_true", help="print findings and the summary only")
    ap.add_argument("--strict", action="store_true", help="ignore the baseline: every finding FAILs, old or new")
    ap.add_argument("--baseline-write", action="store_true",
                    help="record the current findings of these files as the baseline (.tfcore/.session/doc-check-baseline.json) and print nothing else")
    a = ap.parse_args(argv)

    if not os.path.isdir(TEMPLATE_DIR):
        print(f"tf-doc-check: template folder not found at {TEMPLATE_DIR}", file=sys.stderr)
        return 2
    root = os.path.abspath(a.root) if a.root else None
    files = list(a.files)
    if a.app:
        root = root or os.getcwd()
        files += app_files(root, a.app)
        if not files:
            print(f"tf-doc-check: no documents for app {a.app} under {root}", file=sys.stderr)
            return 2
    if not files:
        ap.print_help()
        return 2
    root = root or find_root(files[0])

    rep = Report(a.warn)
    ctxs, checked = {}, 0
    for f in files:
        if not os.path.exists(f):
            rep.fail(os.path.relpath(f, root), "file not found")
            continue
        ctx = check_document(f, rep, a.size, root)
        checked += 1
        if ctx:
            ctxs[(ctx["doc"], ctx["phase"])] = ctx
    if len(ctxs) > 1:
        cross_checks(ctxs, rep, root)

    # The baseline (Sitting 4c, 2026-09-06; Schemas §7.1 decision 8): findings that were already
    # there when the command started are printed as OLD and do not block; only a finding this
    # command introduced FAILs. tf-phase.sh start writes the baseline; --strict ignores it.
    base_path = os.path.join(root, ".tfcore", ".session", "doc-check-baseline.json")
    if a.baseline_write:
        base = {}
        try:
            with open(base_path, encoding="utf-8") as fh:
                base = json.load(fh) or {}
        except Exception:
            base = {}
        for f in files:
            r = os.path.relpath(f, root)
            base[r] = sorted({l.split(": ", 1)[1] for l in rep.lines if l.startswith("FAIL ") and l.split(": ", 1)[0].endswith(" " + r)})
        os.makedirs(os.path.dirname(base_path), exist_ok=True)
        with open(base_path, "w", encoding="utf-8") as fh:
            json.dump(base, fh, indent=1)
        print(f"tf-doc-check: baseline written for {len(files)} file(s) ({sum(len(v) for v in base.values())} old finding(s))")
        return 0
    old = 0
    if not a.strict and not a.warn and os.path.isfile(base_path):
        try:
            import time as _t
            if _t.time() - os.path.getmtime(base_path) < 24 * 3600:
                with open(base_path, encoding="utf-8") as fh:
                    base = json.load(fh) or {}
                relined = []
                for l in rep.lines:
                    if l.startswith("FAIL "):
                        head, msg = l.split(": ", 1)
                        r = head[len("FAIL "):]
                        if msg in set(base.get(r, [])):
                            relined.append("OLD  " + l[5:])
                            rep.fails -= 1
                            old += 1
                            continue
                    relined.append(l)
                rep.lines = relined
        except Exception:
            pass

    for line in rep.lines:
        print(line)
    if not a.quiet:
        for f in files:
            if os.path.exists(f):
                r = os.path.relpath(f, root)
                if not any(l.split(": ", 1)[0].endswith(" " + r) for l in rep.lines):
                    print(f"OK   {r}")
    print(f"tf-doc-check: {rep.fails} FAIL, {rep.warns} WARN in {checked} document(s)"
          + (f"; {old} OLD finding(s) from before this command, not blocking (repair through *amend-docs)" if old else ""))
    return 1 if rep.fails else 0


if __name__ == "__main__":
    sys.exit(main())
