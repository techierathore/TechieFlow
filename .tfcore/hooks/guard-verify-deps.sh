#!/usr/bin/env bash
# TechieFlow PreToolUse hook — a verify run may START a dependency, never CREATE one,
# and never point the application at a different one.
#
# TfLens, 2026-09-01 (MISS-TfLens-20260901-02). The configured dev database was refusing
# connections. The agent ran `docker compose up -d db || docker compose up -d` — the
# service is named `postgres`, so the `||` fallback executed the BARE compose command and
# started every service, creating an application container and image the owner had to
# delete by hand. It then exported the connection-string variable to point the whole test
# suite at a different PostgreSQL and reported "689/689 pass" against it.
#
# Both halves are the same error. A verify run's entire product is trustworthy verdicts,
# and verdicts measured against a system nobody chose are not weaker evidence — they are
# evidence about a DIFFERENT system, reported under the checklist's name. The empty
# substitute database then produced RENDER-EMPTY on nine controls whose real cause was
# "no data", which is the plausible-wrong-number failure this framework exists to prevent,
# arriving inside the verifier itself.
#
# §1 was already strict about unasked-for FILES (tests/.artifacts/, guard-artifacts.sh) and
# silent about unasked-for INFRASTRUCTURE. A container, a volume and an image are exactly
# as much machine state as a stray directory. This hook is that rule, as a rule and not a
# paragraph (maintenance contract 3).
#
# REFUSES:
#   - `docker compose up` / `docker-compose up` with no service named
#   - any `|| docker compose up` fallback, which widens the command precisely when it failed
#   - `docker compose run|create`, `docker run`, `docker volume create` — creating, not starting
#   - an inline or exported connection-string variable in front of a test/run command
# ALLOWS: `docker start <name>`, `docker compose up <service>`, `docker compose start`,
#   `docker ps|logs|inspect`, and anything that is not one of the above.
#
# Wired in .claude/settings.json -> hooks.PreToolUse (matcher "Bash"); OpenCode via
# .opencode/plugin/techieflow.js. Exit 2 + stderr = block and feed the message back.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable — a guard that cannot
# read its input must not stop the run.
#
# Tested by tests/regression/run.sh tf_013.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

cmd = (data.get("tool_input") or {}).get("command")
if not isinstance(cmd, str) or not cmd.strip():
    sys.exit(0)

def block(what, instead):
    print("BLOCKED by TechieFlow policy: %s\n"
          "A verify run may START a service the project already defines; it may not CREATE "
          "one, and it may never measure the application against a different instance — a "
          "green suite against the wrong database is worse than a red one, because it is "
          "quotable.\n%s\n"
          "If the dependency is down and you cannot start the project's own definition of "
          "it BY NAME, stop and ask, naming the one command the owner should run. Record "
          "the resolved target (host, port, database — never credentials) in the verify "
          "report, so which system was measured is on the face of it."
          % (what, instead), file=sys.stderr)
    sys.exit(2)

# --- creating infrastructure, rather than starting what the project already defines ------
COMPOSE = r"docker(?:\s+compose|-compose)"

# a bare `up`: no service name before the end of the segment. Flags are not service names.
for seg in re.split(r"(?:\|\||&&|;|\||\n)", cmd):
    seg = seg.strip()
    m = re.search(COMPOSE + r"\s+up\b(.*)$", seg, re.I)
    if m:
        rest = m.group(1)
        # drop flags and their values; whatever is left is a service name
        words = [w for w in re.split(r"\s+", rest.strip()) if w]
        svc = []
        skip = False
        for w in words:
            if skip:
                skip = False
                continue
            if w.startswith("-"):
                if "=" not in w and w in ("--scale", "--timeout", "--project-name", "-p", "--file", "-f"):
                    skip = True
                continue
            svc.append(w)
        if not svc:
            block("`%s` starts EVERY service in the compose file." % seg[:120],
                  "Name the service: `docker compose up -d <service>` — and check the name, "
                  "because a `|| docker compose up` fallback runs the bare command exactly "
                  "when the named one was wrong.")

if re.search(r"\|\|\s*" + COMPOSE + r"\s+up\b", cmd, re.I):
    block("a `|| docker compose up` fallback widens the command when the named service failed.",
          "Drop the fallback. If the named service does not exist, the name is wrong — fix "
          "the name or ask; do not start everything instead.")

if re.search(COMPOSE + r"\s+(?:run|create)\b", cmd, re.I) or \
   re.search(r"\bdocker\s+(?:run|create)\b", cmd, re.I) or \
   re.search(r"\bdocker\s+volume\s+create\b", cmd, re.I):
    block("this CREATES container or volume state the owner did not ask for.",
          "Start what the project defines: `docker start <name>` or `docker compose up -d <service>`.")

# --- repointing the application at a different instance ----------------------------------
# The variable is whatever the project named it, so match the SHAPE of a connection string
# rather than a list of names that would never be complete.
CONNSTR = r"(?:Host|Server|Data\s*Source|Endpoint)\s*=|(?:postgres|postgresql|mysql|mongodb|mssql|sqlserver|redis)(?:\+srv)?://"
ASSIGN = r"(?:\bexport\s+|\bset\s+|^|\s|;|&&)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[\"']?([^\"'\s;&|]*)"

for m in re.finditer(ASSIGN, cmd):
    name, val = m.group(1), m.group(2)
    if re.search(CONNSTR, val, re.I) or (re.search(r"conn|db|database|datasource", name, re.I)
                                         and re.search(r"[=:]//|Host\s*=|Port\s*=", val, re.I)):
        block("`%s` points the application or its tests at a connection string chosen here, "
              "not the one the project is configured with." % name,
              "Use the app's own configured connection. TfLens's own test helper already "
              "carries this rule — \"there is deliberately no default here … so tests and app "
              "can never drift onto different servers again\" — and it cost a day to learn.")

sys.exit(0)
PY
exit $?
