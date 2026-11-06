#!/usr/bin/env python3
"""tf-testsettings.py — the verify harness's settings, read the way .NET reads appsettings (Sevak TF-015).

    python3 .tfcore/utils/tf-testsettings.py get <Key:Path> [--env-name OLD_VARIABLE]
    python3 .tfcore/utils/tf-testsettings.py pairs <Key:Path>       # NAME=VALUE per line, from an object
    python3 .tfcore/utils/tf-testsettings.py show                   # every key, passwords masked
    python3 .tfcore/utils/tf-testsettings.py set-local <Key:Path> <value>

Two files, laid one over the other key by key, as appsettings.json and appsettings.Development.json are:
  tests/verify/testsettings.json        committed; every key, with empty values
  tests/verify/testsettings.Local.json  git-ignored; this machine's real values (passwords included)
A key missing from the Local file keeps the committed value; nested objects merge, any other value
replaces. Keys are read with ':' (or '.') between levels, as `dotnet user-secrets` writes them:
`Verify:Runner`, `TestUsers:1:Password`. TF_TESTSETTINGS_DIR names another folder (the self-tests).

No environment variable is a setting (stack rules Q1 and Q11.2: appsettings-style files only). For one
release, `get --env-name OLD` still reads the old variable when the files leave the key empty, and prints
on stderr which key in testsettings.Local.json to move it to. The framework's keys:
  Verify:Runner           wsl | windows: the side of a WSL machine a web head runs on   (was TF_BOOT_RUNNER)
  Verify:BootWaitSeconds  seconds a web copy has to answer, default 120                  (was TF_BOOT_WAIT)
  Verify:WindowsAppData   the Windows %APPDATA% seen from WSL, for user-secrets          (was TF_WIN_APPDATA)
  Verify:AppEnv           {"NAME": "value"} handed to the app at boot, as --env NAME=VALUE
  Verify:Login:Path / User / Password   the screen and mockup checks' sign-in (--login-path/--user/--password)
  Verify:Login:TestUser   the Test users number to sign in as, when User is empty (its Email and Password)
  TestUsers:<n>:Email / Password / FirstName / LastName   the usage guide's Test users, by their number
  AppManager:BaseUrl / ApiKey / ApplicationId / DeviceId  for tf-register-test-users.mjs only
`get` prints the value (an empty line when unset) and exits 0; `set-local` writes only the Local file.
Python 3 standard library only.
"""
import json
import os
import re
import sys

DIR = os.environ.get("TF_TESTSETTINGS_DIR") or os.path.join("tests", "verify")
BASE = os.path.join(DIR, "testsettings.json")
LOCAL = os.path.join(DIR, "testsettings.Local.json")


def _read(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            v = json.load(f)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as e:
        sys.stderr.write(f"tf-testsettings: {path} is not valid JSON ({e}); it is ignored\n")
        return {}
    return v if isinstance(v, dict) else {}


def _layer(base, over):
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _layer(out[k], v)
        else:
            out[k] = v
    return out


def settings():
    return _layer(_read(BASE), _read(LOCAL))


def _path(key):
    return [p for p in re.split(r"[:.]", key) if p]


def lookup(tree, key):
    node = tree
    for part in _path(key):
        if isinstance(node, dict):
            # .NET configuration keys are case-insensitive
            hit = next((k for k in node if k.lower() == part.lower()), None)
            if hit is None:
                return None
            node = node[hit]
        elif isinstance(node, list) and part.isdigit() and int(part) < len(node):
            node = node[int(part)]
        else:
            return None
    return node


def text(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (dict, list)):
        return json.dumps(v)
    return str(v)


def get(key, env_name=None):
    s = settings()
    v = text(lookup(s, key))
    if key.lower().replace(".", ":") == "verify:login:user" and not v:
        n = text(lookup(s, "Verify:Login:TestUser"))
        v = text(lookup(s, f"TestUsers:{n}:Email")) if n else ""
    if key.lower().replace(".", ":") == "verify:login:password" and not v:
        n = text(lookup(s, "Verify:Login:TestUser"))
        v = text(lookup(s, f"TestUsers:{n}:Password")) if n else ""
    if not v and env_name and os.environ.get(env_name):
        sys.stderr.write(f"tf-testsettings: {env_name} is read for one more release only; move it to "
                         f"{LOCAL} as \"{key}\" (no environment variable is a setting, stack rule Q11.2)\n")
        v = os.environ[env_name]
    return v


def set_local(key, value):
    tree = _read(LOCAL)
    node = tree
    parts = _path(key)
    for part in parts[:-1]:
        hit = next((k for k in node if k.lower() == part.lower()), part)
        if not isinstance(node.get(hit), dict):
            node[hit] = {}
        node = node[hit]
    last = next((k for k in node if k.lower() == parts[-1].lower()), parts[-1])
    node[last] = value
    os.makedirs(DIR, exist_ok=True)
    tmp = LOCAL + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(tree, f, indent=2)
        f.write("\n")
    os.replace(tmp, LOCAL)


def _mask(tree):
    if isinstance(tree, dict):
        return {k: ("***" if re.search(r"(?i)password|apikey|secret|token", k) and tree[k] else _mask(tree[k])) for k in tree}
    return tree


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) >= 2 else 3
    cmd = argv[1]
    if cmd == "get" and len(argv) >= 3:
        env = argv[argv.index("--env-name") + 1] if "--env-name" in argv else None
        print(get(argv[2], env))
        return 0
    if cmd == "pairs" and len(argv) >= 3:
        v = lookup(settings(), argv[2])
        if isinstance(v, dict):
            for k, x in v.items():
                if x is not None and text(x) != "":
                    print(f"{k}={text(x)}")
        return 0
    if cmd == "show":
        print(json.dumps(_mask(settings()), indent=2))
        return 0
    if cmd == "set-local" and len(argv) >= 4:
        set_local(argv[2], argv[3])
        return 0
    print(__doc__)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
