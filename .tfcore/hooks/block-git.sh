#!/usr/bin/env bash
# TechieFlow PreToolUse hook for Bash — the git guard + the YOLO permission gate.
#
# Two jobs, one hook (wired in .claude/settings.json → hooks.PreToolUse, matcher
# "Bash"; the OpenCode plugin .opencode/plugin/techieflow.js feeds it the same
# Claude-shaped stdin for the `bash` tool):
#
#  1. GIT GUARD. Git is MANUAL in TechieFlow — agents never COMMIT, PUSH, STAGE,
#     RESET, CHECKOUT or otherwise WRITE to git, ever (.tfcore/tasks/_smoke-test-policy.md
#     §"Git is manual", _status-update-gate.md §"Never run git"). Outside YOLO,
#     agents never READ git either (status/log/diff/blame) — status evidence is the
#     checklist table + working tree + a fresh build. In YOLO mode (below) READ-ONLY
#     git/gh is allowed; WRITES stay blocked in every mode. settings.json's deny
#     rules list the write subcommands as a second layer (deny rules hold in every
#     permission mode, bypass included); this hook catches the compound forms
#     prefix-matching misses ("cd x && git log", "foo | git …", "bash -c 'git …'").
#
#  2. YOLO GATE (.tfcore/tasks/_yolo-mode.md). Claude Code honours settings.json
#     `ask` rules EVEN in bypassPermissions mode and EVEN when a hook says allow —
#     so `rm`/`rmdir`/`sudo` are NOT in settings.json `ask` any more; this hook is
#     the only place that decides. Outside YOLO it returns permissionDecision=ask
#     for them (same prompt the owner always had). In YOLO it stays silent and the
#     bare "Bash" allow rule lets them run — an unattended goal run never stalls on
#     a delete. Catastrophic `rm -rf /|~` stay in settings.json `deny` (every mode).
#
# YOLO is ON when any of: env TF_YOLO=1 · .tfcore/.session/yolo.json exists
# (tf-yolo.sh on) · the hook payload's permission_mode is bypassPermissions/auto.
#
# Exit codes: 2 + stderr = BLOCK (both harnesses); 0 + JSON on stdout = decision
# (Claude Code only; OpenCode ignores stdout and uses its own permission map).
# Any internal failure → fall back to the ORIGINAL conservative behaviour
# (block any command word git/gh via regex; leave rm to the harness).

INPUT="$(cat)"
ROOT="${CLAUDE_PROJECT_DIR:-${TF_PROJECT_DIR:-}}"
STRICT_GIT="${TF_STRICT_GIT:-0}"

YOLO=0
[[ "${TF_YOLO:-0}" == "1" ]] && YOLO=1
[[ -n "$ROOT" && -f "$ROOT/.tfcore/.session/yolo.json" ]] && YOLO=1
if [[ $YOLO -eq 0 ]] && printf '%s' "$INPUT" | grep -qE '"permission_mode"[[:space:]]*:[[:space:]]*"(bypassPermissions|auto)"'; then YOLO=1; fi

block_git_msg() {
  cat >&2 <<'MSG'
BLOCKED by TechieFlow policy: agents NEVER WRITE to git or gh — no commit / push / add / reset / checkout / stash / tag / merge / rebase / branch edits / gh pr|issue create|merge|close. Git is manual, owner-only, in EVERY mode including YOLO.
Do NOT retry with another git/gh form. Instead:
- Status updates / "what changed": read the checklist Requirements Status table + the working-tree files (ls -lt, find -newer, Read/Glob/Grep) + a fresh dotnet build — never commit history (.tfcore/tasks/_status-update-gate.md).
- Investigating code: read the files on disk at file:line — the working tree IS the as-built code.
- Committing/tagging: never yours. Record REQ IDs in the checklist Remarks, not in commits. The owner commits manually.
- If your command merely CONTAINS the word git (e.g. writing a doc, grepping for the string): use the Write/Edit/Grep tools instead of bash — that is the standing tool-preference rule anyway.
MSG
}
block_read_msg() {
  if [[ "$STRICT_GIT" == "1" ]]; then
    cat >&2 <<'MSG'
BLOCKED by TechieFlow Codex policy: agents do not run any git or gh command, including read-only status/log/diff/blame, in any mode.
Use the checklist Requirements Status table, working-tree files, filesystem metadata, and fresh build/test evidence instead. The owner performs version-control operations manually.
MSG
    return
  fi
  cat >&2 <<'MSG'
BLOCKED by TechieFlow policy: agents do not READ git outside YOLO mode (no status/log/diff/show/blame/grep) — git is manual, owner-only.
Do NOT retry with another git/gh form. Instead:
- Status updates / "what changed": read the checklist Requirements Status table + the working-tree files (ls -lt, find -newer, Read/Glob/Grep) + a fresh dotnet build — never commit history (.tfcore/tasks/_status-update-gate.md).
- Investigating code: read the files on disk at file:line — the working tree IS the as-built code.
- Read-only git (status/log/diff/blame) becomes available only in YOLO / goal mode (`*yolo` → bash .tfcore/utils/tf-yolo.sh on). Git WRITES are never available.
MSG
}

