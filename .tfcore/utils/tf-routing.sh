#!/usr/bin/env bash
# tf-routing.sh — the ONE command for model routing. Run it from an app repo.
#
#   bash .tfcore/utils/tf-routing.sh status                     what is routing doing right now?
#   bash .tfcore/utils/tf-routing.sh on                         turn routing ON  (generates all bindings)
#   bash .tfcore/utils/tf-routing.sh off                        turn routing OFF (removes all bindings)
#   bash .tfcore/utils/tf-routing.sh set-tier  <phase> <tier>   e.g. set-tier verify-phase economy
#   bash .tfcore/utils/tf-routing.sh set-model <tier> <harness> <model>
#                                                               e.g. set-model economy opencode opencode-go/deepseek-v4-flash
#                                                               e.g. set-model frontier claude opus
#   bash .tfcore/utils/tf-routing.sh bind                       re-generate bindings after editing routing.yaml by hand
#   bash .tfcore/utils/tf-routing.sh set-escalation <phase> <attempts> <tier>
#                                                               e.g. set-escalation fix-issues 2 frontier
#                                                               ADVISORY: "after <attempts> runs of <phase> on the same
#                                                               REQs, launch the next one on <tier>" — you apply it at
#                                                               launch; nothing switches a running phase's model.
#
# Everything edits .tfcore/routing.yaml in place (comments preserved) and then
# regenerates the harness bindings automatically via tf-routing-bind.sh — you
# never have to touch the generated files. Design: docs/Adapter-Design.md §5;
# owner guide: README §17b / WORKFLOW.html §17b.

set +e
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(bash "$SELF_DIR/tf-harness.sh" root)"
RY="$ROOT/.tfcore/routing.yaml"
CMD="${1:-status}"

[[ -f "$RY" ]] || { echo "No .tfcore/routing.yaml here ($ROOT) — run update-framework.sh first." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

_bind() { bash "$SELF_DIR/tf-routing-bind.sh" "$ROOT"; }

case "$CMD" in
  on)
    python3 - "$RY" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s2 = re.sub(r"^enabled:.*$", "enabled: true", s, count=1, flags=re.M)
open(p, "w", encoding="utf-8", newline="\n").write(s2)
PY
    echo "routing: ENABLED in $RY"
    _bind
    echo "Check with: bash .tfcore/utils/tf-routing.sh status"
    ;;
  off)
    python3 - "$RY" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s2 = re.sub(r"^enabled:.*$", "enabled: false", s, count=1, flags=re.M)
open(p, "w", encoding="utf-8", newline="\n").write(s2)
PY
    echo "routing: DISABLED in $RY"
    _bind
    ;;
  bind)
    _bind
    ;;
  set-tier)
    NAME="${2:-}"; TIER="${3:-}"
    case "$TIER" in frontier|standard|economy|inherit) ;; *)
      echo "usage: tf-routing.sh set-tier <phase-or-subagent> <frontier|standard|economy|inherit>" >&2; exit 2 ;;
    esac
    [[ -n "$NAME" ]] || { echo "usage: tf-routing.sh set-tier <phase-or-subagent> <tier>" >&2; exit 2; }
    python3 - "$RY" "$NAME" "$TIER" <<'PY'
import sys
p, name, tier = sys.argv[1:4]
lines = open(p, encoding="utf-8").read().splitlines(True)
sect = None; done = False
for i, line in enumerate(lines):
    if line.strip() and not line.startswith(" ") and not line.lstrip().startswith("#"):
        sect = line.split(":")[0].strip()
    elif sect in ("phases", "subagents") and line.strip().startswith(name + ":"):
        lines[i] = "  %s: %s\n" % (name, tier)
        done = True
        break
if not done:
    # unknown name: add it under phases (most common case)
    for i, line in enumerate(lines):
        if line.startswith("phases:"):
            lines.insert(i + 1, "  %s: %s\n" % (name, tier))
            done = True
            break
