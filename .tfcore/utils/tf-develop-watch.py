#!/usr/bin/env python3
"""tf-develop-watch.py — what a *develop-end-to-end run is doing, seen from any window (TF-062, 2026-11-19).

    python3 tf-develop-watch.py status <app-dir>            *develop-status: exit 0 running, 1 not running, 2 no run here
    python3 tf-develop-watch.py follow <app-dir> [--next]   the launching window's follow; ends when the run ends
    python3 tf-develop-watch.py stop <app-dir>              --stop: the supervisor and every process the run started
    python3 tf-develop-watch.py session-model <harness>     the launching session's model id, or nothing
    python3 tf-develop-watch.py progress <app-dir> <step> <supervisor-pid>    run by tf-develop.sh inside a step
    python3 tf-develop-watch.py cycles <app-dir> <step> <model>               tf-goal's stderr in, its lines logged
    python3 tf-develop-watch.py tokens <app-dir> <step> <since> <attempt>     a finished attempt's tokens, saved
    python3 tf-develop-watch.py backfill <app-dir>                            tokens of a stopped attempt, before a resume
    python3 tf-develop-watch.py mode <app-dir>                                develop mode: on only inside the run

tf-develop.sh calls every one of these; the owner and the agents call tf-develop.sh. Times shown to the
owner are local (HH:MM); develop.log keeps UTC, as it always has.

ALIVE IS CHECKED, NEVER ASSUMED. develop.json holds the supervisor's pid, the host it runs on and the run's
id. A run is "running" only when that pid is alive on this host and still carries the run's id; otherwise it
reads "stopped". The AstroLyfe run of 19 Nov had none of this: a window could not tell a live run from a dead one.

EVERY PROCESS THE RUN STARTED carries TF_DEVELOP_RUN=<run id> in its environment, which tf-develop.sh
exports and every child inherits, including a web server the agent starts in a session of its own (the
AstroLyfe run left one listening on port 5201 after it stopped). `stop` finds them by that mark (Linux:
/proc; elsewhere `ps -E`), sends TERM, then KILL to any left after ten seconds. A database container is a
service, not a process of the run: it is kept, so --resume finds its data.

follow --next returns at the next step start or end, the next verify result, a heartbeat, or the run's end:
for a harness whose background commands report once, when they exit (OpenCode). Without --next it prints
every event and exits only when the run ends: for a harness that streams a command's lines (Claude Code's
Monitor). Python 3 standard library only.
"""
import calendar, glob, json, os, re, signal, socket, sqlite3, subprocess, sys, time

SESSION = ".tfcore/.session"
TITLES = {"day1": "Day 1, stage 1", "day1-2": "Day 1, stage 2", "build": "build and verify", "handoff": "handoff"}
BUILT = {"implemented", "partial", "verified", "fail", "needs re-verify"}
STEP_EVENT = re.compile(r" (started|skipped|done|blocked|failed|stopped|UAT-ready)\b| run started")


def p(root, *a): return os.path.join(root, *a)
def load(path, default=None):
    try: return json.load(open(path, encoding="utf-8"))
    except Exception: return default
def utc(s):
    try: return calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ"))
    except Exception: return None
def hhmm(epoch):
    if epoch is None: return "?"
    lt = time.localtime(epoch)
    return time.strftime("%H:%M" if time.strftime("%Y%m%d", lt) == time.strftime("%Y%m%d") else "%d %b %H:%M", lt)
def dur(s):
    s = int(max(0, s or 0)); return f"{s // 3600} h {s % 3600 // 60:02d} min" if s >= 3600 else f"{s // 60} min"
def stamp(): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
def log(root, text):
    with open(p(root, SESSION, "develop.log"), "a", encoding="utf-8") as f: f.write(f"[{stamp()}] tf-develop: {text}\n")


def step_title(name, app):
    base, _, n = name.partition("-p")
    if base == "day1" and n == "": return TITLES["day1"]
    if name == "day1-2": return TITLES["day1-2"]
    return f"phase {n or 1}: {TITLES.get(base, base)}"


