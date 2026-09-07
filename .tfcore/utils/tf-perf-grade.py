#!/usr/bin/env python3
"""tf-perf-grade.py — grade a tf-perf.sh measurement against a row's budget (see tf-perf-grade.sh).

    bash .tfcore/utils/tf-perf-grade.sh --budget "p95 ttfb <= 500ms @ concurrency 50" \
         --json tests/.artifacts/verify/perf/REQ-NFR-001.json [--json-out <file>]

Prints one line: PERF-OK | PERF-MARGINAL (over the budget by up to a quarter: a warning, never a
demotion) | PERF-FAIL (slower than budget × 1.25, or the app shed a tenth or more of the requests
at that concurrency) | PERF-UNMEASURED with the reason (unreachable, auth wall, non-200 answers,
errors during the run, a Debug build, fewer than 20 samples). It reads the budget, never invents
one. Exit 0 OK or MARGINAL · 1 FAIL · 2 UNMEASURED · 3 usage.
"""
import json
import os
import re
import sys

BUDGET = re.compile(r"(p50|p95|max)\s+(ttfb|load)\s*<=\s*(\d+)\s*ms(?:\s*@\s*concurrency\s+(\d+))?", re.I)


def grade(budget, data):
    """-> dict(verdict, reason, metric, percentile, measured, budget, concurrency, failure_class)"""
    m = BUDGET.search(budget or "")
    if not m:
        return {"verdict": "PERF-UNMEASURED", "reason": f"budget line not in the fixed form: {budget!r}"}
    pct, metric, limit, conc = m.group(1).lower(), m.group(2).lower(), int(m.group(3)), int(m.group(4) or 1)
    out = {"metric": metric, "percentile": pct, "budget": limit, "concurrency": conc, "measured": None, "failure_class": None}
    st = data.get("status")
    if st == "unreachable":
        return dict(out, verdict="PERF-UNMEASURED", reason="the app was unreachable (a build check problem, not a speed result)")
    if st == "redirected":
        return dict(out, verdict="PERF-UNMEASURED", reason="auth wall: every request was redirected; present a session with --cookie or --header")
    levels = data.get("levels") or []
    if not levels:
        return dict(out, verdict="PERF-UNMEASURED", reason="no measurement level in the file")
    lvl = next((l for l in levels if l.get("concurrency") == conc), None)
    note = ""
    if lvl is None:
        lvl = levels[0]
        note = f" (measured at concurrency {lvl.get('concurrency')}, the budget names {conc})"
    err_rate = lvl.get("error_rate") or 0
    if err_rate >= 0.10:
        surv = (lvl.get(f"{metric}_ms") or {}).get(pct)
        return dict(out, verdict="PERF-FAIL", failure_class="timeout", measured=surv,
                    reason=f"{lvl.get('errors')} of {lvl.get('samples', 0) + lvl.get('errors', 0)} requests failed at concurrency {lvl.get('concurrency')}: the budget is not servable; survivors' {pct} {metric} {surv} ms")
    if lvl.get("non_200"):
        return dict(out, verdict="PERF-UNMEASURED", reason=f"non-200 answers ({', '.join(lvl['non_200'][:3])}); a wrong path or a correctness failure, not a speed result")
    if (lvl.get("redirect_rate") or 0) > 0:
        return dict(out, verdict="PERF-UNMEASURED", reason="some requests were redirected (auth wall); present a session and re-measure")
    if err_rate > 0:
        return dict(out, verdict="PERF-UNMEASURED", reason=f"errors during the run (rate {err_rate}); re-run when quiet")
    if str(data.get("build_config", "unknown")) != "Release":
        return dict(out, verdict="PERF-UNMEASURED", reason=f"build is {data.get('build_config', 'unknown')}, not Release; a Debug number is not evidence")
    val = (lvl.get(f"{metric}_ms") or {}).get(pct)
    if val is None:
        return dict(out, verdict="PERF-UNMEASURED", reason=f"no {pct} {metric} figure in the file")
    out["measured"] = val
    if lvl.get("weak"):
        return dict(out, verdict="PERF-UNMEASURED", reason=f"weak sample ({lvl.get('samples')} requests behind the {pct}); raise --requests and re-run")
    if val <= limit:
        return dict(out, verdict="PERF-OK", reason=f"{pct} {metric} {val} ms within {limit} ms @ concurrency {lvl.get('concurrency')}{note}")
    if val <= limit * 1.25:
        return dict(out, verdict="PERF-MARGINAL", reason=f"{pct} {metric} {val} ms vs budget {limit} ms @ concurrency {lvl.get('concurrency')} (marginal){note}")
    return dict(out, verdict="PERF-FAIL", failure_class="slow-ttfb" if metric == "ttfb" else "slow-load",
                reason=f"{pct} {metric} {val} ms vs budget {limit} ms @ concurrency {lvl.get('concurrency')}{note}")


def main(argv):
    budget = jpath = out = None
    i = 1
    while i < len(argv):
        if argv[i] == "--budget" and i + 1 < len(argv):
            budget = argv[i + 1]; i += 2
        elif argv[i] == "--json" and i + 1 < len(argv):
            jpath = argv[i + 1]; i += 2
        elif argv[i] == "--json-out" and i + 1 < len(argv):
            out = argv[i + 1]; i += 2
        else:
            print(__doc__); return 3
    if not budget or not jpath:
        print(__doc__); return 3
    if not os.path.isfile(jpath):
        print(f"PERF-UNMEASURED reason=measurement file {jpath} does not exist"); return 2
    try:
        data = json.load(open(jpath, encoding="utf-8"))
    except Exception as e:
        print(f"PERF-UNMEASURED reason=measurement file unreadable: {e}"); return 2
    g = grade(budget, data)
    if out:
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        json.dump(g, open(out, "w"), indent=1)
    print(f"{g['verdict']} reason={g['reason']}")
    return {"PERF-OK": 0, "PERF-MARGINAL": 0, "PERF-FAIL": 1}.get(g["verdict"], 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
