const { contextBridge, ipcRenderer } = require("electron")

const call = async (channel, ...args) => {
  const res = await ipcRenderer.invoke(channel, ...args)
  if (!res?.ok) throw new Error(res?.error ?? "שגיאה לא ידועה")
  return res.value
}

contextBridge.exposeInMainWorld("tv", {
  // targets = sets and standalone devices, i.e. whatever the remote can point at
  list: () => call("targets:list"),
  send: (targetId, cmd, arg) => call("target:send", targetId, cmd, arg),
  power: (targetId) => call("target:power", targetId),
  connectTarget: (targetId) => call("target:connect", targetId),
  apps: (targetId) => call("target:apps", targetId),
  suggested: (targetId) => call("target:suggested", targetId),

  addApp: (deviceId, entry) => call("apps:add", deviceId, entry),
  removeApp: (deviceId, launch) => call("apps:remove", deviceId, launch),

  saveRoom: (room) => call("rooms:save", room),
  removeRoom: (id) => call("rooms:remove", id),

  add: (device) => call("devices:add", device),
  update: (id, patch) => call("devices:update", id, patch),
  remove: (id) => call("devices:remove", id),
  connect: (id) => call("devices:connect", id),
  disconnect: (id) => call("devices:disconnect", id),
  discover: (opts) => call("devices:discover", opts),
  pin: (id, code) => call("devices:pin", id, code),
  wake: (id) => call("devices:wake", id),

  getSettings: () => call("settings:get"),
  setSetting: (k, v) => call("settings:set", k, v),
  hide: () => call("window:hide"),
  info: () => call("app:info"),
  openAtLogin: () => call("app:openAtLogin"),
  setOpenAtLogin: (enabled) => call("app:setOpenAtLogin", enabled),

  onDevices: (cb) => ipcRenderer.on("devices:changed", (_e, snapshot) => cb(snapshot)),
  onError: (cb) => ipcRenderer.on("device:error", (_e, err) => cb(err)),
  onShown: (cb) => ipcRenderer.on("window:shown", () => cb()),
  onNavigate: (cb) => ipcRenderer.on("window:navigate", (_e, view) => cb(view)),
})
