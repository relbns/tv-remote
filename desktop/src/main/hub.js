import { EventEmitter } from "node:events"
import { app } from "electron"
import { AndroidTvDriver } from "./drivers/androidtv.js"
import { WebosDriver } from "./drivers/webos.js"
import { TizenDriver } from "./drivers/tizen.js"
import * as store from "./store.js"
import { browseMdns, sweepNetwork } from "./discovery.js"
import { KEYS as SHARED_KEYS } from "./shared.js"
import { ANDROID_CATALOG, isLaunchable, labelForPackage, launchTargetForPackage } from "./apps.js"

const DRIVERS = { androidtv: AndroidTvDriver, webos: WebosDriver, tizen: TizenDriver }

export const KIND_LABELS = {
  androidtv: "ממיר / Android TV",
  webos: "טלוויזיית LG",
  tizen: "טלוויזיית Samsung",
}

/** Short form for tight list rows, where the long label wraps. */
export const KIND_SHORT = { androidtv: "ממיר", webos: "LG", tizen: "Samsung" }

export const IS_DISPLAY = (kind) => kind === "webos" || kind === "tizen"

/**
 * Which half of a set a command belongs to.
 *
 * Navigation and playback belong to whatever is producing the picture — the box.
 * Volume and input belong to the screen. Either list falls back to the other
 * device when its own is missing, offline, or lacks the command: that fallback
 * is what makes volume work on a TV with no network control, since the box
 * forwards its volume keys down the HDMI cable over CEC.
 */
const PREFER_DISPLAY = new Set(SHARED_KEYS.routing.preferDisplay)

const EMPTY_STATUS = { connected: false, powered: null, volume: null, muted: null, currentApp: null }

class Hub extends EventEmitter {
  constructor() {
    super()
    this.drivers = new Map()
    this.states = new Map()
    this.pairing = new Map()
    /** Packages seen in the wild per device, so the UI can offer to save them. */
    this.seenApps = new Map()
  }

  /* ---------------- drivers ---------------- */

  #driverFor(device) {
    const existing = this.drivers.get(device.id)
    if (existing) return existing

    const Driver = DRIVERS[device.kind]
    if (!Driver) throw new Error(`סוג מכשיר לא מוכר: ${device.kind}`)

    const driver = new Driver(device, { userDataDir: app.getPath("userData") })

    driver.on("status", (status) => {
      this.states.set(device.id, status)
      if (device.kind === "androidtv" && isLaunchable(status.currentApp)) this.#noteApp(device.id, status.currentApp)
      this.#publish()
    })
    driver.on("pair-required", (info) => {
      this.pairing.set(device.id, info ?? { kind: "pin" })
      this.#publish()
    })
    driver.on("paired", (creds) => {
      store.upsertDevice({ id: device.id, creds: { ...store.getDevice(device.id)?.creds, ...creds } })
      driver.device = store.getDevice(device.id)
      this.pairing.delete(device.id)
      this.#publish()
    })
    driver.on("mac", (mac) => {
      store.upsertDevice({ id: device.id, mac })
      driver.device = store.getDevice(device.id)
    })
    driver.on("unpaired", () => {
      store.upsertDevice({ id: device.id, creds: null })
      driver.device = store.getDevice(device.id)
    })
    driver.on("error", (err) =>
      this.emit("device-error", { id: device.id, message: err?.message ?? String(err) }),
    )

