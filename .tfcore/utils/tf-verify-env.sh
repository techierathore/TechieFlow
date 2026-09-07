#!/usr/bin/env bash
# tf-verify-env.sh — make sure the browser tooling for a verify is present (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-env.sh [--check]
#
# Ensures, in the current project: package.json; the playwright and @playwright/test packages;
# the Chromium browser; playwright.config.ts with its output pinned under tests/.artifacts/;
# the .gitignore lines for everything this tooling generates. --check reports and changes nothing.
# Prints one line per item and READY at the end, or NOT-READY with the one command the owner
# must run once (only when a browser install needs sudo and sudo is unavailable).
# Exit 0 ready · 1 not ready · 2 node or npm missing.
set -u
CHECK=0; [[ "${1:-}" == "--check" ]] && CHECK=1
command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || { echo "NOT-READY node and npm are required"; exit 2; }
ok=1

say() { echo "  $*"; }

# package.json
if [[ ! -f package.json ]]; then
  if [[ $CHECK -eq 1 ]]; then say "package.json: missing"; ok=0; else npm init -y >/dev/null 2>&1 && say "package.json: created"; fi
else say "package.json: present"; fi

# packages
need=()
node -e "require.resolve('playwright')" >/dev/null 2>&1 || need+=("playwright")
node -e "require.resolve('@playwright/test')" >/dev/null 2>&1 || need+=("@playwright/test")
if [[ ${#need[@]} -gt 0 ]]; then
  if [[ $CHECK -eq 1 ]]; then say "packages: missing ${need[*]}"; ok=0
  else say "packages: installing ${need[*]}"; npm install -D "${need[@]}" >/dev/null 2>&1 || { say "packages: npm install failed"; ok=0; }; fi
else say "packages: playwright and @playwright/test present"; fi

# browser
if node -e "const {chromium}=require('playwright'); const p=chromium.executablePath(); require('fs').existsSync(p)?process.exit(0):process.exit(1)" >/dev/null 2>&1; then
  say "chromium: present"
else
  if [[ $CHECK -eq 1 ]]; then say "chromium: missing"; ok=0
  else
    say "chromium: installing"
    if ! npx playwright install chromium >/dev/null 2>&1; then
      if ! npx playwright install --with-deps chromium >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
          sudo npx playwright install --with-deps chromium >/dev/null 2>&1 || { say "chromium: install failed even with sudo"; ok=0; }
        else
          say "chromium: needs system libraries; run once: sudo npx playwright install --with-deps chromium"; ok=0
        fi
      fi
    fi
  fi
fi

# playwright.config.ts
CFG='import { defineConfig } from '"'"'@playwright/test'"'"';
export default defineConfig({
  testDir: '"'"'./tests/verify'"'"',
  outputDir: '"'"'./tests/.artifacts/test-results'"'"',
  reporter: '"'"'line'"'"',
  use: { headless: true, screenshot: '"'"'only-on-failure'"'"', trace: '"'"'retain-on-failure'"'"' },
});'
if [[ ! -f playwright.config.ts ]]; then
  if [[ $CHECK -eq 1 ]]; then say "playwright.config.ts: missing"; ok=0; else printf '%s\n' "$CFG" > playwright.config.ts; say "playwright.config.ts: written"; fi
elif ! grep -q "tests/.artifacts" playwright.config.ts; then
  if [[ $CHECK -eq 1 ]]; then say "playwright.config.ts: outputDir not under tests/.artifacts"; ok=0
  else
    if grep -q "outputDir" playwright.config.ts; then
      sed -i "s#outputDir:[^,]*,#outputDir: './tests/.artifacts/test-results',#" playwright.config.ts
    else
      sed -i "s#defineConfig({#defineConfig({\n  outputDir: './tests/.artifacts/test-results',#" playwright.config.ts
    fi
    say "playwright.config.ts: outputDir pinned under tests/.artifacts"
  fi
else say "playwright.config.ts: present, output pinned"; fi

# .gitignore
missing=()
for line in "node_modules/" "tests/.artifacts/" "test-results/" "playwright-report/" "/docs/.last-verify.json" ".verify/"; do
  grep -qsF -- "$line" .gitignore || missing+=("$line")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  if [[ $CHECK -eq 1 ]]; then say ".gitignore: missing ${missing[*]}"; ok=0
  else
    { [[ -f .gitignore ]] && [[ -n "$(tail -c1 .gitignore)" ]] && echo; echo "# TechieFlow agent artifacts — machine-generated test harness & logs, never commit"; printf '%s\n' "${missing[@]}"; } >> .gitignore
    say ".gitignore: added ${missing[*]}"
  fi
else say ".gitignore: complete"; fi

mkdir -p tests/.artifacts/verify tests/verify 2>/dev/null
if [[ $ok -eq 1 ]]; then echo "READY"; exit 0; else echo "NOT-READY"; exit 1; fi
