import { createAndroidRemote } from "@kud/androidtv-remote"

const host = process.argv[2]
const remote = createAndroidRemote(host, { service_name: "Mac Remote" })
let done = false
const finish = (msg, code) => {
  if (done) return
  done = true
  console.log(msg)
  try { remote.stop() } catch {}
  process.exit(code)
}

remote.on("secret", () => finish(`✅ ${host}: לחיצת יד TLS + protobuf הצליחו — הטלוויזיה מציגה קוד צימוד`, 0))
remote.on("ready",  () => finish(`✅ ${host}: כבר מצומד ומחובר`, 0))
remote.on("error",  (e) => finish(`❌ ${host}: ${e?.message || e}`, 1))

setTimeout(() => finish(`⏱  ${host}: timeout`, 1), 12000)

try { await remote.start() } catch (e) { finish(`❌ ${host}: start נכשל — ${e?.message || e}`, 1) }
