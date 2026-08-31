#!/usr/bin/env bash
# TechieFlow — asset-integrity harness. Feeds verify-phase §4a2 (the assets gate).
#
#   bash .tfcore/utils/tf-assets.sh --base http://localhost:5099 \
#        --paths "/,/login,/export" --cookie 'AuthCookie=<value>'
#
# WHAT IT ASKS, and it is the only question no other gate asks:
#
#     "Did the assets this page DECLARES actually arrive?"
#
# WHY IT EXISTS (TfLens TF-007, 2026-08-28). A build reporting 140 of 143 `Verified`
# — acceptance, data-render, visual-truth, standards, parity and perf all green —
# shipped a `/login` that rendered as an unstyled single column, because one
# stylesheet (a Blazor scoped-CSS bundle carrying 100% of that page's layout) 404ed.
# Every gate passed, and none of them COULD have caught it:
#
#   acceptance   every control was present and every behavioural assertion held.
#                An unstyled page behaves correctly.
#   render §4a   "does this control carry non-placeholder text?" — yes. Text renders
#                fine with no CSS at all.
#   visual §4b   "do these boxes overlap / clip / leave the viewport?" — no. A single
#                stacked column overlaps nothing. It is the TIDIEST possible failure:
#                partial breakage overlaps, complete breakage stacks neatly.
#   standards    file-level; never loads the app.
#   perf         an unstyled page is, if anything, faster.
#
# A 404 on a <link rel=stylesheet> or a <script src> produces no console error the
# gates read, no server log line, no Blazor error boundary and no failed assertion.
# The app renders something that looks intentional. The check is generic — it needs
# no knowledge of the app, only the rendered document — which is why it belongs in
# the framework rather than being re-written in every project.
#
# WHAT IT IS NOT: a verdict. Like tf-perf.sh it produces findings, never a status.
# verify-phase §4a2 decides what a finding means for a REQ. A measurement tool that
# also judges is a tool you cannot audit when a result looks wrong.
#
# SAME-ORIGIN BY DEFAULT, and this is deliberate. A CDN that is briefly slow or
# rate-limited would fail the gate on every screen for a reason that is not the
# app's defect — and a gate that cries wolf teaches the owner to ignore verdicts,
# which costs more than the defects it catches (verify-phase §4c states the same
# rule for perf). Cross-origin assets are still LISTED, marked `"external":true`,
# and only graded when you pass --include-external.
#
# Exit codes: 0 every declared asset arrived · 2 base unreachable (that is a `build`
#             gate problem, not an assets result) · 3 bad arguments
#             · 4 every path redirected (auth wall — nothing was graded; present a
#               session with --cookie / --header and re-run)
#             · 5 at least one declared asset did not arrive -> the gate FAILS.
# Requires python3 only.

set -uo pipefail

BASE=""; PATHS="/"; TIMEOUT=20; LABEL=""; OUT=""; EXTERNAL=0; MINBYTES=1
HDRS=""   # newline-separated "K: V" pairs (--header, repeatable; --cookie is sugar)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)             BASE="${2:-}"; shift 2 ;;
    --paths)            PATHS="${2:-}"; shift 2 ;;
    --timeout)          TIMEOUT="${2:-}"; shift 2 ;;
    --label)            LABEL="${2:-}"; shift 2 ;;
    --json-out)         OUT="${2:-}"; shift 2 ;;
    --min-bytes)        MINBYTES="${2:-}"; shift 2 ;;
    --include-external) EXTERNAL=1; shift ;;
    --header)           HDRS="${HDRS}${2:-}"$'\n'; shift 2 ;;
    --cookie)           HDRS="${HDRS}Cookie: ${2:-}"$'\n'; shift 2 ;;
    -h|--help)          sed -n '2,48p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 3 ;;
  esac
done

[[ -n "$BASE" ]] || { printf '%s\n' \
  "usage: tf-assets.sh --base URL [--paths /,/login] [--cookie 'k=v'] [--include-external]" \
  "                    [--json-out tests/.artifacts/assets/REQ-NFR-015.json]" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo '{"status":"no-python3"}'; exit 3; }

