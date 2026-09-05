// Apple Silicon refuses to launch any Mach-O without a signature, and packaging
// invalidates the one Electron ships with. Without a paid Developer ID the best
// available is an ad-hoc signature: it costs nothing, and it is the difference
// between "unidentified developer" (a prompt the user can accept) and "damaged"
// (a dead end).
const { execFileSync } = require("node:child_process")
const { join } = require("node:path")

exports.default = async function adhocSign(context) {
  if (context.electronPlatformName !== "darwin") return
  const app = join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`)

  // No hardened runtime and no forced identifier: both are for Developer ID
  // builds. Under an ad-hoc signature the hardened runtime turns on library
  // validation, which then rejects the Electron framework for having no Team ID
  // — the app dies at dyld before it ever reaches Gatekeeper.
  execFileSync("codesign", ["--force", "--deep", "--sign", "-", app], {
    stdio: "inherit",
  })

  // Fail the build rather than ship a bundle that dies on launch.
  execFileSync("codesign", ["--verify", "--deep", "--strict", app], { stdio: "inherit" })
  console.log(`  • ad-hoc signed  ${app}`)
}