open(p, "w", encoding="utf-8", newline="\n").write("".join(lines))
print(("set %s -> %s" % (name, tier)) if done else "FAILED: no phases: section found")
PY
    _bind
    ;;
  set-model)
    TIER="${2:-}"; HARNESS="${3:-}"; MODEL="${4:-}"
    case "$TIER" in frontier|standard|economy) ;; *)
      echo "usage: tf-routing.sh set-model <frontier|standard|economy> <claude|opencode> <model-id>" >&2; exit 2 ;;
    esac
    case "$HARNESS" in claude|opencode) ;; *)
      echo "harness must be 'claude' (values: opus|sonnet|haiku or a model id) or 'opencode' (provider/model — list with: opencode models)" >&2; exit 2 ;;
    esac
    [[ -n "$MODEL" ]] || { echo "usage: tf-routing.sh set-model <tier> <claude|opencode> <model-id>" >&2; exit 2; }
    python3 - "$RY" "$TIER" "$HARNESS" "$MODEL" <<'PY'
import sys
p, tier, harness, model = sys.argv[1:5]
lines = open(p, encoding="utf-8").read().splitlines(True)
in_tiers = in_tier = False; done = False
for i, line in enumerate(lines):
    if line.strip() and not line.startswith(" ") and not line.lstrip().startswith("#"):
        in_tiers = line.startswith("tiers:")
        in_tier = False
    elif in_tiers and line.startswith("  ") and not line.startswith("    ") and line.strip().rstrip(":"):
        in_tier = line.strip().rstrip(":") == tier
    elif in_tiers and in_tier and line.strip().startswith(harness + ":"):
        lines[i] = "    %s: %s\n" % (harness, model)
        done = True
        break
open(p, "w", encoding="utf-8", newline="\n").write("".join(lines))
print(("set tiers.%s.%s -> %s" % (tier, harness, model)) if done else "FAILED: tier '%s' / key '%s' not found in tiers: map" % (tier, harness))
PY
    _bind
    ;;
  set-escalation)
    PHASE="${2:-}"; ATTEMPTS="${3:-}"; TIER="${4:-}"
    [[ -n "$PHASE" ]] || { echo "usage: tf-routing.sh set-escalation <phase> <attempts> <frontier|standard|economy>" >&2; exit 2; }
    [[ "$ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || { echo "attempts must be a positive integer (e.g. 2)" >&2; exit 2; }
    case "$TIER" in frontier|standard|economy) ;; *)
      echo "usage: tf-routing.sh set-escalation <phase> <attempts> <frontier|standard|economy>" >&2; exit 2 ;;
    esac
    python3 - "$RY" "$PHASE" "$ATTEMPTS" "$TIER" <<'PY'
import sys
p, phase, attempts, tier = sys.argv[1:5]
lines = open(p, encoding="utf-8").read().splitlines(True)
block = ["  %s:\n" % phase, "    after_attempts: %s\n" % attempts, "    tier: %s\n" % tier]
sect = None; start = end = None; esc_at = None
for i, line in enumerate(lines):
    if line.strip() and not line.startswith(" ") and not line.lstrip().startswith("#"):
        if sect == "escalation" and start is not None and end is None:
            end = i
        sect = line.split(":")[0].strip()
        if sect == "escalation":
            esc_at = i
    elif sect == "escalation":
        if line.startswith("  ") and not line.startswith("    ") and line.strip().rstrip(":") == phase:
            start = i
        elif start is not None and end is None and line.startswith("  ") and not line.startswith("    "):
            end = i
if start is not None:
    # replace the existing <phase> block (its 2-space header + 4-space children)
    if end is None:
        end = len(lines)
        while end > start + 1 and not lines[end - 1].strip():
            end -= 1
    lines[start:end] = block
    what = "updated"
elif esc_at is not None:
    lines[esc_at + 1:esc_at + 1] = block
    what = "added"
else:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines += ["\n", "# Advisory escalation — see DECISIONS.md 2026-08-21.\n", "escalation:\n"] + block
    what = "added (new escalation: section)"
open(p, "w", encoding="utf-8", newline="\n").write("".join(lines))
print("escalation.%s %s -> after_attempts: %s, tier: %s (advisory — applied at launch, never mid-run)" % (phase, what, attempts, tier))
PY
    # No _bind: escalation is advisory and generates no harness binding.
    ;;
  status)
    python3 - "$RY" "$ROOT" <<'PY'
