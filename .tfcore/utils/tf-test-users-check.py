#!/usr/bin/env python3
"""tf-test-users-check.py — no test may create, delete or change an account on a shared AppManager (FW-001).

    python3 .tfcore/utils/tf-test-users-check.py [--app <App>] [--files <f> ...] [--changed]
                                                 [--json-out <path>] [--quiet] [--all] [--emit <cmd>]

Scans the app's test files: every verify spec (tests/verify/**) and every unit or integration test
file (*.spec.*, *.test.*, a .cs file in a test project or under tests/, test_*.py, *_test.py,
*_test.go, *Test(s).java/.kt). With --files, only those (each must still be a test file); with
--changed, only the test files git says are changed or new (read-only git; a builder's files).

Two findings, each a failure that names the file and the line:
  register   a call to an AppManager register endpoint (AuthSvc/register, UserSvc/register,
             device-register, a client's Register…() call) or the submit of a register form or
             route (a click on a register/sign-up/create-account submit in a test that opened one)
  email      an email address built at run time (Date.now(), a Guid, random, uuid, a time, a
             timestamp in the local part) that is not in the usage guide's Test users table
Allowed:
  - an address in docs/<App>-UsageGuide.md's Test users section (table or the lines under it)
  - an address ending in .invalid or @example.com, built at run time or not, in a test that submits
    no register form and calls no register endpoint (it is only typed into a form that rejects it,
    such as Forgot password)
  - a register-form submit, or a register call, whose only address is a Test users address (the
    "email already in use" path with test user 1), ONLY after a sign-in with that same address earlier
    in the same test and a stop between the two (a skip, a return, a throw or an assertion) for when
    that sign-in is refused. Without it, a test user AppManager no longer holds is created by the
    submit (Sevak TF-016, 2026-11-03: AppManager user 14). Finding kind `register`, "submits Register
    with test user …'s address with no successful sign-in as that user before it".
  - a register-form submit that types no address at all (the form's own validation)
  - a file where the AppManager client is replaced (page.route on the auth calls, nock, msw,
    jest/vi.mock, a Mock/Substitute/Fake of the client, WebApplicationFactory/TestServer): no
    network reaches a shared AppManager
The "register creates an account" path of any app is verified by hand once per release and recorded
in the checklist with the date; the automated row checks only the form's validation and the "email
already in use" path using test user 1, after signing in as test user 1 in the same test and stopping,
with nothing submitted, when that sign-in is refused. The one place a Test users account is ever
registered is the owner-run register-test-users script (stack rule Q4a), never a verify test.

--emit <cmd> appends one gate record per failing row (gate test-users, verdict FAIL) through
tf-emit.sh, run_id from the running command's marker (.tfcore/.session/phase.json): the build gate's
records; the verify gate's come from tf-verify-emit.sh. --all enforces on an app that keeps its own
accounts (by default only an app that signs in through a shared AppManager fails).

Each finding carries the REQ ids of the test it sits in (a helper's finding: every test that calls
the helper). tf-verify-verdict.py fails those rows on gate test-users; tf-build.sh runs it with
--changed and fails the build line.

Prints one line per finding and a verdict line:
  PASS  test-users — 41 test file(s), no test creates an account; 3 test users in docs/Chatur-UsageGuide.md
  FAIL  test-users — 2 finding(s) in 1 file(s): tests/verify/signin-register.spec.ts:96, …
Exit 0 PASS · 1 FAIL · 2 could not run. Python 3 standard library only.
"""
import json
import os
import re
import subprocess
import sys

SKIP_DIRS = {"node_modules", "bin", "obj", ".git", ".tfcore", ".artifacts", "dist", "build", "packages", ".venv",
             "venv", "__pycache__", ".claude", ".opencode", "playwright-report", "test-results", ".tfbuild",
             ".trblazeui", ".techierag", "wwwroot", ".vs", ".idea"}
JS_TEST = re.compile(r"\.(spec|test)\.(ts|tsx|js|jsx|mjs|cjs)$", re.I)
OTHER_TEST = re.compile(r"(^test_.*\.py$|_test\.py$|_test\.go$|Tests?\.(java|kt)$)", re.I)
CS_TEST_DIR = re.compile(r"(^|/)(tests?|[^/]*\.?(Unit|Integration|Ui|E2E|Acceptance)?Tests?)(/|$)", re.I)

