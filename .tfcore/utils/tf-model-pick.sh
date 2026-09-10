#!/usr/bin/env bash
# tf-model-pick.sh — which model should this tier run on RIGHT NOW, and how is it paid for.
#
# Two questions the framework could not answer before 2026-09-10, both found by the owner
# (MISS-TechieFlow-20260910-01 and -02):
#
#   1. The tier model's usage limit is reached. What now?  ->  `pick` walks the tier's
#      `fallbacks:` chain and returns the first model that is not on cooldown. tf-goal.sh puts
#      the limited model on cooldown until its stated reset; tf-routing-bind.sh asks the same
#      question when it writes the harness bindings, so the sub-agents move with the main agent.
#
#   2. What does a cost number from this model MEAN?  ->  `billing` says whether the model is
#      paid for by a flat-fee subscription (marginal dollars are zero, count tokens), by a
#      metered API key (the dollars are real money), or by nothing at all because it runs on
#      this machine. tf-emit.sh stamps the answer on every run record so a report can never sum
#      a subscription's zero into a money figure.
#
# USAGE
#   tf-model-pick.sh pick <tier> [harness]        -> the model id to use now ("inherit" if none)
#   tf-model-pick.sh chain <tier> [harness]       -> the whole ordered chain, one per line,
#                                                    each marked ok | cooldown until <time>
#   tf-model-pick.sh cooldown <harness> <model> <until> ["<why>"]
#                                                 -> park a model. <until> is an epoch, or +<n>
#                                                    minutes, or "probe" for the no-reset-time
#                                                    case (parked for TF_MODEL_PROBE_MIN, 60m).
#   tf-model-pick.sh clear [harness] [model]      -> unpark; no arguments clears everything
#   tf-model-pick.sh status                       -> what every tier resolves to, and why
#   tf-model-pick.sh billing <model> [harness]    -> mode<TAB>source<TAB>detail
#   tf-model-pick.sh rate <model> [harness]       -> input<TAB>output<TAB>cache_read<TAB>cache_write
#                                                    <TAB>source, in US$ per million tokens; exit 1
#                                                    with no output when nothing prices the model
#   tf-model-pick.sh was-limited <harness> <model> <epoch>
#                                                 -> exit 0 if that model was on cooldown then
#
# WHERE THE COOLDOWN LIVES. Inside the project, at `.tfcore/.session/model-cooldown.json`, because
# that is where TechieFlow itself lives: it is installed per project through npm/npx and never at
# machine level, and the owner has to be able to change it for one project without touching
# another (owner, 2026-09-10). `cooldown_file:` in routing.yaml moves it — an absolute path, or a
# path relative to the project root — and TF_MODEL_HEALTH_FILE overrides both for a single run.
#
# The cost of keeping it per project, said plainly: a usage limit belongs to an account, so two
# projects each discover the same limit for themselves, one wasted cycle apiece. Point them at one
# shared `cooldown_file:` if you would rather they learned it from each other.
#
# Expired entries are kept for 30 days so tf-emit.sh can answer "was this run a fallback?" after
# the fact, then pruned.
#
# Fail-soft everywhere: an unreadable file, a missing catalog, a provider nobody recognises — the
# answer degrades to the tier model and to billing mode "unknown". Routing is declared and
# observed, never enforced; this script keeps that property.

set +e
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(bash "$SELF_DIR/tf-harness.sh" root)"
command -v python3 >/dev/null 2>&1 || { echo "tf-model-pick: python3 required" >&2; exit 0; }

TF_MP_ROOT="$ROOT" python3 - "$@" <<'PY'
import json, os, sys, time, datetime

root = os.environ.get("TF_MP_ROOT") or os.getcwd()
argv = sys.argv[1:]
cmd = argv[0] if argv else "status"

