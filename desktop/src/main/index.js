import { app, BrowserWindow, Tray, Menu, ipcMain, globalShortcut, nativeImage, shell } from "electron"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { hub } from "./hub.js"
import * as store from "./store.js"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, "..", "..")

const WINDOW = { width: 340, height: 700 }

let tray = null
let win = null

function createWindow() {
  win = new BrowserWindow({
    ...WINDOW,
    show: false,
    frame: false,
    resizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    transparent: true,
    vibrancy: "under-window",
    visualEffectState: "active",
    roundedCorners: true,
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })

  win.loadFile(join(ROOT, "src", "renderer", "index.html"))

  // Surface renderer errors on the terminal during development; a silent
  // exception in the UI is otherwise invisible.
  if (process.env.TV_REMOTE_DEV) {
    win.webContents.on("console-message", (_e, level, message, line, source) => {
      if (level >= 2) console.error(`[renderer] ${message} (${source}:${line})`)
    })
  }
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })

  // Clicking away should dismiss the popover, but not while DevTools is open.
  win.on("blur", () => {
    if (!win.webContents.isDevToolsOpened()) hideWindow()
  })

  // Keep the app self-contained: anything external opens in the real browser.
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url)
    return { action: "deny" }
  })

  // A link without target=_blank would navigate the popover away from the app
  // with no way back, so treat any navigation off the local page the same way.
  win.webContents.on("will-navigate", (event, url) => {
    if (url.startsWith("file://")) return
    event.preventDefault()
    shell.openExternal(url)
  })

  return win
}

function positionWindow() {
  if (!tray) return
  const { x, y, width } = tray.getBounds()
  const [w] = win.getSize()
  win.setPosition(Math.round(x + width / 2 - w / 2), Math.round(y + 4), false)
}

function showWindow() {
  positionWindow()
  win.show()
  win.focus()
  win.webContents.send("window:shown")
}

function hideWindow() {
  win?.hide()
}

function toggleWindow() {
  if (win?.isVisible()) hideWindow()
  else showWindow()
}

function createTray() {
  const icon = nativeImage.createFromPath(join(ROOT, "assets", "trayTemplate.png"))
  if (icon.isEmpty()) throw new Error("אייקון שורת התפריטים לא נטען — הרץ npm run icons")
  icon.setTemplateImage(true)
  tray = new Tray(icon)
  tray.setToolTip("שלט טלוויזיה")
  tray.on("click", toggleWindow)
  tray.on("right-click", () => {
    tray.popUpContextMenu(
      Menu.buildFromTemplate([
        { label: "פתח שלט", click: showWindow },
        { type: "separator" },
        { label: "חבר מחדש את כל המכשירים", click: () => hub.connectAll() },
        { label: "פתח תיקיית הגדרות", click: () => shell.showItemInFolder(store.storePath()) },
        { type: "separator" },
        {
          label: "אודות",
          click: () => {
            showWindow()
            win.webContents.send("window:navigate", "about")
          },
        },
        { type: "separator" },
        { label: "יציאה", role: "quit" },
      ]),
    )
  })
}

/** Bridge every hub capability to the renderer, with errors marshalled as values. */
function registerIpc() {
  const handle = (channel, fn) =>
    ipcMain.handle(channel, async (_e, ...args) => {
      try {
        return { ok: true, value: await fn(...args) }
      } catch (err) {
        return { ok: false, error: err?.message ?? String(err) }
      }
    })

  handle("targets:list", () => hub.snapshot())
  handle("target:send", (id, cmd, arg) => hub.send(id, cmd, arg))
  handle("target:power", (id) => hub.power(id))
  handle("target:connect", (id) => hub.connectTarget(id))
  handle("target:apps", (id) => hub.apps(id))
  handle("target:suggested", (id) => hub.suggestedApps(id))

  handle("apps:add", (deviceId, entry) => hub.addApp(deviceId, entry))
  handle("apps:remove", (deviceId, launch) => hub.removeApp(deviceId, launch))

  handle("rooms:save", (room) => hub.saveRoom(room))
  handle("rooms:remove", (id) => hub.removeRoom(id))

  handle("devices:add", (d) => hub.addDevice(d))
  handle("devices:update", (id, patch) => hub.updateDevice(id, patch))
  handle("devices:remove", (id) => hub.removeDevice(id))
  handle("devices:connect", (id) => hub.connect(id))
  handle("devices:disconnect", (id) => hub.disconnect(id))
  handle("devices:discover", (opts) => hub.discover(opts ?? {}))
  handle("devices:pin", (id, pin) => hub.submitPin(id, pin))
  handle("devices:wake", (id) => hub.wake(id))

  handle("settings:get", () => store.getSettings())
  handle("settings:set", (k, v) => store.setSetting(k, v))
  handle("window:hide", () => hideWindow())
  handle("app:info", () => appInfo())
  handle("app:openAtLogin", () => opensAtLogin())
  handle("app:setOpenAtLogin", (enabled) => {
    setOpenAtLogin(Boolean(enabled))
    return opensAtLogin()
  })

  hub.on("devices", (devices) => win?.webContents.send("devices:changed", devices))
  hub.on("device-error", (e) => win?.webContents.send("device:error", e))
}

