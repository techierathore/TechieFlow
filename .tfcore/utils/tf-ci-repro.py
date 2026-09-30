#!/usr/bin/env python3
"""tf-ci-repro.py — run a CI workflow's steps here the way a fresh runner does (Lekhak TF-019, 2026-09-30).

Called by tf-ci-repro.sh; see that file for the usage and the verdict lines.

A developer machine hides CI failures in two places: its package caches and its build output.
Lekhak's CI failed with NETSDK1112 (the win-x64 runtime pack was never downloaded) while the same
commands passed on the developer's machine, because the pack was already in ~/.nuget/packages.
triage-and-fix reported the failure fixed; the owner's next CI run failed again. This script:
  * copies the repository without anything its .gitignore files ignore (no bin/, obj/,
    node_modules/ ...), as a fresh checkout has none of them, to a folder outside the repository;
  * points every package cache it knows at an empty folder (NuGet, npm, yarn, pnpm, pip, Go,
    Gradle, Maven);
  * runs the job's `run:` steps in order, in the shell the runner would use, and stops at the
    first failing one, as the runner does.
`uses:` steps are not run: the copy stands in for the checkout, the tools installed here for the
setup actions, and a cache action is left out on purpose. A step that needs a secret is skipped:
this machine's own credentials stand in. A step that only installs tools on the machine
(workloads, apt, choco, brew, winget) is skipped unless --run-setup.
"""
import json, os, re, shutil, subprocess, sys, time
from datetime import datetime, timezone

CACHES = [  # env var, folder name, whose cache
    ("NUGET_PACKAGES", "nuget", "NuGet"), ("NUGET_HTTP_CACHE_PATH", "nuget-http", None),
    ("npm_config_cache", "npm", "npm"), ("YARN_CACHE_FOLDER", "yarn", "yarn"),
    ("npm_config_store_dir", "pnpm", "pnpm"), ("PIP_CACHE_DIR", "pip", "pip"),
    ("GOMODCACHE", "gomod", "Go"), ("GRADLE_USER_HOME", "gradle", "Gradle"),
]
SETUP_RX = re.compile(r"^\s*(sudo\s+)?(dotnet\s+workload\s+(install|update)|apt(-get)?\s+(update|install)|"
                      r"choco\s+install|brew\s+install|winget\s+install|npm\s+(i|install)\s+(-g|--global))\b", re.I)


def say(*a):
    print(*a, flush=True)


# ---- a workflow reader that needs no PyYAML -----------------------------------------------------
# A stock Mac's python3 has no PyYAML, and CI's stock-Mac job failed on it (2026-09-30). PyYAML is used
# when it is installed; otherwise this reader takes the part of YAML a workflow file uses: block
# mappings and sequences, | and > block scalars, quoted and plain scalars, and one-line [ ] and { }.
# Anchors, tags and multi-line flow collections are not read.
def _strip_comment(s):
    q = None
    for i, c in enumerate(s):
        if q:
            if c == q:
                q = None
        elif c in "'\"" and (i == 0 or s[i - 1] in " [{,:"):
            q = c
        elif c == "#" and (i == 0 or s[i - 1] in " \t"):
            return s[:i].rstrip()
    return s.rstrip()


def _split_flow(s):
    parts, depth, q, cur = [], 0, None, ""
    for c in s:
        if q:
            q = None if c == q else q
        elif c in "'\"":
            q = c
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(cur.strip()); cur = ""; continue
        cur += c
    if cur.strip():
        parts.append(cur.strip())
    return parts


def _scalar(s):
    s = s.strip()
    if not s:
        return None
    if s[0] == "'" and s.endswith("'") and len(s) > 1:
        return s[1:-1].replace("''", "'")
    if s[0] == '"' and s.endswith('"') and len(s) > 1:
        try:
            return json.loads(s)
        except ValueError:
            return s[1:-1]
    if s[0] == "[" and s.endswith("]"):
        return [_scalar(p) for p in _split_flow(s[1:-1])]
    if s[0] == "{" and s.endswith("}"):
        out = {}
        for p in _split_flow(s[1:-1]):
            k, _, v = p.partition(":")
            out[_scalar(k)] = _scalar(v)
        return out
    s = _strip_comment(s)
    low = s.lower()
    if low in ("true", "false"):
        return low == "true"
    if low in ("null", "~"):
        return None
    if re.match(r"^-?\d+$", s):
        return int(s)
    if re.match(r"^-?\d+\.\d+$", s):
        return float(s)
    return s


