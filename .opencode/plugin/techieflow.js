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
//   bash  {command}                        -> Bash  {command}            -> block-git.sh + guard-artifacts.sh
//   edit  {filePath,oldString,newString}   -> Edit  {file_path,old_string,new_string}
//   write {filePath,content}               -> Write {file_path,content}  -> guard-status.sh + guard-verify.sh
//   session.idle (root session)            -> Stop  {stop_hook_active}   -> guard-status-html.sh
//   session.created (first root session)   -> SessionStart              -> sweep-artifacts.sh
// OpenCode has no blocking Stop hook, so the stale-PROJECT-STATUS.html guard
// (_status-update-gate.md §8) is bridged as a ONE-SHOT nudge: when the root
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

import fs from "node:fs"
import path from "node:path"
import os from "node:os"
import { spawnSync } from "node:child_process"

const GUARD_TIMEOUT_MS = 10000

export const TechieFlowPlugin = async ({ directory, client }) => {
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

  // Stop-hook analogue for guard-status-html.sh (see header). Never throws.
  function nudgeStaleStatusHtml(rootID) {
    try {
      if (!client || !client.session || typeof client.session.prompt !== "function") return
      const msg = guardBlocks("guard-status-html.sh", {
        hook_event_name: "Stop",
        cwd: root,
        session_id: rootID,
        stop_hook_active: htmlNudged[rootID] === true,
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
                  "\n\nThis is the policy operating correctly, not an obstacle: re-render " +
                  "PROJECT-STATUS.html from PROJECT-STATUS.md now, then finish.",
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
      if (input.tool === "bash") {
        payload = { tool_name: "Bash", tool_input: { command: String(args.command || "") } }
        scripts = ["block-git.sh", "guard-artifacts.sh", "guard-status.sh"]
      } else if (input.tool === "edit") {
        payload = {
          tool_name: "Edit",
          tool_input: {
            file_path: String(args.filePath || ""),
            old_string: String(args.oldString || ""),
            new_string: String(args.newString || ""),
          },
        }
        scripts = ["guard-status.sh", "guard-verify.sh"]
      } else if (input.tool === "write") {
        payload = {
          tool_name: "Write",
          tool_input: { file_path: String(args.filePath || ""), content: String(args.content || "") },
        }
        scripts = ["guard-status.sh", "guard-verify.sh"]
      } else if (input.tool === "apply_patch") {
        const patch = String(args.patchText || "")
        if (/PROJECT-STATUS\.md|-Checklist\.md/i.test(patch)) {
          throw new Error(
            "TechieFlow: apply_patch is not allowed on PROJECT-STATUS.md or *-Checklist.md — " +
              "use the edit or write tool for those files so the status/verify guards can vet the change.",
          )
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
            nudgeStaleStatusHtml(sid)
          }
          return
        }
      } catch {} // telemetry never blocks anything
    },
  }
}
