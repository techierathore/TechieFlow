#!/usr/bin/env python3
"""tf-render-html — render framework Markdown docs to the shared HTML shell.

Implements .tfcore/templates/v4custom/html-render-shell.md. That file stays the
SPECIFICATION and the single source of truth: the CSS (§2), the flash-free theme
script (§3) and the JS (§7) are EXTRACTED FROM IT at render time, never copied in
here, so the shell cannot drift from its own documentation.

Usage:
    python3 tf-render-html.py <file.md> [more.md ...] [--out DIR] [--quiet]

Writes a sibling <file>.html for each input. Exit codes:
    0  all rendered
    1  a render failed
    2  refused (checklist, or missing spec)

Dependency-free by design: Python 3 standard library only. The reference machine
has no pandoc / python-markdown / node markdown library installed.
"""

import datetime
import html as _html
import os
import re
import sys

SPEC_REL = os.path.join("templates", "v4custom", "html-render-shell.md")


# ----------------------------------------------------------------------------
# Spec extraction — §2 CSS, §3 head theme script, §7 JS
# ----------------------------------------------------------------------------

def find_spec(explicit=None):
    """Locate html-render-shell.md. Framework files live under a hidden,
    gitignored .tfcore/ — never search for them, resolve the known path."""
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    here = os.path.dirname(os.path.abspath(__file__))          # .tfcore/utils
    cand = [os.path.join(os.path.dirname(here), SPEC_REL)]      # .tfcore/...
    cwd = os.getcwd()
    cand.append(os.path.join(cwd, ".tfcore", SPEC_REL))
    for c in cand:
        if os.path.isfile(c):
            return c
    return None


def _fence(spec_text, lang, after=None):
    """Return the body of the first ```<lang> fence, optionally after a marker."""
    text = spec_text
    if after:
        i = text.find(after)
        if i < 0:
            return None
        text = text[i:]
    m = re.search(r"^```" + lang + r"\s*\n(.*?)^```", text, re.S | re.M)
    return m.group(1) if m else None


def load_shell(spec_path):
    spec = open(spec_path, encoding="utf-8").read()
    css = _fence(spec, "css", after="## 2. CSS")
    js = _fence(spec, "javascript", after="## 7. JavaScript")
    skeleton = _fence(spec, "html", after="## 3. Page skeleton")
    head_js = None
    if skeleton:
        m = re.search(r"<script>\s*(/\* Resolve the theme.*?)</script>",
                      skeleton, re.S)
        if m:
            head_js = m.group(1)
    missing = [n for n, v in (("§2 CSS", css), ("§7 JS", js),
                              ("§3 theme script", head_js)) if not v]
    if missing:
        raise SystemExit("tf-render-html: cannot extract %s from %s"
                         % (", ".join(missing), spec_path))
    return css.rstrip(), head_js.strip(), js.rstrip()


# ----------------------------------------------------------------------------
# §1 slug rule
# ----------------------------------------------------------------------------

class Slugger(object):
    def __init__(self):
        self.seen = {}
        self.n = 0

    def slug(self, text):
        self.n += 1
        s = re.sub(r"<[^>]+>", "", text)                 # strip any inline html
        s = re.sub(r"[*_`~]", "", s)                     # strip md emphasis
        s = s.lower()
        # 2. leading numbering / § / dashes, only before the first letter
        s = re.sub(r"^[\s\d.§#—–\-]+", "", s)
        s = re.sub(r"[^a-z0-9]+", "-", s)                # 3.
        s = s.strip("-")                                 # 4.
        if not s:                                        # 5.
            s = "section-%d" % self.n
        c = self.seen.get(s, 0) + 1                      # 6.
        self.seen[s] = c
        return s if c == 1 else "%s-%d" % (s, c)


# ----------------------------------------------------------------------------
# Inline conversion
# ----------------------------------------------------------------------------

RAW_TAG = re.compile(
    r"</?(?:a|abbr|b|br|code|em|i|img|kbd|mark|s|small|span|strong|sub|sup|u)\b[^>]*>",
    re.I)


