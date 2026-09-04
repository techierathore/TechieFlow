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
    ("-checklist.md", "checklist", "app-checklist-tmpl.md"),
    ("coding-standards.md", "coding-standards", "app-coding-standards-tmpl.md"),
    ("project-status.md", "project-status", "app-project-status-tmpl.md"),
    ("-usageguide.md", "usageguide", "app-usageguide-tmpl.md"),
    ("-usage-guide.md", "usageguide", "app-usageguide-tmpl.md"),
    ("-devguide.md", "devguide", "app-devguide-tmpl.md"),
    ("-productguide.md", "productguide", "app-productguide-tmpl.md"),
]
SIZED_DOCS = {"brd", "architecture", "uidesign", "checklist", "usageguide", "devguide", "productguide"}

SIZE_NAMES = {"s": "S", "small": "S", "m": "M", "medium": "M", "l": "L", "large": "L"}
SIZE_LONG = {"S": "Small", "M": "Medium", "L": "Large"}
REQ_CAP = {"S": 50, "M": 100, "L": 100}

CHECKLIST_HEADER = "| ID | Requirement | Status | % | Remarks | Details |"
STATUS_VALUES = {
    "not started", "in progress", "implemented", "verified", "done (pre-existing)",
    "needs re-verify", "partial", "fail", "blocked", "n/a",
}
PERF_BUDGET = re.compile(
    r"perf-budget:\s*(p50|p95|max)\s+(ttfb|load)\s*<=\s*\d+\s*ms(\s*@\s*concurrency\s+\d+)?", re.I
)
ACCEPT_LINE = re.compile(r"\*Acceptance:?\*|^\s*[-*]\s*Acceptance:", re.I)
ACCEPT_FORM = re.compile(
    r"^\s*[-*]\s*\*?Acceptance:?\*?:?\s*(?:Given\b[^,]*,\s*)?When\b.+?,\s*then\b.+", re.I
)
NAMES_SCREEN = re.compile(r"\b(on|opens?|from|in)\b", re.I)


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
    return {m.group(1) for m in re.finditer(rf"((?:\./|\.\./|docs/)?{folder}/[^\s)\]\"'`>|]+)", text)}


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
                m = re.match(r"^(appSize|appKind):\s*(\S+)", line)
                if m and m.group(2) not in ("null", "~", "''", '""'):
                    out[m.group(1)] = m.group(2).strip("'\"")
    return out


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

    # 2. sections: strangers, order, presence
    present = [(norm_heading(h), h, txt) for h, txt in split_sections(clean, 2) if h is not None]
    always_ok = {"table of contents"} | ({"recovery note"} if doc == "project-status" else set())
    for key, h, txt in present:
        if schema.declared(key) or key in always_ok:
            continue
        if doc == "checklist" and re.search(r"<a id=['\"]d-req-", txt, re.I):
            continue  # a page group holding detail entries
        extra = "; bugs and feedback go to the misses stream, not the checklist" if doc == "checklist" else ""
        rep.fail(rel, f'section "{h}" is not in the template{extra}')

    order_of = {norm_heading(n): i for i, (n, _f, _m) in enumerate(schema.sections)}
    last_idx, last_name = -1, None
    for key, h, _txt in present:
        d = schema.declared(key)
        if not d:
            continue
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
            n = word_count(txt)
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
        if sec_txt is not None:
            for h3, etxt in split_sections(sec_txt, 3):
                if h3 is None:
                    continue
                if prefix and not h3.lower().startswith(prefix.lower()):
                    rep.fail(rel, f'entry "{h3}" must start with "{prefix}"')
                    continue
                ename = h3[len(prefix):].strip() if prefix else h3
                ename = re.sub(r"\s*\(.*$", "", ename).strip("` ").strip()
                entry_names.append(ename)
                if schema.per_entry:
                    n = word_count(etxt)
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
               size=size, kind=kind, root=root, path=path, rel=rel, entry_names=entry_names)
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


