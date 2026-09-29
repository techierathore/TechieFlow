// TechieFlow OpenCode guard bridge + telemetry — .opencode/plugin/techieflow.js
//
// Design: docs/Adapter-Design.md §2.1 (adapter boundary decision, DECISIONS.md
// 2026-08-19 §1). Runtime behaviors this file relies on were all verified
// against the DEPLOYED OpenCode 1.18.18 binary on 2026-08-20 (DECISIONS.md
// 2026-08-19 §7): local plugin files auto-load with no npm install; a `throw`
// in `tool.execute.before` blocks the tool call (the error text becomes the
// tool result, the session survives) and fires for subagent sessions too;
// `shell.env` reaches the bash child process; `message.updated` events carry
// real tokens + cost; `session.created` carries `parentID`; `session.idle`
// fires per session with the root's idle last.
//
// RULE: THIS FILE CONTAINS NO POLICY. It is a payload translator + process
// runner. The guards live in .tfcore/hooks/*.sh, unchanged, reading the same
// Claude-shaped stdin JSON they get from Claude Code's PreToolUse hooks. The
// one flag it reads itself is the YOLO switch (.tfcore/.session/yolo.json /
// TF_YOLO=1, rule .tfcore/tasks/_yolo-mode.md): while on, `permission.ask`
// auto-approves the permission map's rm/rmdir/sudo asks and TF_YOLO=1 is
// exported to tool shells so block-git.sh allows read-only git. Writes to
// git never reach this hook — they are `deny` in the map.
//   bash  {command}                        -> Bash  {command}            -> block-git.sh + guard-artifacts.sh + guard-verify-deps.sh
//   edit  {filePath,oldString,newString}   -> Edit  {file_path,old_string,new_string}
//   write {filePath,content}               -> Write {file_path,content}  -> guard-status.sh + guard-verify.sh
//   session.idle (root session)            -> Stop  {stop_hook_active, last_assistant_message, turn_started} -> guard-status-html.sh
//   session.created (first root session)   -> SessionStart              -> sweep-artifacts.sh
// OpenCode has no blocking Stop hook, so the stale-PROJECT-STATUS.html guard
// (_status-update-gate.md step 4) is bridged as a ONE-SHOT nudge: when the root
// session idles with the .html older than the .md, the guard's message is sent
// back into that session as a follow-up prompt. The second idle passes
// stop_hook_active=true (the Claude loop guard) so it can never ping-pong.
// Guard exit 2 -> throw (block, message to the model). Anything else — missing
// script, missing python3, spawn error, timeout — allows (fail-open, the same
// posture as the Claude side). Telemetry likewise NEVER blocks (tf-emit.sh has
// no veto and neither does this file).
//
// apply_patch has no Claude analogue; per Adapter-Design §2.1 the safe rule is
// to refuse it only for the two guard-protected file shapes and point the model
// at edit/write, which the guards can actually vet.
//
// The one Claude-side divergence: sessions.jsonl gets a CUMULATIVE snapshot at
// every root-session idle (a TUI session idles after each turn; `opencode run`
// idles once). Records share session_id; consumers take the record with the
// highest output_tokens (or latest ts) per session_id. SCHEMA.md §4 notes this.

//
// Two OpenCode plugin APIs, one file (2026-09-27). OpenCode 1.x (the design's 1.18.18; 1.18.32 is
// the last 1.x) reads the default export's `server`; OpenCode 2 (checked on 2.0.18, 2026-09-28)
// accepts only a default export with `id` and `setup`, and refused this file with "Plugin must export
// a default definition with an id and an effect or setup function". The default export carries all
// three; `setup` translates 2.x's hook and event API into the 1.x hooks below, so the guards, the
// shell env and telemetry are the same code in both. What 2.x does not offer: `permission.ask` (YOLO
// auto-approval; OpenCode 2's own `--auto` flag is the switch there) and the session's messages, so
// the Stop nudge's owner-text check (guard-status-html.sh check 5) is skipped there; checks 1-4 run.

import fs from "node:fs"
import path from "node:path"
import os from "node:os"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const GUARD_TIMEOUT_MS = 10000