if ! command -v python3 >/dev/null 2>&1; then
  # Original conservative behaviour — no parser available.
  if printf '%s' "$INPUT" | grep -qE '(^|[^[:alnum:]_./@-])(git|gh)([^[:alnum:]_.-]|$)'; then block_git_msg; exit 2; fi
  exit 0
fi

# Verdicts: ALLOW | ASK_RM | BLOCK_WRITE | BLOCK_READ
VERDICT="$(TF_HOOK_INPUT="$INPUT" TF_YOLO_ON="$YOLO" python3 - <<'PY' 2>/dev/null
import json, os, re, shlex, sys

raw = os.environ.get("TF_HOOK_INPUT", "")
yolo = os.environ.get("TF_YOLO_ON") == "1"
strict_git = os.environ.get("TF_STRICT_GIT") == "1"
try:
    data = json.loads(raw)
    cmd = str((data.get("tool_input") or {}).get("command") or "")
except Exception:
    cmd = raw  # be conservative: scan whatever we got

# ---- git / gh classification --------------------------------------------------
GIT_READ = {
    "status", "log", "diff", "show", "blame", "grep", "ls-files", "ls-tree", "rev-parse",
    "rev-list", "describe", "shortlog", "cat-file", "name-rev", "merge-base", "cherry",
    "whatchanged", "count-objects", "fsck", "var", "check-ignore", "check-attr",
    "for-each-ref", "diff-tree", "diff-index", "diff-files", "show-ref", "show-branch",
    "ls-remote", "version", "help", "range-diff", "annotate", "bisect", "reflog",
}
# read-only only with these arg shapes (no args == list/show)
BRANCH_LIST_FLAGS = {"-a", "-r", "-v", "-vv", "--list", "--show-current", "--contains", "--no-contains",
                     "--merged", "--no-merged", "--all", "--remotes", "--verbose", "--points-at", "--sort"}
TAG_LIST_FLAGS = {"-l", "--list", "-n", "--contains", "--no-contains", "--points-at", "--sort", "--merged", "--no-merged"}

def _listing(a, list_flags):
    """read-only iff every flag is a listing flag AND (no positional args, or an explicit list flag is present)."""
    flags = [t for t in a if t.startswith("-")]
    pos = [t for t in a if not t.startswith("-")]
    if any(t.split("=", 1)[0] not in list_flags and not t.startswith("-n") for t in flags):
        return False
    return not pos or any(t.split("=", 1)[0] in list_flags for t in flags)

GIT_COND = {
    "branch":   lambda a: _listing(a, BRANCH_LIST_FLAGS),
    "tag":      lambda a: _listing(a, TAG_LIST_FLAGS),
    "stash":    lambda a: bool(a) and a[0] in ("list", "show"),
    "remote":   lambda a: (not a) or a[0] in ("-v", "--verbose", "show", "get-url"),
    "config":   lambda a: any(t in ("--get", "--get-all", "--get-regexp", "--list", "-l") for t in a)
                          and not any(t in ("--unset", "--unset-all", "--add", "--replace-all", "--edit", "-e",
                                            "--remove-section", "--rename-section") for t in a),
    "worktree": lambda a: bool(a) and a[0] == "list",
    "submodule": lambda a: bool(a) and a[0] in ("status", "summary"),
    "notes":    lambda a: (not a) or a[0] in ("list", "show"),
    "reflog":   lambda a: (not a) or a[0] in ("show",) or a[0].startswith("-"),
    "bisect":   lambda a: bool(a) and a[0] in ("log", "view", "visualize"),
}
GH_READ_VERBS = {"list", "view", "status", "checks", "diff", "watch", "download"}
GH_READ_TOP = {"auth": {"status"}, "pr": GH_READ_VERBS, "issue": GH_READ_VERBS, "run": GH_READ_VERBS,
               "release": GH_READ_VERBS, "repo": {"view", "list"}, "search": None, "browse": None,
               "label": {"list"}, "workflow": {"list", "view"}, "gist": {"list", "view"},
               "cache": {"list"}, "variable": {"list"}, "secret": {"list"}, "ruleset": {"list", "view"}}

