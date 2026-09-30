#!/usr/bin/env bash
# tf-ci-repro.sh — reproduce a CI job here the way a fresh runner runs it (Lekhak TF-019, 2026-09-30).
#
#   bash .tfcore/utils/tf-ci-repro.sh [<workflow.yml>] [--job <id>] [--list] [--keep] [--run-setup]
#
# Run from the repository root. A developer machine hides CI failures in its package caches and its
# build output: Lekhak's CI failed with NETSDK1112 because the win-x64 runtime pack was never
# downloaded, while the same commands passed locally where the pack was already cached. A local run
# with warm caches is therefore no proof that a CI failure is fixed. This script copies the repository
# without anything .gitignore ignores, to a folder outside it, points every package cache it knows
# (NuGet, npm, yarn, pnpm, pip, Go, Gradle, Maven) at an empty folder, and runs the job's `run:` steps
# in the runner's shell, stopping at the first failure. A Windows job runs Windows-side from WSL.
# `uses:` steps, steps that need a secret and steps that only install tools on the machine are
# skipped, each with the reason. --list prints the plan and runs nothing; --keep keeps the copy.
# Prints ONE verdict line last:
#   PASS     job <id>: <n> run step(s) passed on a clean copy with empty caches (…) — logs <dir>   exit 0
#   FAIL     job <id>: step <n> "<name>" failed (exit N) with empty caches — <first error> — log <file>   exit 1
#   NOT-RUN  <why: no workflow, several jobs, a macOS job off a Mac, no PyYAML …>              exit 2
# Logs: tests/.artifacts/ci-repro/<UTC time>/step-NN.log. The first run downloads every package, so
# it takes as long as a cold CI restore.
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
exec python3 "$(dirname "${BASH_SOURCE[0]}")/tf-ci-repro.py" "$@"
