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
# What it allows only while .tfcore/.session/phase.json says build-phase, fix-issues or
# triage-and-fix (whose step 3 runs the fix-issues steps)
# (written by bash .tfcore/utils/tf-phase.sh start <command>, step 0 of every task):
#   - a migration runner: dotnet ef database update, dotnet run --project <…Db|…Migration(s)…>,
#     dbup, flyway migrate, liquibase update, alembic upgrade, prisma migrate, knex migrate,
#     rails db:migrate, sequelize db:migrate
#   - code a python / node / deno / bun / ruby / perl / pwsh run executes, inline or from a script
#     file, that uses a database library and holds a SQL write, unless every database path it names
#     is a throw-away (tests/.artifacts/, /tmp, :memory:) (Sevak TF-002)
# A client or a SQL verb that is only mentioned (a grep pattern, a note written to a file) passes.
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

# What counts is what RUNS, not what a command mentions (Sevak TF-002, 2026-10-06).
#  - A client is a write only when it is the command word of a segment (after a start, ; & | ( or
#    a backtick, past sudo / env / `exec <container>`), so a grep or a note naming a client and a
#    SQL verb passes, while `<client> app.db "<write>"` does not.
#  - A heredoc's body is SQL when it feeds a client, code when it feeds an interpreter, and data
#    (dropped) when it feeds anything else (`cat > notes.md <<EOF`).
#  - An interpreter (python, node, deno, bun, ruby, perl, pwsh) running inline code or a script
#    file has that code read: a database library together with a SQL write is refused unless every
#    database path it names is a throw-away one (tests/.artifacts/, /tmp, :memory:). A sub-agent's
#    script deleted four owner settings from Sevak's app database because the guard saw only
#    `python3 x.py`.
# Words inside an echo/printf string or a comment line are not commands (MISS-TechieFlow-20260906-20),
# unless the string is redirected into a file, which may then be run.
SEG = (r"(?:^|[;&|(`\n]|\$\()\s*(?:sudo\s+(?:-\S+\s+)*)?(?:env\s+(?:\S+=\S*\s+)*)?"
       r"(?:[\w./\\-]*\bexec\s+(?:-\S+\s+)*\S+\s+)?")
CLIENT_AT = SEG + r"(?:\S*/)?" + CLIENTS
INTERP = r"(?:python3?|py|node|deno|bun|ruby|perl|pwsh|powershell(?:\.exe)?|tsx|ts-node)"
INTERP_AT = SEG + r"(?:\S*/)?" + INTERP + r"\b"
DB_LIBS = (r"\bsqlite3\b|better-sqlite3|\bsql\.js\b|node:sqlite|\bpsycopg|\bpymysql\b|mysql\.connector|\bmysql2\b"
           r"|require\(\s*['\"]pg['\"]\s*\)|from\s+['\"]pg['\"]|\bsqlalchemy\b|microsoft\.data\.sqlite|system\.data\.sqlite"
           r"|\bpymongo\b|\bmongodb\b|\baiosqlite\b|\bduckdb\b|invoke-sqlcmd")
SQL_WRITE = (r"\binsert\s+(?:or\s+\w+\s+)?into\b|\bupdate\s+[\w\"`\[\].]+\s+set\b|\bdelete\s+from\b"
             r"|\bdrop\s+(?:table|index|view|database)\b|\bcreate\s+(?:table|index|view|trigger)\b|\balter\s+table\b"
             r"|\btruncate\b|\breplace\s+into\b|\bexecutescript\b"
             r"|\.(?:delete_many|delete_one|insert_one|insert_many|update_one|update_many|replace_one|drop)\s*\(")
DB_PATH = r"['\"]([^'\"\n]*\.(?:db|sqlite3?|mdf)|:memory:)['\"]"
SCRIPT_EXT = r"\.(?:py|js|mjs|cjs|ts|mts|rb|pl|ps1)\b"


def throwaway(path):
    q = path.replace("\\", "/").lower()
    return q == ":memory:" or "tests/.artifacts/" in q or q.startswith("/tmp/") or "/tmp/" in q or q.startswith("tmp/")


def code_writes(code):
    """A database library and a SQL write in the same code, against a database that is not a throw-away."""
    c = code.lower()
    if not (re.search(DB_LIBS, c) and re.search(SQL_WRITE, c)):
        return False
    paths = re.findall(DB_PATH, c)
    return not paths or not all(throwaway(x) for x in paths)


low = cmd.lower()
low = re.sub(r"(?m)^\s*#.*$", "", low)

# heredocs first: keep the body only where it is SQL (fed to a client) or code (fed to an interpreter)
code_bits, body_sql = [], []


runs_code = bool(re.search(INTERP_AT, low))


