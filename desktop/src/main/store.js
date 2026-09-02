import { app } from "electron"
import { readFileSync, writeFileSync, renameSync, mkdirSync } from "node:fs"
import { join, dirname } from "node:path"

let FILE = null
const file = () => (FILE ??= join(app.getPath("userData"), "devices.json"))

const SCHEMA = 2

const DEFAULTS = {
  version: SCHEMA,
  devices: [],
  rooms: [],
  apps: {},
  settings: { lastTargetId: null, hotkey: "Command+Shift+T", seenHelp: false },
}

let cache = null

/**
 * v1 kept a free-text `room` on each device and had no sets. Fold those strings
 * into real rooms, pairing each display with the source found alongside it.
 */
function migrate(saved) {
  if ((saved.version ?? 1) >= SCHEMA) return saved

  const byRoom = new Map()
  for (const device of saved.devices ?? []) {
    const key = device.room?.trim()
    if (!key) continue
    if (!byRoom.has(key)) byRoom.set(key, [])
    byRoom.get(key).push(device)
  }

  const rooms = []
  for (const [name, members] of byRoom) {
    const display = members.find((d) => d.kind === "webos" || d.kind === "tizen")
    const source = members.find((d) => d.kind === "androidtv")
    // A lone device is not a set; it stays reachable on its own.
    if (!display || !source) continue
    rooms.push({ id: `room-${rooms.length + 1}`, name, displayId: display.id, sourceId: source.id })
  }

  return {
    ...saved,
    version: SCHEMA,
    rooms,
    apps: saved.apps ?? {},
    settings: { ...DEFAULTS.settings, ...saved.settings, lastTargetId: null },
  }
}

function load() {
  if (cache) return cache
  let migrated = false
  try {
    const raw = JSON.parse(readFileSync(file(), "utf8"))
    migrated = (raw.version ?? 1) < SCHEMA
    const saved = migrate(raw)
    cache = {
      ...DEFAULTS,
      ...saved,
      settings: { ...DEFAULTS.settings, ...saved.settings },
    }
  } catch {
    cache = structuredClone(DEFAULTS)
  }
  // Write the upgraded shape back immediately, so the file on disk always
  // matches what the app is actually running on.
  if (migrated) persist()
  return cache
}

function persist() {
  mkdirSync(dirname(file()), { recursive: true })
  // Write to a sibling temp file and rename, so a crash mid-write cannot
  // truncate the file that holds the pairing certificates.
  const tmp = `${file()}.tmp`
  writeFileSync(tmp, JSON.stringify(cache, null, 2), { mode: 0o600 })
  renameSync(tmp, file())
}

export const storePath = () => file()

/* ---------------- devices ---------------- */

export const getDevices = () => load().devices
export const getDevice = (id) => load().devices.find((d) => d.id === id) ?? null

export function upsertDevice(device) {
  const devices = load().devices
  const i = devices.findIndex((d) => d.id === device.id)
  if (i === -1) devices.push(device)
  else devices[i] = { ...devices[i], ...device }
  persist()
  return getDevice(device.id)
}

export function removeDevice(id) {
  const s = load()
  s.devices = s.devices.filter((d) => d.id !== id)
  // A set without both halves is no longer a set.
  s.rooms = s.rooms.filter((r) => r.displayId !== id && r.sourceId !== id)
  delete s.apps[id]
  if (s.settings.lastTargetId === id) s.settings.lastTargetId = null
  persist()
}

/* ---------------- rooms ---------------- */

export const getRooms = () => load().rooms
export const getRoom = (id) => load().rooms.find((r) => r.id === id) ?? null

export function upsertRoom(room) {
  const rooms = load().rooms
  const id = room.id ?? `room-${Date.now().toString(36)}`
  const i = rooms.findIndex((r) => r.id === id)
  if (i === -1) rooms.push({ ...room, id })
  else rooms[i] = { ...rooms[i], ...room, id }
  persist()
  return getRoom(id)
}

export function removeRoom(id) {
  const s = load()
  s.rooms = s.rooms.filter((r) => r.id !== id)
  if (s.settings.lastTargetId === id) s.settings.lastTargetId = null
  persist()
}

/* ---------------- app shortcuts ---------------- */

export const getApps = (deviceId) => load().apps[deviceId] ?? []

export function setApps(deviceId, apps) {
  load().apps[deviceId] = apps
  persist()
  return apps
}

export function addApp(deviceId, entry) {
  const apps = getApps(deviceId)
  // `launch` is the identity: the same target added twice is one shortcut.
  if (apps.some((a) => a.launch === entry.launch)) return apps
  return setApps(deviceId, [...apps, entry])
}

export function removeApp(deviceId, launch) {
  return setApps(
    deviceId,
    getApps(deviceId).filter((a) => a.launch !== launch),
  )
}

/* ---------------- settings ---------------- */

export const getSettings = () => load().settings

export function setSetting(key, value) {
  load().settings[key] = value
  persist()
}