def inline(text):
    """Markdown inline -> HTML. Code spans and deliberate raw inline HTML are
    protected before escaping, so `<a id="d-req-ui-001"></a>` survives verbatim
    (html-render-shell §4) while stray < and & are still escaped."""
    slots = []

    def stash(s):
        slots.append(s)
        return "\x00%d\x00" % (len(slots) - 1)

    # code spans first — their content must never be md-parsed
    def code_span(m):
        return stash("<code>%s</code>" % _html.escape(m.group(2), quote=False))
    text = re.sub(r"(`+)(.+?)\1", code_span, text, flags=re.S)

    # deliberate raw inline HTML (anchors above all)
    text = RAW_TAG.sub(lambda m: stash(m.group(0)), text)

    text = _html.escape(text, quote=False)

    # images before links
    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)",
                  lambda m: '<img src="%s" alt="%s" style="max-width:100%%">'
                            % (m.group(2), m.group(1)), text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)",
                  lambda m: '<a href="%s">%s</a>' % (m.group(2), m.group(1)), text)
    text = re.sub(r"<(https?://[^>\s]+)>", r'<a href="\1">\1</a>', text)

    text = re.sub(r"\*\*\*(.+?)\*\*\*", r"<strong><em>\1</em></strong>", text, flags=re.S)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text, flags=re.S)
    text = re.sub(r"~~(.+?)~~", r"<s>\1</s>", text, flags=re.S)
    text = re.sub(r"(?<![\w*])\*(?!\s)([^*]+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r"(?<![\w_])_(?!\s)([^_]+?)(?<!\s)_(?![\w_])", r"<em>\1</em>", text)

    for i, s in enumerate(slots):
        text = text.replace("\x00%d\x00" % i, s)
    return text


# ----------------------------------------------------------------------------
# Block parsing
# ----------------------------------------------------------------------------

# §6b — visible blockquotes addressed to the DRAFTING AGENT, never to the reader.
AGENT_NOTE = re.compile(
    r"(depth mandate|mermaid mandate|read (this )?before drafting|"
    r"how to use this template|template instructions?:|"
    r"ai agent:|agent note:|note to the agent)", re.I)

FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([\w+-]*)\s*$")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
HR = re.compile(r"^\s*(?:-{3,}|\*{3,}|_{3,})\s*$")
LI = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")
HTML_BLOCK = re.compile(r"^\s*<(/?)([a-zA-Z][\w-]*)")


class Renderer(object):
    def __init__(self, slugger):
        self.sl = slugger
        self.out = []
        self.toc = []            # (level, slug, text)
        self.h2 = 0
        self.stripped_notes = 0
        self.diagrams = 0
        self.bad_labels = []

    # -- helpers ---------------------------------------------------------
    def emit(self, s):
        self.out.append(s)

    def heading(self, level, text):
        slug = self.sl.slug(text)
        if level in (2, 3, 4):
            self.emit('<h%d id="%s">%s<a class="anchor-link" href="#%s">#</a></h%d>'
                      % (level, slug, inline(text), slug, level))
        else:
            self.emit("<h%d>%s</h%d>" % (level, inline(text), level))
        if level == 2:
            self.h2 += 1
        if level in (2, 3):
            self.toc.append((level, slug, re.sub(r"<[^>]+>", "", inline(text))))

    def mermaid(self, src):
        self.diagrams += 1
        self.check_mermaid(src)
        # Concatenation, not %-formatting: this block legitimately contains
        # "100%" and a % literal makes %-formatting choke on the next char.
        self.emit('<div class="diagram">\n'
                  '  <div class="dt">\n'
                  '    <button data-zout title="Zoom out">&minus;</button>\n'
                  '    <span class="zlabel">100%</span>\n'
                  '    <button data-zin title="Zoom in">+</button>\n'
                  '    <button data-fit title="Fit to width">Fit</button>\n'
                  '    <button data-one title="Actual size">1:1</button>\n'
                  '    <button data-fs title="Fullscreen">&#9166;</button>\n'
                  '    <button data-pop title="Open in new tab">&#8599;</button>\n'
                  '  </div>\n'
                  '  <pre class="mermaid">' + src.rstrip() + '</pre>\n'
                  '</div>')

    def check_mermaid(self, src):
        """§5.5 self-check: report unquoted labels containing special chars, and
        a lowercase `end` node id. Reported, never silently rewritten — the
        renderer does not get to guess what the author meant."""
        # Scope: flowcharts ONLY. §5.5 says sequence diagrams rarely break —
        # their message text is free-form, so `A->>B: SignIn(cookie: id, email)`
        # is legal and scanning it reports pure false positives.
        first = next((l.strip() for l in src.split("\n") if l.strip()), "")
        if not re.match(r"^(flowchart|graph)\b", first):
            return
        for line in src.split("\n"):
            # A quoted label is safe BY DEFINITION (§5.5 rule 1) and may legally
            # contain (), /, & and the rest. Drop every quoted span first, or the
            # scan reports the inside of correctly-quoted labels as broken.
            bare = re.sub(r'"[^"]*"', '""', line)
            # Each shape's label runs to its OWN closing bracket, so an inner
            # "(v2)" stays part of the label instead of matching on its own.
            cands = [m for m in re.finditer(r"\[([^\]]*)\]|\{([^}]*)\}|\(([^)]*)\)", bare)]
            cands += list(re.finditer(r"\|([^|]+)\|", bare))   # rule 6 edge labels
            for m in cands:
                lab = next((g for g in m.groups() if g is not None), "")
                core = re.sub(r'^[\[\({"\s]+|[\]\)}"\s]+$', "", lab.strip())
                if not core or not re.search(r"[A-Za-z0-9]", core):
                    continue
                if re.search(r"[()/\\&:,;#@<>|`%]", core):
                    self.bad_labels.append(core[:60])
        for m in re.finditer(r"(?m)^\s*end\s*(\[|\(|\{|-->)", src):
            self.bad_labels.append("reserved node id `end`")

    def code(self, lang, src):
        cls = ' class="language-%s"' % lang if lang else ""
        self.emit("<pre><code%s>%s</code></pre>"
                  % (cls, _html.escape(src.rstrip("\n"), quote=False)))

    def table(self, header, rows, aligns):
        def cell(tag, text, i):
            a = aligns[i] if i < len(aligns) else ""
            st = ' style="text-align:%s"' % a if a else ""
            return "<%s%s>%s</%s>" % (tag, st, inline(text), tag)
        h = "".join(cell("th", c, i) for i, c in enumerate(header))
        body = []
        for r in rows:
            body.append("<tr>%s</tr>"
                        % "".join(cell("td", c, i) for i, c in enumerate(r)))
        self.emit("<table>\n<thead><tr>%s</tr></thead>\n<tbody>\n%s\n</tbody>\n</table>"
                  % (h, "\n".join(body)))


def split_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    parts, buf, esc = [], "", False
    for ch in line:
        if esc:
            buf += ch
            esc = False
        elif ch == "\\":
            esc = True
            buf += "\\"
        elif ch == "|":
            parts.append(buf.strip())
            buf = ""
        else:
            buf += ch
    parts.append(buf.strip())
    return [p.replace("\\|", "|") for p in parts]


def parse(lines, r):
    i, n = 0, len(lines)
    para = []

    def flush_para():
        if para:
            r.emit("<p>%s</p>" % inline("\n".join(para).strip()))
            del para[:]

    while i < n:
        line = lines[i]

        # fenced block
        m = FENCE.match(line)
        if m:
            flush_para()
            marker, lang = m.group(2), (m.group(3) or "").lower()
            i += 1
            buf = []
            while i < n and not (lines[i].strip().startswith(marker[0] * len(marker))
                                 and lines[i].strip().rstrip(marker[0]) == ""):
                buf.append(lines[i])
                i += 1
            i += 1
            src = "\n".join(buf)
            if lang == "mermaid":
                r.mermaid(_html.escape(src, quote=False))
            else:
                r.code(lang, src)
            continue

        # html comment — invisible by design (§6b)
        if line.lstrip().startswith("<!--"):
            flush_para()
            while i < n and "-->" not in lines[i]:
                i += 1
            i += 1
            continue

        m = HEADING.match(line)
        if m:
            flush_para()
            r.heading(len(m.group(1)), m.group(2))
            i += 1
            continue

        if HR.match(line) and not para:
            flush_para()
            r.emit("<hr>")
            i += 1
            continue

        # table
        if "|" in line and i + 1 < n and TABLE_SEP.match(lines[i + 1]):
            flush_para()
            header = split_row(line)
            aligns = []
            for spec in split_row(lines[i + 1]):
                s = spec.strip()
                aligns.append("center" if s.startswith(":") and s.endswith(":")
                              else "right" if s.endswith(":")
                              else "left" if s.startswith(":") else "")
            i += 2
            rows = []
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append(split_row(lines[i]))
                i += 1
            r.table(header, rows, aligns)
            continue

        # blockquote
        if line.lstrip().startswith(">"):
            flush_para()
            buf = []
            while i < n and (lines[i].lstrip().startswith(">") or
                             (buf and lines[i].strip() and not FENCE.match(lines[i])
                              and not HEADING.match(lines[i]))):
                buf.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            body = "\n".join(buf).strip()
            if AGENT_NOTE.search(body.split("\n")[0]) or AGENT_NOTE.search(body[:160]):
                r.stripped_notes += 1          # §6b — never shown to a reader
                continue
            sub = Renderer(r.sl)
            sub.h2 = -10 ** 6                  # quotes never contribute to TOC
            parse(body.split("\n"), sub)
            r.diagrams += sub.diagrams
            r.bad_labels += sub.bad_labels
            r.emit("<blockquote>\n%s\n</blockquote>" % "\n".join(sub.out))
            continue

        # list
        if LI.match(line):
            flush_para()
            i = parse_list(lines, i, r)
            continue

        # raw html block (deliberate anchors, divs, details…)
        if HTML_BLOCK.match(line) and not para:
            flush_para()
            r.emit(line)
            i += 1
            continue

        if not line.strip():
            flush_para()
            i += 1
            continue

        para.append(line)
        i += 1

    flush_para()


def parse_list(lines, i, r):
    n = len(lines)
    m = LI.match(lines[i])
    base = len(m.group(1))
    ordered = not m.group(2) in ("-", "*", "+")
    tag = "ol" if ordered else "ul"
    r.emit("<%s>" % tag)
    while i < n:
        m = LI.match(lines[i])
        if not m:
            if not lines[i].strip():
                # blank line: continue only if the next line is still this list
                j = i + 1
                while j < n and not lines[j].strip():
                    j += 1
                if j < n and LI.match(lines[j]) and len(LI.match(lines[j]).group(1)) >= base:
                    i = j
                    continue
            break
        indent = len(m.group(1))
        if indent < base:
            break
        if indent > base:
            i = parse_list(lines, i, r)
            continue
        content = [m.group(3)]
        i += 1
        # lazy continuation lines belonging to this item
        while i < n and lines[i].strip() and not LI.match(lines[i]) \
                and not HEADING.match(lines[i]) and not FENCE.match(lines[i]) \
                and len(lines[i]) - len(lines[i].lstrip()) > base:
            content.append(lines[i].strip())
            i += 1
        r.emit("<li>%s" % inline(" ".join(content)))
        if i < n:
            m2 = LI.match(lines[i])
            if m2 and len(m2.group(1)) > base:
                i = parse_list(lines, i, r)
        r.emit("</li>")
    r.emit("</%s>" % tag)
    return i


# ----------------------------------------------------------------------------
# Document assembly
# ----------------------------------------------------------------------------

def frontmatter(lines):
    if not lines or lines[0].strip() != "---":
        return {}, lines
    for j in range(1, len(lines)):
        if lines[j].strip() == "---":
            fm = {}
            for ln in lines[1:j]:
                if ":" in ln:
                    k, v = ln.split(":", 1)
                    fm[k.strip()] = v.strip().strip('"\'')
            return fm, lines[j + 1:]
    return {}, lines


def render(md_path, css, head_js, body_js, out_dir=None):
    base = os.path.basename(md_path)
    if re.search(r"-Checklist\.md$", base, re.I):
        raise Refused("%s is a checklist — checklists are AI-agent working "
                      "documents and are NEVER rendered to HTML "
                      "(html-render-shell §0)." % base)

    raw = open(md_path, encoding="utf-8").read().replace("\r\n", "\n")
    lines = raw.split("\n")
    fm, lines = frontmatter(lines)

    title = None
    for k, ln in enumerate(lines):
        m = HEADING.match(ln)
        if m and len(m.group(1)) == 1:
            title = m.group(2).strip()
            lines = lines[:k] + lines[k + 1:]
            break
    if not title:
        title = re.sub(r"\.md$", "", base)

    r = Renderer(Slugger())
    parse(lines, r)

    today = datetime.date.today().isoformat()
    subtitle = "Rendered %s &middot; source <code>%s</code>" % (today, base)

    fm_rows = ""
    if fm:
        fm_rows = ("<table>\n<tbody>\n%s\n</tbody>\n</table>" % "\n".join(
            "<tr><th>%s</th><td>%s</td></tr>" % (_html.escape(k), inline(v))
            for k, v in fm.items() if v))

    toc_items = "\n".join(
        '        <li%s><a href="#%s">%s</a></li>'
        % (' class="h3"' if lvl == 3 else "", slug, _html.escape(txt))
        for lvl, slug, txt in r.toc)

    inline_toc = ""
    if r.h2 >= 2 and toc_items:
        inline_toc = ('    <div class="toc-inline">\n      <div>Contents</div>\n'
                      '      <ol>\n%s\n      </ol>\n    </div>\n' % toc_items)

    side = ""
    layout_cls = " no-toc"
    if r.h2 > 6:
        layout_cls = ""
        side = ('  <nav class="side">\n    <h1>%s</h1>\n'
                '    <div class="sub">Last rendered: %s</div>\n'
                '    <div class="group">Contents</div>\n    <ol>\n%s\n    </ol>\n'
                '  </nav>\n' % (_html.escape(title), today, toc_items))

    # Token replacement, NOT %-formatting or .format(): the §2 CSS and §7 JS are
    # pasted in verbatim and are full of % (100%, max-width:100%) and { } — both
    # of which those mechanisms would try to interpret.
    skeleton = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>@@TITLE@@</title>
<script>
@@HEADJS@@
</script>
<style>
@@CSS@@
</style>
</head>
<body>
<button id="themeToggle" class="theme-toggle" title="Toggle light / dark">&#9790; Dark</button>
<div class="layout@@LAYOUT@@">
@@SIDE@@  <main>
    <h1>@@TITLEH@@</h1>
    <div class="subtitle">@@SUBTITLE@@</div>
@@FM@@
@@INLINETOC@@@@BODY@@
  </main>
</div>

<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
<script>
@@JS@@
</script>
</body>
</html>
"""
    doc = skeleton
    for token, value in (("@@TITLE@@", _html.escape(title)),
                         ("@@TITLEH@@", inline(title)),
                         ("@@HEADJS@@", head_js),
                         ("@@CSS@@", css),
                         ("@@JS@@", body_js),
                         ("@@LAYOUT@@", layout_cls),
                         ("@@SIDE@@", side),
                         ("@@SUBTITLE@@", subtitle),
                         ("@@FM@@", fm_rows),
                         ("@@INLINETOC@@", inline_toc),
                         ("@@BODY@@", "\n".join(r.out))):
        doc = doc.replace(token, value)

    target_dir = out_dir or os.path.dirname(os.path.abspath(md_path))
    # --out may name a directory that does not exist yet; create it rather than
    # failing with a bare ENOENT on the output path.
    if out_dir:
        os.makedirs(target_dir, exist_ok=True)
    out_path = os.path.join(target_dir, re.sub(r"\.md$", "", base) + ".html")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(doc)
    return out_path, r, len(doc)


class Refused(Exception):
    pass


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    quiet = "--quiet" in argv
    out_dir = None
    for a in argv:
        if a.startswith("--out="):
            out_dir = a.split("=", 1)[1]
    spec_path = None
    for a in argv:
        if a.startswith("--spec="):
            spec_path = a.split("=", 1)[1]

    if not args:
        print(__doc__.strip())
        return 2

    spec = find_spec(spec_path)
    if not spec:
        sys.stderr.write(
            "tf-render-html: cannot find templates/v4custom/html-render-shell.md.\n"
            "  It ships in every installation at .tfcore/templates/v4custom/.\n"
            "  That path is hidden AND gitignored, so a search will not find it —\n"
            "  check the literal path, or run update-framework.sh <repo>.\n")
        return 2

    css, head_js, body_js = load_shell(spec)

    rc = 0
    for md in args:
        if not os.path.isfile(md):
            sys.stderr.write("tf-render-html: no such file: %s\n" % md)
            rc = 1
            continue
        try:
            out, r, size = render(md, css, head_js, body_js, out_dir)
        except Refused as e:
            sys.stderr.write("tf-render-html: REFUSED — %s\n" % e)
            rc = 2
            continue
        except Exception as e:                                # noqa: BLE001
            sys.stderr.write("tf-render-html: failed on %s: %s\n" % (md, e))
            rc = 1
            continue
        if not quiet:
            bits = ["%s (%.1f KB, %d H2" % (out, size / 1024.0, r.h2)]
            bits.append("sidebar" if r.h2 > 6 else "no sidebar")
            if r.diagrams:
                bits.append("%d diagram%s" % (r.diagrams, "" if r.diagrams == 1 else "s"))
            if r.stripped_notes:
                bits.append("%d agent note(s) stripped per §6b" % r.stripped_notes)
            print("  rendered %s)" % ", ".join(bits))
            for lab in dict.fromkeys(r.bad_labels):
                sys.stderr.write("  ⚠ mermaid §5.5: unquoted label or reserved id: %s\n" % lab)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
