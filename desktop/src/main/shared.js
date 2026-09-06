import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

/**
 * Loader for the repository's shared data. `npm run shared` copies ../../shared
 * into src/shared before start and before packaging; readFileSync is used rather
 * than a JSON import so it keeps working inside a packaged asar archive.
 */
const here = dirname(fileURLToPath(import.meta.url))
const read = (name) => JSON.parse(readFileSync(join(here, "..", "shared", name), "utf8"))

/** Strip the "$comment" documentation keys before a map is used as data. */
export const plain = (obj) =>
  Object.fromEntries(Object.entries(obj).filter(([k]) => !k.startsWith("$")))

export const KEYS = read("keys.json")
export const APPS = read("apps.json")
export const HELP = read("help.json")
export const CHANNELS = read("channels.json")
