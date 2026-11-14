#!/usr/bin/env python3
"""tf-checks-model.py — the provider and model the app under test called while the checks ran (Chatur TF-028).

    python3 .tfcore/utils/tf-checks-model.py [<project-dir>]

Prints one JSON object for a run record: {"checks_provider": "...", "checks_model": "..."}, either field
left out when it is not set, {} when the project names neither. tf-verify-emit.sh and tf-fix-close.sh add
it to the run record they write (SCHEMA.md §2.5c). `model` stays the agent's own.

Read from the first of tests/verify/testsettings.Local.json, testsettings.json, test-settings.json that
names one: `testProvider: {name, model}`, or `Verify: {TestProvider: {Name, Model}}`, or the flat keys
`Verify:TestProvider:Name` / `Verify:TestProvider:Model`. Only the name and the model are read; a key,
an address or anything else in the block is never printed. Never fails: a missing or broken file is {}.
"""
import json, os, sys

FILES = ("testsettings.Local.json", "testsettings.json", "test-settings.json")


def pick(d):
    """-> (provider, model) from one settings object, or (None, None)"""
    if not isinstance(d, dict):
        return None, None
    low = {str(k).lower(): v for k, v in d.items()}
    block = low.get("testprovider")
    if block is None and isinstance(low.get("verify"), dict):
        block = {str(k).lower(): v for k, v in low["verify"].items()}.get("testprovider")
    if isinstance(block, dict):
        b = {str(k).lower(): v for k, v in block.items()}
        return b.get("name"), b.get("model")
    return low.get("verify:testprovider:name"), low.get("verify:testprovider:model")


def main(root):
    for f in FILES:
        try:
            d = json.load(open(os.path.join(root, "tests", "verify", f), encoding="utf-8-sig"))
        except (OSError, ValueError):
            continue
        prov, model = pick(d)
        out = {k: v.strip() for k, v in (("checks_provider", prov), ("checks_model", model)) if isinstance(v, str) and v.strip()}
        if out:
            return out
    return {}


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1] if len(sys.argv) > 1 else ".")))
