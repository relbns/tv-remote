import { createSocket } from "node:dgram"

const normalize = (mac) => mac.replace(/[^0-9a-fA-F]/g, "").toLowerCase()

/**
 * Send a Wake-on-LAN magic packet: 6 × 0xFF followed by the target MAC
 * repeated 16 times. Broadcast, so it only ever reaches the local subnet.
 */
export function wake(mac, { address = "255.255.255.255", port = 9, count = 3 } = {}) {
  const hex = normalize(mac)
  if (hex.length !== 12) throw new Error(`כתובת MAC לא תקינה: ${mac}`)

  const bytes = Buffer.from(hex, "hex")
  const packet = Buffer.concat([Buffer.alloc(6, 0xff), ...Array(16).fill(bytes)])

  return new Promise((resolve, reject) => {
    const socket = createSocket("udp4")
    socket.once("error", (err) => {
      socket.close()
      reject(err)
    })
    socket.bind(() => {
      socket.setBroadcast(true)
      let sent = 0
      const fire = () => {
        socket.send(packet, 0, packet.length, port, address, (err) => {
          if (err) {
            socket.close()
            return reject(err)
          }
          if (++sent >= count) {
            socket.close()
            return resolve()
          }
          setTimeout(fire, 100)
        })
      }
      fire()
    })
  })
}