_KEY = re.compile(r"""^('(?:[^']|'')*'|"(?:[^"\\]|\\.)*"|[^\s'"#\-\[{][^:#]*?|-[^\s:][^:#]*?)\s*:(?:\s+|$)(.*)$""")


def mini_yaml(text):
    lines = text.replace("\t", "    ").splitlines()
    ends_nl = text.endswith("\n")   # a block scalar that ends the file keeps a newline only if the file has one

    def meaningful(i):
        while i < len(lines) and (not lines[i].strip() or lines[i].strip().startswith("#") or lines[i].strip() == "---"):
            i += 1
        return i

    def ind(i):
        return len(lines[i]) - len(lines[i].lstrip(" "))

    def block_scalar(head, i, parent):
        style, chomp = head[0], ("-" if "-" in head else "+" if "+" in head else "")
        body, width = [], None
        while i < len(lines) and (not lines[i].strip() or ind(i) > parent):
            if lines[i].strip() and width is None:
                width = ind(i)
            body.append(lines[i][width:] if width is not None and len(lines[i]) > width else "")
            i += 1
        while body and chomp != "+" and body[-1] == "":
            body.pop()
        if style == "|":
            txt = "\n".join(body)
        else:
            txt, prev_blank = "", False
            for ln in body:
                if not ln:
                    txt += "\n"; prev_blank = True
                else:
                    txt += (ln if not txt or txt.endswith("\n") else " " + ln); prev_blank = False
        last_line_open = i >= len(lines) and not ends_nl and not (chomp != "+" and not lines[-1].strip())
        return txt + ("" if chomp == "-" or not txt or last_line_open else "\n"), i

    def value(rest, i, n):
        rest = _strip_comment(rest) if not rest.startswith(("'", '"')) else rest
        if rest[:1] in ("|", ">"):
            return block_scalar(rest, i, n)
        if rest:
            return _scalar(rest), i
        j = meaningful(i)
        if j < len(lines) and (ind(j) > n or (ind(j) == n and lines[j].lstrip().startswith("- ") )):
            return node(j)
        return None, i

    def node(i):
        i = meaningful(i)
        if i >= len(lines):
            return None, i
        n = ind(i)
        if lines[i].lstrip().startswith("-") and lines[i].strip() in ("-",) or lines[i].lstrip().startswith("- "):
            seq = []
            while i < len(lines) and ind(i) == n and (lines[i].strip() == "-" or lines[i].lstrip().startswith("- ")):
                content = lines[i].strip()[1:].lstrip()
                if not content:
                    v, i = node(i + 1)
                elif _KEY.match(content) and not content.startswith(("'", '"', "[", "{")) or re.match(r"""^('[^']*'|"[^"]*")\s*:(\s|$)""", content):
                    lines[i] = " " * (len(lines[i]) - len(content)) + content
                    v, i = node(i)
                else:
                    v, i = value(content, i + 1, n)
                seq.append(v)
                i = meaningful(i)
            return seq, i
        out = {}
        while i < len(lines) and ind(i) == n and not lines[i].lstrip().startswith("- "):
            m = _KEY.match(lines[i].strip())
            if not m:
                raise ValueError("line %d: cannot read %r" % (i + 1, lines[i].strip()))
            out[_scalar(m.group(1))], i = value(m.group(2), i + 1, n)
            i = meaningful(i)
        return out, i

    v, _ = node(0)
    return v


def load_workflow(path):
    text = open(path, encoding="utf-8").read()
    if not os.environ.get("TF_CI_REPRO_NO_PYYAML"):
        try:
            import yaml
            return yaml.safe_load(text)
        except ImportError:
            pass
    return mini_yaml(text)