import sys, os, re
p, root = sys.argv[1], sys.argv[2]
cfg = {"enabled": False, "phases": {}, "subagents": {}, "tiers": {}, "effort": {}, "escalation": {}}
sect = tier = None
for line in open(p, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    if not line.startswith(" "):
        key, _, val = line.partition(":")
        sect, tier = key.strip(), None
        if sect == "enabled":
            cfg["enabled"] = val.strip() == "true"
    elif sect in ("tiers", "escalation"):
        if re.match(r"^  [a-z0-9-]+:\s*$", line):
            tier = line.strip()[:-1]; cfg[sect][tier] = {}
        elif tier and line.startswith("    "):
            k, _, v = line.strip().partition(":")
            cfg[sect][tier][k.strip()] = v.strip()
    elif sect in ("phases", "subagents", "effort"):
        k, _, v = line.strip().partition(":")
        cfg[sect][k.strip()] = v.strip()

manifest = os.path.join(root, ".tfcore", ".session", "routing-bind.manifest")
bound = os.path.isfile(manifest)
n_art = sum(1 for l in open(manifest)) if bound else 0

print("Routing: %s   (bindings on disk: %s)" % ("ON" if cfg["enabled"] else "OFF",
      "%d generated artifacts" % n_art if bound else "none"))
if cfg["enabled"] != bound:
    print("  !! flag and bindings disagree — run: bash .tfcore/utils/tf-routing.sh bind")
print()
print("Tier models:")
for t in ("frontier", "standard", "economy"):
    m = cfg["tiers"].get(t, {})
    print("  %-9s claude: %-10s opencode: %s" % (t, m.get("claude", "-"), m.get("opencode", "-")))
print()
print("Phases by tier:")
for t in ("frontier", "standard", "economy", "inherit"):
    ph = sorted(k for k, v in cfg["phases"].items() if v == t)
    if ph:
        print("  %-9s %s" % (t, ", ".join(ph)))
sub = ["%s=%s" % (k, v) for k, v in sorted(cfg["subagents"].items())]
if sub:
    print("Subagents:  " + ", ".join(sub))
print()
print("Escalation (ADVISORY — you apply it when you launch; nothing switches a model mid-run):")
if cfg["escalation"]:
    for ph in sorted(cfg["escalation"]):
        e = cfg["escalation"][ph]
        n, t = e.get("after_attempts", "?"), e.get("tier", "?")
        base = cfg["phases"].get(ph, "inherit")
        print("  %-18s after %s attempt(s) on the same REQs -> launch the next on %s (base tier: %s)" % (ph, n, t, base))
    print("  next attempt number: bash .tfcore/utils/tf-emit.sh --next-run-attempt <phase> <REQ-ID>...")
    print("  change:              bash .tfcore/utils/tf-routing.sh set-escalation <phase> <attempts> <tier>")
else:
    print("  none declared — add one: bash .tfcore/utils/tf-routing.sh set-escalation fix-issues 2 frontier")
print()
if cfg["enabled"]:
    print("Invoke routed phases as:")
    print("  OpenCode:    /techieflow:tasks:<phase>        (same commands as always — model now pinned)")
    print("  Claude Code: /tf:<phase>                      (new wrappers; old commands still work, unrouted)")
    print()
    print("WHERE YOU SEE IT — opening the TUI looks UNCHANGED on purpose: your normal chat")
    print("(the default 'build' agent) stays on YOUR selected model. Routing becomes visible when:")
    print("  1. you run a /techieflow:tasks:* command  -> the run executes on the tier model (footer)")
    print("  2. you Tab to a persona (flow-master, flow-verifier, ...) -> each carries its bound model")
    print("  3. a phase finishes -> docs/metrics/*.jsonl records tier, observed model, routed, cost")
    print("NOTE (verified): in the TUI a routed command's model STAYS for the session afterwards —")
    print("pick your model from the model list (or start a new session) if you keep chatting.")
else:
    print("Turn on with:  bash .tfcore/utils/tf-routing.sh on")
PY
    ;;
  *)
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
exit 0