TF_BASE="$BASE" TF_PATHS="$PATHS" TF_TIMEOUT="$TIMEOUT" TF_LABEL="$LABEL" TF_OUT="$OUT" \
TF_HEADERS="$HDRS" TF_EXTERNAL="$EXTERNAL" TF_MINBYTES="$MINBYTES" python3 - <<'PY'
import html.parser, json, os, ssl, sys, urllib.error, urllib.request
from urllib.parse import urljoin, urlsplit

BASE     = os.environ["TF_BASE"].rstrip("/")
PATHS    = [p.strip() for p in os.environ["TF_PATHS"].split(",") if p.strip()]
TIMEOUT  = float(os.environ["TF_TIMEOUT"])
LABEL    = os.environ.get("TF_LABEL") or None
OUT      = os.environ.get("TF_OUT") or None
EXTERNAL = os.environ.get("TF_EXTERNAL") == "1"
MINBYTES = int(os.environ.get("TF_MINBYTES") or 1)

HEADERS = []
for line in (os.environ.get("TF_HEADERS") or "").splitlines():
    if ":" in line:
        k, _, v = line.partition(":")
        HEADERS.append((k.strip(), v.strip()))

# A dev cert in WSL is routinely untrusted; refusing to look would make the gate
# unusable on exactly the local https head it is meant to check. This harness reads
# public assets off a machine-local dev server — it is not a security boundary.
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

UA = "TechieFlow-tf-assets/1.0"


class AssetParser(html.parser.HTMLParser):
    """Collect what the DOCUMENT DECLARES — not what a browser eventually loaded.

    That distinction is the whole point. A headless browser check would report the
    assets that *succeeded*; a 404ed stylesheet simply would not be in the list, so
    the failure would be invisible in exactly the way TF-007 describes. Reading the
    declaration and then fetching each one is what makes the absence observable.

    Honours <base href>, because a page that sets one and an asset resolver that
    ignores it disagree about every relative URL on the page."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.base_href = None
        self.assets = []          # (kind, raw_url)

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "base" and a.get("href") and self.base_href is None:
            self.base_href = a["href"]
        elif tag == "link":
            rel = " ".join(a.get("rel", "").lower().split())
            href = a.get("href", "").strip()
            if not href:
                return
            if "stylesheet" in rel:
                self.assets.append(("stylesheet", href))
            elif "preload" in rel and a.get("as", "").lower() in ("style", "script", "font"):
                # A preload that 404s is a real miss on a page that then depends on it.
                self.assets.append(("preload-" + a["as"].lower(), href))
            elif "modulepreload" in rel:
                self.assets.append(("modulepreload", href))
            elif "icon" in rel:
                self.assets.append(("icon", href))
        elif tag == "script":
            src = a.get("src", "").strip()
            if src:
                self.assets.append(("script", src))


def fetch(url, want_body=True):
    """Return (status, nbytes, error). Never raises — a transport failure is a
    finding, not a crash, and the caller needs every path's result."""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for k, v in HEADERS:
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=CTX) as r:
            body = r.read() if want_body else b""
            return r.status, len(body), None, body
    except urllib.error.HTTPError as e:
        try:
            body = e.read()
        except Exception:
            body = b""
        return e.code, len(body), None, body
    except Exception as e:
        return None, 0, "%s: %s" % (type(e).__name__, e), b""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None                       # surface the 3xx instead of following it


REDIRECT_OPENER = urllib.request.build_opener(
    NoRedirect, urllib.request.HTTPSHandler(context=CTX))


def fetch_page(url):
    """Pages are fetched WITHOUT following redirects, so an auth wall is visible as
    an auth wall rather than as a successfully-loaded /login (which has its own,
    perfectly healthy assets — the exact way a gate reports green on a page nobody
    asked about). Same lesson as tf-perf.sh's exit 4."""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for k, v in HEADERS:
        req.add_header(k, v)
    try:
        with REDIRECT_OPENER.open(req, timeout=TIMEOUT) as r:
            return r.status, r.read(), None
    except urllib.error.HTTPError as e:
        try:
            body = e.read()
        except Exception:
            body = b""
        return e.code, body, None
    except Exception as e:
        return None, b"", "%s: %s" % (type(e).__name__, e)


# --- reachability first: an unreachable base is a `build` problem, not an assets one
probe_status, _, probe_err = fetch_page(BASE + "/")
if probe_status is None:
    print(json.dumps({"status": "unreachable", "base": BASE, "error": probe_err,
                      "label": LABEL, "note": "app not reachable — this is a `build` "
                      "gate problem, not an assets result"}, indent=2))
    raise SystemExit(2)