# --- (a) register calls ------------------------------------------------------------------------------
ENDPOINT = re.compile(r"(?i)\b(?:AuthSvc|UserSvc)/register\b|device-register\b|/devices?/register\b")
CLIENT_REGISTER = re.compile(r"(?i)\b\w*(?:AppManager|AppMgr|AuthSvc|UserSvc|AuthClient|AuthService|AccountClient|UserClient)\w*"
                             r"\s*\.\s*Register(?:User|Device|Account)?(?:Async)?\s*\(")
DEVICE = re.compile(r"(?i)device-register\b|/devices?/register\b|RegisterDevice")
REG_CONTEXT = re.compile(r"(?i)['\"`/](?:account/)?(?:register|sign-?up|create-account)\b|register-|\w*register\w*\s*\(|signUp\w*\s*\(")
SUBMIT = re.compile(r"(?i)\.click\s*\(|\.tap\s*\(|\.dblclick\s*\(|press\s*\(\s*['\"`]Enter|requestSubmit\s*\(|\.submit\s*\(|ClickAsync\s*\(|\.Click\s*\(|SubmitAsync\s*\(")
SUBMIT_WHAT = re.compile(r"(?i)submit|register|sign[- ]?up|create (?:an |your |my )?account|create-account")

# --- (b) addresses -----------------------------------------------------------------------------------
# a quoted string holding an @: the local part may carry ${…} (JS), {…} (C# $"…", Python f"…"), %s / {}
QUOTED = re.compile(r"""(?P<pre>\$@?|@\$|[fFbBrR]{0,2})(?P<q>["'`])(?P<s>(?:\\.|(?!(?P=q)).)*?@(?:\\.|(?!(?P=q)).)*?)(?P=q)""")
EMAIL = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}")
RUNTIME = re.compile(r"(?i)Date\.now|new Date|getTime|performance\.now|Guid\.NewGuid|NewGuid|randomUUID|uuid|Math\.random|random"
                     r"|DateTime(?:Offset)?\.(?:Utc)?Now|Ticks|time\.time|datetime\.now|Stopwatch|nanoid|faker|Random\(")
STAMP = re.compile(r"\d{10,}|20\d\d[01]\d[0-3]\d")      # a timestamp written into the local part
ASSERT_ONLY = re.compile(r"(?i)\bexpect\s*\(|toHaveText|toContainText|Assert\.|\.Should\(|assert\s")
EMAIL_FIELD = re.compile(r"(?i)email|e-mail|user(?:name)?['\"\]= ]")
SELECTOR_ARG = re.compile(r"(?i)(?:getByPlaceholder|getByLabel|getByText|getByTitle|Placeholder|placeholder\s*[=:])\s*\(?\s*$")
TEST_USER_REF = re.compile(r"(?i)credentials\s*\(|test_?users?|testuser|\bowner|\buser_?1\b|yolo|second")
TYPE_CALL = re.compile(r"(?i)\.fill\s*\(|\.type\s*\(|pressSequentially\s*\(|SendKeys\s*\(|FillAsync\s*\(|TypeAsync\s*\(|\btype\s*\(")
# Sevak TF-016: a sign-in as the same user before a Register submit, and a stop when it is refused
SIGNIN = re.compile(r"(?i)\bsign_?in\w*\s*\(|\blog_?in(?:As|With|User|Async)?\w*\s*\(|AuthSvc/login|UserSvc/login|/(?:account/)?(?:sign-?in|login)\b|\.Login\w*\s*\(|SignInAsync\s*\(")
STOP = re.compile(r"(?i)\b(?:test|it)\.skip\s*\(|\bskip\s*\(|\breturn\b|\bthrow\b|\bexpect\s*\(|\bAssert\.|\.Should\(|Skip\.If\w*\s*\(|\bAssume\.|pytest\.(?:skip|fail)\s*\(|\bt\.(?:Skip|Fatal)\w*\s*\(|^\s*assert\s")
SIGNIN_SUBMIT = re.compile(r"(?i)^(?!.*(?:register|sign-?up|create-account)).*(?:sign-?in|log-?in)[\w-]*(?:-form|-submit|-button|\b)")   # the sign-in form's own submit
TYPED_ARG = re.compile(r"(?i)(?:\.fill|\.type|pressSequentially|SendKeys|FillAsync|TypeAsync)\s*\(\s*(?:[^,()]*,\s*)?([A-Za-z_$][\w$.!?]*|['\"`][^'\"`]+['\"`])\s*[,)]")

