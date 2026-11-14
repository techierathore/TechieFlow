#!/usr/bin/env python3
"""tests/faults/secrets/scan.py — run every script in a utils folder against a project full of fake secrets.

    python3 tests/faults/secrets/scan.py <utils-dir> <scratch-dir>

AppManager, 2026-11-13: tf-verify-list.sh printed the two test users' passwords from the UsageGuide into
the session. The rule since: no framework script prints a password, a key, a token or a connection
string; it prints the name and whether it is set. This builds a project (<scratch-dir>/fx) holding a
fake secret in every place a project keeps one (the usage guide's Test users table, the TestNUsageDoc,
both test settings files, the provider settings, appsettings, .env, the environment), copies the
scripts into its .tfcore/utils, and runs each one there with no arguments, with the app's name, with
the app and `all`, and with --help. Commands that reach outside the machine or start an app (git,
dotnet, npx, npm, curl, claude, opencode, powershell) are stand-ins that do nothing. Each run has 20 s.

Prints one line per script and argument set that printed a secret: `LEAK <script> <args>: <secret name>`
(the name of the fake, never anything real), then `scanned N runs of M scripts, K leaks`. Exit 0 no
leak, 1 a leak, 2 could not run.
"""
import json, os, shutil, stat, subprocess, sys

FAKES = {  # name -> value: every value starts FAKE-SECRET so a leak is unmistakable
    "usage-guide password": "FAKE-SECRET-pw-usage-guide-7d1",
    "TestNUsageDoc password": "FAKE-SECRET-pw-testn-doc-4c2",
    "testsettings password": "FAKE-SECRET-pw-settings-9a8",
    "testsettings test user password": "FAKE-SECRET-pw-testuser-3e5",
    "Local settings password": "FAKE-SECRET-pw-local-6b0",
    "Local settings API key": "FAKE-SECRET-key-local-2f9",
    "Local settings token": "FAKE-SECRET-token-local-8c4",
    "AppManager API key": "FAKE-SECRET-key-appmanager-5a1",
    "provider key": "FAKE-SECRET-key-provider-1d7",
    "connection string password": "FAKE-SECRET-cs-appsettings-0e3",
    "JWT signing key": "FAKE-SECRET-key-jwt-4b6",
    ".env key": "FAKE-SECRET-key-dotenv-2a2",
    "environment key": "FAKE-SECRET-key-environ-9f1",
}
STUBS = ("git", "dotnet", "npx", "npm", "curl", "claude", "opencode", "powershell.exe", "cmd.exe", "pwsh",
         "open", "xdg-open", "wslpath", "osascript", "xcrun", "appium", "gh", "sqlcmd", "psql")
