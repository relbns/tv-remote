import { Bonjour } from "bonjour-service"
import { networkInterfaces } from "node:os"
import { Socket } from "node:net"
import { fetchDeviceInfo } from "./drivers/tizen.js"

/**
 * Two ways of finding devices, because neither alone is enough:
 *  - mDNS catches Android TV boxes and LG sets while they are awake;
 *  - a port sweep catches sets that answer on their control port but do not
 *    advertise, which is common once a TV has been asleep for a while.
 */

const PROBE_TIMEOUT = 700

function probe(host, port, timeout = PROBE_TIMEOUT) {
  return new Promise((resolve) => {
    const socket = new Socket()
    const done = (ok) => {
      socket.destroy()
      resolve(ok)
    }
    socket.setTimeout(timeout)
    socket.once("connect", () => done(true))
    socket.once("timeout", () => done(false))
    socket.once("error", () => done(false))
    socket.connect(port, host)
  })
}

/** Every IPv4 /24 this machine sits on, as a list of host addresses. */
function localSubnets() {
  const out = []
  for (const addrs of Object.values(networkInterfaces())) {
    for (const a of addrs ?? []) {
      if (a.family !== "IPv4" || a.internal) continue
      const base = a.address.split(".").slice(0, 3).join(".")
      if (!out.includes(base)) out.push(base)
    }
  }
  return out
}

export function browseMdns({ onFound, duration = 6000 } = {}) {
  const bonjour = new Bonjour()
  const seen = new Set()

  const emit = (device) => {
    const key = `${device.kind}:${device.host}`
    if (seen.has(key)) return
    seen.add(key)
    onFound?.(device)
  }

  const androidtv = bonjour.find({ type: "androidtvremote2", protocol: "tcp" }, (svc) => {
    const host = svc.referer?.address ?? svc.addresses?.find((a) => a.includes("."))
    if (host) emit({ kind: "androidtv", name: svc.name, host, port: svc.port ?? 6466 })
  })

  // LG sets do not publish an SSAP record, but they do publish AirPlay with
  // enough TXT metadata to identify the manufacturer.
  const airplay = bonjour.find({ type: "airplay", protocol: "tcp" }, async (svc) => {
    const host = svc.referer?.address ?? svc.addresses?.find((a) => a.includes("."))
    const txt = svc.txt ?? {}
    if (!host) return
    const isLg = /lg/i.test(txt.manufacturer ?? "") || /lg/i.test(svc.name)
    if (isLg && (await probe(host, 3001))) {
      emit({ kind: "webos", name: svc.name.replace(/^\[LG\]\s*/, ""), host, model: txt.model })
    }
  })

  const stop = () => {
    try {
      androidtv.stop()
      airplay.stop()
      bonjour.destroy()
    } catch {}
  }
  const timer = setTimeout(stop, duration)
  return () => {
    clearTimeout(timer)
    stop()
  }
}

/** Sweep the local /24 for the three control ports we know how to speak. */
export async function sweepNetwork({ onFound } = {}) {
  const found = []
  const targets = []
  for (const base of localSubnets()) {
    for (let i = 1; i < 255; i++) targets.push(`${base}.${i}`)
  }

  const CHECKS = [
    { port: 6466, kind: "androidtv" },
    { port: 3001, kind: "webos" },
    { port: 8002, kind: "tizen" },
  ]

  // 64 at a time: enough to cover a /24 in a couple of seconds without
  // exhausting the file-descriptor budget.
  const queue = [...targets]
  const worker = async () => {
    while (queue.length) {
      const host = queue.shift()
      for (const { port, kind } of CHECKS) {
        if (!(await probe(host, port))) continue
        let name = host
        if (kind === "tizen") {
          try {
            const info = await fetchDeviceInfo(host)
            name = info.name || name
          } catch {}
        }
        const device = { kind, name, host }
        found.push(device)
        onFound?.(device)
        break
      }
    }
  }
  await Promise.all(Array.from({ length: 64 }, worker))
  return found
}