# --- the AppManager client replaced: no network ------------------------------------------------------
MOCKS = [re.compile(p) for p in (
    r"(?i)\b(?:page|context|browserContext)\.route\s*\([^\n]*(?:register|auth|appmgr|appmanager|usersvc)",
    r"\bnock\s*\(", r"\b(?:jest|vi)\.mock\s*\(", r"\bsetupServer\s*\(", r"from ['\"]msw",
    r"(?:new Mock|Mock\.Of|Substitute\.For|A\.Fake)\s*<\s*I?\w*(?:AppManager|AppMgr|Auth|User|Account)\w*",
    r"\bFake\w*(?:AppManager|AppMgr|Auth|Account)\w*\b", r"MockHttpMessageHandler|WireMock",
    r"WebApplicationFactory\s*<|new TestServer\s*\(", r"unittest\.mock|@patch\s*\(|\bresponses\.add\s*\(|httpx_mock|\brespx\b")]

REQ = re.compile(r"\bREQ[-_]([A-Z]{2,5})[-_](\d{3,})\b")
JS_START = re.compile(r"^\s*(?:test|it)(?:\.(?:only|skip|fixme|fail|slow))?\s*\(\s*['\"`]")   # a title: test.skip(cond, …) inside a test is not one
CS_START = re.compile(r"^\s*\[(?:Fact|Theory|Test|TestMethod|TestCase|SkippableFact|SkippableTheory)\b")
PY_START = re.compile(r"^\s*(?:async\s+)?def\s+test_")
GO_START = re.compile(r"^func\s+Test\w*\s*\(")
JAVA_START = re.compile(r"^\s*@Test\b")
HELPER = re.compile(r"^(?:export\s+)?(?:async\s+)?function\s+(\w+)|^(?:export\s+)?(?:const|let)\s+(\w+)\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)\s*=>"
                    r"|^\s*(?:async\s+)?def\s+(?!test_)(\w+)\s*\(|^\s*(?:private|internal|public|protected)?\s*(?:static\s+)?(?:async\s+)?[\w<>\[\],]+\s+(\w+)\s*\([^;]*\)\s*$")
CONST = re.compile(r"""^\s*(?:export\s+)?(?:const|let|var|static\s+readonly\s+string|const\s+string|private\s+const\s+string|\w+)?\s*([A-Za-z_]\w*)\s*[:=]\s*(?:string\s*=\s*)?["'`]([^"'`\s]+@[^"'`\s]+)["'`]""")


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def find_app(root, app):
    if app:
        return app
    docs = os.path.join(root, "docs")
    names = sorted(os.listdir(docs)) if os.path.isdir(docs) else []
    here = os.path.basename(os.path.abspath(root))
    apps = [m.group(1) for n in names for m in [re.match(r"^(.+?)-(?:P\d+-)?(?:Checklist|BRD)\.md$", n)] if m]
    if here in apps:
        return here
    with_brd = [a for a in apps if f"{a}-BRD.md" in names]
    if with_brd or apps:
        return (with_brd or apps)[0]
    for n in names:
        m = re.match(r"^(.+?)-Usage-?Guide\.md$", n)
        if m:
            return m.group(1)
    return os.path.basename(os.path.abspath(root))


def guides(root, app):
    docs = os.path.join(root, "docs")
    if not os.path.isdir(docs):
        return []
    pat = re.compile(rf"^{re.escape(app)}-(?:P\d+-)?Usage-?Guide\.md$", re.I)
    return [os.path.join(docs, n) for n in sorted(os.listdir(docs)) if pat.match(n)]


def test_users(root, app):
    """Every address in the Test users section of the app's usage guide(s): the table and the lines
    under it (a guide that also names a seeded local account there documents it)."""
    users, where, text = set(), [], ""
    for g in guides(root, app):
        m = re.search(r"(?ms)^#{2,3}\s+(?:\d+[.)]\s*)?Test users[^\n]*\n(.*?)(?=^#{1,3} |\Z)", read(g))
        if m:
            text += m.group(1)
            found = {e.lower() for e in EMAIL.findall(m.group(1))}
            if found:
                users |= found
                where.append(os.path.relpath(g, root))
    return users, where, text