ARGS = ([], ["Fx"], ["Fx", "all"], ["--help"])
SKIP = {"tf-cdp-relay.ps1"}   # PowerShell, run on Windows by the boot script only


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def build(fx, utils):
    f = FAKES
    w(f"{fx}/docs/Fx-Checklist.md", "# Fx — Checklist\n\n| ID | Title | Status | % | Screen | Remarks |\n|---|---|---|---|---|---|\n"
      "| REQ-UI-001 | Sign in | Implemented | 90 | Sign in | |\n| REQ-FN-001 | Save | Verified | 100 | Home | |\n")
    w(f"{fx}/docs/Fx-UsageGuide.md", "# Fx — Usage guide\n\n## Test users\n\n| # | User | Password | Role |\n|---|---|---|---|\n"
      f"| 1 | admin@fx.app | {f['usage-guide password']} | Admin |\n| 2 | tester@fx.app | {f['usage-guide password']} | User |\n")
    w(f"{fx}/docs/Fx-TestNUsageDoc.md", "# Fx — Test & Usage Document\n\n## 2. Test User Accounts\n\n### Account Setup\n\n"
      f"| # | Email | Password | Role |\n|---|---|---|---|\n| 1 | admin@fx.app | {f['TestNUsageDoc password']} | Admin |\n")
    w(f"{fx}/tests/verify/testsettings.json", json.dumps({
        "Verify": {"BaseUrl": "http://127.0.0.1:9", "Login": {"Path": "/signin", "User": "admin@fx.app", "Password": f["testsettings password"]}},
        "TestUsers": {"1": {"Email": "admin@fx.app", "Password": f["testsettings test user password"]}, "2": {"Email": "new@fx.app"}},
        "AppManager": {"BaseUrl": "http://127.0.0.1:9", "ApiKey": f["AppManager API key"], "ApplicationId": "4"}}, indent=1))
    w(f"{fx}/tests/verify/testsettings.Local.json", json.dumps({
        "Verify": {"Login": {"Password": f["Local settings password"]}}, "ApiKey": f["Local settings API key"],
        "Token": f["Local settings token"]}, indent=1))
    w(f"{fx}/tests/verify/test-settings.json", json.dumps({"testProvider": {"name": "Fake", "model": "fake-model-1", "key": f["provider key"]}}))
    w(f"{fx}/tests/verify/a.spec.ts", "test('REQ-UI-001 signs in', async ({ page }) => { await page.goto(process.env.BASE_URL); });\n")
    app = {"ConnectionStrings": {"Default": f"Server=db;User Id=sa;Password={f['connection string password']}"},
           "Jwt": {"Key": f["JWT signing key"]}, "AppManager": {"ApiKey": f["AppManager API key"]}}
    w(f"{fx}/src/Fx/appsettings.json", json.dumps(app, indent=1))
    w(f"{fx}/src/Fx/appsettings.Development.json", json.dumps(app, indent=1))
    w(f"{fx}/src/Fx/Fx.csproj", '<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><UserSecretsId>fx-fake</UserSecretsId></PropertyGroup></Project>\n')
    w(f"{fx}/.env", f"API_KEY={f['.env key']}\n")
    w(f"{fx}/.tfcore/core-config.yaml", "appName: Fx\nappSize: S\nappKind: app\nappPhase: 1\n")
    for s in ("runs", "gates", "sessions", "commits", "misses"):
        w(f"{fx}/docs/metrics/{s}.jsonl", "")
    shutil.copytree(utils, f"{fx}/.tfcore/utils", ignore=shutil.ignore_patterns("__pycache__"))
    for n in STUBS:
        w(f"{fx}/.stubs/{n}", "#!/usr/bin/env bash\nexit 0\n")
        os.chmod(f"{fx}/.stubs/{n}", os.stat(f"{fx}/.stubs/{n}").st_mode | stat.S_IEXEC)
    os.makedirs(f"{fx}/.home", exist_ok=True)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    utils, scratch = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    fx = os.path.join(scratch, "fx")
    shutil.rmtree(fx, ignore_errors=True)
    build(fx, utils)
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_PROJECT_DIR", "TF_PROJECT_DIR", "TF_YOLO")}
    env.update({"PATH": f"{fx}/.stubs:" + env.get("PATH", ""), "HOME": f"{fx}/.home", "TF_METRICS_ROOT": fx,
                "TF_SKIP_SELFCHECK": "1", "OPENAI_API_KEY": FAKES["environment key"], "ANTHROPIC_API_KEY": FAKES["environment key"]})
    scripts = sorted(n for n in os.listdir(f"{fx}/.tfcore/utils") if n.endswith((".sh", ".py", ".mjs", ".ps1")) and n not in SKIP)
    leaks = runs = 0
    for n in scripts:
        run = {".sh": ["bash"], ".py": ["python3"], ".mjs": ["node"]}[os.path.splitext(n)[1]]
        for a in ARGS:
            runs += 1
            try:
                p = subprocess.run(run + [f".tfcore/utils/{n}"] + a, cwd=fx, env=env, stdin=subprocess.DEVNULL,
                                   capture_output=True, timeout=20)
                out = (p.stdout + p.stderr).decode("utf-8", "replace")
            except subprocess.TimeoutExpired as e:
                out = ((e.stdout or b"") + (e.stderr or b"")).decode("utf-8", "replace")
            except OSError as e:
                out = str(e)
            for name, val in FAKES.items():
                if val in out:
                    leaks += 1
                    print(f"LEAK {n} {' '.join(a) or '(no arguments)'}: {name}")
    print(f"scanned {runs} runs of {len(scripts)} scripts, {leaks} leak(s)")
    return 1 if leaks else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
