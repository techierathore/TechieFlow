#!/usr/bin/env bash
# tf-routing-bind.sh — emit (or remove) the harness bindings declared by
# .tfcore/routing.yaml (docs/Adapter-Design.md §5.3/§5.4; DECISIONS.md 2026-08-20).
#
# WHAT IT GENERATES when routing.yaml says `enabled: true`:
#   Claude Code (§5.3):
#     .claude/commands/tf/<phase>.md    — routed wrapper commands (/tf:<phase>),
#                                         frontmatter model:+effort: from the tier
#     .claude/agents/{tf-builder,tf-test-writer,tf-explorer,trblazeui,techierag}.md
#                                       — tier-bound subagents
#   OpenCode (§5.4):
#     .opencode/opencode.json           — pure-JSON binding file loaded ALONGSIDE
#                                         .opencode/opencode.jsonc; deep-merges
#                                         model onto the existing agents/commands
#                                         (verified against OpenCode 1.18.18:
#                                         model-only agent entries merge, command
#                                         entries must be complete → they carry
#                                         template+description+model)
#     skills remain thin loaders and do not claim to switch the main thread.
#
# When `enabled: false` (the default) every generated artifact is REMOVED, using
# the manifest .tfcore/.session/routing-bind.manifest (gitignored) — the script
# never deletes anything it did not generate. Run it after editing routing.yaml.
# update-framework.sh runs it automatically in each app.
#
# Fail-soft: exits 0 unless the target is not a TechieFlow repo. Routing is
# declared and OBSERVED (runs.jsonl model/tier/routed) — never enforced.

set +e

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(bash "$SELF_DIR/tf-harness.sh" root)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"
[[ -n "$ROOT" && -d "$ROOT/.tfcore" ]] || { echo "tf-routing-bind: not a TechieFlow repo: ${ROOT:-<none>}" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "tf-routing-bind: python3 required" >&2; exit 0; }

python3 - "$ROOT" <<'PY'
import json, os, re, sys

root = sys.argv[1]
ryaml = os.path.join(root, ".tfcore", "routing.yaml")
manifest_path = os.path.join(root, ".tfcore", ".session", "routing-bind.manifest")

# --- migration: a project's routing.yaml is never overwritten -------------
# `update-framework.sh` leaves a project's own routing.yaml alone on purpose, so a block added to
# the framework default after the project was scaffolded would never reach it. Both delivery
# routes run THIS script, so the migration lives here: a missing block is APPENDED, with the
# Claude aliases filled in (opus/sonnet/haiku exist on every account) and the OpenCode lines left
# empty, because guessing a model id for a provider this machine may not have would produce a
# fallback that fails at the moment it is needed. Existing lines are never touched, and a file
# that already has the block is left exactly as it is.
MIGRATIONS = [
    ("fallbacks:", """
# Which models this tier drops to while its own is limited, in order, comma-separated.
# Added by tf-routing-bind.sh. The opencode lines are OpenCode Go models
# (https://opencode.ai/docs/go); change them if this project uses a different provider —
# `opencode models` prints what this machine can reach.
# The "limited until <time>" record is kept in this project, at
# .tfcore/.session/model-cooldown.json. Uncomment to move it (relative to the project root, or
# absolute); several projects sharing one file learn about a limit from each other.
# cooldown_file: .tfcore/.session/model-cooldown.json
# Full explanation: docs/TechieFlow-Routing-Guide.md §9.
fallbacks:
  frontier:
    claude: opus, haiku
    opencode: opencode-go/glm-5.3, opencode-go/kimi-k3, openai/gpt-5.6-sol
  standard:
    claude: haiku
    opencode: opencode-go/mimo-v2.5, opencode-go/qwen3.8-max, openai/gpt-5.6-luna
  economy:
    claude: sonnet
    opencode: opencode-go/deepseek-v4-flash, opencode-go/glm-5.3-flash, openai/gpt-5.6-luna
"""),
    ("billing:", """
# How each harness is paid for, so a cost figure knows what it means (SCHEMA.md §2.5b).
# subscription = a flat fee, marginal dollars are zero; metered = an API key, real money;
# local = no bill; auto = work it out per model from OpenCode's own sign-in file.
# Add a provider by name here to override the guess, e.g. "  myserver: local".
billing:
  claude: subscription
  opencode: auto
"""),
]
try:
    _txt = open(ryaml, encoding="utf-8").read()
    _added = []
    for key, block in MIGRATIONS:
        if not re.search(r"^%s\s*$" % re.escape(key), _txt, re.M):
            if not _txt.endswith("\n"):
                _txt += "\n"
            _txt += block
            _added.append(key.rstrip(":"))
    if _added:
        with open(ryaml, "w", encoding="utf-8", newline="\n") as _fh:
            _fh.write(_txt)
        print("tf-routing-bind: added %s to .tfcore/routing.yaml (nothing existing was changed)"
              % " and ".join(_added))
