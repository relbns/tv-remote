import { EventEmitter } from "node:events"
import { createAndroidRemote, RemoteKeyCode as K, RemoteDirection } from "@kud/androidtv-remote"
import { KEYS as SHARED, plain } from "../shared.js"

/**
 * Android TV Remote v2 — the protocol the yes / Google TV boxes speak.
 * Pairing is a one-time TLS handshake where the box shows a 6-character PIN;
 * the certificate it hands back is reused on every later connection.
 */

const KEYS = Object.fromEntries(
  Object.entries(plain(SHARED.androidtv)).map(([cmd, name]) => {
    // A typo in the shared table would otherwise become a button that silently
    // does nothing, so an unknown constant fails loudly at startup.
    if (K[name] === undefined) throw new Error(`keys.json: קוד לא מוכר ${name} עבור ${cmd}`)
    return [cmd, K[name]]
  }),
)

export class AndroidTvDriver extends EventEmitter {
  static kind = "androidtv"

  constructor(device) {
    super()
    this.device = device
    this.remote = null
    this.retry = null
    this.stopped = false
    // volumeMax is kept because a box that passes HDMI audio through reports a
    // maximum of 0 — the difference between "lost the command" and "nothing to turn up".
    this.status = { connected: false, powered: null, volume: null, volumeLevel: null, volumeMax: null, muted: null, currentApp: null }
  }

  get capabilities() {
    return [...Object.keys(KEYS), "text", "applink"]
  }

  #update(patch) {
    this.status = { ...this.status, ...patch }
    this.emit("status", this.status)
  }

  async connect() {
    this.#clearRetry()
    if (this.remote) await this.disconnect()
    this.stopped = false

    const remote = createAndroidRemote(this.device.host, {
      cert: this.device.creds ?? undefined,
      service_name: "Mac Remote",
      manufacturer: "Apple",
      model: "Mac",
    })
    this.remote = remote

    remote.on("secret", () => this.emit("pair-required"))
    remote.on("ready", () => {
      this.#update({ connected: true })
      // The certificate only materialises after a successful pairing; storing it
      // on every ready is harmless and covers the first-pair case.
      const creds = remote.getCertificate()
      if (creds?.cert && creds.cert !== this.device.creds?.cert) this.emit("paired", creds)
    })
    remote.on("powered", (powered) => this.#update({ powered }))
    remote.on("volume", (v) =>
      this.#update({
        volume: v.maximum ? v.level / v.maximum : null,
        volumeLevel: v.level,
        volumeMax: v.maximum,
        muted: v.muted,
      }),
    )
    remote.on("current_app", (currentApp) => this.#update({ currentApp }))
    remote.on("unpaired", () => {
      this.emit("unpaired")
      this.#update({ connected: false })
    })
    remote.on("error", (err) => {
      this.emit("error", err)
      this.#update({ connected: false })
      this.#scheduleRetry()
    })

    try {
      await remote.start()
    } catch (err) {
      this.#update({ connected: false })
      this.#scheduleRetry()
      throw err
    }
  }

  submitPin(pin) {
    if (!this.remote) throw new Error("אין חיבור פעיל")
    return this.remote.sendCode(pin.trim().toUpperCase())
  }

  async send(cmd, arg) {
    if (!this.remote || !this.status.connected) throw new Error("המכשיר אינו מחובר")

    if (cmd === "text") return this.remote.sendText(String(arg ?? ""))
    if (cmd === "applink") return this.remote.sendAppLink(String(arg ?? ""))

    const keycode = KEYS[cmd]
    if (keycode === undefined) throw new Error(`פקודה לא נתמכת: ${cmd}`)
    return this.remote.sendKey(keycode, RemoteDirection.SHORT)
  }

  async wake() {
    if (this.device.mac) {
      const { wake } = await import("../wol.js")
      await wake(this.device.mac)
    }
    if (this.status.connected) await this.send("power")
    else await this.connect()
  }

  #scheduleRetry() {
    // The box drops the socket whenever it powers down; keep a slow poll alive
    // so the remote reconnects on its own once it comes back.
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

  async disconnect() {
    this.stopped = true
    this.#clearRetry()
    try {
      this.remote?.stop()
    } catch {}
    this.remote = null
    this.#update({ connected: false })
  }
}