def signs_in_through_appmanager(root, app, section_text):
    """The Architecture's authentication row names AppManager (as tf-doc-check.py reads it), or the
    usage guide's Test users section says the users live on an AppManager."""
    arch = os.path.join(root, "docs", f"{app}-Architecture.md")
    for line in read(arch).splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")] if line.strip().startswith("|") else []
        if len(c) >= 2 and re.search(r"(?i)\bq4\b|auth|identity|sign-in", " ".join(c[:2])) \
                and re.search(r"(?i)app ?manager", " ".join(c[1:3])):
            return True
    return bool(re.search(r"(?i)app ?manager", section_text))


def is_test_file(rel):
    rel = rel.replace("\\", "/")
    base = os.path.basename(rel)
    if JS_TEST.search(base) or OTHER_TEST.search(base):
        return True
    if rel.startswith("tests/verify/") and base.endswith((".ts", ".js", ".mjs")) and not base.endswith(".d.ts"):
        return bool(re.search(r"\b(?:test|it)(?:\.\w+)?\s*\(", read_cache(rel)))
    if base.endswith(".cs") and CS_TEST_DIR.search(os.path.dirname(rel) + "/"):
        return True
    return False


_cache = {}


def read_cache(rel):
    if rel not in _cache:
        _cache[rel] = read(os.path.join(ROOT, rel))
    return _cache[rel]


def all_test_files(root):
    out = []
    for d, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS and not x.startswith(".") or x in (".github",))
        for n in sorted(files):
            rel = os.path.relpath(os.path.join(d, n), root).replace("\\", "/")
            if is_test_file(rel):
                out.append(rel)
    return out


