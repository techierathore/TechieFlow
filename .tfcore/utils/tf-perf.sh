#!/usr/bin/env bash
# TechieFlow — performance measurement harness. Feeds verify-phase §4c (the perf gate).
#
#   bash .tfcore/utils/tf-perf.sh --base http://localhost:5099 \
#        --paths "/,/posts,/admin/dashboard" --levels 1,50 --build-config Release
#
# WHAT IT IS: a deterministic TTFB / full-load sampler over a declared path set at
# declared concurrency levels. It prints ONE JSON object and measures nothing else.
#
# WHAT IT IS NOT: a verdict. It never decides pass/fail, never reads a budget, never
# touches a checklist, and never emits telemetry. verify-phase §4c compares its numbers
# against the budget declared in the REQ; this script only produces the numbers. That
# separation is deliberate — a measurement tool that also judges is a tool you cannot
# audit when a number looks wrong.
#
# MEASUREMENT DEFINITIONS (stated because a perf number is meaningless without them):
#   ttfb_ms  wall time from issuing the request to the FIRST BYTE of the response body
#            (headers already received). This is what a page-load budget is really about.
#   load_ms  wall time until the response body is fully read.
#   Both EXCLUDE connection setup of the warm-up requests, which are discarded: ASP.NET
#   JITs on first hit and a cold first request is not what a user experiences.
#
# HONESTY RULES BAKED IN:
#   - p95 is the headline, never the mean. One 4-second stall matters; an average hides it.
#   - Every sample count is reported. A p95 over 4 samples is noise and says so (`"weak":true`).
#   - build_config is stamped, never guessed. A Debug-build number is not evidence and
#     verify-phase §4c refuses to fail a REQ on one.
#   - machine fingerprint is printed for the HUMAN so two runs are never silently compared
#     across hosts. It is NOT telemetry and must never be emitted to gates.jsonl.
#
# Exit codes: 0 measured · 2 app unreachable (nothing measured) · 3 bad arguments.
# Requires python3 only (the framework already depends on it for the guard hooks).

set -uo pipefail

BASE=""; PATHS="/"; LEVELS="1"; REQS=5; WARMUP=3; TIMEOUT=30; BUILD="unknown"; LABEL=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)         BASE="${2:-}"; shift 2 ;;
    --paths)        PATHS="${2:-}"; shift 2 ;;
    --levels)       LEVELS="${2:-}"; shift 2 ;;
    --requests)     REQS="${2:-}"; shift 2 ;;
    --warmup)       WARMUP="${2:-}"; shift 2 ;;
    --timeout)      TIMEOUT="${2:-}"; shift 2 ;;
    --build-config) BUILD="${2:-}"; shift 2 ;;
    --label)        LABEL="${2:-}"; shift 2 ;;
    --json-out)     OUT="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 3 ;;
  esac
done

[[ -n "$BASE" ]] || { echo "usage: tf-perf.sh --base URL [--paths /,/a] [--levels 1,50] [--build-config Release]" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo '{"status":"no-python3"}'; exit 3; }
case "$BUILD" in Release|Debug|unknown) ;; *) echo "--build-config must be Release|Debug|unknown" >&2; exit 3 ;; esac

TF_BASE="$BASE" TF_PATHS="$PATHS" TF_LEVELS="$LEVELS" TF_REQS="$REQS" TF_WARMUP="$WARMUP" \
TF_TIMEOUT="$TIMEOUT" TF_BUILD="$BUILD" TF_LABEL="$LABEL" TF_OUT="$OUT" python3 - <<'PY'
import http.client, json, os, platform, ssl, statistics, sys, threading, time
from urllib.parse import urlparse

BASE    = os.environ["TF_BASE"].rstrip("/")
PATHS   = [p.strip() for p in os.environ["TF_PATHS"].split(",") if p.strip()]
LEVELS  = [int(x) for x in os.environ["TF_LEVELS"].split(",") if x.strip()]
REQS    = int(os.environ["TF_REQS"]); WARMUP = int(os.environ["TF_WARMUP"])
TIMEOUT = float(os.environ["TF_TIMEOUT"]); BUILD = os.environ["TF_BUILD"]
LABEL   = os.environ["TF_LABEL"] or None; OUT = os.environ["TF_OUT"]

u = urlparse(BASE)
HOST, PORT, HTTPS = u.hostname, u.port or (443 if u.scheme == "https" else 80), u.scheme == "https"
CTX = ssl._create_unverified_context() if HTTPS else None   # dev certs: verified elsewhere, not here


