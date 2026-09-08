# _smoke-test-policy (shared rule — every task that builds or fixes code)

Every code change is smoke-tested by the agent that made it, in the same session, before it is handed to the verifier or called done. A green build is not a smoke test. A smoke test boots the application, exercises the changed feature once, and looks at the screen.

## What passes

A screen passes only if all three hold, at a desktop width and a mobile width:

1. Every data-bound control shows its data: rows with values, not a count over an empty table, not a placeholder.
2. Nothing overlaps, nothing is clipped or off-screen, nothing renders unstyled. Take a screenshot and look at it.
3. The screen maps to its mockup control by control (`docs/mockups/<screen>.html`, as listed in the UIDesign).

A failure on any of the three is a defect: write it into the row's Remarks (prefix `⚠ visual:` for 2 and 3) and do not report the row done. A smoke earns a row at most `Implemented`; only an executed verify run writes `Verified`.

The evidence of a smoke is the file `bash .tfcore/utils/tf-verify-screens.sh --screen <name>=<route> … --base <url>` writes (`tests/.artifacts/verify/screens.json`, with a screenshot per screen and width); a row is written `Implemented` only after that run, and its Remark names the file. The application is booted with `bash .tfcore/utils/tf-verify-boot.sh start`, which also drives an embedded-browser desktop head Windows head; a head the script cannot boot leaves the row below `Implemented` with the reason.

## Run it yourself

The build ladder (`.tfcore/templates/v4custom/build-invocation-ladder.md`) says how to build, run and reach the running UI on every supported host, including native and mobile heads. Follow it. A dependent service that is down is something you start, from its own configuration, in dependency order. Ask the owner to run something only after the ladder's last rung has failed, and then still run the smoke yourself once they answer.

## Test users

Resolve credentials in this order and stop at the first that works:

1. The Test users table in `docs/<App>-UsageGuide.md`.
2. An existing account in the database, read with the connection string from the configuration.
3. Ask the owner, showing what you would create.
4. Only after a yes, create it and add it to the Test users table.

Never invent a throwaway account.

## Say what ran

Name the exact command and where it ran: which host, which rung, focused tests or the full build, your own smoke or an executed verify. A green intermediate step is not a pass of the whole.