    this.drivers.set(device.id, driver)
    return driver
  }

  #noteApp(deviceId, pkg) {
    const seen = this.seenApps.get(deviceId) ?? []
    if (seen.includes(pkg)) return
    this.seenApps.set(deviceId, [pkg, ...seen].slice(0, 12))
  }

  /* ---------------- snapshots ---------------- */

  #deviceSnapshot(d) {
    return {
      id: d.id,
      kind: d.kind,
      kindLabel: KIND_LABELS[d.kind] ?? d.kind,
      kindShort: KIND_SHORT[d.kind] ?? d.kind,
      isDisplay: IS_DISPLAY(d.kind),
      name: d.name,
      host: d.host,
      mac: d.mac ?? null,
      paired: Boolean(d.creds),
      pairing: this.pairing.get(d.id) ?? null,
      capabilities: this.drivers.get(d.id)?.capabilities ?? [],
      status: this.states.get(d.id) ?? EMPTY_STATUS,
    }
  }

  /**
   * Everything the remote can be pointed at: configured sets first, then any
   * device that is not part of one.
   */
  snapshot() {
    const devices = store.getDevices().map((d) => this.#deviceSnapshot(d))
    const byId = new Map(devices.map((d) => [d.id, d]))
    const rooms = store.getRooms()
    const grouped = new Set(rooms.flatMap((r) => [r.displayId, r.sourceId]))

    for (const room of rooms) {
      for (const id of [room.displayId, room.sourceId]) {
        const device = byId.get(id)
        if (device) device.roomName = room.name
      }
    }

    const targets = rooms.map((room) => {
      const display = byId.get(room.displayId) ?? null
      const source = byId.get(room.sourceId) ?? null
      const members = [display, source].filter(Boolean)
      return {
        id: room.id,
        type: "room",
        name: room.name,
        display,
        source,
        // The set can do anything either half can do.
        capabilities: [...new Set(members.flatMap((m) => m.capabilities))],
        pairing: members.find((m) => m.pairing)?.pairing ?? null,
        pairingDeviceId: members.find((m) => m.pairing)?.id ?? null,
        status: {
          connected: members.some((m) => m.status.connected),
          allConnected: members.length > 0 && members.every((m) => m.status.connected),
          powered: members.some((m) => m.status.powered),
          volume: display?.status.volume ?? source?.status.volume ?? null,
          muted: display?.status.muted ?? source?.status.muted ?? null,
          currentApp: source?.status.currentApp ?? display?.status.currentApp ?? null,
        },
      }
    })

    for (const d of devices) {
      if (grouped.has(d.id)) continue
      targets.push({
        id: d.id,
        type: "device",
        name: d.name,
        display: d.isDisplay ? d : null,
        source: d.isDisplay ? null : d,
        capabilities: d.capabilities,
        pairing: d.pairing,
        pairingDeviceId: d.pairing ? d.id : null,
        status: { ...d.status, allConnected: d.status.connected },
      })
    }

    return { targets, devices, rooms }
  }

  #publish() {
    this.emit("devices", this.snapshot())
  }

  /* ---------------- routing ---------------- */

  #resolveTarget(targetId) {
    const room = store.getRoom(targetId)
    if (room) {
      return {
        display: store.getDevice(room.displayId),
        source: store.getDevice(room.sourceId),
      }
    }
    const device = store.getDevice(targetId)
    if (!device) throw new Error("היעד לא נמצא")
    return IS_DISPLAY(device.kind) ? { display: device, source: null } : { display: null, source: device }
  }

  /** A device is usable for `cmd` only if it is connected and advertises it. */
  #usable(device, cmd) {
    if (!device) return null
    const driver = this.drivers.get(device.id)
    if (!driver || !this.states.get(device.id)?.connected) return null
    return driver.capabilities.includes(cmd) ? driver : null
  }

  async send(targetId, cmd, arg) {
    const { display, source } = this.#resolveTarget(targetId)
    // Anything not explicitly a screen command is tried on the box first.
    const order = PREFER_DISPLAY.has(cmd) ? [display, source] : [source, display]

    for (const device of order) {
      const driver = this.#usable(device, cmd)
      if (!driver) continue
      await driver.send(cmd, arg)
      return { deviceId: device.id, deviceName: device.name }
    }

    const anyConnected = [display, source].some((d) => d && this.states.get(d.id)?.connected)
    throw new Error(anyConnected ? `אף מכשיר בסט לא תומך בפקודה ${cmd}` : "אין חיבור פעיל")
  }

  /** Turn a whole set on or off with one press. */
  async power(targetId) {
    const { display, source } = this.#resolveTarget(targetId)
    const members = [display, source].filter(Boolean)
    const live = members.filter((d) => this.states.get(d.id)?.connected)

    if (!live.length) {
      // Everything is asleep: the control sockets are gone, so wake by MAC.
      const results = await Promise.allSettled(members.map((d) => this.wake(d.id)))
      if (results.every((r) => r.status === "rejected")) {
        throw new Error(results[0]?.reason?.message ?? "לא ניתן להדליק")
      }
      return { action: "on" }
    }

    // Ask each half to power down in whichever way it supports.
    await Promise.allSettled(
      live.map((d) => {
        const driver = this.drivers.get(d.id)
        const cmd = IS_DISPLAY(d.kind) ? "tvpower" : "power"
        return driver.capabilities.includes(cmd) ? driver.send(cmd) : driver.send("power")
      }),
    )
    return { action: "off" }
  }

  /* ---------------- apps ---------------- */

  /**
   * For a screen this is the real installed-app list. For a box it is the saved
   * shortcuts, since the protocol cannot enumerate anything.
   */
  async apps(targetId) {
    const { display, source } = this.#resolveTarget(targetId)

    const out = []
    if (source) {
      const saved = store.getApps(source.id)
      const list = saved.length ? saved : ANDROID_CATALOG.map(({ label, launch }) => ({ label, launch }))
      out.push({
        deviceId: source.id,
        deviceName: source.name,
        editable: true,
        live: false,
        apps: list.map((a) => ({ ...a, cmd: "applink" })),
      })
    }

    if (display) {
      const driver = this.#usable(display, "apps")
      if (driver) {
        try {
          const apps = await driver.send("apps")
          out.push({
            deviceId: display.id,
            deviceName: display.name,
            editable: false,
            live: true,
            apps: apps.map((a) => ({ label: a.title, launch: a.id, icon: a.icon, cmd: "launch" })),
          })
        } catch {
          /* the screen is up but refused the query — simply offer nothing */
        }
      }
    }

    return out
  }

  /** Packages the box has actually been seen running, minus ones already saved. */
  suggestedApps(targetId) {
    const { source } = this.#resolveTarget(targetId)
    if (!source) return []
    const saved = new Set(store.getApps(source.id).map((a) => a.package ?? a.launch))
    return (this.seenApps.get(source.id) ?? [])
      .filter((pkg) => !saved.has(pkg))
      .map((pkg) => ({
        package: pkg,
        label: labelForPackage(pkg),
        launch: launchTargetForPackage(pkg),
        deviceId: source.id,
      }))
  }

  addApp(deviceId, entry) {
    // First save on a box promotes the catalogue to real, editable entries.
    if (!store.getApps(deviceId).length) {
      store.setApps(deviceId, ANDROID_CATALOG.map(({ label, launch, package: p }) => ({ label, launch, package: p })))
    }
    store.addApp(deviceId, entry)
    this.#publish()
  }

  removeApp(deviceId, launch) {
    if (!store.getApps(deviceId).length) {
      store.setApps(deviceId, ANDROID_CATALOG.map(({ label, launch: l, package: p }) => ({ label, launch: l, package: p })))
    }
    store.removeApp(deviceId, launch)
    this.#publish()
  }

  /* ---------------- lifecycle ---------------- */

  async connect(id) {
    const device = store.getDevice(id)
    if (!device) throw new Error("המכשיר לא נמצא")
    const driver = this.#driverFor(device)
    driver.device = device
    await driver.connect()
    this.#publish()
  }

  /** Connect every half of a set, reporting the first real failure. */
  async connectTarget(targetId) {
    const { display, source } = this.#resolveTarget(targetId)
    const members = [display, source].filter(Boolean)
    const results = await Promise.allSettled(members.map((d) => this.connect(d.id)))
    const failed = results.find((r) => r.status === "rejected")
    if (failed && results.every((r) => r.status === "rejected")) throw failed.reason
  }

  async connectAll() {
    const paired = store.getDevices().filter((d) => d.creds)
    const results = await Promise.allSettled(paired.map((d) => this.connect(d.id)))
    this.#publish()
    return results
  }

  async disconnect(id) {
    await this.drivers.get(id)?.disconnect()
    this.drivers.delete(id)
    this.#publish()
  }

  async submitPin(id, pin) {
    const driver = this.drivers.get(id)
    if (!driver?.submitPin) throw new Error("המכשיר הזה אינו משתמש בקוד צימוד")
    const ok = driver.submitPin(pin)
    if (ok !== false) this.pairing.delete(id)
    this.#publish()
    return ok
  }

  async wake(id) {
    const device = store.getDevice(id)
    if (!device) throw new Error("המכשיר לא נמצא")
    return this.#driverFor(device).wake()
  }

  /* ---------------- configuration ---------------- */

  addDevice({ kind, name, host, mac = null }) {
    const id = `${kind}-${host.replace(/\./g, "-")}`
    const device = store.upsertDevice({
      id, kind, name, host, mac,
      creds: store.getDevice(id)?.creds ?? null,
    })
    this.#publish()
    return device
  }

  updateDevice(id, patch) {
    const device = store.upsertDevice({ id, ...patch })
    const driver = this.drivers.get(id)
    if (driver) driver.device = device
    this.#publish()
    return device
  }

  async removeDevice(id) {
    await this.disconnect(id)
    store.removeDevice(id)
    this.states.delete(id)
    this.pairing.delete(id)
    this.seenApps.delete(id)
    this.#publish()
  }

  saveRoom(room) {
    const saved = store.upsertRoom(room)
    this.#publish()
    return saved
  }

  removeRoom(id) {
    store.removeRoom(id)
    this.#publish()
  }

  async discover({ sweep = false } = {}) {
    const known = new Set(store.getDevices().map((d) => `${d.kind}:${d.host}`))
    const results = new Map()
    const collect = (d) => {
      const key = `${d.kind}:${d.host}`
      if (!known.has(key) && !results.has(key)) results.set(key, d)
    }

    await new Promise((resolve) => {
      const stop = browseMdns({ onFound: collect, duration: 5000 })
      setTimeout(() => {
        stop()
        resolve()
      }, 5000)
    })

    if (sweep) await sweepNetwork({ onFound: collect })

    return [...results.values()].map((d) => ({
      ...d,
      kindLabel: KIND_LABELS[d.kind] ?? d.kind,
      kindShort: KIND_SHORT[d.kind] ?? d.kind,
      isDisplay: IS_DISPLAY(d.kind),
    }))
  }
}

export const hub = new Hub()
