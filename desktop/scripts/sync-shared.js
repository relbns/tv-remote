import { copyFileSync, mkdirSync, readdirSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

/**
 * Copy the repository's shared data into the app before it runs or is packaged.
 *
 * The canonical files live in ../shared so both clients read one source, but an
 * Electron bundle can only ship files from inside its own project directory —
 * hence the copy. The destination is generated, and git-ignored.
 */
const here = dirname(fileURLToPath(import.meta.url))
const from = join(here, "..", "..", "shared")
const to = join(here, "..", "src", "shared")

mkdirSync(to, { recursive: true })
const files = readdirSync(from).filter((f) => f.endsWith(".json"))
for (const file of files) copyFileSync(join(from, file), join(to, file))
console.log(`shared: ${files.join(", ")} → src/shared/`)
