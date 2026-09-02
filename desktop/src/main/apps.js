/**
 * App shortcuts.
 *
 * The three platforms differ in what they will tell us:
 *  - webOS and Tizen enumerate their installed apps, so those lists are live.
 *  - Android TV Remote v2 has exactly one app message, RemoteAppLinkLaunchRequest,
 *    and no way to list anything. For boxes we therefore ship a catalogue of
 *    known deep links and learn the rest from the `current_app` event, which the
 *    box does emit every time the foreground app changes.
 */
import { APPS, plain } from "./shared.js"

/** Deep links that Android TV resolves to a specific app. */
export const ANDROID_CATALOG = APPS.catalog.map((a) => ({
  label: a.label,
  launch: a.androidLink,
  package: a.package,
}))

/** Package names worth showing a friendly label for when they are learned. */
const KNOWN_PACKAGES = {
  ...Object.fromEntries(APPS.catalog.map((a) => [a.package, a.label])),
  ...plain(APPS.friendlyNames),
}

/** Packages that are the launcher or a system screen — never worth a shortcut. */
const IGNORED = new Set(APPS.ignoredPackages)

export const isLaunchable = (pkg) => Boolean(pkg) && !IGNORED.has(pkg)

/** Turn a package name into something a person would recognise. */
export function labelForPackage(pkg) {
  if (KNOWN_PACKAGES[pkg]) return KNOWN_PACKAGES[pkg]
  // il.co.yes.yesplus -> "Yesplus"; last meaningful path segment, capitalised.
  const segment = pkg.split(".").filter((p) => !["com", "org", "il", "co", "net", "android", "tv", "app"].includes(p)).pop()
  if (!segment) return pkg
  return segment.charAt(0).toUpperCase() + segment.slice(1)
}

/**
 * What to send in order to launch a learned package.
 *
 * The box resolves the app_link string itself, so a catalogue deep link is used
 * when we know one; otherwise we fall back to an Android intent URI naming the
 * package directly.
 */
export function launchTargetForPackage(pkg) {
  const known = ANDROID_CATALOG.find((a) => a.package === pkg)
  return known?.launch ?? `intent:#Intent;package=${pkg};end`
}