def hit(path):
    """One request. Returns (ttfb_ms, load_ms, status) or (None, None, error-string)."""
    conn = None
    try:
        conn = (http.client.HTTPSConnection(HOST, PORT, timeout=TIMEOUT, context=CTX) if HTTPS
                else http.client.HTTPConnection(HOST, PORT, timeout=TIMEOUT))
        t0 = time.perf_counter()
        conn.request("GET", path, headers={"Accept": "text/html,*/*", "Connection": "close"})
        resp = conn.getresponse()
        resp.read(1)                                  # <- first body byte defines TTFB
        ttfb = (time.perf_counter() - t0) * 1000.0
        resp.read()
        return ttfb, (time.perf_counter() - t0) * 1000.0, resp.status
    except Exception as e:
        return None, None, type(e).__name__
    finally:
        if conn:
            try: conn.close()
            except Exception: pass


# --- reachability, before anything is measured -------------------------------
probe = None
for _ in range(3):
    probe = hit(PATHS[0])
    if probe[0] is not None:
        break
    time.sleep(1)
if probe[0] is None:
    print(json.dumps({"status": "unreachable", "base": BASE, "path": PATHS[0], "error": probe[2]}))
    sys.exit(2)

# --- warm-up: discarded on purpose (JIT / first-request compilation) ---------
for p in PATHS:
    for _ in range(WARMUP):
        hit(p)


def pct(xs, q):
    if not xs: return None
    xs = sorted(xs)
    if len(xs) == 1: return round(xs[0], 1)
    k = (len(xs) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return round(xs[lo] + (xs[hi] - xs[lo]) * (k - lo), 1)


def summarize(xs):
    return {"p50": pct(xs, 0.50), "p95": pct(xs, 0.95), "max": round(max(xs), 1) if xs else None,
            "mean": round(statistics.fmean(xs), 1) if xs else None}


results = []
for conc in LEVELS:
    samples, lock = {p: {"ttfb": [], "load": []} for p in PATHS}, threading.Lock()
    errors, non200 = [], []

    def worker():
        for _ in range(REQS):
            for p in PATHS:
                ttfb, load, st = hit(p)
                with lock:
                    if ttfb is None:
                        errors.append(st)
                    else:
                        if st != 200: non200.append((p, st))
                        samples[p]["ttfb"].append(ttfb); samples[p]["load"].append(load)

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(conc)]
    t0 = time.perf_counter()
    for t in threads: t.start()
    for t in threads: t.join()
    elapsed = time.perf_counter() - t0

    all_ttfb = [v for p in PATHS for v in samples[p]["ttfb"]]
    all_load = [v for p in PATHS for v in samples[p]["load"]]
    results.append({
        "concurrency": conc,
        "samples": len(all_ttfb),
        # A p95 needs samples behind it. Below 20 the number is indicative, not evidence,
        # and verify-phase §4c must not fail a REQ on it.
        "weak": len(all_ttfb) < 20,
        "errors": len(errors),
        # Rate, not just count — verify-phase §4c branches on it. A handful of errors
        # contaminates a latency sample (do not grade); a large fraction IS the result
        # (the app did not serve the declared concurrency). Only the rate separates them.
        "attempted": len(all_ttfb) + len(errors),
        "error_rate": (round(len(errors) / (len(all_ttfb) + len(errors)), 3)
                       if (len(all_ttfb) + len(errors)) else None),
        "error_kinds": sorted(set(errors))[:5],
        "non_200": sorted({f"{p}:{s}" for p, s in non200})[:5],
        "wall_s": round(elapsed, 2),
        "ttfb_ms": summarize(all_ttfb),
        "load_ms": summarize(all_load),
        "per_path": [{"path": p,
                      "samples": len(samples[p]["ttfb"]),
                      "ttfb_p95": pct(samples[p]["ttfb"], 0.95),
                      "load_p95": pct(samples[p]["load"], 0.95)} for p in PATHS],
    })

out = {
    "status": "ok",
    "schema": "tf-perf/1",
    "base": BASE,
    "label": LABEL,
    "build_config": BUILD,
    "paths": PATHS,
    "warmup_discarded": WARMUP,
    "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    # For the HUMAN reading the report: never compare two runs whose fingerprints differ.
    # NOT telemetry — must never reach gates.jsonl (SCHEMA.md §3.3, constraint 7).
    "machine": {"platform": platform.system(), "release": platform.release(),
                "cpus": os.cpu_count(), "python": platform.python_version()},
    "levels": results,
}
text = json.dumps(out, indent=2)
if OUT:
    os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(text + "\n")
    print(text)
else:
    print(text)
PY