KEEP_DAYS = 30
PROBE_MIN = int(os.environ.get("TF_MODEL_PROBE_MIN") or 60)
LOCAL_PROVIDERS = ("lmstudio", "ollama", "llamacpp", "llama-cpp", "vllm", "localhost", "local")
# A flat monthly fee whose usage is metered IN DOLLARS against a per-model allowance. OpenCode Go
# is $10/month with a $15–$60 monthly limit per model and 5-hour / weekly / monthly thresholds
# (https://opencode.ai/docs/go), so the dollars it reports are ALLOWANCE CONSUMED, not an invoice
# — and they are the very numbers that produce the limit the fallback chain exists for. An API
# key alone cannot tell you this; the provider name can, and `billing:` overrides it either way.
PLAN_PROVIDERS = ("opencode-go",)


def die(msg, code=2):
    sys.stderr.write("tf-model-pick: %s\n" % msg)
    raise SystemExit(code)


def now():
    return int(time.time())


def iso(ep):
    try:
        return datetime.datetime.fromtimestamp(
            int(ep), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return str(ep)


# --- routing.yaml (the same flat two-space format every other reader uses) --
def routing():
    cfg = {"enabled": False, "tiers": {}, "fallbacks": {}, "billing": {}, "phases": {},
           "cooldown_file": ""}
    sect = tier = None
    try:
        for line in open(os.path.join(root, ".tfcore", "routing.yaml"), encoding="utf-8"):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not line.startswith(" "):
                key, _, val = line.partition(":")
                sect, tier = key.strip(), None
                if sect == "enabled":
                    cfg["enabled"] = val.strip() == "true"
                elif sect == "cooldown_file":
                    cfg["cooldown_file"] = val.strip()
            elif sect in ("tiers", "fallbacks"):
                if line.rstrip().endswith(":") and not line.startswith("    "):
                    tier = line.strip()[:-1]
                    cfg[sect].setdefault(tier, {})
                elif tier and line.startswith("    "):
                    k, _, v = line.strip().partition(":")
                    cfg[sect][tier][k.strip()] = v.strip()
            elif sect in ("billing", "phases"):
                k, _, v = line.strip().partition(":")
                cfg[sect][k.strip()] = v.strip()
    except Exception:
        pass
    return cfg


CFG = routing()


def health_file():
    """Project first: TechieFlow is installed per project, so its state lives per project too."""
    env = os.environ.get("TF_MODEL_HEALTH_FILE")
    if env:
        return env
    declared = CFG.get("cooldown_file") or ""
    if declared:
        return declared if os.path.isabs(declared) else os.path.join(root, declared)
    return os.path.join(root, ".tfcore", ".session", "model-cooldown.json")


HEALTH = health_file()


def hkey(harness):
    """routing.yaml writes the harness column as claude|opencode; callers may say claude-code."""
    return "opencode" if str(harness).startswith("opencode") else "claude"


def norm(model, harness):
    """The key two names for the same model share.

    routing.yaml writes Claude models as the aliases a person types — opus, sonnet, haiku — while
    a transcript reports the full id it resolved to, `claude-sonnet-5`. Parking one and looking up
    the other would silently never match, so the family word is the key on Claude. OpenCode ids
    are already exact and are left alone."""
    m = (model or "").strip().lower()
    if hkey(harness) != "claude":
        return m
    for fam in ("opus", "sonnet", "haiku", "fable"):
        if fam in m:
            return fam
    return m


def chain_for(tier, harness):
    k = hkey(harness)
    out = []
    first = (CFG["tiers"].get(tier) or {}).get(k)
    if first:
        out.append(first)
    for m in (CFG["fallbacks"].get(tier) or {}).get(k, "").split(","):
        m = m.strip()
        if m and m not in out:
            out.append(m)
    return out


# --- the cooldown file -----------------------------------------------------
def load():
    try:
        with open(HEALTH, encoding="utf-8") as fh:
            d = json.load(fh)
        if isinstance(d, dict) and isinstance(d.get("cooldown"), list):
            return d
    except Exception:
        pass
    return {"cooldown": []}


def save(d):
    cut = now() - KEEP_DAYS * 86400
    d["cooldown"] = [e for e in d["cooldown"] if int(e.get("until_epoch") or 0) > cut]
    try:
        os.makedirs(os.path.dirname(HEALTH), exist_ok=True)
        tmp = HEALTH + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(d, fh, indent=1)
        os.replace(tmp, HEALTH)
        return True
    except Exception as e:
        sys.stderr.write("tf-model-pick: could not write %s (%s) — cooldown not recorded\n" % (HEALTH, e))
        return False


def parked(d, harness, model, at=None):
    """The live cooldown entry for this model at time `at`, or None."""
    at = now() if at is None else int(at)
    k = hkey(harness)
    want = norm(model, harness)
    for e in d["cooldown"]:
        if hkey(e.get("harness")) != k or norm(e.get("model"), e.get("harness")) != want:
            continue
        if int(e.get("since_epoch") or 0) <= at < int(e.get("until_epoch") or 0):
            return e
    return None


# --- billing mode ----------------------------------------------------------
def opencode_auth():
    p = os.environ.get("OPENCODE_AUTH") or os.path.join(
        os.path.expanduser("~"), ".local", "share", "opencode", "auth.json")
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def opencode_catalog():
    p = os.environ.get("OPENCODE_MODELS") or os.path.join(
        os.path.expanduser("~"), ".cache", "opencode", "models.json")
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def billing(model, harness):
    """-> (mode, source, detail). Mode is subscription | metered | local | unknown."""
    if hkey(harness) == "claude":
        declared = (CFG["billing"].get("claude") or "subscription").strip()
        if declared == "auto":
            if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN"):
                return ("metered", "env", "ANTHROPIC_API_KEY is set")
            return ("subscription", "auto", "no API key in the environment")
        if declared in ("subscription", "metered", "local"):
            return (declared, "routing.yaml", "billing.claude")
        return ("unknown", "routing.yaml", "billing.claude is %r" % declared)

    declared = (CFG["billing"].get("opencode") or "auto").strip()
    if declared in ("subscription", "metered", "local"):
        return (declared, "routing.yaml", "billing.opencode")
    provider = (model or "").split("/")[0]
    if not provider:
        return ("unknown", "none", "no model id")
    # A named provider in `billing:` beats every guess below. This is the escape hatch for a
    # local runtime called something the framework has never heard of, and for a key whose
    # billing the owner knows and OpenCode's auth file does not say.
    override = (CFG["billing"].get(provider) or "").strip()
    if override in ("subscription", "plan", "metered", "local"):
        return (override, "routing.yaml", "billing.%s" % provider)
    if provider in PLAN_PROVIDERS:
        return ("plan", "known-plan", "%s is a monthly plan with a per-model allowance" % provider)
    auth = opencode_auth().get(provider)
    if isinstance(auth, dict):
        t = (auth.get("type") or "").lower()
        if t == "oauth":
            return ("subscription", "opencode-auth", "%s signed in with OAuth" % provider)
        if t in ("api", "apikey", "api_key", "wellknown"):
            return ("metered", "opencode-auth", "%s uses an API key" % provider)
        return ("unknown", "opencode-auth", "%s auth type %r" % (provider, t))
    if provider.lower().startswith(LOCAL_PROVIDERS):
        return ("local", "provider-name", "%s runs on this machine" % provider)
    cat = opencode_catalog().get(provider)
    if isinstance(cat, dict):
        # In the catalog but not signed in: it is a hosted, billable provider this machine has
        # simply not authenticated. Saying "metered" would invent a bill; say so instead.
        return ("unknown", "models.dev", "%s is a hosted provider with no credential here" % provider)
    return ("unknown", "none", "provider %s is in neither auth.json nor the catalog" % provider)


# --- the rate card ---------------------------------------------------------
# What a model would cost at list price, per million tokens. This is a PRICE LIST, not a bill: it
# is what makes a subscription run comparable with a metered one (owner, 2026-09-10), and it is
# kept in its own field so that nothing ever overwrites a figure a provider actually measured.
#
# Two sources, project first:
#   .tfcore/rate-card.json   {"<model id>": {"input":5,"output":25,"cache_read":0.5,"cache_write":6.25}}
#                            for a negotiated rate, or a model the catalog has never heard of.
#   models.dev              the catalog OpenCode already keeps at ~/.cache/opencode/models.json.
#
# Two simplifications, stated rather than hidden: the BASE rate is used, so a provider's
# long-context surcharge (`context_over_200k`) is not applied — nothing records per-message
# context length, and guessing it would be worse than the small understatement; and a rate the
# catalog does not carry produces no number at all rather than a zero.
def project_rate_card():
    try:
        with open(os.path.join(root, ".tfcore", "rate-card.json"), encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def rate(model, harness):
    """-> (input, output, cache_read, cache_write, source) per 1M tokens, or None."""
    m = (model or "").strip()
    if not m or m.startswith("<"):        # "<synthetic>" and friends are not models
        return None
    own = project_rate_card()
    for key in (m, m.split("/")[-1]):
        r = own.get(key)
        if isinstance(r, dict):
            return (float(r.get("input") or 0), float(r.get("output") or 0),
                    float(r.get("cache_read") or 0), float(r.get("cache_write") or 0),
                    ".tfcore/rate-card.json")
    cat = opencode_catalog()
    provider, _, bare = m.partition("/")
    entries = []
    if bare and provider in cat:
        entries = [(provider, cat[provider].get("models", {}).get(bare))]
    else:
        # A bare id — every Claude Code model is one, and an older OpenCode record can be. Look
        # in anthropic first, because that is what a Claude transcript reports; then in the
        # providers this machine is actually signed in to, because those are the ones that could
        # have served it; then everything else alphabetically, so the same id always prices the
        # same way. Two providers list `gpt-5.6-sol` at different rates, and picking the one you
        # are signed in to is the difference between $4 and $5 per million input tokens.
        signed_in = [k for k in sorted(opencode_auth()) if k in cat and k != "anthropic"]
        rest = sorted(k for k in cat if k != "anthropic" and k not in signed_in)
        order = (["anthropic"] if "anthropic" in cat else []) + signed_in + rest
        entries = [(p, cat[p].get("models", {}).get(m)) for p in order]
    for provider, entry in entries:
        if not isinstance(entry, dict):
            continue
        c = entry.get("cost")
        if not isinstance(c, dict):
            continue
        return (float(c.get("input") or 0), float(c.get("output") or 0),
                float(c.get("cache_read") or 0), float(c.get("cache_write") or 0),
                "models.dev/" + provider)
    return None


# --- commands --------------------------------------------------------------
if cmd == "pick":
    if len(argv) < 2:
        die("usage: tf-model-pick.sh pick <tier> [harness]")
    tier, harness = argv[1], (argv[2] if len(argv) > 2 else "claude")
    d = load()
    for m in chain_for(tier, harness):
        if not parked(d, harness, m):
            print(m)
            raise SystemExit(0)
    print("inherit")   # every model in the chain is limited — the caller waits
    raise SystemExit(0)

if cmd == "chain":
    if len(argv) < 2:
        die("usage: tf-model-pick.sh chain <tier> [harness]")
    tier, harness = argv[1], (argv[2] if len(argv) > 2 else "claude")
    d = load()
    ch = chain_for(tier, harness)
    if not ch:
        print("(no model declared for tier %s on %s)" % (tier, harness))
        raise SystemExit(0)
    for i, m in enumerate(ch):
        e = parked(d, harness, m)
        mark = "cooldown until %s (%s)" % (iso(e["until_epoch"]), e.get("why") or "limited") if e else "ok"
        print("%d\t%s\t%s%s" % (i + 1, m, mark, "" if i else "   <- tier model"))
    raise SystemExit(0)

if cmd == "cooldown":
    if len(argv) < 4:
        die("usage: tf-model-pick.sh cooldown <harness> <model> <epoch|+minutes|probe> [\"why\"]")
    harness, model, until = argv[1], argv[2], argv[3]
    why = argv[4] if len(argv) > 4 else "usage limit"
    if until == "probe":
        until_ep = now() + PROBE_MIN * 60
    elif until.startswith("+"):
        until_ep = now() + int(float(until[1:])) * 60
    else:
        try:
            until_ep = int(float(until))
        except Exception:
            die("<until> must be an epoch, +<minutes> or probe")
    if until_ep <= now():
        until_ep = now() + 60
    d = load()
    d["cooldown"] = [e for e in d["cooldown"]
                     if not (hkey(e.get("harness")) == hkey(harness)
                             and norm(e.get("model"), e.get("harness")) == norm(model, harness)
                             and int(e.get("until_epoch") or 0) > now())]
    d["cooldown"].append({"harness": hkey(harness), "model": model,
                          "since_epoch": now(), "since": iso(now()),
                          "until_epoch": until_ep, "until": iso(until_ep),
                          "why": why, "app": os.path.basename(root)})
    save(d)
    print("cooldown: %s/%s until %s (%s)" % (hkey(harness), model, iso(until_ep), why))
    raise SystemExit(0)

if cmd == "clear":
    d = load()
    before = len(d["cooldown"])
    if len(argv) == 1:
        d["cooldown"] = []
    else:
        harness = argv[1]
        model = argv[2] if len(argv) > 2 else None
        d["cooldown"] = [e for e in d["cooldown"]
                         if not (hkey(e.get("harness")) == hkey(harness)
                                 and (model is None
                                      or norm(e.get("model"), e.get("harness")) == norm(model, harness))
                                 and int(e.get("until_epoch") or 0) > now())]
    save(d)
    print("cleared %d cooldown entr(y/ies)" % (before - len(d["cooldown"])))
    raise SystemExit(0)

if cmd == "billing":
    if len(argv) < 2:
        die("usage: tf-model-pick.sh billing <model> [harness]")
    model = argv[1]
    harness = argv[2] if len(argv) > 2 else ("opencode" if "/" in model else "claude")
    print("%s\t%s\t%s" % billing(model, harness))
    raise SystemExit(0)

if cmd == "rate":
    if len(argv) < 2:
        die("usage: tf-model-pick.sh rate <model> [harness]")
    model = argv[1]
    harness = argv[2] if len(argv) > 2 else ("opencode" if "/" in model else "claude")
    r = rate(model, harness)
    if not r:
        raise SystemExit(1)
    print("%g\t%g\t%g\t%g\t%s" % r)
    raise SystemExit(0)

if cmd == "was-limited":
    if len(argv) < 4:
        die("usage: tf-model-pick.sh was-limited <harness> <model> <epoch>")
    raise SystemExit(0 if parked(load(), argv[1], argv[2], argv[3]) else 1)

if cmd == "status":
    d = load()
    live = [e for e in d["cooldown"] if int(e.get("until_epoch") or 0) > now()]
    print("Cooldown file: %s" % HEALTH)
    print("Routing: %s" % ("ON" if CFG["enabled"] else "OFF"))
    print()
    for harness in ("claude", "opencode"):
        print("%s:" % harness)
        for tier in ("frontier", "standard", "economy"):
            ch = chain_for(tier, harness)
            if not ch:
                continue
            use = next((m for m in ch if not parked(d, harness, m)), None)
            mode = billing(use, harness)[0] if use else "-"
            skipped = [m for m in ch if parked(d, harness, m)]
            note = "  (skipping %s)" % ", ".join(skipped) if skipped else ""
            print("  %-9s -> %-34s [%s]%s" % (tier, use or "inherit (all limited — wait)", mode, note))
        print()
    if live:
        print("On cooldown now:")
        for e in sorted(live, key=lambda x: x["until_epoch"]):
            print("  %-9s %-34s until %s  (%s, from %s)"
                  % (e.get("harness"), e.get("model"), e.get("until"), e.get("why"), e.get("app")))
    else:
        print("On cooldown now: nothing.")
    print()
    print("Park a model by hand:  bash .tfcore/utils/tf-model-pick.sh cooldown opencode <model> +180 \"monthly limit\"")
    print("Unpark:                bash .tfcore/utils/tf-model-pick.sh clear opencode <model>")
    raise SystemExit(0)

die("unknown command %r — run with no arguments for the usage block" % cmd)
PY
rc=$?
if [[ $rc -eq 2 ]]; then sed -n '17,32p' "$0" | sed 's/^# \{0,1\}//' >&2; fi
exit $rc
