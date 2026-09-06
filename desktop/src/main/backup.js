/**
 * Moving a setup between installations — including between a phone and a Mac.
 *
 * The format is the one the Android client already writes, and it turned out
 * the two agree on everything that matters: the same device-kind names and the
 * same `{cert, key}` PEM pair for a pairing. So a backup taken on a phone
 * restores here, and the reverse, rather than each platform talking only to
 * itself.
 *
 * Two shapes, because they carry different risk. Settings alone are ordinary
 * data — addresses, the names you chose, your shortcuts — and small enough to
 * travel as a QR code. Adding the certificates means the other machine works
 * without walking to the television, but the file then *is* the credential.
 */
import { gzipSync, gunzipSync } from "node:zlib"
import * as store from "./store.js"

export const FORMAT_VERSION = 1

export function build({ includeCredentials }) {
  const devices = store.getDevices()
  const apps = {}
  for (const device of devices) {
    const saved = store.getApps(device.id)
    if (saved.length) apps[device.id] = saved
  }

  const backup = {
    v: FORMAT_VERSION,
    devices: devices.map(({ id, kind, name, host, mac }) => ({
      id,
      kind,
      name,
      host,
      ...(mac ? { mac } : {}),
    })),
    apps,
    // No defaultTab: the phone opens on a chosen tab, the desktop has no tabs,
    // and sending a made-up 0 would silently reset that choice on import.
  }

  const rooms = store.getRooms()
  if (rooms.length) backup.rooms = rooms

  if (includeCredentials) {
    // Each protocol proves itself differently — Android TV with a certificate
    // and key, LG with a client key, Samsung with a token — so the entry is
    // whatever that device's protocol uses, and the reader dispatches on kind.
    const certs = {}
    for (const { id, creds } of devices) {
      if (!creds) continue
      if (creds.cert && creds.key) certs[id] = { cert: creds.cert, key: creds.key }
      else if (creds.clientKey) certs[id] = { clientKey: creds.clientKey }
      else if (creds.token) certs[id] = { token: creds.token }
    }
    if (Object.keys(certs).length) backup.certs = certs
  }
  return backup
}

export const toPrettyJson = (backup) => JSON.stringify(backup, null, 2)

/** Compact form for a QR code: gzip then base64url, matching the phone. */
export const toCompact = (backup) =>
  gzipSync(Buffer.from(JSON.stringify(backup), "utf8"))
    .toString("base64url")

export function parse(text) {
  const trimmed = text.trim()
  let json
  try {
    json = JSON.parse(trimmed)
  } catch {
    try {
      json = JSON.parse(gunzipSync(Buffer.from(trimmed, "base64url")).toString("utf8"))
    } catch {
      throw new Error("הקובץ אינו גיבוי תקין")
    }
  }
  if ((json.v ?? 0) > FORMAT_VERSION) {
    throw new Error("הגיבוי נוצר בגרסה חדשה יותר של האפליקציה. עדכן ונסה שוב.")
  }
  return json
}

/**
 * Merge a backup into this installation.
 *
 * Existing pairings are never overwritten by a settings-only import: the whole
 * point of that shape is that it cannot take control away from anyone, and
 * silently clearing a working certificate would do exactly that.
 */
export function apply(backup) {
  const summary = { devices: 0, rooms: 0, shortcuts: 0, credentials: 0 }

  for (const incoming of backup.devices ?? []) {
    const existing = store.getDevice(incoming.id)
    const creds = backup.certs?.[incoming.id] ?? existing?.creds ?? null
    if (backup.certs?.[incoming.id]) summary.credentials++
    store.upsertDevice({ ...existing, ...incoming, creds })
    summary.devices++
  }

  for (const room of backup.rooms ?? []) {
    // A set whose halves did not come along would point at nothing.
    const known = (id) => !id || store.getDevice(id)
    if (!known(room.displayId) || !known(room.sourceId)) continue
    store.upsertRoom(room)
    summary.rooms++
  }

  for (const [deviceId, entries] of Object.entries(backup.apps ?? {})) {
    if (!store.getDevice(deviceId)) continue
    store.setApps(deviceId, entries)
    summary.shortcuts += entries.length
  }

  return summary
}