# ---- a clean copy: what a fresh checkout holds ------------------------------------------------
# Every .gitignore in the tree is read the way git reads it (last matching rule wins, "!" re-includes,
# a trailing "/" means a folder, a "/" elsewhere anchors the rule to that .gitignore's folder, "**"
# crosses folders). An ignored folder is not entered. Done in Python so the copy needs no rsync
# `--filter` support, which a stock Mac's rsync may lack.
def _glob_rx(pat):
    rx, i = "", 0
    while i < len(pat):
        c = pat[i]
        if pat.startswith("**/", i):
            rx += "(?:.*/)?"; i += 3; continue
        if pat.startswith("/**", i) and i + 3 == len(pat):
            rx += "/.*"; i += 3; continue
        if pat.startswith("**", i):
            rx += ".*"; i += 2; continue
        if c == "*":
            rx += "[^/]*"
        elif c == "?":
            rx += "[^/]"
        elif c == "\\" and i + 1 < len(pat):
            i += 1; rx += re.escape(pat[i])
        elif c == "[":
            j = pat.find("]", i + 1)
            if j < 0:
                rx += "\\["
            else:
                rx += "[" + pat[i + 1:j].replace("!", "^", 1) + "]"; i = j
        else:
            rx += re.escape(c)
        i += 1
    return rx


def _read_ignore(path):
    rules = []
    for ln in read_text(path).splitlines():
        ln = ln.rstrip("\r")
        if not ln.strip() or ln.startswith("#"):
            continue
        ln = re.sub(r"(?<!\\)\s+$", "", ln)
        neg = ln.startswith("!")
        if neg:
            ln = ln[1:]
        dir_only = ln.endswith("/")
        ln = ln.rstrip("/")
        anchored = "/" in ln
        ln = ln.lstrip("/")
        rules.append((re.compile("^" + _glob_rx(ln) + "$"), neg, dir_only, anchored))
    return rules


def clean_copy(src, dst):
    stack = []   # (folder relative to src, rules)

    def ignored(rel, is_dir):
        hit = False
        for base, rules in stack:
            if base and not rel.startswith(base + "/"):
                continue
            sub = rel[len(base) + 1:] if base else rel
            name = sub.rsplit("/", 1)[-1]
            for rx, neg, dir_only, anchored in rules:
                if dir_only and not is_dir:
                    continue
                if rx.match(sub if anchored else name):
                    hit = not neg
        return hit

    n = 0
    for root, dirs, files in os.walk(src):
        rel_root = os.path.relpath(root, src).replace(os.sep, "/")
        rel_root = "" if rel_root == "." else rel_root
        while stack and stack[-1][0] and not (rel_root == stack[-1][0] or rel_root.startswith(stack[-1][0] + "/")):
            stack.pop()
        if ".gitignore" in files:
            stack.append((rel_root, _read_ignore(os.path.join(root, ".gitignore"))))
        keep = []
        for d in sorted(dirs):
            rel = (rel_root + "/" if rel_root else "") + d
            if d == ".git" or rel == "tests/.artifacts" or ignored(rel, True):
                continue
            keep.append(d)
            os.makedirs(os.path.join(dst, rel), exist_ok=True)
        dirs[:] = keep
        for f in files:
            rel = (rel_root + "/" if rel_root else "") + f
            if ignored(rel, False):
                continue
            s, t = os.path.join(root, f), os.path.join(dst, rel)
            os.makedirs(os.path.dirname(t), exist_ok=True)
            if os.path.islink(s):
                os.symlink(os.readlink(s), t)
            else:
                shutil.copy2(s, t)
            n += 1
    return n


def is_wsl():
    try:
        return "microsoft" in open("/proc/version").read().lower()
    except OSError:
        return False


HOST = "macos" if sys.platform == "darwin" else ("windows" if os.name == "nt" else ("wsl" if is_wsl() else "linux"))


def winpath(p):
    return subprocess.run(["wslpath", "-w", p], capture_output=True, text=True).stdout.strip() if HOST == "wsl" else p