def check_doc_rule(rule, c, rep):
    rel, root, path, body, clean, nocomment, present, size = (
        c["rel"], c["root"], c["path"], c["body"], c["clean"], c["nocomment"], c["present"], c["size"])

    if rule == "brd-ledger":
        ids = re.findall(r"\*\*BRD-(\d+)\*\*", clean)
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
    for l in rows:
        cells = [x.strip() for x in l.strip().strip("|").split("|")]
        if len(cells) < 6:
            rep.fail(rel, f"row {cells[0] if cells else '?'} has {len(cells)} cells; six are needed")
            continue
        rid, _req, status, pct, remarks, details = cells[:6]
        rid = rid.strip("`* ")
        ids.append(rid)
        if not re.fullmatch(r"REQ-(UI|FN|RAG|NFR)-\d{3}", rid):
            rep.fail(rel, f'id "{rid}" is not REQ-UI/FN/RAG/NFR- plus three digits')
        if status.strip("`* ").lower() not in STATUS_VALUES:
            rep.fail(rel, f'{rid} status "{status}" is not one of the fixed values')
        if pct.strip("`* ").rstrip("%").strip() not in ("0", "25", "50", "75", "100"):
            rep.fail(rel, f'{rid} % "{pct}" must be 0, 25, 50, 75 or 100')
        n = len(re.findall(r"\S+", remarks))
        if n > 60:
            rep.fail(rel, f"{rid} Remarks is {n} words; at most 60, current state only (history lives in the telemetry streams)")
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
        m = re.search(rf"<a id=['\"]d-{re.escape(rid.lower())}['\"]", body)
        if not m:
            continue  # reported above through the Details link
        pos = m.start()
        nxt = re.search(r"\n\s*<a id=|\n## |\n### ", body[pos + 1:])
        entry = body[pos: pos + 1 + nxt.start()] if nxt else body[pos:]
        acc = [l for l in entry.splitlines() if ACCEPT_LINE.search(l)]
        if len(acc) != 1:
            rep.fail(rel, f"{rid} must have exactly one acceptance line; found {len(acc)}")
        elif not ACCEPT_FORM.match(acc[0]):
            rep.fail(rel, f'{rid} acceptance line does not read "When <actor> <does what> on <screen>, then <observable result>"')
        elif rid.startswith(("REQ-UI", "REQ-FN")) and not NAMES_SCREEN.search(acc[0].split(", then", 1)[0]):
            rep.fail(rel, f'{rid} acceptance line must name the screen ("… on <screen>, then …")')
        for l in entry.splitlines():
            if "perf-budget:" in l.lower() and not PERF_BUDGET.search(l):
                rep.fail(rel, f"{rid} perf-budget line is not in the form perf-budget: <p50|p95|max> <ttfb|load> <= <N>ms [@ concurrency <N>]")
        refs = re.findall(r"BRD-(\d+)", entry)
        if not refs:
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
def cross_checks(ctxs: dict, rep: Report, root: str):
    brd, ui, cl = ctxs.get("brd"), ctxs.get("uidesign"), ctxs.get("checklist")
    if brd and ui and brd.get("brd_screens") is not None and ui["kind"] == "app":
        b = {re.sub(r"\s+", " ", s.strip("`* ")).lower() for s in brd["brd_screens"]}
        u = {re.sub(r"\s+", " ", s).lower() for s in ui["entry_names"]}
        for s in sorted(b - u):
            rep.fail(brd["rel"], f'screen "{s}" is in the BRD but has no "### Screen:" entry in the UIDesign')
        for s in sorted(u - b):
            rep.fail(ui["rel"], f'screen "{s}" is in the UIDesign but not in the BRD screens table')
    if brd and cl and brd.get("brd_ids") is not None and cl.get("checklist_brd_refs") is not None:
        missing = sorted(brd["brd_ids"] - cl["checklist_brd_refs"], key=int)
        if missing:
            shown = ", ".join(f"BRD-{m}" for m in missing[:20]) + (" …" if len(missing) > 20 else "")
            rep.fail(cl["rel"], f"BRD items with no checklist row ({len(missing)}): {shown}")
    if ui:
        mock_dir = os.path.join(root, "docs", "mockups")
        if os.path.isdir(mock_dir):
            linked = {os.path.basename(l.split("#")[0]) for l in links_to(ui["clean"], "mockups")}
            for f in sorted(os.listdir(mock_dir)):
                if f.lower().endswith(".html") and f not in linked:
                    rep.warn(ui["rel"], f"mockup {f} is not linked from any screen")


# ----------------------------------------------------------------------------
def app_files(root: str, app: str):
    docs = os.path.join(root, "docs")
    names = [f"{app}-BRD.md", f"{app}-Architecture.md", f"{app}-UIDesign.md", f"{app}-Checklist.md",
             f"{app}-Coding-Standards.md", f"{app}-UsageGuide.md", f"{app}-DevGuide.md", f"{app}-ProductGuide.md"]
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
            ctxs[ctx["doc"]] = ctx
    if len(ctxs) > 1:
        cross_checks(ctxs, rep, root)

    for line in rep.lines:
        print(line)
    if not a.quiet:
        for f in files:
            if os.path.exists(f):
                r = os.path.relpath(f, root)
                if not any(l.split(": ", 1)[0].endswith(" " + r) for l in rep.lines):
                    print(f"OK   {r}")
    print(f"tf-doc-check: {rep.fails} FAIL, {rep.warns} WARN in {checked} document(s)")
    return 1 if rep.fails else 0


if __name__ == "__main__":
    sys.exit(main())
