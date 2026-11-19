#!/usr/bin/env python3
"""tests/develop/oc-session-fixture.py — a throw-away OpenCode session store for the dev_model case.

    python3 tests/develop/oc-session-fixture.py <db-path under tests/.artifacts> <session-id> <provider> <model>

Writes one assistant message in the shape OpenCode 2.3 keeps (session_message.data.model), so
tf-develop-watch.py session-model can be tested without the owner's own store. Never point it anywhere else.
"""
import json, os, sqlite3, sys

db, sid, prov, mid = sys.argv[1:5]
if "tests/.artifacts" not in db.replace(os.sep, "/"):
    sys.exit("oc-session-fixture: the store must sit under tests/.artifacts")
os.makedirs(os.path.dirname(db), exist_ok=True)
c = sqlite3.connect(db)
c.execute("create table if not exists session_message (id text, session_id text, type text, seq int, time_created int, time_updated int, data text)")
c.execute("insert into session_message values (?, ?, 'assistant', 1, 1, 1, ?)", ("m-" + sid, sid, json.dumps({"model": {"id": mid, "providerID": prov}})))
c.commit()
