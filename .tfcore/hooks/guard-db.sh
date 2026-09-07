#!/usr/bin/env bash
# TechieFlow PreToolUse hook — database writes happen only from build-phase or fix-issues,
# and only through the migration path the Stack decisions name (owner, 2026-09-05;
# MISS-TechieFlow-20260905-09: a day-1 run created a user and patched two stored
# procedures in the development database).
#
# What it refuses, in every command:
#   - a direct SQL write through a client: psql, pgcli, sqlite3, mysql, mariadb, sqlcmd,
#     mongosh with INSERT / UPDATE / DELETE / CREATE / ALTER / DROP / TRUNCATE / GRANT /
#     REPLACE / MERGE in the command text, a -f / -i script, or stdin redirected from a file
#   - dropping or resetting a database
# What it allows only while .tfcore/.session/phase.json says build-phase or fix-issues
# (written by bash .tfcore/utils/tf-phase.sh start <command>, step 0 of every task):
#   - a migration runner: dotnet ef database update, dotnet run --project <…Db|…Migration(s)…>,
#     dbup, flyway migrate, liquibase update, alembic upgrade, prisma migrate, knex migrate,
#     rails db:migrate, sequelize db:migrate
# Reads (SELECT, \d, .tables, dumps to stdout) pass. YOLO does not relax this.
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Bash"); OpenCode via
# .opencode/plugin/techieflow.js. Exit 2 + stderr = block the call and tell the agent why.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

TF_HOOK_INPUT="$INPUT" TF_ROOT="$ROOT" python3 - <<'PY'
import json, os, re, sys, time

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command")
if not isinstance(cmd, str) or not cmd.strip():
    sys.exit(0)

WRITE_VERBS = r"\b(insert|update|delete|create|alter|drop|truncate|grant|revoke|replace|merge|upsert)\b"
CLIENTS = r"\b(psql|pgcli|sqlite3|mysql|mariadb|sqlcmd|mongosh|mongo)\b"
MIGRATORS = (r"\bdotnet\s+ef\s+database\s+(update|drop)\b"
             r"|\bdotnet\s+run\b[^|;&]*--project\s+\S*(db|migration|migrations)\b"
             r"|\bdbup\b|\bflyway\s+(migrate|clean|undo)\b|\bliquibase\s+(update|rollback|drop-all)\b"
             r"|\balembic\s+(upgrade|downgrade)\b|\bprisma\s+(migrate|db\s+push)\b|\bknex\s+migrate\b"
             r"|\brails\s+db:(migrate|reset|drop|schema:load)\b|\bsequelize\s+db:migrate\b|\bgoose\s+(up|down|reset)\b")
DROP_DB = r"\b(dropdb|drop\s+database|mongo(sh)?\b[^|;&]*dropDatabase)\b"

def phase():
    p = os.path.join(os.environ.get("TF_ROOT", "."), ".tfcore", ".session", "phase.json")
    try:
        if time.time() - os.path.getmtime(p) > 24 * 3600:
            return None
        with open(p, encoding="utf-8") as fh:
            return (json.load(fh) or {}).get("cmd")
    except Exception:
        return None

# Words inside an echo/printf string or a comment line are not commands: an echo naming the
# migration tool refused a verify run's read on 2026-09-06 (MISS-TechieFlow-20260906-20).
# Strip them before matching, so only a command that runs a migrator or writes through a
# client is refused.
low = cmd.lower()
low = re.sub(r"(?m)^\s*#.*$", "", low)
low = re.sub(r"\b(echo|printf)\s+(\"[^\"]*\"|'[^']*'|[^\n;|&]*)", r"\1", low)
direct_write = (re.search(CLIENTS, low)
                and (re.search(WRITE_VERBS, low)
                     or re.search(r"\s-(f|i)\s+\S+\.sql\b", low)
                     or re.search(r"<\s*\S+\.sql\b", low)))
if direct_write or re.search(DROP_DB, low):
    print("BLOCKED by TechieFlow policy: a direct database write (SQL through a client, or dropping "
          "a database) is not allowed from any command. Schema and data changes go through the "
          "migration path named in the Architecture's Stack decisions (for the .NET answer set, the "
          "<App>Db DbUp project), run from *build-phase or *fix-issues. A read (SELECT, \\d, .tables) "
          "is fine. Owner rule 2026-09-05.", file=sys.stderr)
    sys.exit(2)

if re.search(MIGRATORS, low):
    ph = phase()
    if ph in ("build-phase", "fix-issues"):
        sys.exit(0)
    who = f"the marker says {ph}" if ph else "no command marker is set"
    print("BLOCKED by TechieFlow policy: a database migration runs only from *build-phase or "
          f"*fix-issues, and {who}. Day-1, mockups, split-brd, amend-docs, devguide, verify, "
          "triage and status commands write documents and records, never the database. If you are "
          "inside build-phase or fix-issues, step 0 was skipped: run "
          "bash .tfcore/utils/tf-phase.sh start <command> <App> and retry. Owner rule 2026-09-05.",
          file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
exit $?