def _heredoc(m):
    head, body = m.group(1), m.group(4)
    if re.search(CLIENT_AT, head):
        body_sql.append(body)
    elif re.search(INTERP_AT, head) or runs_code:
        # fed to an interpreter, or written to a file in a command that also runs one
        # (`cat > s.py <<EOF … EOF; python3 s.py`): the file does not exist when this hook runs
        code_bits.append(body)
    return head + "\n"


low = re.sub(r"(?ms)^([^\n]*?)<<-?\s*(['\"]?)(\w+)\2[^\n]*\n(.*?)^\s*\3\s*$", _heredoc, low)
if runs_code:
    code_bits.append(low)   # printf '…' > s.py && python3 s.py: the code is in the command itself
# an echo/printf string is dropped unless it is redirected into a file
low = re.sub(r"\b(echo|printf)\s+(?:\"[^\"]*\"|'[^']*'|[^\n;|&>]*)(?!\s*>)", r"\1", low)

direct_write = bool(re.search(CLIENT_AT, low)
                    and (re.search(WRITE_VERBS, low)
                         or re.search(r"\s-(f|i)\s+\S+\.sql\b", low)
                         or re.search(r"<\s*\S+\.sql\b", low))) or any(re.search(WRITE_VERBS, b) for b in body_sql)

# inline code (-c / -e / --eval / -Command) and script files run by an interpreter
script_write, script_name = False, ""
if re.search(INTERP_AT, low) or code_bits:
    for m in re.finditer(INTERP_AT + r"[^\n;|&]*?\s(?:-c|-e|--eval|-p|-command)\s+(\"(?:[^\"\\]|\\.)*\"|'[^']*')", low):
        code_bits.append(m.group(1))
    roots = [data.get("cwd") or "", os.environ.get("TF_ROOT", ".")]
    # `cd tools && python3 seed.py`: the script is found from the folder the command moved to
    for cdir in re.findall(r"(?:^|[;&|(]\s*)cd\s+(['\"]?)([^\s'\";&|]+)\1", cmd):
        roots += [os.path.join(r, cdir[1]) for r in list(roots) if r] + [cdir[1]]
    for seg in re.finditer(INTERP_AT + r"([^\n;|&]*)", cmd, flags=re.I):
        for tok in re.findall(r"[^\s'\"]+" + SCRIPT_EXT, seg.group(1), flags=re.I):
            for cand in [tok] + [os.path.join(r, tok) for r in roots if r]:
                try:
                    if os.path.isfile(cand) and os.path.getsize(cand) < 2_000_000:
                        with open(cand, encoding="utf-8", errors="replace") as fh:
                            if code_writes(fh.read()):
                                script_write, script_name = True, tok
                        break
                except Exception:
                    pass
    script_write = script_write or any(code_writes(b) for b in code_bits)

if script_write:
    print("BLOCKED by TechieFlow policy: this runs code that writes to a database directly "
          f"({script_name or 'inline code'}: a database library and an INSERT / UPDATE / DELETE / DROP / CREATE). "
          "The app's database changes only through its migration path or through the app itself. For a "
          "smoke or a seed, point the script at a throw-away copy whose path names tests/.artifacts/, /tmp "
          "or :memory:, written literally in the script. Owner rule 2026-09-05; Sevak TF-002.", file=sys.stderr)
    sys.exit(2)
if direct_write or re.search(DROP_DB, low):
    print("BLOCKED by TechieFlow policy: a direct database write (SQL through a client, or dropping "
          "a database) is not allowed from any command. Schema and data changes go through the "
          "migration path named in the Architecture's Stack decisions (for the .NET answer set, the "
          "<App>Db DbUp project), run from *build-phase or *fix-issues. A read (SELECT, \\d, .tables) "
          "is fine. Owner rule 2026-09-05.", file=sys.stderr)
    sys.exit(2)

if re.search(MIGRATORS, low):
    ph = phase()
    # triage-and-fix step 3 is fix-issues steps 2 to 5 under its own marker (AppManager TF-027)
    if ph in ("build-phase", "fix-issues", "triage-and-fix"):
        sys.exit(0)
    who = f"the marker says {ph}" if ph else "no command marker is set"
    print("BLOCKED by TechieFlow policy: a database migration runs only from *build-phase, "
          f"*fix-issues or *triage-and-fix, and {who}. Day-1, mockups, split-brd, amend-docs, devguide, verify, "
          "triage and status commands write documents and records, never the database. If you are "
          "inside build-phase or fix-issues, step 0 was skipped: run "
          "bash .tfcore/utils/tf-phase.sh start <command> <App> and retry. Owner rule 2026-09-05.",
          file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
exit $?