origin = urlsplit(BASE)
pages, findings = [], []
redirected = 0
graded_assets = 0

for p in PATHS:
    page_url = BASE + (p if p.startswith("/") else "/" + p)
    status, body, err = fetch_page(page_url)
    if status is None:
        pages.append({"path": p, "status": None, "error": err, "assets": [],
                      "declared": 0, "graded": 0, "failed": 0})
        findings.append({"path": p, "kind": "page", "url": page_url,
                         "problem": "unreachable", "detail": err})
        continue
    if 300 <= status < 400:
        redirected += 1
        pages.append({"path": p, "status": status, "assets": [], "declared": 0,
                      "graded": 0, "failed": 0, "redirected": True})
        continue
    if status != 200:
        pages.append({"path": p, "status": status, "assets": [], "declared": 0,
                      "graded": 0, "failed": 0})
        findings.append({"path": p, "kind": "page", "url": page_url,
                         "problem": "non-200", "detail": status})
        continue

    parser = AssetParser()
    try:
        parser.feed(body.decode("utf-8", "replace"))
    except Exception:
        pass
    doc_base = urljoin(page_url, parser.base_href) if parser.base_href else page_url

    seen, rows, failed = set(), [], 0
    for kind, raw in parser.assets:
        if raw.startswith(("data:", "blob:", "javascript:", "#")):
            continue
        url = urljoin(doc_base, raw)
        if url in seen:
            continue
        seen.add(url)
        u = urlsplit(url)
        is_external = (u.scheme, u.netloc) != (origin.scheme, origin.netloc)
        row = {"kind": kind, "url": url, "external": is_external}
        if is_external and not EXTERNAL:
            row["graded"] = False
            row["note"] = "cross-origin — not graded (pass --include-external to grade it)"
            rows.append(row)
            continue
        st, n, ferr, _ = fetch(url)
        row.update({"graded": True, "status": st, "bytes": n})
        graded_assets += 1
        problem = None
        if ferr:
            problem, row["error"] = "unreachable", ferr
        elif st != 200:
            problem = "status-%s" % st
        elif n < MINBYTES:
            problem = "empty-body"
        if problem:
            failed += 1
            row["problem"] = problem
            findings.append({"path": p, "kind": kind, "url": url,
                             "problem": problem, "status": st, "bytes": n,
                             "external": is_external})
        rows.append(row)

    pages.append({"path": p, "status": status, "declared": len(rows),
                  "graded": sum(1 for r in rows if r.get("graded")),
                  "failed": failed, "assets": rows})

# Every path turned away = nothing was graded. Reporting "0 findings" there would be
# a PASS on a screen the harness never saw — the same false green tf-perf.sh's exit 4
# exists to prevent, and the same shape as TF-011's ungradeable-looks-clean failure.
if PATHS and redirected == len(PATHS):
    out = {"status": "redirected", "base": BASE, "label": LABEL, "pages": pages,
           "findings": [], "note": "every path answered 3xx — nothing was graded. "
           "Present a session with --cookie / --header and re-run. Grade the REQ "
           "ASSETS-UNMEASURED (auth wall); never record this as a pass."}
    print(json.dumps(out, indent=2))
    if OUT:
        os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
        open(OUT, "w", encoding="utf-8").write(json.dumps(out, indent=2))
    raise SystemExit(4)

out = {
    "status": "measured" if not findings else "failed",
    "base": BASE, "label": LABEL,
    "paths_checked": len(PATHS),
    "paths_redirected": redirected,
    "assets_graded": graded_assets,
    "findings_n": len(findings),
    "findings": findings,
    "pages": pages,
    "include_external": EXTERNAL,
    # An assets run that graded nothing is UNGRADEABLE, not clean. Said out loud in
    # the payload so a consumer cannot read `findings_n: 0` as coverage.
    "ungradeable": graded_assets == 0,
}
if graded_assets == 0:
    out["note"] = ("no asset was graded — the pages declared none, or all of them "
                   "were cross-origin. This is ASSETS-UNGRADEABLE, never a pass.")
print(json.dumps(out, indent=2))
if OUT:
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(json.dumps(out, indent=2))
raise SystemExit(5 if findings else 0)
PY
