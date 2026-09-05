/**
 * Cheap load test: import every main-process module that does not need Electron,
 * and assert the shared tables resolve. A module that throws on import produces
 * an app that starts to a blank error window, which is easy to ship by accident.
 */
import { KEYS, APPS, plain } from "../src/main/shared.js"
import * as apps from "../src/main/apps.js"
import * as discovery from "../src/main/discovery.js"
import * as wol from "../src/main/wol.js"
import { isNewer, versionFromTag } from "../src/main/updates.js"

const problems = []
const check = (ok, message) => ok || problems.push(message)

check(Object.keys(plain(KEYS.androidtv)).length > 20, "keys.json: מפת Android TV נראית חסרה")
check(Object.keys(plain(KEYS.webos.buttons)).length > 10, "keys.json: מפת LG נראית חסרה")
check(Object.keys(plain(KEYS.tizen)).length > 20, "keys.json: מפת Samsung נראית חסרה")
check(Array.isArray(KEYS.routing?.preferDisplay), "keys.json: חסר routing.preferDisplay")
check(APPS.catalog?.length > 0, "apps.json: קטלוג ריק")
check(apps.ANDROID_CATALOG.every((a) => a.label && a.launch), "apps.json: רשומה בלי label או קישור")
check(!apps.isLaunchable("com.google.android.tvlauncher"), "apps.js: המשגר אמור להיות מסונן")
check(typeof discovery.sweepNetwork === "function", "discovery.js: חסר sweepNetwork")
check(typeof wol.wake === "function", "wol.js: חסר wake")

// Every command a driver can be asked for must exist somewhere in the tables.
const known = new Set([
  ...Object.keys(plain(KEYS.androidtv)),
  ...Object.keys(plain(KEYS.webos.buttons)),
  ...Object.keys(plain(KEYS.webos.requests)),
  ...Object.keys(plain(KEYS.tizen)),
])
for (const cmd of KEYS.routing.preferDisplay) {
  if (cmd === "setvolume") continue // handled directly, not via a key table
  check(known.has(cmd), `routing מפנה לפקודה שאינה במפות: ${cmd}`)
}

// The update check fails silently by design, so a wrong comparison would never
// announce itself — it would just quietly stop offering updates forever.
check(isNewer("1.0.1", "1.0.0"), "1.0.1 אמורה להיות חדשה מ-1.0.0")
check(isNewer("0.10.0", "0.9.0"), "0.10.0 אמורה להיות חדשה מ-0.9.0 (השוואה מספרית)")
check(isNewer("1.1.0", "1.0.9"), "1.1.0 אמורה להיות חדשה מ-1.0.9")
check(!isNewer("1.0.0", "1.0.0"), "גרסה זהה אינה עדכון")
check(!isNewer("0.9.0", "1.0.0"), "גרסה ישנה אינה עדכון")
check(versionFromTag("v1.2.3") === "1.2.3", "תג v1.2.3 אמור להיקרא כ-1.2.3")
check(versionFromTag("android-v1.2.3") === "1.2.3", "תג ישן עם קידומת אמור להיקרא נכון")

if (problems.length) {
  console.error("✗ " + problems.join("\n✗ "))
  process.exit(1)
}
console.log(`✓ טעינה תקינה — ${known.size} פקודות, ${APPS.catalog.length} אפליקציות בקטלוג`)