const TechieFlowPlugin = async ({ directory, client }) => {
  const root = directory
  const hooksDir = path.join(root, ".tfcore", "hooks")
  const tfEmit = path.join(root, ".tfcore", "utils", "tf-emit.sh")
  const pointerDir = path.join(root, ".tfcore", ".session")
  const dbPath = process.env.OPENCODE_DB || path.join(os.homedir(), ".local", "share", "opencode", "opencode.db")

  // Not a TechieFlow-shaped repo -> do nothing at all (plugin may be copied anywhere).
  const active = fs.existsSync(hooksDir)

  const env = {
    ...process.env,
    CLAUDE_PROJECT_DIR: root,
    TF_PROJECT_DIR: root,
    TF_HARNESS: "opencode",
  }

  // YOLO flag: env TF_YOLO=1 (tf-goal.sh) or .tfcore/.session/yolo.json (tf-yolo.sh on).
  // The on-disk flag EXPIRES after TF_YOLO_TTL_HOURS (default 24, 0 disables) —
  // same rule and default as tf-yolo.sh `flag_live` and block-git.sh, so the two
  // harnesses never disagree about whether YOLO is on. `off` and `done` clear the
  // flag; the expiry only catches a run that was killed before either ran. TF_YOLO=1
  // is checked first and never expires, so a long supervised run is unaffected.
  function yoloOn() {
    try {
      if (process.env.TF_YOLO === "1") return true
      const flag = path.join(root, ".tfcore", ".session", "yolo.json")
      if (!fs.existsSync(flag)) return false
      const ttlHours = Number(process.env.TF_YOLO_TTL_HOURS ?? 24)
      if (!Number.isFinite(ttlHours) || ttlHours <= 0) return true
      return Date.now() - fs.statSync(flag).mtimeMs < ttlHours * 3600 * 1000
    } catch {
      return false
    }
  }

  // Returns the guard's stderr when the guard BLOCKS (exit 2), else null.
  function guardBlocks(script, payload) {
    try {
      const file = path.join(hooksDir, script)
      if (!fs.existsSync(file)) return null
      const res = spawnSync("bash", [file], {
        input: JSON.stringify(payload),
        env,
        encoding: "utf8",
        timeout: GUARD_TIMEOUT_MS,
      })
      if (res && res.status === 2) return String(res.stderr || "").trim() || "Blocked by TechieFlow guard " + script
      return null
    } catch {
      return null // fail-open
    }
  }

  // ---- telemetry state (per plugin instance = per OpenCode instance) ----
  const parents = Object.create(null) // sessionID -> parentID | null
  const msgs = Object.create(null) // messageID -> {sessionID, model, cost, in, out, cacheR, cacheW, t0, t1}
  const emitted = Object.create(null) // rootID -> output_tokens at last emit
  const htmlNudged = Object.create(null) // rootID -> true once the stale-HTML nudge was sent
  let pointerWritten = false

  // What Claude Code hands its Stop hook and OpenCode does not: the closing message, and when
  // the turn began (the last prompt the owner typed). The guard checks the message the owner
  // reads at the end of a command (tf-owner-text.sh). Empty on any failure: the check then skips.
  async function closingTurn(rootID) {
    try {
      if (typeof client.session.messages !== "function") return {}
      const res = await client.session.messages({ path: { id: rootID } })
      const list = Array.isArray(res) ? res : (res && res.data) || []
      const text = (m) => (m.parts || []).filter((x) => x.type === "text" && !x.synthetic).map((x) => x.text).join("\n")
      let message = "", turn = null
      for (const m of list) {
        const info = m.info || {}
        if (info.role === "user" && text(m).trim()) turn = (info.time || {}).created || turn
        if (info.role === "assistant" && text(m).trim()) message = text(m)
      }
      return turn ? { last_assistant_message: message, turn_started: turn } : {}
    } catch {
      return {}
    }
  }

  // Stop-hook analogue for guard-status-html.sh (see header). Never throws.
  async function nudgeStaleStatusHtml(rootID) {
    try {
      if (!client || !client.session || typeof client.session.prompt !== "function") return
      const msg = guardBlocks("guard-status-html.sh", {
        hook_event_name: "Stop",
        cwd: root,
        session_id: rootID,
        stop_hook_active: htmlNudged[rootID] === true,
        ...(htmlNudged[rootID] === true ? {} : await closingTurn(rootID)),
      })
      if (!msg) return
      htmlNudged[rootID] = true
      client.session
        .prompt({
          path: { id: rootID },
          body: {
            parts: [
              {
                type: "text",
                text:
                  "[TechieFlow harness — guard-status-html.sh]\n" +
                  msg +
                  "\n\nThis is the policy operating correctly, not an obstacle: do what each " +
                  "line above says, then finish.",
              },
            ],
          },
        })
        .catch(() => {})
    } catch {}
  }

  function rootOf(sessionID) {
    let id = sessionID
    for (let i = 0; i < 20 && parents[id]; i++) id = parents[id]
    return id
  }

  function writePointer(sessionID) {
    try {
      fs.mkdirSync(pointerDir, { recursive: true })
      fs.writeFileSync(
        path.join(pointerDir, "opencode.json"),
        JSON.stringify({ session_id: sessionID, db_path: dbPath, ts: new Date().toISOString() }) + "\n",
      )
    } catch {}
  }

  // SessionStart analogue of sweep-artifacts.sh: runs once per OpenCode instance
  // on the first root session. Deletes run material under tests/.artifacts/ and
  // .verify/ older than the retention window plus banned repo-root legacy dirs.
  // No veto: failures are swallowed; the summary line goes to stderr only.
  function sweepArtifacts(sessionID) {
    try {
      const file = path.join(hooksDir, "sweep-artifacts.sh")
      if (!fs.existsSync(file)) return
      const res = spawnSync("bash", [file], {
        input: JSON.stringify({ hook_event_name: "SessionStart", cwd: root, session_id: sessionID }),
        env,
        encoding: "utf8",
        timeout: 30000,
      })
      const summary = res && String(res.stdout || "").trim()
      if (summary) process.stderr.write(summary + "\n")
    } catch {}
  }

  function emitSession(rootID) {
    try {
      let model = null
      let modelOut = -1
      const sum = { in: 0, out: 0, cacheR: 0, cacheW: 0, cost: 0 }
      let t0 = Infinity
      let t1 = -Infinity
      const children = new Set()
      for (const id in msgs) {
        const m = msgs[id]
        if (rootOf(m.sessionID) !== rootID) continue
        if (m.sessionID !== rootID) children.add(m.sessionID)
        sum.in += m.in
        sum.out += m.out
        sum.cacheR += m.cacheR
        sum.cacheW += m.cacheW
        sum.cost += m.cost
        if (m.t0 < t0) t0 = m.t0
        if (m.t1 > t1) t1 = m.t1
        if (m.out > modelOut) {
          modelOut = m.out
          model = m.model
        }
      }
      if (sum.in + sum.out === 0) return
      if (emitted[rootID] === sum.out) return // nothing new since last snapshot
      emitted[rootID] = sum.out
      const record = {
        kind: "session",
        session_id: rootID,
        model,
        duration_s: t1 > t0 ? Math.round((t1 - t0) / 1000) : 0,
        input_tokens: sum.in,
        output_tokens: sum.out,
        cache_read_tokens: sum.cacheR,
        cache_creation_tokens: sum.cacheW,
        cost_usd: Math.round(sum.cost * 1e6) / 1e6,
        children_sessions: children.size,
      }
      if (!fs.existsSync(tfEmit)) return
      spawnSync("bash", [tfEmit, "sessions"], {
        input: JSON.stringify(record),
        env,
        encoding: "utf8",
        timeout: GUARD_TIMEOUT_MS,
      })
    } catch {}
  }

  return {
    "tool.execute.before": async (input, output) => {
      if (!active || !input || !output) return
      const args = output.args || {}
      let payload = null
      let scripts = []
      if (input.tool === "bash" || input.tool === "shell") {
        // 1.x calls it bash; 2.x calls it shell (same `command` argument)
        payload = { tool_name: "Bash", tool_input: { command: String(args.command || ""), run_in_background: !!(args.background || args.run_in_background) } }
        scripts = ["block-git.sh", "guard-artifacts.sh", "guard-status.sh", "guard-metrics.sh", "guard-db.sh", "guard-build.sh", "guard-verify-deps.sh"]
      } else if (input.tool === "edit") {
        // 1.x names the file filePath, 2.x names it path
        payload = {
          tool_name: "Edit",
          tool_input: {
            file_path: String(args.filePath || args.path || ""),
            old_string: String(args.oldString || ""),
            new_string: String(args.newString || ""),
          },
        }
        scripts = ["guard-status.sh", "guard-verify.sh", "guard-metrics.sh"]
      } else if (input.tool === "write") {
        payload = {
          tool_name: "Write",
          tool_input: { file_path: String(args.filePath || args.path || ""), content: String(args.content || "") },
        }
        scripts = ["guard-status.sh", "guard-verify.sh", "guard-metrics.sh"]
      } else if (input.tool === "apply_patch") {
        // OpenAI models edit ONLY through apply_patch (no edit/write tool), so refusing the
        // patch outright left every OpenAI run unable to update a checklist row or the status
        // file (MISS-TechieFlow-20260906-14). Instead, each file in the patch is vetted by the
        // same guards an Edit would meet: old_string = the removed lines, new_string = the
        // added lines (a new file arrives as a Write with its full content).
        const patch = String(args.patchText || "")
        const files = []
        let cur = null
        for (const raw of patch.split("\n")) {
          let m
          if ((m = raw.match(/^\*\*\* (Update|Add) File: (.+)$/))) {
            cur = { path: m[2].trim(), kind: m[1], old: [], neu: [] }
            files.push(cur)
          } else if (raw.startsWith("*** ")) {
            cur = null
          } else if (cur && raw.startsWith("+")) {
            cur.neu.push(raw.slice(1))
          } else if (cur && raw.startsWith("-")) {
            cur.old.push(raw.slice(1))
          }
        }
        for (const f of files) {
          const p =
            f.kind === "Add"
              ? { tool_name: "Write", tool_input: { file_path: f.path, content: f.neu.join("\n") } }
              : { tool_name: "Edit", tool_input: { file_path: f.path, old_string: f.old.join("\n"), new_string: f.neu.join("\n") } }
          p.hook_event_name = "PreToolUse"
          p.cwd = root
          p.session_id = input.sessionID
          for (const script of ["guard-status.sh", "guard-verify.sh", "guard-metrics.sh"]) {
            const msg = guardBlocks(script, p)
            if (msg) throw new Error(msg)
          }
        }
        return
      } else {
        return
      }
      payload.hook_event_name = "PreToolUse"
      payload.cwd = root
      payload.session_id = input.sessionID
      for (const script of scripts) {
        const msg = guardBlocks(script, payload)
        if (msg) throw new Error(msg)
      }
    },

    // YOLO / goal mode (.tfcore/tasks/_yolo-mode.md): when the flag is on, the
    // `rm * / rmdir * / sudo *` asks from the permission map are auto-approved so
    // an unattended run never stalls on a delete. Git WRITES never reach this
    // hook — they are `deny` in the map and exit-2 in block-git.sh. Fail-open:
    // if the harness never calls permission.ask, nothing changes.
    "permission.ask": async (input, output) => {
      try {
        if (!active || !output) return
        if (!yoloOn()) return
        const type = String((input && input.type) || "")
        if (type && type !== "bash") return
        output.status = "allow"
      } catch {}
    },

    "shell.env": async (input, output) => {
      try {
        if (!output || !output.env) return
        output.env.TF_HARNESS = "opencode"
        output.env.TF_PROJECT_DIR = root
        if (input && input.sessionID) output.env.TF_SESSION_ID = input.sessionID
        if (yoloOn()) output.env.TF_YOLO = "1"
      } catch {}
    },

    event: async (input) => {
      if (!active) return
      try {
        const event = input && input.event
        if (!event) return
        const p = event.properties || {}
        if (event.type === "session.created" || event.type === "session.updated") {
          const info = p.info || {}
          if (info.id) {
            parents[info.id] = info.parentID || null
            if (!info.parentID && !pointerWritten) {
              pointerWritten = true
              writePointer(info.id)
              sweepArtifacts(info.id)
            }
          }
          return
        }
        if (event.type === "message.updated") {
          const info = p.info || {}
          if (info.role !== "assistant" || !info.sessionID) return
          const t = info.tokens || {}
          const cache = t.cache || {}
          const time = info.time || {}
          const id = info.id || info.sessionID + ":" + String(time.created || "")
          msgs[id] = {
            sessionID: info.sessionID,
            model: (info.providerID ? info.providerID + "/" : "") + (info.modelID || ""),
            cost: Number(info.cost) || 0,
            in: Number(t.input) || 0,
            out: Number(t.output) || 0,
            cacheR: Number(cache.read) || 0,
            cacheW: Number(cache.write) || 0,
            t0: Number(time.created) || Date.now(),
            t1: Number(time.completed || time.created) || Date.now(),
          }
          return
        }
        if (event.type === "session.idle") {
          const sid = p.sessionID
          if (!sid) return
          if (rootOf(sid) === sid) {
            emitSession(sid)
            await nudgeStaleStatusHtml(sid)
          }
          return
        }
      } catch {} // telemetry never blocks anything
    },
  }
}