def read_text(p):
    try:
        b = open(p, "rb").read()
    except OSError:
        return ""
    if b[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return b.decode("utf-16")
    return b.decode("utf-8-sig", errors="replace")


def parse_kv_file(p):
    """GITHUB_OUTPUT / GITHUB_ENV: name=value lines and name<<DELIM heredocs."""
    out, lines, i = {}, read_text(p).replace("\r\n", "\n").split("\n"), 0
    while i < len(lines):
        ln = lines[i]; i += 1
        m = re.match(r"^([^=<\s]+)<<(\S+)$", ln)
        if m:
            buf = []
            while i < len(lines) and lines[i] != m.group(2):
                buf.append(lines[i]); i += 1
            i += 1; out[m.group(1)] = "\n".join(buf)
        elif "=" in ln:
            k, v = ln.split("=", 1); out[k.strip()] = v
    return out


# ---- expressions ------------------------------------------------------------------------------
class NeedsSecret(Exception):
    pass


class Unknown(Exception):
    pass


def evaluate(expr, ctx):
    """The small part of the ${{ }} language a run step or its `if:` usually needs."""
    toks = re.findall(r"'(?:[^']|'')*'|&&|\|\||==|!=|!|\(|\)|[A-Za-z_][\w\-]*(?:\.[\w\-\*]+)*(?:\(\))?|-?\d+(?:\.\d+)?", expr)
    if "".join(toks).replace(" ", "") != re.sub(r"\s+", "", expr):
        raise Unknown(expr)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take():
        t = toks[pos[0]]; pos[0] += 1; return t

    def atom():
        t = take()
        if t == "(":
            v = orx()
            if take() != ")":
                raise Unknown(expr)
            return v
        if t == "!":
            return not truthy(atom())
        if t.startswith("'"):
            return t[1:-1].replace("''", "'")
        if re.match(r"^-?\d", t):
            return float(t)
        if t in ("true", "false"):
            return t == "true"
        if t == "null":
            return None
        if t in ("always()", "success()"):
            return True
        if t in ("failure()", "cancelled()"):
            return False
        return lookup(t, ctx)

    def cmp():
        v = atom()
        while peek() in ("==", "!="):
            op, r = take(), atom()
            eq = str(v).lower() == str(r).lower() if not (isinstance(v, float) and isinstance(r, float)) else v == r
            v = eq if op == "==" else not eq
        return v

    def andx():
        v = cmp()
        while peek() == "&&":
            take(); r = cmp(); v = r if truthy(v) else v
        return v

    def orx():
        v = andx()
        while peek() == "||":
            take(); r = andx(); v = v if truthy(v) else r
        return v

    v = orx()
    if pos[0] != len(toks):
        raise Unknown(expr)
    return v


def truthy(v):
    return v not in (None, False, "", 0, 0.0)


def lookup(name, ctx):
    parts = name.split(".")
    if parts[0] == "secrets":
        raise NeedsSecret(name)
    if parts[0] == "steps" and len(parts) == 4 and parts[2] == "outputs":
        return ctx["outputs"].get(parts[1], {}).get(parts[3], "")
    if parts[0] == "steps" and len(parts) == 3 and parts[2] in ("outcome", "conclusion"):
        return ctx["outcome"].get(parts[1], "")
    if parts[0] == "env" and len(parts) == 2:
        return ctx["env"].get(parts[1], "")
    if parts[0] == "matrix" and len(parts) == 2 and parts[1] in ctx["matrix"]:
        return ctx["matrix"][parts[1]]
    fixed = {"runner.os": ctx["runner_os"], "runner.temp": ctx["temp_shell"], "github.workspace": ctx["work_shell"],
             "github.event_name": "workflow_dispatch", "github.run_number": "1", "github.run_id": "0"}
    if name in fixed:
        return fixed[name]
    raise Unknown(name)


def expand(text, ctx):
    def one(m):
        v = evaluate(m.group(1), ctx)
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return "" if v is None else str(v)
    return re.sub(r"\$\{\{\s*(.*?)\s*\}\}", one, str(text), flags=re.S)


def secrets_in(obj):
    return sorted(set(re.findall(r"secrets\.([A-Za-z_]\w*)", json.dumps(obj, default=str))))


# ---- main -------------------------------------------------------------------------------------
def pick_workflow(arg):
    if arg:
        return arg if os.path.isfile(arg) else None
    found = sorted(os.path.join(".github/workflows", f) for f in os.listdir(".github/workflows")
                   if f.endswith((".yml", ".yaml"))) if os.path.isdir(".github/workflows") else []
    if len(found) == 1:
        return found[0]
    _notrun("no workflow under .github/workflows; name one" if not found else
            "%d workflows here (%s); name one" % (len(found), ", ".join(found)))


def _notrun(msg):
    say("NOT-RUN  " + msg)
    sys.exit(2)


def runner_os(runs_on, matrix):
    s = json.dumps(runs_on).lower()
    if "matrix." in s:
        for v in matrix.values():
            s += " " + str(v).lower()
    return "Windows" if "windows" in s else ("macOS" if "macos" in s else "Linux")


def work_root():
    base = os.environ.get("TF_CI_REPRO_DIR")
    if not base and HOST == "wsl":
        t = subprocess.run(["cmd.exe", "/c", "echo %TEMP%"], capture_output=True, text=True, cwd="/mnt/c").stdout.strip()
        base = subprocess.run(["wslpath", "-u", t], capture_output=True, text=True).stdout.strip() if t else ""
    if not base:
        base = os.environ.get("TMPDIR") or "/tmp"
    return os.path.join(base, "tf-ci-repro", "%s-%d" % (os.path.basename(os.getcwd()), os.getpid()))


def main():
    a = sys.argv[1:]
    opt = {"workflow": None, "job": None, "list": False, "keep": False, "setup": False}
    while a:
        x = a.pop(0)
        if x == "--job": opt["job"] = a.pop(0) if a else None
        elif x == "--list": opt["list"] = True
        elif x == "--keep": opt["keep"] = True
        elif x == "--run-setup": opt["setup"] = True
        elif x.startswith("-"): _notrun("unknown option %s" % x)
        else: opt["workflow"] = x
    wf_path = pick_workflow(opt["workflow"])
    if not wf_path:
        _notrun("no workflow file %s" % opt["workflow"])
    try:
        wf = load_workflow(wf_path) or {}
    except ValueError as e:
        _notrun("could not read %s without PyYAML (%s); python3 -m pip install pyyaml" % (wf_path, e))
    jobs = wf.get("jobs") or {}
    if not jobs:
        _notrun("%s has no jobs" % wf_path)
    if opt["job"] and opt["job"] not in jobs:
        _notrun("no job %s in %s (jobs: %s)" % (opt["job"], wf_path, ", ".join(jobs)))
    if not opt["job"] and len(jobs) > 1:
        _notrun("%s has %d jobs (%s); name one with --job" % (wf_path, len(jobs), ", ".join(jobs)))
    jid = opt["job"] or next(iter(jobs))
    job = jobs[jid] or {}
    if "uses" in job:
        _notrun("job %s calls another workflow (%s); run that one" % (jid, job["uses"]))
    mx = ((job.get("strategy") or {}).get("matrix") or {})
    matrix = {k: (v[0] if isinstance(v, list) and v else v) for k, v in mx.items() if k not in ("include", "exclude")}
    if not matrix and isinstance(mx.get("include"), list) and mx["include"]:
        matrix = dict(mx["include"][0])
    ros = runner_os(job.get("runs-on", ""), matrix)
    if ros == "macOS" and HOST != "macos":
        _notrun("job %s runs on macOS and this is %s; run it on a Mac" % (jid, HOST))
    if ros == "Windows" and HOST not in ("windows", "wsl"):
        _notrun("job %s runs on Windows and this is %s; run it on Windows or WSL" % (jid, HOST))
    win = ros == "Windows" and HOST == "wsl"   # the steps run on the Windows side, called from WSL
    defaults = ((wf.get("defaults") or {}).get("run") or {}).copy()
    defaults.update(((job.get("defaults") or {}).get("run") or {}))
    steps = job.get("steps") or []

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    logdir = os.path.join("tests/.artifacts/ci-repro", stamp)
    root = work_root()
    work, cache, temp = os.path.join(root, "work"), os.path.join(root, "caches"), os.path.join(root, "tmp")
    ctx = {"outputs": {}, "outcome": {}, "env": {}, "matrix": matrix, "runner_os": ros,
           "temp_shell": winpath(temp) if win else temp, "work_shell": winpath(work) if win else work}

    plan = []
    for n, st in enumerate(steps, 1):
        st = st or {}
        name = st.get("name") or (("Run " + str(st["run"]).strip().splitlines()[0]) if st.get("run") else st.get("uses", "step %d" % n))
        if "uses" in st:
            u = str(st["uses"])
            why = ("the copy stands in for the checkout" if u.startswith("actions/checkout") else
                   "left out on purpose: the caches start empty" if "/cache" in u else
                   "the tools installed here stand in" if "/setup-" in u else "an action is not run here")
            plan.append((n, name, st, "skip", "uses %s — %s" % (u, why)))
            continue
        body = str(st.get("run") or "")
        lines = [l for l in body.splitlines() if l.strip() and not l.strip().startswith("#")]
        sec = secrets_in({"run": body, "env": st.get("env"), "if": st.get("if")})
        if sec:
            plan.append((n, name, st, "skip", "needs secrets.%s; this machine's own credentials stand in" % ", secrets.".join(sec)))
        elif lines and all(SETUP_RX.match(l) or l.rstrip().endswith(("`", "\\")) for l in lines) and SETUP_RX.match(lines[0]) and not opt["setup"]:
            plan.append((n, name, st, "skip", "sets up the machine; what is installed here stands in (--run-setup runs it)"))
        else:
            plan.append((n, name, st, "run", ""))
    caches = sorted({w for _, _, w in CACHES if w})
    if opt["list"]:
        say("workflow %s, job %s (runs on %s; here: %s)" % (wf_path, jid, ros, HOST))
        for n, name, st, what, why in plan:
            say("  %-4s %2d %s%s" % (what, n, name, ("  — " + why) if why else ""))
        say("empty caches: %s; the copy leaves out everything .gitignore ignores" % ", ".join(caches))
        return 0

    os.makedirs(logdir, exist_ok=True)
    shutil.rmtree(root, ignore_errors=True)
    for d in (work, temp):
        os.makedirs(d, exist_ok=True)
    say("copying the repository to %s (without what .gitignore ignores) …" % work)
    try:
        clean_copy(".", work)
    except OSError as e:
        _notrun("could not copy the repository: %s" % e)

    env = dict(os.environ)
    wslenv = [x for x in env.get("WSLENV", "").split(":") if x]
    pathvars = []
    for var, folder, _ in CACHES:
        os.makedirs(os.path.join(cache, folder), exist_ok=True)
        env[var] = os.path.join(cache, folder); pathvars.append(var)
    env["MAVEN_OPTS"] = (env.get("MAVEN_OPTS", "") + " -Dmaven.repo.local=" + (winpath(os.path.join(cache, "m2")) if win else os.path.join(cache, "m2"))).strip()
    env.update({"CI": "true", "GITHUB_WORKSPACE": work, "RUNNER_TEMP": temp, "RUNNER_OS": ros})
    pathvars += ["GITHUB_WORKSPACE", "RUNNER_TEMP"]
    plain = ["CI", "RUNNER_OS", "MAVEN_OPTS"]
    for src in (wf.get("env") or {}, job.get("env") or {}):
        for k, v in src.items():
            try:
                ctx["env"][k] = expand(v, ctx)
            except (NeedsSecret, Unknown):
                ctx["env"][k] = ""
    job_timeout = float(job.get("timeout-minutes") or 360) * 60
    t_job = time.time()
    verdict, ran = None, 0
    for n, name, st, what, why in plan:
        if what == "skip":
            say("skip %2d %s — %s" % (n, name, why)); continue
        sid = st.get("id") or "_%d" % n
        if "if" in st:
            cond = str(st["if"]).strip()
            cond = re.sub(r"^\$\{\{\s*(.*?)\s*\}\}$", r"\1", cond, flags=re.S)
            try:
                if not truthy(evaluate(cond, ctx)):
                    say("skip %2d %s — its condition is false here (%s)" % (n, name, cond)); ctx["outcome"][sid] = "skipped"; continue
            except NeedsSecret:
                say("skip %2d %s — its condition reads a secret" % (n, name)); continue
            except Unknown:
                say("note %2d %s — condition %r not understood here; the step runs" % (n, name, cond))
        try:
            body = expand(st.get("run", ""), ctx)
            senv = {k: expand(v, ctx) for k, v in (st.get("env") or {}).items()}
        except Unknown as e:
            say("skip %2d %s — uses ${{ %s }}, which this script cannot know here" % (n, name, e)); continue
        files = {k: os.path.join(temp, "%s_%d" % (k.lower(), n)) for k in ("GITHUB_OUTPUT", "GITHUB_ENV", "GITHUB_PATH", "GITHUB_STEP_SUMMARY")}
        for p in files.values():
            open(p, "w").close()
        senv_all = dict(env); senv_all.update(ctx["env"]); senv_all.update(senv); senv_all.update(files)
        names = plain + list(ctx["env"]) + list(senv)
        if win:
            senv_all["WSLENV"] = ":".join(wslenv + [v + "/p" for v in pathvars + list(files)] + names)
        shell = str(st.get("shell") or defaults.get("shell") or ("pwsh" if ros == "Windows" else "bash"))
        wd = os.path.normpath(os.path.join(work, expand(st.get("working-directory") or defaults.get("working-directory") or ".", ctx)))
        sp = os.path.join(temp, "step_%d" % n)
        if shell in ("pwsh", "powershell"):
            sp += ".ps1"
            open(sp, "w", encoding="utf-8-sig").write("$ErrorActionPreference = 'stop'\n%s\nif ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }\n" % body)
            exe = (shell + ".exe") if win else shell
            cmd = [exe, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", winpath(sp) if win else sp]
        elif shell == "cmd":
            sp += ".cmd"
            open(sp, "w", newline="\r\n").write("@echo off\n" + body + "\n")
            cmd = ["cmd.exe", "/D", "/E:ON", "/V:OFF", "/S", "/C", "CALL " + (winpath(sp) if win else sp)]
        elif shell == "python":
            sp += ".py"; open(sp, "w").write(body); cmd = ["python3", sp]
        elif shell.startswith(("bash", "sh")):
            sp += ".sh"; open(sp, "w", newline="\n").write(body + "\n")
            cmd = ["bash", "--noprofile", "--norc", "-eo", "pipefail", sp] if shell.startswith("bash") else ["sh", "-e", sp]
        else:
            say("skip %2d %s — shell %r is not supported here" % (n, name, shell)); continue
        if win and shell in ("bash", "sh"):
            say("note %2d %s — a bash step of a Windows job runs in WSL bash here, not Git Bash" % (n, name))
        log = os.path.join(logdir, "step-%02d.log" % n)
        t0 = time.time()
        left = job_timeout - (t0 - t_job)
        tmo = min(left, float(st.get("timeout-minutes") or 1e9) * 60)
        say("run  %2d %s …" % (n, name))
        with open(log, "w", encoding="utf-8") as lf:
            try:
                rc = subprocess.run(cmd, cwd=wd, env=senv_all, stdout=lf, stderr=subprocess.STDOUT, timeout=max(tmo, 1)).returncode
            except subprocess.TimeoutExpired:
                rc = 124
            except OSError as e:
                lf.write(str(e)); rc = 127
        secs = int(time.time() - t0)
        ctx["outputs"][sid] = parse_kv_file(files["GITHUB_OUTPUT"])
        ctx["env"].update(parse_kv_file(files["GITHUB_ENV"]))
        ran += 1
        if rc == 0:
            ctx["outcome"][sid] = "success"
            say("ok   %2d %s (%d s)" % (n, name, secs)); continue
        ctx["outcome"][sid] = "failure"
        text = read_text(log)
        first = next((l.strip() for l in text.splitlines() if re.search(r"\berror\b|\bERR!|Error:|FAILED|fatal:", l, re.I)), "")
        if not first:
            first = (text.strip().splitlines() or ["(no output)"])[-1].strip()
        first = re.sub(r"\s+", " ", first)[:300]
        if rc == 124:
            first = "timed out after %d min" % (tmo // 60)
        if st.get("continue-on-error") is True:
            say("FAIL %2d %s (%d s, exit %d; continue-on-error) — %s" % (n, name, secs, rc, first)); continue
        say("FAIL %2d %s (%d s, exit %d) — %s" % (n, name, secs, rc, first))
        verdict = ("FAIL     job %s: step %d \"%s\" failed (exit %d) with empty caches — %s — log %s"
                   % (jid, n, name, rc, first, log))
        break
    if not opt["keep"]:
        shutil.rmtree(root, ignore_errors=True)
        try:
            os.rmdir(os.path.dirname(root))   # tf-ci-repro/, when no other run is using it
        except OSError:
            pass
    else:
        say("kept the copy and its caches at %s" % root)
    if verdict:
        say(verdict); return 1
    if ran == 0:
        _notrun("job %s has no step this script could run" % jid)
    say("PASS     job %s: %d run step(s) passed on a clean copy with empty caches (%s) — logs %s"
        % (jid, ran, ", ".join(caches), logdir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
