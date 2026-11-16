"""tf_nav.py — how each screen is reached, read from the code (used by tf-verify-list.py).

A Blazor Hybrid head on a Mac shows mac2 no data-testid and no URL, so its screens are reached by
clicking what a person clicks. The code says what that is: a page declares its route with @page, and
a link or button anywhere names a route in href/Href with its visible text. A link in a file that is
not a page (a layout, the menu) is on every screen; a link on a page is on that page only. Only the
code of the screen's own project and the projects it references counts, so a website page is never
looked for in the desktop app's menu.

A menu built as data (TrStudio TF-006): a C# call or initializer whose first two arguments are a label
and a route, `new("Characters", "/avatar/characters", "users")`, is a link on every screen, as a
layout's link is. A page's own links are kept as well (TrStudio TF-004): the screen the app opens on
is a page, and its links are the only way to the screens next to it. `navigation` returns the whole
graph, so the Mac checker plans its clicks from the screen it finds on view, not only from the menu.
Python 3 standard library only.
"""
import html
import os
import re

CODE_DIRS = ("src", "source")
SKIP_DIRS = {"bin", "obj", "node_modules", ".git", ".tfbuild", "tests", "wwwroot"}
LINK = re.compile(r"<([A-Za-z][\w.]*)\b([^>]*?)\b[Hh]ref\s*=\s*\"([^\"]+)\"([^>]*)>(.*?)</\1\s*>", re.S)
DATA_LINK = re.compile(r"\(\s*\"([^\"\\]{1,60})\"\s*,\s*\"(/[A-Za-z0-9_/{}:@.-]*)\"")


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def route_key(r):
    """'/admin/llm-signin/{ProviderId:long}' and 'admin/llm-signin/@p.Id' -> ('admin', 'llm-signin', '*')"""
    r = re.split(r"[?#]", r.strip())[0].strip("/").lower()
    return tuple("*" if ("{" in seg or "@" in seg) else seg for seg in r.split("/")) if r else ()


def label_of(inner):
    t = re.sub(r"<[^>]+>", " ", inner)
    if "@" in t:
        return ""                                    # a label the code computes is not known here
    t = html.unescape(t)
    t = "".join(ch for ch in t if ch.isalnum() or ch in " +-'&/.,()")   # icon glyphs out
    return re.sub(r"\s+", " ", t).strip()


def code_map():
    """-> projects {dir: [referenced dirs]}, pages {route_key: (file, project dir)}, links [(file, own keys, project, key, label)]"""
    projects, pages, links, files, data = {}, {}, [], [], []
    for top in CODE_DIRS:
        for d, subs, names in os.walk(top):
            subs[:] = [x for x in subs if x not in SKIP_DIRS and not x.startswith(".")]
            for n in names:
                p = os.path.join(d, n)
                if n.endswith(".csproj"):
                    refs = re.findall(r'<ProjectReference\s+Include="([^"]+)"', read(p))
                    projects[d] = [os.path.normpath(os.path.join(d, os.path.dirname(x.replace("\\", "/")))) for x in refs]
                elif n.endswith(".razor") or n.endswith(".cshtml"):
                    files.append(p)
                elif n.endswith(".cs"):
                    data.append(p)
    def project_of(f):
        d = os.path.dirname(f)
        while d and d not in projects:
            nd = os.path.dirname(d)
            if nd == d:
                return ""
            d = nd
        return d
    for f in files:
        t = read(f)
        own = [route_key(r) for r in re.findall(r'(?m)^\s*@page\s+"([^"]+)"', t)]
        for k in own:
            pages.setdefault(k, (f, project_of(f)))
        for m in LINK.finditer(t):
            lab = label_of(m.group(5))
            # a route wholly computed ("@url") names no screen: it would match any route of its length
            if lab and not m.group(3).startswith(("http:", "https:", "mailto:", "#")) and any(g != "*" for g in route_key(m.group(3))):
                links.append((f, own, project_of(f), route_key(m.group(3)), lab))
    for f in data:
        for lab, to in DATA_LINK.findall(read(f)):
            lab = label_of(lab)
            if lab and route_key(to) and route_key(to)[0] != "api":
                links.append((f, [], project_of(f), route_key(to), lab))
    return projects, pages, links


def closure(projects, d):
    seen, todo = [], [d]
    while todo:
        x = todo.pop()
        if x in seen:
            continue
        seen.append(x)
        todo.extend(projects.get(x, []))
    return seen


def matches(a, b):
    return len(a) == len(b) and all(x == y or "*" in (x, y) for x, y in zip(a, b))


def _paths(mine, seeds):
    """breadth first over the links, from the seed links; -> {key: [labels]}"""
    paths, todo = {}, []
    for f, own, _, to, lab in seeds:
        if to not in paths:
            paths[to] = [lab]; todo.append(to)
    while todo:
        cur = todo.pop(0)
        for f, own, _, to, lab in mine:
            if any(matches(o, cur) for o in own) and to not in paths:
                paths[to] = paths[cur] + [lab]; todo.append(to)
    return paths


def navigation(screens):
    """Adds page, project, key and nav (labels to click, in order, from any screen) to each screen the
    code serves; a screen no menu reaches gets nav_from (the page whose own links reach it) and that
    path. Returns the link graph [{from, to, label, project}], from '' for a link on every screen."""
    projects, pages, links = code_map()
    for s in screens:
        k = route_key(s["route"])
        s["key"] = "/".join(k)
        hit = next(((f, pr) for pk, (f, pr) in pages.items() if matches(pk, k)), None)
        if not hit:
            continue
        s["page"], s["project"] = hit[0], hit[1]
        scope = set(closure(projects, hit[1]))
        mine = [l for l in links if l[2] in scope]
        # from the links on every screen (a layout, the menu, a menu built as data)
        nav = next((p for to, p in _paths(mine, [l for l in mine if not l[1]]).items() if matches(to, k)), None)
        if nav is not None:
            s["nav"] = nav
            continue
        # else from a page's own links: the screen the app opens on is such a page (TF-004)
        best = None
        for pk in sorted({o for l in mine for o in l[1]}):
            p = next((p for to, p in _paths(mine, [l for l in mine if pk in l[1]]).items() if matches(to, k)), None)
            if p is not None and not matches(pk, k) and (best is None or len(p) < len(best[1])):
                best = ("/" + "/".join(pk), p)
        if best:
            s["nav_from"], s["nav"] = best
    seen, graph = set(), []
    for f, own, pr, to, lab in links:
        for frm in (own or [None]):
            row = ("" if frm is None else "/".join(frm), "/".join(to), lab, pr)
            if row not in seen:
                seen.add(row); graph.append(dict(zip(("from", "to", "label", "project"), row)))
    return graph
