import { EventEmitter } from "node:events"
import WebSocket from "ws"
import { KEYS as SHARED, plain } from "../shared.js"

/**
 * Samsung Tizen (2016+) — a JSON WebSocket on 8002.
 *
 * On the first connection the TV shows an "allow this device?" dialog and, once
 * accepted, hands back a token in its ms.channel.connect frame. The token is
 * stored and appended to the URL from then on.
 *
 * Written directly against `ws`: the published wrappers still pull in the
 * deprecated `request` package.
 */

const KEYS = plain(SHARED.tizen)

const b64 = (s) => Buffer.from(s, "utf8").toString("base64")

/** Read the unauthenticated info endpoint — also the cheapest liveness check. */
export async function fetchDeviceInfo(host, { timeout = 3000 } = {}) {
  const res = await fetch(`http://${host}:8001/api/v2/`, { signal: AbortSignal.timeout(timeout) })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const info = await res.json()
  return {
    name: info?.device?.name ?? null,
    model: info?.device?.modelName ?? null,
    mac: info?.device?.wifiMac ?? null,
    powered: info?.device?.PowerState ? info.device.PowerState === "on" : null,
    tokenAuth: info?.device?.TokenAuthSupport === "true",
  }
}

export class TizenDriver extends EventEmitter {
  static kind = "tizen"

  constructor(device) {
    super()
    this.device = device
    this.ws = null
    this.retry = null
    this.stopped = false
    this.status = { connected: false, powered: null, volume: null, muted: null, currentApp: null }
  }

  get capabilities() {
    return [...Object.keys(KEYS), "text", "launch"]
  }

  #update(patch) {
    this.status = { ...this.status, ...patch }
    this.emit("status", this.status)
  }

  async connect() {
    this.stopped = false
    this.#clearRetry()
    if (this.ws) await this.disconnect({ keepRetry: true })

    const params = new URLSearchParams({ name: b64("Mac Remote") })
    if (this.device.creds?.token) params.set("token", this.device.creds.token)

    const url = `wss://${this.device.host}:8002/api/v2/channels/samsung.remote.control?${params}`
    // The TV presents a self-signed certificate it will not let you replace,
    // so chain validation is off; the connection stays inside the LAN.
    const ws = new WebSocket(url, { rejectUnauthorized: false, handshakeTimeout: 8000 })
    this.ws = ws

    if (!this.device.creds?.token) this.emit("pair-required", { kind: "confirm" })

    ws.on("message", (raw) => {
      let msg
      try {
        msg = JSON.parse(raw.toString())
      } catch {
        return
      }
      if (msg.event === "ms.channel.connect") {
        this.#update({ connected: true, powered: true })
        if (msg.data?.token && msg.data.token !== this.device.creds?.token) {
          this.emit("paired", { token: String(msg.data.token) })
        }
      } else if (msg.event === "ms.channel.unauthorized") {
        this.emit("error", new Error("הטלוויזיה דחתה את הבקשה — יש לאשר את המכשיר בתפריט"))
      }
    })

    ws.on("close", () => {
      this.#update({ connected: false })
      this.#scheduleRetry()
    })
    ws.on("error", (err) => {
      this.emit("error", err)
      this.#update({ connected: false, powered: false })
    })

    await new Promise((resolve, reject) => {
      ws.once("open", resolve)
      ws.once("error", reject)
    })
  }

  #send(payload) {
    if (this.ws?.readyState !== WebSocket.OPEN) throw new Error("הטלוויזיה אינה מחוברת")
    this.ws.send(JSON.stringify(payload))
  }

  async send(cmd, arg) {
    if (cmd === "text") {
      return this.#send({
        method: "ms.remote.control",
        params: { Cmd: b64(String(arg ?? "")), DataOfCmd: "base64", TypeOfRemote: "SendInputString" },
      })
    }
    if (cmd === "launch") {
      return this.#send({
        method: "ms.channel.emit",
        params: { event: "ed.apps.launch", to: "host", data: { appId: String(arg), action_type: "DEEP_LINK" } },
      })
    }

    const key = KEYS[cmd]
    if (!key) throw new Error(`פקודה לא נתמכת: ${cmd}`)
    return this.#send({
      method: "ms.remote.control",
      params: { Cmd: "Click", DataOfCmd: key, Option: "false", TypeOfRemote: "SendRemoteKey" },
    })
  }

  async wake() {
    const { wake } = await import("../wol.js")
    if (!this.device.mac) throw new Error("אין כתובת MAC — יש להדליק ידנית פעם אחת כדי לזהות אותה")
    await wake(this.device.mac)
    // Give the panel a moment to bring its network stack up before reconnecting.
    setTimeout(() => this.connect().catch(() => {}), 4000)
  }

  #scheduleRetry() {
    if (this.retry || this.stopped) return
    this.retry = setTimeout(() => {
      this.retry = null
      this.connect().catch(() => {})
    }, 15_000)
  }

  #clearRetry() {
    if (this.retry) clearTimeout(this.retry)
    this.retry = null
  }

  async disconnect({ keepRetry = false } = {}) {
    if (!keepRetry) {
      this.stopped = true
      this.#clearRetry()
    }
    try {
      this.ws?.removeAllListeners()
      this.ws?.close()
    } catch {}
    this.ws = null
    this.#update({ connected: false })
  }
}