/** Identity for the About view, read from the manifest so it cannot drift.
 *
 * The native macOS About panel was the obvious choice and the wrong one: this
 * app has no dock presence, so the panel opened behind the popover with no way
 * to reach it, wore Electron's own icon, and had nowhere to put a link.
 */
function appInfo() {
  const manifest = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"))
  return {
    name: "שלט טלוויזיה",
    version: manifest.version,
    license: manifest.license,
    homepage: manifest.homepage,
    repository: manifest.repository?.url ?? "",
    electron: process.versions.electron,
  }
}

/** Whether the app is really registered to start when the user logs in.
 *
 * `openAtLogin` can report true for an app that is not actually registered —
 * an unsigned build run from outside /Applications, for instance. The field
 * that reflects reality is `executableWillLaunchAtLogin`, so it wins when
 * macOS provides it.
 */
function opensAtLogin() {
  const settings = app.getLoginItemSettings()
  return settings.executableWillLaunchAtLogin ?? settings.openAtLogin
}

function setOpenAtLogin(enabled) {
  app.setLoginItemSettings({
    openAtLogin: enabled,
    // A remote that reopens its window on every login would be in the way; it
    // belongs in the menu bar, waiting.
    openAsHidden: true,
  })
}

app.whenReady().then(() => {
  // A menubar utility has no business owning a Dock tile.
  app.dock?.hide()

  createWindow()
  createTray()
  registerIpc()

  const { hotkey } = store.getSettings()
  if (hotkey) globalShortcut.register(hotkey, toggleWindow)

  // Reconnect saved devices in the background so the remote is live on first open.
  hub.connectAll().catch(() => {})

  // `TV_REMOTE_DEV=1 npm start` opens the popover immediately, so the UI can be
  // worked on without chasing the menubar icon.
  if (process.env.TV_REMOTE_DEV) {
    console.log("userData:", app.getPath("userData"))
    console.log("store:", store.storePath())
    showWindow()
    if (!process.env.TV_REMOTE_SHOT) win.webContents.openDevTools({ mode: "detach" })
  }

  // TV_REMOTE_SHOT=<path> renders the popover to a PNG and exits — lets the UI
  // be checked without Screen Recording permission.
  if (process.env.TV_REMOTE_SHOT) {
    win.webContents.once("did-finish-load", () => {
      setTimeout(async () => {
        // TV_REMOTE_SHOT_JS runs in the page first, so any view can be captured.
        if (process.env.TV_REMOTE_SHOT_JS) {
          await win.webContents.executeJavaScript(process.env.TV_REMOTE_SHOT_JS)
          await new Promise((r) => setTimeout(r, 600))
        }
        const image = await win.webContents.capturePage()
        const { writeFileSync } = await import("node:fs")
        writeFileSync(process.env.TV_REMOTE_SHOT, image.toPNG())
        console.log("SHOT:" + process.env.TV_REMOTE_SHOT)
        app.exit(0)
      }, 1200)
    })
  }
})

app.on("window-all-closed", (e) => e.preventDefault())
app.on("will-quit", () => globalShortcut.unregisterAll())
