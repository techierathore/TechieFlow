#!/usr/bin/env python3
"""tf-verify-verdict.py — turn a verify run's evidence into one verdict per row (see tf-verify-verdict.sh).

    bash .tfcore/utils/tf-verify-verdict.sh <App> [--apply] [--dir tests/.artifacts/verify] [--started <ISO>]

Reads, from the evidence folder: list.json (the rows), boot.json (what was booted), tests.json (the
acceptance tests), screens.json (render and visual), assets.json (tf-assets.sh --json-out),
parity.json (tf-mockup-parity.sh --json-out) and perf/<REQ>.json (tf-perf.sh --json-out per budget
row). A file that is absent means that check did not run.

For each row, the seven checks in order, and the first that fails is the verdict:
  build       the app booted (or was built) — boot.json
  acceptance  a test carrying the row's id passed — tests.json
  render      every anchored control on its screen shows something — screens.json
  assets      every stylesheet and script its screen declares arrived — assets.json
  visual      nothing overlaps, nothing clipped or off-screen — screens.json
  mockup      the screen carries the structure its mockup draws — parity.json
  speed       within the row's perf-budget, only when it declares one — perf/<REQ>.json
  (standards has no script yet and is never listed as run)

Verdicts: PASS · FAIL (acceptance) · BUILD-FAIL · RENDER-FAIL · ASSET-FAIL · VISUAL-FAIL · MOCKUP-FAIL ·
PERF-FAIL · NOT-TESTED (no test carried the id, or every test carrying it was skipped; the screen
checks passed or did not run) ·
NOT-OBSERVABLE (an NFR row with no budget and no unit test) · NOT-DRIVEN (its screen was never driven:
the head could not be booted, or has no driver). A row is Verified only on PASS. NOT-* rows keep their
status and get a Remark saying so; nothing is ever written as a static-only pass.

Writes docs/.last-verify.json (the ledger the verify hook reads: date, app, scope, booted, the checks
that ran, and every row's verdict) and <dir>/verdicts.json (for tf-verify-emit.sh). With --apply it
rewrites the Status, % and Remarks cells of every graded row in the checklist. Prints the table.
Exit 0 · 2 could not run.
"""
import datetime
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAILING = {"BUILD-FAIL": "build", "FAIL": "acceptance", "RENDER-FAIL": "render", "ASSET-FAIL": "assets",
           "VISUAL-FAIL": "visual", "MOCKUP-FAIL": "mockup-parity", "PERF-FAIL": "perf"}
STATUS = {"PASS": "Verified", "FAIL": "FAIL", "BUILD-FAIL": "FAIL", "RENDER-FAIL": "Needs re-verify", "ASSET-FAIL": "Needs re-verify",
          "VISUAL-FAIL": "Needs re-verify", "MOCKUP-FAIL": "Needs re-verify", "PERF-FAIL": "Needs re-verify"}


def die(msg):
    print(f"tf-verify-verdict: {msg}", file=sys.stderr)
    sys.exit(2)


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except Exception as e:
        die(f"{path} is not valid JSON: {e}")