def rows(root, app, step):
    """(total, built, verified, {status: n}) of the step's checklist, or None"""
    n = step.partition("-p")[2] or "1"
    path = p(root, "docs", f"{app}-Checklist.md" if n == "1" else f"{app}-P{n}-Checklist.md")
    try: text = open(path, encoding="utf-8", errors="replace").read()
    except OSError: return None
    text = text.split("## Requirements Status", 1)[-1].split("\n## ", 1)[0]
    counts = {}
    for m in re.finditer(r"^\|\s*REQ-[A-Z0-9-]+\s*\|[^|\n]*\|\s*([^|\n]*?)\s*\|", text, re.M):
        counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    total = sum(counts.values())
    if not total: return None
    built = sum(v for k, v in counts.items() if k.lower() in BUILT)
    return total, built, counts.get("Verified", 0), counts


def rows_line(r):
    if not r: return "no checklist rows yet"
    total, built, verified, counts = r
    rest = ", ".join(f"{v} {k}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1]) if k != "Verified")
    return f"{built} of {total} rows built, {verified} verified" + (f" ({rest})" if rest else "")


def proc_env(pid):
    try: return open(f"/proc/{pid}/environ", "rb").read().decode("utf-8", "replace").split("\0")
    except OSError: return None


def marked(run_id):
    """pids carrying TF_DEVELOP_RUN=<run_id>, never this process or its parents"""
    mark, skip, out = f"TF_DEVELOP_RUN={run_id}", set(), []
    pid = os.getpid()
    while pid > 1:
        skip.add(pid)
        try: pid = int(open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[1])
        except Exception: pid = os.getppid() if pid == os.getpid() else 1
    if os.path.isdir("/proc/self"):
        for d in os.listdir("/proc"):
            if d.isdigit() and int(d) not in skip and mark in (proc_env(d) or []): out.append(int(d))
        return out
    try: listing = subprocess.run(["ps", "-axwwE", "-o", "pid=,command="], capture_output=True, text=True).stdout
    except Exception: return out
    for line in listing.splitlines():
        f = line.split(None, 1)
        if len(f) == 2 and f[0].isdigit() and int(f[0]) not in skip and re.search(re.escape(mark) + r"(\s|$)", f[1]): out.append(int(f[0]))
    return out


def alive(st):
    """True, False, or None when the run is on another machine; and the words for it"""
    pid, host = st.get("pid"), st.get("host")
    if not pid: return False, "no process id recorded (the run started before tf-develop.sh recorded one), so it cannot be running under this supervisor"
    if host and host != socket.gethostname(): return None, f"pid {pid} on host {host}, not this machine: not checked"
    try: os.kill(int(pid), 0)
    except (OSError, ValueError): return False, f"pid {pid} on host {host}: not running (checked {hhmm(time.time())})"
    env = proc_env(pid)
    try: cmd = open(f"/proc/{pid}/cmdline", "rb").read().decode("utf-8", "replace")
    except OSError: cmd = None
    if env is not None and f"TF_DEVELOP_RUN={st.get('run_id')}" not in env and "tf-develop.sh" not in (cmd or ""):
        return False, f"pid {pid} on host {host}: now another program, so the run is not running (checked {hhmm(time.time())})"
    return True, f"pid {pid} on host {host}: running (checked {hhmm(time.time())})"


def cycle_tokens(root, since, until=None):
    """tokens of the goal cycles written between <since> and <until> (epoch), from Claude Code's stream; None for OpenCode"""
    tot, seen = {"in": 0, "out": 0, "cache_read": 0, "cache_write": 0}, False
    for f in glob.glob(p(root, SESSION, "goal-cycle-*.out")):
        if os.path.getmtime(f) < since or (until is not None and os.path.getmtime(f) > until): continue
        tail, done = {}, False
        for line in open(f, encoding="utf-8", errors="replace"):
            if not line.startswith("{") or '"usage"' not in line: continue
            try: d = json.loads(line)
            except Exception: continue
            u = d.get("usage") if d.get("type") == "result" else (d.get("message") or {}).get("usage")
            if not isinstance(u, dict): continue
            seen = True
            if d.get("type") == "result":
                for k, src in (("in", "input_tokens"), ("out", "output_tokens"), ("cache_read", "cache_read_input_tokens"), ("cache_write", "cache_creation_input_tokens")):
                    tot[k] += int(u.get(src) or 0)
                tail = {}
            else: tail[(d.get("message") or {}).get("id")] = u   # a turn still running: its messages so far
        for u in tail.values():
            tot["out"] += int(u.get("output_tokens") or 0); tot["in"] += int(u.get("input_tokens") or 0)
            tot["cache_read"] += int(u.get("cache_read_input_tokens") or 0)
    return tot if seen else None


def cycle_model(root):
    fs = sorted(glob.glob(p(root, SESSION, "goal-cycle-*.out")), key=os.path.getmtime)
    for f in reversed(fs):
        m = re.findall(r'"model":"([^"<]+)"', open(f, encoding="utf-8", errors="replace").read(200000))
        if m: return m[-1]
    return ""


def last_activity(root):
    fs = glob.glob(p(root, SESSION, "goal-cycle-*.out")) + [p(root, SESSION, n) for n in ("goal.log", "develop.log")]
    ts = [os.path.getmtime(f) for f in fs if os.path.exists(f)]
    return max(ts) if ts else None


def state_of(root):
    st = load(p(root, SESSION, "develop.json"))
    if st: return st, False
    st = load(p(root, SESSION, "develop-done.json"))
    return (st, True) if st else (None, False)


def report_lines(root, app):
    try: text = open(p(root, "docs", f"{app}-Build-Report.md"), encoding="utf-8").read()
    except OSError: return []
    return [f"  {m.group(1)}: {m.group(2).strip()}" for m in re.finditer(r"^\| (Result|Built in|Harness and model|Tokens) \| (.*) \|$", text, re.M)]


def summary(root, quiet=False):
    """(lines, running) — the status block, or one line with --quiet"""
    st, finished = state_of(root)
    if not st: return [f"no develop run recorded in {root}"], None
    app = st.get("app", "?"); ph = st.get("phases") or []
    cur = ph[-1] if ph else {}
    ok, how = (False, "the run has ended") if finished else alive(st)
    status = cur.get("status") or "not started"
    if finished: state = "finished: ready for UAT"
    elif ok: state = "running"
    elif ok is None: state = "unknown (another machine)"
    elif st.get("stopped"): state = f"stopped by --stop during {st['stopped'].get('at')}"
    elif status in ("running", ""): state = "stopped: the supervisor is gone and the step was not finished"
    else: state = f"stopped: {cur.get('name')} {status}"
    step = cur.get("name") or "-"
    t0, s0 = utc(st.get("started", "")), utc(cur.get("started", ""))
    end = utc(cur.get("ended", "")) if not ok else None
    act = last_activity(root); r = rows(root, app, step) if step != "-" else None
    model = st.get("model") or (f"{cycle_model(root)} (not recorded; read from the goal cycles' output)" if cycle_model(root) else "not recorded")
    done_toks = load(p(root, SESSION, "develop-tokens.json"), {})
    att = str(cur.get("attempt", "1"))
    toks = None if quiet or not s0 else (cycle_tokens(root, 0) if ok else done_toks[step][att] if att in (done_toks.get(step) or {}) else cycle_tokens(root, s0 - 5))
    run_out = sum(int(v.get("out") or 0) for k, a in done_toks.items() for n, v in a.items() if (k, n) != (step, att)) + (toks or {}).get("out", 0)
    if quiet:
        return [f"{app}: {state} · {step} ({step_title(step, app)}) · {st.get('harness')} / {model} · {rows_line(r)} · "
                f"last activity {hhmm(act)}"], ok
    L = [f"{app} develop run — {state}",
         f"  process: {how}",
         f"  harness and model: {st.get('harness')}, {model}" + (f" ({st.get('model_from')})" if st.get("model_from") else ""),
         f"  step: {step} ({step_title(step, app)}), attempt {cur.get('attempt', 1)}, started {hhmm(s0)}"
         + (f", ended {hhmm(end)} ({status})" if end else f", running for {dur(time.time() - s0) if s0 else '?'}"),
         f"  elapsed: {dur((end or time.time()) - t0) if t0 else '?'} since the run started at {hhmm(t0)}",
         f"  last activity: {hhmm(act)}" + (f" ({dur(time.time() - act)} ago)" if act else ""),
         f"  rows: {rows_line(r)}",
         f"  tokens so far: " + (f"this step {toks['out']:,} out, {toks['in']:,} in, {toks['cache_read']:,} read from cache; " if toks else "")
         + f"the whole run {run_out:,} out (read from the goal cycles' own output)",
         f"  log: {SESSION}/develop.log · report: docs/{app}-Build-Report.md"]
    blocker = load(p(root, SESSION, "goal-done.json"), {})
    if not ok and not finished and status == "blocked" and blocker.get("summary"): L.append(f"  blocker: {blocker['summary']}")
    if not ok and not finished: L.append(f"  next: *develop-end-to-end {app} --resume (after the blocker, if any, is dealt with)")
    return L, ok


def follow(root, nxt):
    st, _ = state_of(root)
    if not st: print(f"no develop run recorded in {root}"); return 2
    beat = float(os.environ.get("TF_DEVELOP_HEARTBEAT_MIN", "15")) * 60
    tick = float(os.environ.get("TF_DEVELOP_FOLLOW_TICK", "2"))
    logf = p(root, SESSION, "develop.log"); curf = p(root, SESSION, "develop-follow.json")
    size = os.path.getsize(logf) if os.path.exists(logf) else 0
    cur = load(curf, {})   # where the last follow of this run stopped reading: a re-armed follow misses nothing
    if cur.get("run_id") and cur.get("run_id") == st.get("run_id") and 0 <= int(cur.get("pos", -1)) <= size: pos = int(cur["pos"])
    else:   # a first follow shows this run from its start
        pos, text = 0, open(logf, "rb").read() if size else b""
        i = text.rfind(b"tf-develop: run started:")
        if st.get("run_id") and i >= 0: pos = text.rfind(b"\n", 0, i) + 1
        elif not st.get("run_id"): pos = size
    print(summary(root, quiet=True)[0][0], flush=True)
    last = time.time()
    while True:
        lines = []
        if os.path.exists(logf):
            with open(logf, encoding="utf-8", errors="replace") as f:
                f.seek(pos); chunk = f.read(); pos = f.tell()
            lines = [l for l in chunk.splitlines() if l.strip()]
        for l in lines:
            m = re.match(r"\[(\S+)\] tf-develop: (.*)", l)
            print(f"{hhmm(utc(m.group(1)))} {m.group(2)}" if m else l, flush=True)
        if lines:
            last = time.time()
            try: json.dump({"run_id": st.get("run_id"), "pos": pos}, open(curf, "w"))
            except OSError: pass
        _, ok = summary(root, quiet=True)
        if ok is False:
            L, _ = summary(root)
            st, finished = state_of(root)
            print(f"the run has ended — {L[0].split(' — ', 1)[1]}", flush=True)
            for l in report_lines(root, st.get("app", "")): print(l)
            for l in L[1:]:
                if l.lstrip().startswith(("blocker:", "next:")): print(l)
            if finished: print(f"  next: UAT — docs/{st.get('app')}-UsageGuide.md lists the smoke checklist and the test users")
            return 0
        if nxt and any(STEP_EVENT.search(l) or " verify " in l for l in lines): return 0
        if time.time() - last >= beat:
            print(f"{hhmm(time.time())} still {summary(root, quiet=True)[0][0].split(': ', 1)[1]}", flush=True); last = time.time()
            if nxt: return 0
        time.sleep(tick)


def stop(root):
    path = p(root, SESSION, "develop.json"); st = load(path)
    if not st: print(f"no develop run to stop in {root}"); return 2
    ph = st.get("phases") or []; at = ph[-1]["name"] if ph else "before the first step"
    st["stopped"] = {"at": at, "time": stamp()}            # first, so a follow that sees the process go reads why
    json.dump(st, open(path, "w"), indent=1)
    pids = set(marked(st.get("run_id"))) if st.get("run_id") else set()
    ok, _ = alive(st)
    if ok: pids.add(int(st["pid"]))
    names = {}
    sup = int(st.get("pid") or 0)
    for pid in sorted(pids, key=lambda x: x != sup):   # the supervisor first, so it cannot record the goal's exit
        try: names[pid] = open(f"/proc/{pid}/comm").read().strip()
        except OSError: names[pid] = "?"
        try: os.kill(pid, signal.SIGTERM)
        except OSError: pass
    t = time.time()
    while time.time() - t < 10 and any(_up(x) for x in pids): time.sleep(0.5)
    killed = [x for x in pids if _up(x)]
    for pid in killed:
        try: os.kill(pid, signal.SIGKILL)
        except OSError: pass
    time.sleep(0.5)
    left = [x for x in pids if _up(x)]
    st = load(path) or st; ph = st.get("phases") or []
    if ph:
        if ph[-1].get("status") in ("running", "") or ph[-1].get("goal_exit") in ("130", "143"): ph[-1].update(status="stopped", ended=stamp(), goal_exit="stopped")
    st["stopped"] = {"at": at, "time": stamp(), "processes": len(pids)}
    json.dump(st, open(path, "w"), indent=1)
    g = p(root, SESSION, "goal.json"); gs = load(g)
    if gs is not None: gs.update(last_reason="stopped", ended=stamp()); json.dump(gs, open(g, "w"), indent=1)
    what = ", ".join(f"{names[x]} {x}" for x in sorted(pids)) or "none was running"
    log(root, f"stopped by --stop during {at}: {len(pids)} process(es) ended ({what})" + (f"; STILL RUNNING: {left}" if left else ""))
    print(f"{st.get('app')}: stopped during {at} — {len(pids)} process(es) ended ({what})" + (f"; still running: {left}" if left else ""))
    print(f"  continue it with: *develop-end-to-end {st.get('app')} --resume")
    return 1 if left else 0


def _up(pid):
    try: os.kill(pid, 0)
    except OSError: return False
    try: return open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError: return True


def session_model(harness):
    if harness == "claude" and os.environ.get("CLAUDE_CODE_SESSION_ID"):
        base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
        for f in glob.glob(p(base, "projects", "*", os.environ["CLAUDE_CODE_SESSION_ID"] + ".jsonl")):
            model = ""
            for line in open(f, encoding="utf-8", errors="replace"):
                if '"assistant"' not in line or '"model"' not in line: continue
                try: m = (json.loads(line).get("message") or {}).get("model")
                except Exception: continue
                if m and not m.startswith("<"): model = m
            if model: return model
    if harness == "opencode" and os.environ.get("OPENCODE_SESSION_ID"):
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        db, sid = p(base, "opencode", "opencode.db"), os.environ["OPENCODE_SESSION_ID"]
        try:
            c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            for table in ("session_message", "message"):
                try: got = c.execute(f"select data from {table} where session_id=? order by time_created desc", (sid,)).fetchall()
                except sqlite3.Error: continue
                for (data,) in got:
                    d = json.loads(data); m = d.get("model") if isinstance(d.get("model"), dict) else {}
                    prov, mid = m.get("providerID") or d.get("providerID"), m.get("id") or d.get("modelID")
                    if prov and mid: return f"{prov}/{mid}"
        except Exception: pass
    return ""


def progress(root, step, sup):
    """inside a step: each verify's result and each change in the rows, into develop.log, until the step ends"""
    st = load(p(root, SESSION, "develop.json"), {}); app = st.get("app", "")
    tick = float(os.environ.get("TF_DEVELOP_TICK", "20"))
    gates = p(root, "docs", "metrics", "gates.jsonl")
    pos = os.path.getsize(gates) if os.path.exists(gates) else 0
    runs, quiet, prev = {}, {}, rows_line(rows(root, app, step))
    ending = []
    signal.signal(signal.SIGTERM, lambda *_: ending.append(1))
    while True:
        new = []
        if os.path.exists(gates):
            with open(gates, encoding="utf-8", errors="replace") as f:
                f.seek(pos); new = f.read().splitlines(); pos = f.tell()
        for l in new:
            try: d = json.loads(l)
            except Exception: continue
            if d.get("kind", "gate") != "gate": continue
            r = runs.setdefault(d.get("run_id") or "?", {}); r[d.get("verdict")] = r.get(d.get("verdict"), 0) + 1
            quiet[d.get("run_id") or "?"] = 0
        for rid in list(runs):
            if quiet[rid] >= 1 or ending:
                v = runs.pop(rid); quiet.pop(rid)
                what = ", ".join(f"{n} {k}" for k, n in sorted(v.items(), key=lambda kv: -kv[1]))
                prev = rows_line(rows(root, app, step))
                log(root, f"{step} verify (started {hhmm(utc(rid))}) graded {sum(v.values())} rows: {what} — now {prev}")
            else: quiet[rid] += 1
        now = rows_line(rows(root, app, step))
        if now != prev: log(root, f"{step} rows: {now}"); prev = now
        if ending: return 0
        try: os.kill(sup, 0)
        except OSError: return 0
        for _ in range(int(tick * 2)):
            if ending: break
            time.sleep(0.5)


def cycles(root, step, model):
    """tf-goal's stderr, line by line: kept whole on stderr (develop.out), and into develop.log as the step's progress"""
    for line in sys.stdin:
        sys.stderr.write(line); sys.stderr.flush()
        m = re.match(r"\[\S+\] tf-goal: (.*)", line.rstrip("\n"))
        if not m: continue
        text = m.group(1)
        c = re.match(r"cycle (\d+) \((\w+)\)", text)
        if c: text = f"cycle {c.group(1)} started ({'first' if c.group(2) == 'first' else 'continuing the session'}, model {model or 'the harness default'})"
        elif text.startswith("agent stopped without the goal-done sentinel"):
            n = re.search(r"cycle (\d+)", text)
            text = f"cycle {n.group(1) if n else '?'} ended: the agent stopped before the goal was met — the next cycle starts in a moment"
        elif text.startswith("goal-done sentinel present"):
            o = re.search(r"outcome=(\w+)", text); s = re.search(r'"summary":"((?:[^"\\]|\\.)*)"', text)
            text = f"cycle ended: goal {o.group(1) if o else 'done'}" + (f" — {s.group(1)}" if s else "")
        log(root, f"{step} {text}")
    return 0


def tokens(root, step, since, attempt="1", until=None):
    """an attempt's tokens from its goal cycles' own output, kept per step and attempt for the Build Report.
    The run records count only the stretches a command recorded: AstroLyfe's build of 19 Nov showed 4,763
    tokens out in the report against 29,314 in its four cycles (MISS-TechieFlow-20261119-03)."""
    t = cycle_tokens(root, 0 if since == "all" else (utc(since) or 0) - 5, until)   # 5 s: a file on a Windows drive can read a second early
    if t is None: return 0
    f = p(root, SESSION, "develop-tokens.json"); d = load(f, {})
    d.setdefault(step, {})[str(attempt)] = t
    json.dump(d, open(f, "w"), indent=1)
    return 0


def clear_cycles(root):
    """at a step's start, after every earlier attempt's tokens are saved: the earlier cycle files move to
    cycles-prev/, so every goal-cycle file present belongs to this step and no clock is compared (a file's
    time on a Windows drive can read earlier than the Linux clock, and the step's first cycle went uncounted)"""
    prev = p(root, SESSION, "cycles-prev"); os.makedirs(prev, exist_ok=True)
    for f in glob.glob(p(prev, "goal-cycle-*.out")): os.remove(f)
    for f in glob.glob(p(root, SESSION, "goal-cycle-*.out")): os.replace(f, p(prev, os.path.basename(f)))
    return 0


def backfill(root):
    """before a resume or a report: an attempt that stopped without its tokens saved (a run from before this
    file, or a killed supervisor) gets them from its cycle files while they are still there; the resumed
    step's first cycle overwrites goal-cycle-1.out"""
    st, _ = state_of(root)
    have = load(p(root, SESSION, "develop-tokens.json"), {})
    for x in (st or {}).get("phases") or []:
        if x.get("status") in ("running", "skipped") or not x.get("started") or str(x.get("attempt", "1")) in (have.get(x["name"]) or {}): continue
        end = utc(x.get("ended") or "")
        tokens(root, x["name"], x["started"], x.get("attempt", "1"), end + 120 if end else None)
    return 0


def mode(root):
    """develop mode is on only inside the run: a process carrying the run's own mark. A develop.json left by a
    stopped run turned every new session in the app to develop mode until --resume (MISS-TechieFlow-20261119-04)."""
    st = load(p(root, SESSION, "develop.json"), {})
    on = bool(st.get("run_id")) and st.get("run_id") == os.environ.get("TF_DEVELOP_RUN")
    print("on" if on else "off")
    return 0 if on else 1


def main(a):
    if len(a) < 2: print(__doc__); return 2
    op, root = a[0], a[1]
    if op == "session-model": print(session_model(root)); return 0
    root = os.path.abspath(root)
    if op == "status":
        L, ok = summary(root); print("\n".join(L)); return 2 if L[0].startswith("no develop") else (0 if ok else 1)
    if op == "follow": return follow(root, "--next" in a)
    if op == "stop": return stop(root)
    if op == "progress": return progress(root, a[2], int(a[3]))
    if op == "cycles": return cycles(root, a[2], a[3] if len(a) > 3 else "")
    if op == "tokens": return tokens(root, a[2], a[3], a[4] if len(a) > 4 else "1")
    if op == "backfill": return backfill(root)
    if op == "clear-cycles": return clear_cycles(root)
    if op == "mode": return mode(root)
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
