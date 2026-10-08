#!/usr/bin/env bash
# tests/develop/prove.sh — prove *develop-end-to-end for real on a small brief, in one harness.
#
#   bash tests/develop/prove.sh <work-dir> claude|opencode [--model <id>]
#
# Makes <work-dir>/<harness>/TinyTodo: a fresh folder scaffolded with TechieFlow, made a git repository
# with a local bare repository as its remote (standing in for GitHub), and the brief below. Then starts
# tf-develop.sh detached, as the flow-master's command does, and returns. Follow
# <app>/.tfcore/.session/develop.log; the result is <app>/docs/TinyTodo-Build-Report.md and
# docs/metrics/develop-report.json. The work dir must be outside every other repository.
# This is a long, paid run (Day 1 to UAT); the regression case dev_001 is the cheap check.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
W="${1:?work dir}"; H="${2:?claude|opencode}"; shift 2
case "$H" in claude|opencode) ;; *) echo "harness must be claude or opencode" >&2; exit 2 ;; esac
mkdir -p "$W/$H"; W="$(cd "$W/$H" && pwd)"
if git -C "$W" rev-parse --show-toplevel >/dev/null 2>&1; then echo "prove: $W is inside a git repository; pick a work dir outside every repository" >&2; exit 2; fi
APP="$W/TinyTodo"; REMOTE="$W/TinyTodo-remote.git"
[[ -e "$APP" ]] && { echo "prove: $APP exists; remove it or pick another work dir" >&2; exit 2; }
git init -q --bare "$REMOTE"
mkdir -p "$APP"
bash "$ROOT/scaffold-greenfield.sh" "$APP" >/dev/null 2>&1 || { echo "prove: scaffold failed" >&2; exit 1; }
git -C "$APP" init -q -b main
git -C "$APP" config user.name "TechieFlow develop proof"; git -C "$APP" config user.email "develop-proof@localhost"
git -C "$APP" remote add origin "$REMOTE"
git -C "$APP" add -A && git -C "$APP" commit -q -m "TechieFlow scaffold" && git -C "$APP" push -q -u origin main
cat > "$W/brief.md" <<'BRIEF'
TinyTodo is a single-user to-do list for the web. One screen, the task list: it shows every task with
its title and whether it is done, newest first. At the top a text box and an Add button add a task (a
title of 1 to 200 characters; an empty title is refused with a message). Each task has a checkbox that
marks it done or not done, and a Delete button that removes it after a confirmation. A filter above the
list shows All, Open or Done. Tasks are kept in the database, so they are still there after a restart.
There is no sign-in: whoever opens the app owns the list.
BRIEF
bash "$APP/.tfcore/utils/tf-develop.sh" "$APP" --app TinyTodo --brief "$W/brief.md" --harness "$H" "$@" --detach
