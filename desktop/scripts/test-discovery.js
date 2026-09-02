import { browseMdns, sweepNetwork } from "../src/main/discovery.js"

console.log("mDNS (6 שניות)…")
const viaMdns = []
await new Promise((r) => {
  const stop = browseMdns({ onFound: (d) => { viaMdns.push(d); console.log("  •", d.kind, "|", d.name, "|", d.host) } })
  setTimeout(() => { stop(); r() }, 6000)
})

console.log("\nסריקת פורטים ברשת…")
const t = Date.now()
const viaSweep = await sweepNetwork({ onFound: (d) => console.log("  •", d.kind, "|", d.name, "|", d.host) })
console.log(`\nmDNS: ${viaMdns.length} | סריקה: ${viaSweep.length} (${((Date.now() - t) / 1000).toFixed(1)} שניות)`)
process.exit(0)
