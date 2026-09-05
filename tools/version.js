#!/usr/bin/env node
/**
 * One version for the whole product.
 *
 * The two clients ship separately but are the same thing to the person using
 * them, and two drifting numbers make "which version are you on?" unanswerable.
 * The root package.json holds the number; this writes it into both clients.
 *
 *   node tools/version.js 1.1.0     set a new version
 *   node tools/version.js --show    print the current one
 */
import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const rootPkgPath = join(root, "package.json")
const rootPkg = JSON.parse(readFileSync(rootPkgPath, "utf8"))

const arg = process.argv[2]

if (arg === "--show" || !arg) {
  console.log(rootPkg.version)
  process.exit(0)
}

if (!/^\d+\.\d+\.\d+$/.test(arg)) {
  console.error(`גרסה לא תקינה: ${arg} — הצורה הנדרשת היא 1.2.3`)
  process.exit(1)
}

rootPkg.version = arg
writeFileSync(rootPkgPath, `${JSON.stringify(rootPkg, null, 2)}\n`)

// --- desktop ---
const desktopPath = join(root, "desktop", "package.json")
const desktop = JSON.parse(readFileSync(desktopPath, "utf8"))
desktop.version = arg
writeFileSync(desktopPath, `${JSON.stringify(desktop, null, 2)}\n`)

// --- mobile ---
// Android refuses an update whose versionCode is not higher, so the build
// number is derived from the version rather than tracked separately: 1.2.3
// becomes 10203, which only ever increases.
const pubspecPath = join(root, "mobile", "pubspec.yaml")
const pubspec = readFileSync(pubspecPath, "utf8")
const [major, minor, patch] = arg.split(".").map(Number)
const buildNumber = major * 10000 + minor * 100 + patch
const updated = pubspec.replace(/^version: .*$/m, `version: ${arg}+${buildNumber}`)
if (updated === pubspec) {
  console.error("לא נמצאה שורת version ב-pubspec.yaml")
  process.exit(1)
}
writeFileSync(pubspecPath, updated)

console.log(`גרסה ${arg} נכתבה ל:`)
console.log("  package.json")
console.log("  desktop/package.json")
console.log(`  mobile/pubspec.yaml  (versionCode ${buildNumber})`)