// ---- OpenCode 2.x: translate its API into the 1.x hooks above ----
// The 2.x context names no project directory, and its background service does not run in the
// project, so the root is where this file sits: <root>/.opencode/plugin/techieflow.js.
function projectRoot() {
  try {
    return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")
  } catch {
    return process.cwd()
  }
}

function eventTime(value) {
  const n = typeof value === "number" ? value : Date.parse(String(value || ""))
  return Number.isFinite(n) ? n : Date.now()
}

async function setupV2(context) {
  const root = projectRoot()
  // What the Stop nudge needs from a client: prompt a session. 2.x has no message listing, so
  // closingTurn() finds no messages and the owner-text check is skipped (see the header).
  const client = {
    session: {
      prompt: ({ path: p, body }) =>
        context.session.prompt({
          sessionID: p.id,
          text: ((body && body.parts) || []).map((x) => x.text || "").join("\n"),
        }),
    },
  }
  const hooks = await TechieFlowPlugin({ directory: root, client })
  const registrations = []

  // Guards. A throw here stops the call, as in 1.x.
  registrations.push(
    await context.tool.hook("execute.before", async (event) => {
      await hooks["tool.execute.before"]({ tool: event.tool, sessionID: event.sessionID, callID: event.id }, { args: event.input || {} })
    }),
  )

  // TF_HARNESS, TF_PROJECT_DIR, TF_YOLO for the agent's shell commands.
  registrations.push(
    await context.shell.hook("create.before", async (event) => {
      if (!event || !event.env) return
      await hooks["shell.env"]({}, { env: event.env })
    }),
  )

  // Telemetry and the Stop nudge: 2.x events rewritten as the 1.x events the handler reads.
  // A step carries its own tokens and cost; each step is recorded once, under its own key.
  // The session is created before this subscription starts, so no session.created arrives for
  // it: a session is learned the first time an event of this project names it, and its parent
  // is read with session.get (a root session has no parentID). A turn ends with
  // session.execution.*, which carries no location, so only sessions learned here count.
  const models = Object.create(null) // assistantMessageID -> {model, t0}
  const known = Object.create(null) // sessionID -> true once learned
  let stream = null
  let stopped = false
  const learn = async (sessionID) => {
    if (!sessionID || known[sessionID]) return
    known[sessionID] = true
    let parentID = null
    try {
      const info = await context.session.get({ sessionID })
      parentID = (info && info.parentID) || null
    } catch {}
    await hooks.event({ event: { type: "session.created", properties: { info: { id: sessionID, parentID } } } })
  }
  const translate = (ev) => {
    const d = ev.data || {}
    if (ev.type === "session.step.started") {
      models[d.assistantMessageID] = { model: d.model || {}, t0: eventTime(ev.created) }
      return null
    }
    if (ev.type === "session.step.ended") {
      const started = models[d.assistantMessageID] || { model: {}, t0: eventTime(ev.created) }
      const t = d.tokens || {}
      return {
        type: "message.updated",
        properties: {
          info: {
            role: "assistant",
            id: String(d.assistantMessageID) + ":" + String(ev.id),
            sessionID: d.sessionID,
            providerID: started.model.providerID,
            modelID: started.model.id,
            cost: d.cost,
            tokens: { input: t.input, output: t.output, cache: t.cache || {} },
            time: { created: started.t0, completed: eventTime(ev.created) },
          },
        },
      }
    }
    const idle =
      /^session\.execution\.(succeeded|failed|interrupted)$/.test(ev.type) ||
      (ev.type === "session.status" && d.status && d.status.type === "idle") ||
      ev.type === "session.idle"
    if (idle && known[d.sessionID]) return { type: "session.idle", properties: { sessionID: d.sessionID } }
    return null
  }
  ;(async () => {
    try {
      stream = context.event.subscribe()
      for await (const ev of stream) {
        if (stopped) break
        try {
          if (!ev) continue
          if (ev.location && ev.location.directory) {
            if (path.resolve(ev.location.directory) !== root) continue
            if (ev.data && ev.data.sessionID) await learn(ev.data.sessionID)
          }
          const event = translate(ev)
          if (event) await hooks.event({ event })
        } catch {} // telemetry never blocks anything
      }
    } catch {}
  })()

  return async () => {
    stopped = true
    try {
      if (stream && typeof stream.return === "function") await stream.return()
    } catch {}
    for (const r of registrations) {
      try {
        await r.dispose()
      } catch {}
    }
  }
}

// OpenCode 1.x reads `server`; OpenCode 2.x reads `setup`. Each ignores the other.
export default {
  id: "techieflow",
  server: TechieFlowPlugin,
  setup: setupV2,
}