def changed_files(root):
    """Changed or new files by git (read-only): the files a builder touched in this pass."""
    try:
        a = subprocess.run(["git", "-C", root, "diff", "--name-only", "--relative", "HEAD"], capture_output=True, text=True, timeout=30)
        b = subprocess.run(["git", "-C", root, "ls-files", "-o", "--exclude-standard"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if a.returncode != 0:
        return None
    return sorted({x.strip() for x in (a.stdout + "\n" + b.stdout).splitlines() if x.strip()})


def strip_comment(line):
    s = line.strip()
    if s.startswith(("//", "#", "*", "/*", "--")) and not s.startswith("#["):
        return ""
    return line


def addresses(line):
    """(address with placeholders, runtime-built?) for each email-like string on the line."""
    out = []
    for m in QUOTED.finditer(line):
        s, pre, q = m.group("s"), m.group("pre") or "", m.group("q")
        interp = (q == "`" and "${" in s) or ("$" in pre and "{" in s) or (pre[:1] in "fF" and pre and "{" in s) \
            or "%s" in s or "{}" in s or re.search(r"\{\d+\}", s)
        flat = re.sub(r"\$\{[^}]*\}|\{[^}]*\}|%s", "X", s)
        local, _, dom = flat.rpartition("@")
        if not dom or not re.match(r"[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$", dom):
            continue
        before = line[:m.start()]
        if s.lower().startswith(("placeholder:", "label:", "text:")) or SELECTOR_ARG.search(before):
            continue                         # a locator naming a placeholder or label, never typed
        concat = (not local) and re.search(r"\+\s*$", before)            # 'x-' + Date.now() + '@x.com'
        runtime = bool(interp or concat or STAMP.search(local))
        if runtime and not (interp or STAMP.search(local)) and not RUNTIME.search(line):
            runtime = bool(concat)
        out.append(((local or "X") + "@" + dom, runtime, s))
    return out


def allowed_reject_domain(addr):
    dom = addr.rpartition("@")[2].lower()
    return dom.endswith(".invalid") or dom == "example.com"


def blocks_of(lines, ext):
    """[(start, end, kind, name)]: kind 'test' or 'helper' or 'top'; end exclusive."""
    starts = []
    for i, ln in enumerate(lines):
        if JS_START.match(ln) or CS_START.match(ln) or PY_START.match(ln) or GO_START.match(ln) or JAVA_START.match(ln):
            starts.append((i, "test", None))
            continue
        h = HELPER.match(ln)
        if h and not ln.lstrip().startswith(("return", "await", "if", "for", "while", "new ", "else")):
            name = next(g for g in h.groups() if g)
            if name not in ("if", "for", "while", "switch", "catch", "using", "return"):
                starts.append((i, "helper", name))
    out, prev = [], 0
    if not starts or starts[0][0] > 0:
        out.append((0, starts[0][0] if starts else len(lines), "top", None))
    for k, (i, kind, name) in enumerate(starts):
        end = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        out.append((i, end, kind, name))
    return out


def reqs_in(text):
    return sorted({f"REQ-{a}-{b}" for a, b in REQ.findall(text)})


def scan_file(rel, users):
    text = read_cache(rel)
    lines = text.splitlines()
    mocked = next((p.pattern for p in MOCKS if p.search(text)), None)
    if mocked:
        return [], True
    consts = {}                              # NAME -> (address, built at run time, as written)
    for ln in lines:
        m = CONST.match(ln)
        if m and EMAIL.fullmatch(m.group(2)):
            consts[m.group(1)] = (m.group(2).lower(), False, m.group(2))
            continue
        m = re.match(r"^\s*(?:export\s+)?(?:const|let|var|static\s+readonly\s+string|private\s+static\s+readonly\s+string)\s+([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?=", ln)
        found = addresses(ln) if m else []
        if found:
            addr, runtime, raw = found[-1]
            consts[m.group(1)] = (addr.lower(), runtime, raw)
    blocks = blocks_of(lines, os.path.splitext(rel)[1])
    clean = [strip_comment(l) for l in lines]

    def submits(a, b, ctx_text):
        """lines (1-based) in [a, b) that submit a register form or call a register endpoint"""
        out = []
        ctx = bool(REG_CONTEXT.search(ctx_text))
        for i in range(a, b):
            ln = clean[i]
            if not ln.strip():
                continue
            if ENDPOINT.search(ln) or CLIENT_REGISTER.search(ln):
                out.append((i + 1, "endpoint", bool(DEVICE.search(ln))))
            elif ctx and SUBMIT.search(ln) and not SIGNIN_SUBMIT.search(ln) and SUBMIT_WHAT.search(
                    re.sub(r"(?i)\b(?:goto|go|navigate\w*|openInteractive|waitForURL|toHaveURL)\s*\([^)]*\)", "",
                           (clean[i - 1] + " " if ln.lstrip().startswith(".") and i > a else "") + ln)):
                out.append((i + 1, "form", False))
        return out

    # helpers that register: a call to one in a test is a register submit at the call line
    reg_helpers = {}
    for a, b, kind, name in blocks:
        if kind == "helper" and name:
            s = submits(a, b, "\n".join(clean[a:b]))
            if s:
                reg_helpers[name] = s[0]

    findings = []
    all_reqs = reqs_in(text)
    for a, b, kind, name in blocks:
        body = "\n".join(clean[a:b])
        if kind == "helper" and name in reg_helpers:
            continue                         # judged where it is called
        reqs = reqs_in("\n".join(lines[a:min(b, a + 3)])) or reqs_in(body)
        if kind == "top":
            reqs = all_reqs
        subs = submits(a, b, body)
        for hname, (hl, hk, hdev) in reg_helpers.items():
            for i in range(a, b):
                if re.search(rf"\b{re.escape(hname)}\s*\(", clean[i]) and not HELPER.match(lines[i]):
                    subs.append((i + 1, hk, hdev, hname, hl))
        subs = [s if len(s) == 5 else s + (None, None) for s in subs]
        # the addresses this test types or sends
        addrs = []
        for i in range(a, b):
            ln = clean[i]
            if not ln.strip():
                continue
            for addr, runtime, raw in addresses(ln):
                if ASSERT_ONLY.search(ln) and not runtime:
                    continue                 # an address only read off the screen
                addrs.append((i + 1, addr.lower(), runtime, raw))
            for cname, (cval, crt, craw) in consts.items():
                if re.search(rf"\b{re.escape(cname)}\b", ln) and not re.match(rf"^\s*(?:export\s+)?(?:const|let|var|\w[\w\s]*)\s+{re.escape(cname)}\s*[:=]", lines[i]):
                    addrs.append((i + 1, cval, crt, f"{cname} = {craw}"))
        typed_unknown = any(TYPE_CALL.search(clean[i]) and EMAIL_FIELD.search(clean[i]) for i in range(a, b))
        known_user = [x for x in addrs if x[1] in users]
        others = [x for x in addrs if x[1] not in users]
        # what names the test user's address in this test: the literal, a constant holding it, or the
        # identifier typed into the email field (OWNER_EMAIL read from settings)
        user_tokens = {x[1] for x in known_user} | {c for c, (v, _rt, _r) in consts.items() if v in users}
        for i in range(a, b):
            if TYPE_CALL.search(clean[i]) and EMAIL_FIELD.search(clean[i]):
                for t in TYPED_ARG.findall(clean[i]):
                    t = t.strip("'\"`").rstrip("!?")
                    if t and "@" not in t or t.lower() in users:
                        user_tokens.add(t.lower() if "@" in t else t)

        def signed_in_first(sub_line):
            """a sign-in naming the same user before the submit, then a stop before the submit"""
            for i in range(a, sub_line - 1):
                ln = clean[i]
                if not SIGNIN.search(ln) or HELPER.match(lines[i]):
                    continue
                low = ln.lower()
                if user_tokens and not any((t.lower() if "@" in t else t) in (low if "@" in t else ln) for t in user_tokens):
                    continue
                if any(STOP.search(clean[j]) for j in range(i + 1, sub_line - 1)):
                    return True
            return False

        def via_test_user(ln_no, via):
            return (f"submits Register with a test user's address with no successful sign-in as that user before it{via}: "
                    "when AppManager no longer holds the user, the submit creates it. Sign in as test user 1 first in "
                    "the same test and stop (skip) without submitting when that sign-in is refused")
        for ln_no, how, device, hname, hl in subs:
            via = f" (through {hname}(), line {hl})" if hname else ""
            if device:
                findings.append((ln_no, "register", f"registers a device on AppManager{via}", reqs))
            elif how == "endpoint":
                if known_user and not others:
                    if signed_in_first(ln_no):
                        continue             # "email already in use" with a test user proved to exist
                    findings.append((ln_no, "register", via_test_user(ln_no, via), reqs))
                    continue
                findings.append((ln_no, "register", f"calls an AppManager register endpoint{via}"
                                 + (f" with {others[0][3]}" if others else ""), reqs))
            else:
                if not others and known_user:
                    if signed_in_first(ln_no):
                        continue             # test user 1, proved to exist: the "email already in use" path
                    findings.append((ln_no, "register", via_test_user(ln_no, via), reqs))
                    continue
                if not addrs and typed_unknown and TEST_USER_REF.search(body):
                    # a test user typed by name (OWNER_EMAIL from the settings): the same rule
                    if signed_in_first(ln_no):
                        continue
                    findings.append((ln_no, "register", via_test_user(ln_no, via), reqs))
                    continue
                if not addrs and not typed_unknown:
                    continue                 # no address typed: the form's own validation
                findings.append((ln_no, "register", f"submits the register form{via}"
                                 + (f" with {others[0][3]}" if others else " with an address that is not a test user"), reqs))
        said = set()
        for ln_no, addr, runtime, raw in others:
            if not runtime or addr in said:
                continue                     # one finding per address per test, at its first line
            said.add(addr)
            if allowed_reject_domain(addr) and not subs:
                continue                     # typed into a form that rejects it, never registered
            findings.append((ln_no, "email", f"builds an address at run time ({raw}) that is not in the Test users table", reqs))
    seen, out = set(), []
    for f in sorted(findings, key=lambda x: (x[0], x[1])):
        if (f[0], f[1]) not in seen:
            seen.add((f[0], f[1]))
            out.append(f)
    return out, False


ROOT = "."


def main(argv):
    global ROOT
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    ROOT = argv[argv.index("--root") + 1] if "--root" in argv else "."
    app = find_app(ROOT, argv[argv.index("--app") + 1] if "--app" in argv else None)
    out_json = argv[argv.index("--json-out") + 1] if "--json-out" in argv else None
    quiet = "--quiet" in argv
    files = None
    if "--files" in argv:
        files = []
        for x in argv[argv.index("--files") + 1:]:
            if x.startswith("--"):
                break
            files.append(os.path.relpath(os.path.abspath(x), os.path.abspath(ROOT)).replace("\\", "/"))
    if "--changed" in argv and os.environ.get("TF_TEST_USERS_ALL") != "1":   # =1: every test file (the self-tests)
        ch = changed_files(ROOT)
        if ch is None:
            files = None if files is None else files     # not a git repository: every test file
        else:
            files = sorted(set(files or []) | set(ch))
    users, where, section = test_users(ROOT, app)
    # The rule protects a SHARED AppManager. An app that keeps its own accounts (TechieBlog, Lekhak, and
    # AppManager itself, whose verify runs its own local copy) is reported, never failed; --all enforces.
    enforced = "--all" in argv or (app.lower() != "appmanager" and signs_in_through_appmanager(ROOT, app, section))
    scope = all_test_files(ROOT) if files is None else [f for f in files if os.path.isfile(os.path.join(ROOT, f)) and is_test_file(f)]
    findings, mocked = [], []
    for rel in scope:
        fs, m = scan_file(rel, users)
        if m:
            mocked.append(rel)
        for ln, kind, detail, reqs in fs:
            findings.append({"file": rel, "line": ln, "kind": kind, "detail": detail, "reqs": reqs})
    if not enforced:
        if not quiet:
            for f in findings:
                print(f"NOTE  {f['file']}:{f['line']} {f['kind']}: {f['detail']}")
        print(f"PASS  test-users — not enforced: {app} does not sign in through a shared AppManager (its Architecture "
              f"names none); {len(scope)} test file(s), {len(findings)} local-account note(s)")
        if out_json:
            os.makedirs(os.path.dirname(out_json) or ".", exist_ok=True)
            with open(out_json, "w", encoding="utf-8") as f:
                json.dump({"verdict": "PASS", "enforced": False, "app": app, "files_scanned": len(scope), "notes": findings,
                           "findings": [], "by_req": {}}, f, indent=1)
        return 0
    by_req = {}
    for k, f in enumerate(findings):
        for r in f["reqs"]:
            by_req.setdefault(r, []).append(k)
    verdict = "FAIL" if findings else "PASS"
    src = ", ".join(where) or "no usage guide Test users section"
    if not quiet:
        for f in findings:
            print(f"FAIL  {f['file']}:{f['line']} {f['kind']}: {f['detail']}" + (f" [{', '.join(f['reqs'])}]" if f["reqs"] else ""))
    nfiles = len({f["file"] for f in findings})
    if findings:
        print(f"FAIL  test-users — {len(findings)} finding(s) in {nfiles} file(s): "
              + ", ".join(f"{f['file']}:{f['line']}" for f in findings[:4]) + (" …" if len(findings) > 4 else "")
              + ". A test never creates, deletes or changes an account on a shared AppManager: use a Test users address "
              "(the \"email already in use\" path with test user 1, only after signing in as test user 1 in the same test and "
              "stopping when that sign-in is refused) or check only the form's validation; the "
              "\"register creates an account\" path is verified by hand once per release and recorded in the checklist with the date.")
    else:
        print(f"PASS  test-users — {len(scope)} test file(s), no test creates an account; {len(users)} test user(s) in {src}"
              + (f"; {len(mocked)} file(s) replace the AppManager client" if mocked else ""))
    if out_json:
        os.makedirs(os.path.dirname(out_json) or ".", exist_ok=True)
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump({"verdict": verdict, "enforced": True, "app": app, "files_scanned": len(scope), "test_users": sorted(users),
                       "test_users_from": where, "mocked": mocked, "findings": findings, "by_req": by_req}, f, indent=1)
    if findings and "--emit" in argv:
        emit_gates(argv[argv.index("--emit") + 1], app, by_req, findings)
    return 1 if findings else 0


def emit_gates(cmd, app, by_req, findings):
    """one gate record per failing row, as the other gates write them (SCHEMA.md §3)"""
    marker = os.path.join(ROOT, ".tfcore", ".session", "phase.json")
    run_id = ""
    try:
        run_id = json.load(open(marker, encoding="utf-8")).get("started", "")
    except (OSError, ValueError):
        pass
    emit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tf-emit.sh")
    lines = []
    for rid in sorted(by_req):
        m = re.match(r"REQ-([A-Z]+)-", rid)
        lines.append(json.dumps({"kind": "gate", "app": app, "run_id": run_id or None, "req_id": rid,
                                 "req_class": m.group(1) if m else None, "verdict": "FAIL", "gate": "test-users",
                                 "gates_run": ["build", "test-users"], "failure_class": "test-users"}))
    if not lines:
        return
    try:
        r = subprocess.run(["bash", emit, "gates"], input="\n".join(lines) + "\n", text=True, cwd=ROOT,
                           capture_output=True, timeout=60)
        refused = "REFUSED" in (r.stdout or "") + (r.stderr or "")
        print(f"telemetry: {len(lines)} gate record(s) on gate test-users ({cmd})" if not refused
              else f"telemetry: the gate records were refused: {(r.stdout or r.stderr).strip()[:160]}")
    except (OSError, subprocess.SubprocessError):
        print("telemetry: tf-emit.sh could not run; no gate record written")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