except FileNotFoundError:
    pass

# --- parse routing.yaml (flat format — see its header) --------------------
cfg = {"enabled": False, "phases": {}, "subagents": {}, "tiers": {}, "effort": {}}
sect = tier = None
try:
    for line in open(ryaml, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            key, _, val = line.partition(":")
            sect, tier = key.strip(), None
            if sect == "enabled":
                cfg["enabled"] = val.strip() == "true"
        elif sect == "tiers":
            if re.match(r"^  [a-z-]+:\s*$", line):
                tier = line.strip()[:-1]
                cfg["tiers"][tier] = {}
            elif tier and line.startswith("    "):
                k, _, v = line.strip().partition(":")
                cfg["tiers"][tier][k.strip()] = v.strip()
        elif sect in ("phases", "subagents", "effort"):
            k, _, v = line.strip().partition(":")
            cfg[sect][k.strip()] = v.strip()
except FileNotFoundError:
    pass  # no routing.yaml -> treat as disabled

# A tier resolves to its own model UNLESS that model is on cooldown — a usage limit recorded by
# tf-goal.sh in the per-machine file tf-model-pick.sh owns. Binding the fallback here is what stops
# the sub-agents failing behind a main agent that already moved (Routing-Guide §8, 2026-09-06).
_PICK = os.path.join(root, ".tfcore", "utils", "tf-model-pick.sh")
_picked = {}


def model_for(t, harness):
    declared = cfg["tiers"].get(t, {}).get(harness)
    if not declared or t == "inherit":
        return declared
    if (t, harness) not in _picked:
        got = declared
        if os.path.isfile(_PICK):
            try:
                import subprocess
                out = subprocess.run(["bash", _PICK, "pick", t, harness],
                                     capture_output=True, text=True, timeout=20)
                cand = (out.stdout or "").strip().splitlines()
                cand = cand[-1].strip() if cand else ""
                if cand and cand != "inherit":
                    got = cand
                elif cand == "inherit":
                    got = None   # every model in the chain is limited: bind nothing, let it wait
            except Exception:
                pass
        if got != declared:
            print("tf-routing-bind: tier %s (%s) is on %s — %s is on cooldown"
                  % (t, harness, got or "no model: the whole chain is limited", declared))
        _picked[(t, harness)] = got
    return _picked[(t, harness)]

# --- remove previously generated artifacts (manifest-driven) --------------
removed = 0
try:
    for p in open(manifest_path, encoding="utf-8").read().splitlines():
        p = p.strip()
        if not p or ".." in p:
            continue
        fp = os.path.join(root, p)
        if os.path.isfile(fp):
            os.remove(fp)
            removed += 1
    os.remove(manifest_path)
except FileNotFoundError:
    pass
# prune empty generated dirs
for d in (os.path.join(root, ".claude", "commands", "tf"),):
    try:
        os.rmdir(d)
    except OSError:
        pass

if not cfg["enabled"]:
    print("tf-routing-bind: routing disabled — %d generated artifact(s) removed, nothing emitted" % removed)
    raise SystemExit(0)

generated = []

def write(relpath, content):
    fp = os.path.join(root, relpath)
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    with open(fp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(content)
    generated.append(relpath)

MARK = "<!-- generated by tf-routing-bind.sh from .tfcore/routing.yaml — do not edit; edit routing.yaml and re-run -->"

# A phase whose task file no longer ships gets no binding, with a printed warning: the seven
# never-used commands were removed in Sitting 4c (2026-09-06) and routing.yaml is preserved per
# project, so a stale line there must never write a file reference OpenCode refuses to load
# (MISS-TechieFlow-20260906-27: OpenCode would not start on TechieBlog-oc).
for _ph in sorted(cfg["phases"]):
    if not os.path.isfile(os.path.join(root, ".tfcore", "tasks", _ph + ".md")):
        print("tf-routing-bind: phase %s has no task file .tfcore/tasks/%s.md; no binding written (remove the line from routing.yaml)" % (_ph, _ph))
        del cfg["phases"][_ph]

# --- Claude Code: routed wrapper commands ---------------------------------
OWNER = {"day1-greenfield": "analyst", "day1-brownfield": "analyst",
         "amend-docs": "analyst", "mockups": "analyst",
         "split-brd": "analyst", "verify-phase": "verifier"}
for phase, t in sorted(cfg["phases"].items()):
    m = model_for(t, "claude")
    if t == "inherit" or not m:
        continue
    owner = OWNER.get(phase, "flow-master")
    eff = cfg["effort"].get(t)
    fm = ["---",
          "description: Routed TechieFlow phase — %s on the %s tier" % (phase, t),
          "model: %s" % m]
    if eff:
        fm.append("effort: %s" % eff)
    fm.append("---")
    body = ("%s\n%s\n\nLoad `.tfcore/agents/%s.md` and adopt its core principles "
            "(git ban, smoke policy, status gate) without printing the greeting. "
            "Then execute `.tfcore/tasks/%s.md` with arguments: $ARGUMENTS\n"
            % ("\n".join(fm), MARK, owner, phase))
    write(os.path.join(".claude", "commands", "tf", phase + ".md"), body)

# --- Claude Code: tier-bound subagents ------------------------------------
SUB_BODY = {
    "tf-builder": ("Builds ONE REQ cluster (FN/NFR) to the project's coding standards. "
        "Read `.tfcore/tasks/_smoke-test-policy.md` first. Hard rules: NEVER run git/gh; "
        "smoke your changed feature yourself before returning; tag work with its [REQ-*] id "
        "in the checklist Remarks; return { reqsImplemented[], filesChanged[], libraryIssues[] }."),
    "tf-test-writer": ("Writes verification tests for one REQ cluster (verify-phase §4). "
        "Black-box: never touch application source. NEVER run git/gh. "
        "Return { testsAdded[], testsRefreshed[], unobservable[] }."),
    "tf-explorer": ("Read-only codebase scan (devguide OBSERVE, index-docs). Never edits, "
        "never runs git/gh. Returns findings as structured text."),
    "trblazeui": ("Read the NuGet-deployed TrBlazeUI persona and fully adopt it. Resolve it in this "
        "order and use the FIRST that exists: `.claude/commands/trblazeui.md` (current deploy target), "
        "`.claude/trblazeui.md` (legacy deploy target), `.trblazeui/TrBlazeUI-AI-Reference.md` "
        "(packaged component reference). Only if NONE exists, report that TrBlazeUI is not deployed "
        "(`dotnet build` the app to unpack the package) and stop."),
    "techierag": ("Read the NuGet-deployed TechieRag persona and fully adopt it. Resolve it in this "
        "order and use the FIRST that exists: `.claude/commands/techierag.md` (current deploy target), "
        "`.claude/techierag.md` (legacy deploy target), `.techierag/TechieRag-AI-Reference.md` "
        "(packaged service reference). Only if NONE exists, report that TechieRag is not deployed "
        "(`dotnet build` the app to unpack the package) and stop."),
}
DESC = {
    "tf-builder": "TechieFlow FN/NFR cluster builder (routed tier)",
    "tf-test-writer": "TechieFlow verify-phase test writer (routed tier)",
    "tf-explorer": "TechieFlow read-only explorer (routed tier)",
    "trblazeui": "TrBlazeUI UI builder persona (routed tier wrapper)",
    "techierag": "TechieRag RAG builder persona (routed tier wrapper)",
}
for name, t in sorted(cfg["subagents"].items()):
    m = model_for(t, "claude")
    if t == "inherit" or not m or name not in SUB_BODY:
        continue
    body = ("---\nname: %s\ndescription: %s\nmodel: %s\n---\n%s\n%s\n"
            % (name, DESC[name], m, MARK, SUB_BODY[name]))
    write(os.path.join(".claude", "agents", name + ".md"), body)

# --- OpenCode: pure-JSON binding file -------------------------------------
oc = {"$schema": "https://opencode.ai/config.json", "agent": {}, "command": {}}
PERSONA_TIER = {
    "flow-master": cfg["phases"].get("build-phase"),
    "flow-analyst": cfg["phases"].get("day1-greenfield"),
    "flow-architect": cfg["phases"].get("day1-greenfield"),
    "flow-verifier": cfg["phases"].get("verify-phase"),
}
for name, t in PERSONA_TIER.items():
    m = model_for(t, "opencode") if t else None
    if m and t != "inherit":
        oc["agent"][name] = {"model": m}
for name, t in sorted(cfg["subagents"].items()):
    m = model_for(t, "opencode")
    if t == "inherit" or not m:
        continue
    if name in ("trblazeui", "techierag"):
        oc["agent"][name] = {"model": m}  # registered in opencode.jsonc; merge model on
    else:
        oc["agent"][name] = {  # new subagents: entries must validate standalone
            "description": DESC.get(name, name),
            "mode": "subagent",
            "model": m,
            "prompt": SUB_BODY.get(name, name),
        }
for phase, t in sorted(cfg["phases"].items()):
    m = model_for(t, "opencode")
    if t == "inherit" or not m:
        continue
    oc["command"]["techieflow:tasks:" + phase] = {  # complete entry: files validate standalone
        "template": "{file:../.tfcore/tasks/%s.md}" % phase,
        "description": "Routed: %s (%s tier)" % (phase, t),
        "model": m,
    }
write(os.path.join(".opencode", "opencode.json"),
      json.dumps(oc, indent=2, ensure_ascii=False) + "\n")

# --- manifest -------------------------------------------------------------
os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
with open(manifest_path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(generated) + "\n")
print("tf-routing-bind: routing enabled — %d artifact(s) generated (%d stale removed)"
      % (len(generated), removed))
PY
exit 0
