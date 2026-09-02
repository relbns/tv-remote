import { EventEmitter } from "node:events"
import { join } from "node:path"
import LGTV from "lgtv2"
import { KEYS as SHARED, plain } from "../shared.js"

/**
 * LG webOS — SSAP over a WebSocket on 3001 (TLS) / 3000.
 * First connection pops a confirmation dialog on the TV; accepting it yields a
 * client key that is stored and replayed afterwards.
 *
 * The set can only be powered *off* over the network — the WebSocket dies with
 * it — so powering on goes out as a Wake-on-LAN packet instead.
 */

// D-pad and the other physical buttons do not exist as SSAP endpoints; they go
// through the separate "pointer input" socket the TV exposes for its remote.
const BUTTONS = plain(SHARED.webos.buttons)
const REQUESTS = plain(SHARED.webos.requests)

export class WebosDriver extends EventEmitter {
  static kind = "webos"

  constructor(device, { userDataDir }) {
    super()
    this.device = device
    this.tv = null
    this.pointer = null
    this.userDataDir = userDataDir
    this.status = { connected: false, powered: null, volume: null, muted: null, currentApp: null }
  }

  get capabilities() {
    return [
      ...Object.keys(BUTTONS),
      ...Object.keys(REQUESTS),
      "tvpower",
      "input",
      "launch",
      "text",
      "applink",
      "notify",
      "setvolume",
      "apps",
      "inputs",
    ]
  }

  #update(patch) {
    this.status = { ...this.status, ...patch }
    this.emit("status", this.status)
  }

  async connect() {
    if (this.tv) await this.disconnect()

    const tv = new LGTV({
      host: this.device.host,
      clientKey: this.device.creds?.clientKey,
      // The TV serves a self-signed certificate. 'tofu' pins whatever it
      // presented first, so a later swap is caught instead of blindly trusted.
      verifyCert: "tofu",
      certFile: join(this.userDataDir, `webos-${this.device.id}.cert`),
      keyFile: join(this.userDataDir, `webos-${this.device.id}.key`),
      reconnect: 10_000,
      saveKey: (clientKey, cb) => {
        this.emit("paired", { clientKey })
        cb(null)
      },
    })
    this.tv = tv

    tv.on("prompt", () => this.emit("pair-required", { kind: "confirm" }))
    tv.on("error", (err) => this.emit("error", err))
    tv.on("close", () => {
      this.pointer = null
      this.#update({ connected: false, powered: false })
    })
    tv.on("mac", (macs) => {
      const mac = macs.wired || macs.wifi
      if (mac && mac !== this.device.mac) this.emit("mac", mac)
    })

    tv.on("connect", () => {
      this.#update({ connected: true, powered: true })
      tv.subscribe("ssap://audio/getVolume", (err, res) => {
        if (err || !res) return
        this.#update({
          volume: typeof res.volume === "number" ? res.volume / 100 : null,
          muted: res.muted ?? null,
        })
      })
      tv.subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo", (err, res) => {
        if (!err && res) this.#update({ currentApp: res.appId || null })
      })
    })

    tv.connect()
  }

  async #pointerSocket() {
    if (this.pointer) return this.pointer
    this.pointer = await this.tv.getSocket("ssap://com.webos.service.networkinput/getPointerInputSocket")
    return this.pointer
  }

  async send(cmd, arg) {
    if (!this.tv?.connected) throw new Error("הטלוויזיה אינה מחוברת")

    switch (cmd) {
      case "tvpower":
        return this.tv.request("ssap://system/turnOff")
      case "setvolume":
        return this.tv.request("ssap://audio/setVolume", { volume: Math.round(Number(arg) * 100) })
      case "launch":
        return this.tv.request("ssap://system.launcher/launch", { id: String(arg) })
      case "applink":
        return this.tv.request("ssap://system.launcher/open", { target: String(arg) })
      case "input":
        return this.tv.request("ssap://tv/switchInput", { inputId: String(arg) })
      case "notify":
        return this.tv.request("ssap://system.notifications/createToast", { message: String(arg) })
      case "apps": {
        const res = await this.tv.request("ssap://com.webos.applicationManager/listLaunchPoints")
        return (res?.launchPoints ?? []).map((p) => ({ id: p.id, title: p.title, icon: p.icon }))
      }
      case "inputs": {
        const res = await this.tv.request("ssap://tv/getExternalInputList")
        return (res?.devices ?? []).map((d) => ({ id: d.id, title: d.label || d.id }))
      }
      case "text":
        // The TV only accepts text while its on-screen keyboard has focus.
        return this.tv
          .getSocket("ssap://com.webos.service.ime/registerRemoteKeyboard")
          .then((sock) => sock.send("insertText", { text: String(arg ?? ""), replace: 0 }))
    }

    if (REQUESTS[cmd]) return this.tv.request(REQUESTS[cmd])

    if (BUTTONS[cmd]) {
      const sock = await this.#pointerSocket()
      return sock.send("button", { name: BUTTONS[cmd] })
    }

    throw new Error(`פקודה לא נתמכת: ${cmd}`)
  }

  async wake() {
    if (this.tv) return this.tv.wake()
    const { wake } = await import("../wol.js")
    if (!this.device.mac) throw new Error("אין כתובת MAC להדלקה")
    return wake(this.device.mac)
  }

  async disconnect() {
    this.pointer = null
    try {
      await this.tv?.disconnect()
    } catch {}
    this.tv = null
    this.#update({ connected: false })
  }
}