def perf_grader():
    spec = importlib.util.spec_from_file_location("tf_perf_grade", os.path.join(HERE, "tf-perf-grade.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.grade


def norm_route(r):
    r = (r or "").strip().lower().rstrip("/")
    return r or "/"


def words(s, n=60):
    w = s.split()
    return s if len(w) <= n else " ".join(w[:n]) + "…"   # the ellipsis rides on the last word: the checker counts words, and a bare "…" was a 61st (miss 29)


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = argv[1]
    apply = "--apply" in argv
    d = argv[argv.index("--dir") + 1] if "--dir" in argv else os.path.join("tests", ".artifacts", "verify")
    started = argv[argv.index("--started") + 1] if "--started" in argv else ""
    today = datetime.date.today().isoformat()

    lst = load(os.path.join(d, "list.json")) or die("list.json missing: run tf-verify-list.sh first")
    boot = load(os.path.join(d, "boot.json")) or {"mode": "none", "reason": "tf-verify-boot.sh was not run", "reason_kind": "host", "head": "none"}
    tests = (load(os.path.join(d, "tests.json")) or {}).get("reqs", {})
    tests_ran = os.path.isfile(os.path.join(d, "tests.json"))
    screens = load(os.path.join(d, "screens.json")) or {}
    scr_by_name = {s["name"]: s for s in screens.get("screens", [])}
    assets = load(os.path.join(d, "assets.json")) or {}
    pages = {norm_route(p.get("path")): p for p in assets.get("pages", [])}
    parity = load(os.path.join(d, "parity.json")) or {}
    par_by_name = {s.get("screen"): s for s in parity.get("screens", [])}
    par_by_route = {norm_route(s.get("route")): s for s in parity.get("screens", [])}
    grade = perf_grader()

    booted = boot.get("mode") not in (None, "none")
    build_failed = boot.get("reason_kind") == "build-error"
    boot_text = (f"{boot.get('head')} via {boot.get('rung')} at {boot.get('url')}" if booted
                 else f"not booted: {boot.get('reason')}")
    checks_ran = set()
    if booted or build_failed:
        checks_ran.add("build")

    rows_out, ledger_rows, table = [], {}, []
    for r in lst["rows"]:
        rid = r["id"]
        prior = r.get("status_raw") or ""
        notes = []
        scr = scr_by_name.get(r.get("screen") or "")
        driven = bool(scr) and scr.get("render") != "UNREACHABLE"
        t = tests.get(rid)
        # A row whose every clause was SKIPPED is NOT-TESTED: the acceptance gate did not run on
        # it. It is neither a pass nor a defect, so it grades exactly like a row with no test at
        # all — never Verified, no gate record (TF-022). `t` is kept for the note.
        skipped_only = bool(t) and t.get("result") == "NOT-TESTED"
        if skipped_only:
            notes.append(f"acceptance not measured ({len(t.get('skipped') or [])} test(s) skipped, none ran)")
            t = None
        # every check on its own: (name, ran, failed, verdict, class, detail, evidence); the first failure wins
        checks = []

        # 1 build
        checks.append(("build", booted or build_failed, build_failed, "BUILD-FAIL", "build-error", boot.get("reason", "build failed"), ""))
        # 2 acceptance
        if t:
            checks.append(("acceptance", True, t["result"] != "PASS", "FAIL", "assert-fail", t.get("reason") or "test failed", t.get("screenshot") or ""))
        # 3 render
        if scr:
            if scr.get("render") == "UNREACHABLE":
                f = next((x for w in scr["widths"] for x in w.get("findings", [])), {})
                checks.append(("render", True, True, "RENDER-FAIL", "other", f.get("detail", "screen unreachable"), ""))
            else:
                bad = [(w, f) for w in scr["widths"] for f in w.get("findings", []) if f["check"] == "render"]
                w, f = bad[0] if bad else (None, None)
                checks.append(("render", True, bool(bad), "RENDER-FAIL", f["class"] if f else None,
                               f"{f['detail']} on {r['screen']} @{w['width']}" if f else "", w.get("screenshot", "") if w else ""))
        # 4 assets
        pg = pages.get(norm_route(r.get("route"))) if r.get("route") else None
        if pg and pg.get("graded", 0) > 0:
            bad = next((a for a in pg.get("assets", []) if a.get("graded") and (a.get("status") in (None, 0) or a.get("status") >= 400 or a.get("bytes", 1) == 0)), None)
            checks.append(("assets", True, pg.get("failed", 0) > 0, "ASSET-FAIL", "missing-asset",
                           f"{pg.get('failed', 0)} declared asset(s) did not arrive on {r['route']}" + (f": {bad.get('url')} → {bad.get('status')}" if bad else ""), ""))
        elif pg and pg.get("redirected"):
            notes.append("assets not graded (auth wall)")
        # 5 visual
        if scr and driven:
            bad = [(w, f) for w in scr["widths"] for f in w.get("findings", []) if f["check"] == "visual"]
            w, f = bad[0] if bad else (None, None)
            checks.append(("visual", True, bool(bad), "VISUAL-FAIL", f["class"] if f else None,
                           f"{f['detail']} on {r['screen']}" if f else "", w.get("screenshot", "") if w else ""))
        # 6 mockup parity
        ps = (par_by_name.get(r.get("screen")) or par_by_route.get(norm_route(r.get("route")))) if r.get("screen") else None
        if ps:
            v = ps.get("verdict")
            if v in ("PASS", "FAIL"):
                f = (ps.get("findings") or [{}])[0]
                checks.append(("mockup-parity", True, v == "FAIL", "MOCKUP-FAIL", "mockup-drift",
                               f"{f.get('class', 'drift')} on {f.get('key', ps.get('screen'))} @{f.get('width', '')}: {str(f.get('detail', ''))[:80]}",
                               os.path.join(d, "parity.json")))
            elif v == "UNGRADEABLE":
                notes.append("mockup-parity UNGRADEABLE (add data-testid anchors to the mockup)")
            elif v == "NO-MOCKUP":
                notes.append("no mockup to compare")
        # 7 speed
        if r.get("perf_budget"):
            pf = load(os.path.join(d, "perf", f"{rid}.json"))
            if pf is None:
                notes.append("perf not measured (no tf-perf run for this row)")
            else:
                g = grade(r["perf_budget"], pf)
                if g["verdict"] in ("PERF-OK", "PERF-MARGINAL", "PERF-FAIL"):
                    checks.append(("perf", True, g["verdict"] == "PERF-FAIL", "PERF-FAIL", g.get("failure_class") or "slow-ttfb", g["reason"], ""))
                if g["verdict"] == "PERF-MARGINAL":
                    notes.append(f"⚠ perf: {g['reason']}")
                elif g["verdict"] == "PERF-UNMEASURED":
                    notes.append(f"perf not measured: {g['reason']}")

        ran = [c[0] for c in checks if c[1]]
        first = next((c for c in checks if c[1] and c[2]), None)
        verdict, cls, detail, evidence = (first[3], first[4], first[5], first[6]) if first else (None, None, "", "")

        # the honest non-verdicts
        if verdict is None:
            if r["class"] == "NFR" and not r.get("perf_budget") and not t:
                verdict = "NOT-OBSERVABLE"
                detail = "NFR row with no perf-budget and no unit test carrying its id"
            elif not t and r.get("screen") and not driven:
                verdict = "NOT-DRIVEN"
                detail = (f"{boot.get('head', 'the app')} not driven: {boot.get('reason')}" if not booted
                          else f"screen {r['screen']} was not driven in this run")
            elif not t:
                verdict = "NOT-TESTED"
                detail = (f"every test named {rid} was skipped" if skipped_only else f"no test named {rid} ran") \
                    + (f"; screen {r['screen']} renders and looks right" if driven else "")
            elif r.get("screen") and not driven and not booted:
                verdict = "NOT-DRIVEN"
                detail = f"test passed but {boot.get('head', 'the app')} was not driven: {boot.get('reason')}"
            else:
                verdict = "PASS"
                parts = [f"test {t['tests'][0][:60]}" if t and t.get("tests") else "test passed"]
                if driven:
                    parts.append(f"{r['screen']} renders and looks right @{'/'.join(str(w['width']) for w in scr['widths'])}")
                if "mockup-parity" in ran:
                    parts.append("matches its mockup")
                if "perf" in ran:
                    parts.append("within its speed budget")
                detail = "; ".join(parts)

        status = STATUS.get(verdict, prior)
        pct = r.get("pct")
        if verdict == "PASS":
            pct = 100
        elif verdict in ("RENDER-FAIL", "ASSET-FAIL", "VISUAL-FAIL", "MOCKUP-FAIL", "PERF-FAIL"):
            pct = min(pct if pct is not None else 75, 75)
        gate = FAILING.get(verdict)
        marks = {"FAIL": "⚠ acceptance", "BUILD-FAIL": "⚠ build", "RENDER-FAIL": "⚠ render", "ASSET-FAIL": "⚠ assets",
                 "VISUAL-FAIL": "⚠ visual", "MOCKUP-FAIL": "⚠ mockup-parity", "PERF-FAIL": "⚠ perf",
                 "NOT-TESTED": "not verified", "NOT-OBSERVABLE": "not observable", "NOT-DRIVEN": "not verified", "PASS": "PASS"}
        remark = f"{today} verify: {marks[verdict]} — {detail}"
        if evidence:
            remark += f" ({evidence})"
        if notes:
            remark += "; " + "; ".join(notes[:2])
        remark = words(remark.replace("|", "/"), 60)
        emit = verdict == "PASS" or gate is not None
        row = {"id": rid, "class": r["class"], "verdict": verdict, "gate": gate, "gates_run": ran, "failure_class": cls if gate else None,
               "prior_verdict": prior or None, "status": status, "pct": pct, "remark": remark, "screen": r.get("screen"),
               "emit_gate": emit, "title": r.get("title", "")}
        rows_out.append(row)
        ledger_rows[rid] = verdict
        table.append((rid, verdict, gate or "-", status, detail[:70]))

    checks = []
    for c in ("build", "acceptance", "render", "assets", "visual", "mockup-parity", "perf"):
        if any(c in x["gates_run"] for x in rows_out):
            checks.append(c)
    ledger = {"date": today, "app": app, "scope": lst.get("scope", "all"), "booted": boot_text, "gates": checks,
              "evidence": d, "run_id": started, "rows": ledger_rows}
    os.makedirs("docs", exist_ok=True)
    with open(os.path.join("docs", ".last-verify.json"), "w", encoding="utf-8") as f:
        json.dump(ledger, f, indent=1)
    with open(os.path.join(d, "verdicts.json"), "w", encoding="utf-8") as f:
        json.dump({"app": app, "scope": lst.get("scope", "all"), "date": today, "started": started, "booted": boot_text,
                   "build_result": "fail" if build_failed else ("pass" if booted else "not-run"), "checks": checks,
                   "checklist": lst.get("checklist"), "rows": rows_out}, f, indent=1)

    applied = 0
    if apply:
        cl = lst.get("checklist")
        text = open(cl, encoding="utf-8").read()
        by_id = {x["id"]: x for x in rows_out}
        out = []
        for line in text.splitlines(keepends=True):
            m = re.match(r"^(\s*\|\s*`?)(REQ-[A-Z]+-\d+)(`?\s*\|)", line)
            if m and m.group(2) in by_id:
                c = line.rstrip("\r\n").strip().strip("|").split("|")
                if len(c) >= 6:
                    x = by_id[m.group(2)]
                    c[2] = f" {x['status']} "
                    c[3] = f" {x['pct'] if x['pct'] is not None else ''}{'%' if x['pct'] is not None and '%' in c[3] else ''} "
                    c[4] = f" {x['remark']} "
                    nl = "\r\n" if line.endswith("\r\n") else "\n"
                    line = "|" + "|".join(c) + "|" + nl
                    applied += 1
            out.append(line)
        with open(cl, "w", encoding="utf-8") as f:
            f.write("".join(out))

    counts = {}
    for x in rows_out:
        counts[x["verdict"]] = counts.get(x["verdict"], 0) + 1
    print(f"# tf-verify-verdict — {app} — scope {lst.get('scope')} — booted: {boot_text}")
    print(f"Checks that ran: {', '.join(checks) or 'none'}. Rows: " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())))
    print()
    print("| ID | Verdict | First failing check | Status | Detail |")
    print("|---|---|---|---|---|")
    for t in table:
        print("| " + " | ".join(str(x).replace("|", "/") for x in t) + " |")
    print()
    print(f"Ledger: docs/.last-verify.json ({len(ledger_rows)} rows). Verdicts: {os.path.join(d, 'verdicts.json')}."
          + (f" Checklist: {applied} row(s) rewritten in {lst.get('checklist')}." if apply else " Checklist untouched (no --apply)."))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