WRAPPERS = {"command", "exec", "sudo", "env", "nohup", "time", "nice", "stdbuf", "timeout", "xargs",
            "winrun", "doas", "busybox", "ionice", "chronic", "unbuffer", "script"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
SEPS = {";", "&&", "||", "|", "&", "(", ")", "{", "}", "\n", "|&"}

def basename(tok):
    tok = tok.strip("\"'")
    return tok.rsplit("/", 1)[-1]

def classify_git(args):
    """args = tokens after 'git'. Returns 'read' or 'write'."""
    i = 0
    # skip global options like -C <path>, -c k=v, --git-dir=..., --no-pager
    while i < len(args) and args[i].startswith("-"):
        if args[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") and i + 1 < len(args):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return "read"  # bare `git` prints usage
    sub = args[i]
    rest = args[i + 1:]
    if sub in GIT_READ:
        return "read"
    if sub in GIT_COND:
        try:
            return "read" if GIT_COND[sub](rest) else "write"
        except Exception:
            return "write"
    return "write"

def classify_gh(args):
    a = [t for t in args if not t.startswith("-")] or [""]
    top = a[0]
    if top == "api":
        flags = set(t for t in args if t.startswith("-"))
        if any(f in flags for f in ("-X", "--method", "-f", "-F", "--field", "--raw-field", "--input")):
            # explicit GET is fine
            for k, t in enumerate(args):
                if t in ("-X", "--method") and k + 1 < len(args) and args[k + 1].upper() == "GET":
                    continue
            if any(f in flags for f in ("-f", "-F", "--field", "--raw-field", "--input")):
                return "write"
            for k, t in enumerate(args):
                if t in ("-X", "--method") and k + 1 < len(args) and args[k + 1].upper() != "GET":
                    return "write"
            return "read"
        return "read"
    if top in GH_READ_TOP:
        verbs = GH_READ_TOP[top]
        if verbs is None:
            return "read"
        return "read" if len(a) > 1 and a[1] in verbs else "write"
    return "write"

found = {"read": 0, "write": 0}
found_rm = [False]
found_sudo = [False]

def scan(cmdline, depth=0):
    if depth > 4:
        return
    try:
        lexer = shlex.shlex(cmdline, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        lexer.commenters = ""
        toks = list(lexer)
    except Exception:
        raise
    # split into simple commands
    groups, cur = [], []
    for t in toks:
        if t in SEPS or t in (";;", "&&", "||", "|&"):
            if cur:
                groups.append(cur)
            cur = []
        else:
            # shlex keeps "$(git" / "`git" glued; split those too
            for piece in re.split(r"(?:\$\(|`|<\(|>\()", t):
                if piece:
                    cur.append(piece)
    if cur:
        groups.append(cur)
    for g in groups:
        j = 0
        # env assignments
        while j < len(g) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", g[j]):
            j += 1
        # wrappers
        while j < len(g):
            b = basename(g[j])
            if b in WRAPPERS:
                if b == "sudo" or b == "doas":
                    found_sudo[0] = True
                if b == "timeout" and j + 1 < len(g):
                    j += 2; continue
                if b == "env":
                    j += 1
                    while j < len(g) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", g[j]):
                        j += 1
                    continue
                j += 1
                continue
            break
        if j >= len(g):
            continue
        head = basename(g[j])
        args = g[j + 1:]
        if head in SHELLS:
            # bash -c "<string>" → recurse into the string
            for k, t in enumerate(args):
                if t in ("-c", "-lc", "-ic", "-ec", "-euc", "-exc") and k + 1 < len(args):
                    scan(args[k + 1], depth + 1)
            continue
        if head == "eval":
            scan(" ".join(args), depth + 1)
            continue
        if head in ("git", "git.exe"):
            found[classify_git(args)] += 1
        elif head in ("gh", "gh.exe"):
            found[classify_gh(args)] += 1
        elif head in ("rm", "rmdir", "unlink", "shred"):
            found_rm[0] = True
        elif head in ("find",) and ("-delete" in args or "-exec" in args and any(basename(x) == "rm" for x in args)):
            found_rm[0] = True

try:
    scan(cmd)
except Exception:
    # unparsable (unbalanced quotes etc.) → conservative regex, as before
    if re.search(r'(^|[^A-Za-z0-9_./@-])(git|gh)([^A-Za-z0-9_.-]|$)', cmd):
        print("BLOCK_WRITE" if not yolo else "BLOCK_WRITE")
    else:
        print("ALLOW")
    sys.exit(0)

if found["write"]:
    print("BLOCK_WRITE")
elif found["read"] and (strict_git or not yolo):
    print("BLOCK_READ")
elif (found_rm[0] or found_sudo[0]) and not yolo:
    print("ASK_RM")
else:
    print("ALLOW")
PY
)"

case "$VERDICT" in
  BLOCK_WRITE) block_git_msg; exit 2 ;;
  BLOCK_READ)  block_read_msg; exit 2 ;;
  ASK_RM)
    # Claude Code: surface the owner's usual delete/sudo prompt (hook "ask"
    # beats the bare "Bash" allow). OpenCode: its own `rm *: ask` map prompts.
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"TechieFlow: delete/sudo asks unless YOLO is on (*yolo / tf-yolo.sh on)"}}'
    exit 0 ;;
  ALLOW|"")    exit 0 ;;
  *)
    # Unknown verdict text → original conservative behaviour.
    if printf '%s' "$INPUT" | grep -qE '(^|[^[:alnum:]_./@-])(git|gh)([^[:alnum:]_.-]|$)'; then block_git_msg; exit 2; fi
    exit 0 ;;
esac
