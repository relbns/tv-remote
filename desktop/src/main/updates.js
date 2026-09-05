/**
 * Whether a newer release exists on GitHub.
 *
 * The app is installed by hand from a DMG, so nothing on the machine tells a
 * person a new version came out. Releases carry unversioned asset names, which
 * is what makes a direct download link stable across versions.
 */
import { arch } from "node:process"

const OWNER = "relbns"
const REPO = "tv-remote"

/** Strip the tag's decoration: `v1.2.3`, and older `android-v1.2.3`. */
export function versionFromTag(tag) {
  return (tag ?? "").replace(/^([a-z]+-)?v/, "")
}

/** Compare dotted versions numerically, so 0.10.0 beats 0.9.0. */
export function isNewer(candidate, installed) {
  const parts = (v) =>
    v
      .split(".")
      .slice(0, 3)
      .map((piece) => Number.parseInt(piece.replace(/[^0-9]/g, ""), 10) || 0)
  const a = parts(candidate)
  const b = parts(installed)
  for (let i = 0; i < 3; i++) {
    const left = a[i] ?? 0
    const right = b[i] ?? 0
    if (left !== right) return left > right
  }
  return false
}

export async function checkForUpdate(installed) {
  try {
    const response = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
      {
        headers: { Accept: "application/vnd.github+json" },
        signal: AbortSignal.timeout(10_000),
      },
    )
    if (!response.ok) return null

    const release = await response.json()
    const latest = versionFromTag(release.tag_name)
    if (!latest || !isNewer(latest, installed)) return null

    const asset = arch === "x64" ? "orbit-mac-x64.dmg" : "orbit-mac-arm64.dmg"
    return {
      version: latest,
      downloadUrl: `https://github.com/${OWNER}/${REPO}/releases/latest/download/${asset}`,
      notesUrl: release.html_url ?? "",
    }
  } catch {
    // Offline, rate limited, GitHub down — an update check is never worth an
    // error in someone's face.
    return null
  }
}
