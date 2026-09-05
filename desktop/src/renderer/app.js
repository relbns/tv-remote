"use strict"

const KEYMAP = {
  ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  Enter: "ok", Backspace: "back", " ": "playpause",
  PageUp: "chup", PageDown: "chdown",
  h: "home", m: "mute", "+": "volup", "=": "volup", "-": "voldown",
}

const $ = (s) => document.querySelector(s)
const $$ = (s) => [...document.querySelectorAll(s)]

const el = {
  select: $("#target-select"), dots: $("#status-dots"), toast: $("#toast"),
  pairTitle: $("#pair-title"), pairHelp: $("#pair-help"), pinRow: $("#pair-pin-row"), pin: $("#pin-input"),
  apps: $("#apps-row"), appsEmpty: $("#apps-empty"), text: $("#text-input"),
  hint: $("#hint"), routing: $("#routing-note"), mute: $("#mute-btn"), volRead: $("#vol-read"),
  roomList: $("#room-list"), deviceList: $("#device-list"), foundList: $("#found-list"),
  roomDisplay: $("#room-display"), roomSource: $("#room-source"), roomName: $("#room-name"),
  savedApps: $("#saved-apps"), suggestList: $("#suggest-list"), suggestBlock: $("#suggest-block"),
}

const VIEWS = ["remote-view", "pair-view", "apps-view", "settings-view", "help-view"]

let snapshot = { targets: [], devices: [], rooms: [] }
let currentId = null
let appGroups = []
let viewStack = ["remote-view"]
let toastTimer = null

const current = () => snapshot.targets.find((t) => t.id === currentId) ?? null

/* ---------------- views ---------------- */

function showView(name, { replace = false } = {}) {
  if (replace) viewStack[viewStack.length - 1] = name
  else if (viewStack[viewStack.length - 1] !== name) viewStack.push(name)
  paintView()
}

function goBack() {
  if (viewStack.length > 1) viewStack.pop()
  paintView()
}

function paintView() {
  const target = current()
  let active = viewStack[viewStack.length - 1]
  // Pairing is a state of the device, not a place the user navigated to.
  if (active === "remote-view" && target?.pairing) active = "pair-view"
  if (active === "pair-view" && !target?.pairing) active = "remote-view"

  for (const id of VIEWS) $(`#${id}`).hidden = id !== active
  if (active === "settings-view") renderSettings()
  if (active === "apps-view") renderAppsManager()
}

/* ---------------- helpers ---------------- */

function toast(message, kind = "error") {
  el.toast.textContent = message
  el.toast.className = `toast ${kind === "info" ? "info" : ""}`
  el.toast.hidden = false
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => (el.toast.hidden = true), 4200)
}

async function guard(promise, infoMessage) {
  try {
    if (infoMessage) toast(infoMessage, "info")
    return await promise
  } catch (err) {
    toast(err.message)
  }
}

/* ---------------- remote ---------------- */

function renderPicker() {
  el.select.innerHTML = ""
  for (const t of snapshot.targets) {
    const option = document.createElement("option")
    option.value = t.id
    option.textContent = t.type === "room" ? `${t.name} (סט)` : t.name
    el.select.append(option)
  }
  if (!snapshot.targets.length) {
    const option = document.createElement("option")
    option.value = ""
    option.textContent = "אין מכשירים — פתח הגדרות"
    el.select.append(option)
  }
  el.select.value = snapshot.targets.some((t) => t.id === currentId) ? currentId : snapshot.targets[0]?.id ?? ""
  currentId = el.select.value || null
}

function renderDots() {
  const t = current()
  el.dots.innerHTML = ""
  if (!t) return
  const members = t.type === "room" ? [t.source, t.display].filter(Boolean) : [t.source ?? t.display].filter(Boolean)
  for (const m of members) {
    const dot = document.createElement("span")
    dot.className = `dot ${m.pairing ? "pairing" : m.status.connected ? "on" : "off"}`
    dot.title = `${m.name} — ${m.pairing ? "ממתין לצימוד" : m.status.connected ? "מחובר" : "מנותק"} · ${m.host}`
    el.dots.append(dot)
  }
}

function renderRemote() {
  const t = current()
  const caps = new Set(t?.capabilities ?? [])
  const connected = Boolean(t?.status.connected)

  el.mute.textContent = t?.status.muted ? "🔈" : "🔇"

  // Show what the device reports. A maximum of 0 means the volume keys have
  // nothing to act on, which is worth saying rather than leaving to guesswork.
  const max = t?.status.volumeMax
  el.volRead.hidden = max === null || max === undefined
  el.volRead.textContent = max === 0 ? "אין" : String(t?.status.volumeLevel ?? "")

  for (const button of $$("#remote-view [data-cmd]")) {
    const supported = !t || !caps.size || caps.has(button.dataset.cmd)
    button.hidden = !supported
    button.disabled = !connected || !supported
  }
  el.text.disabled = !connected || !caps.has("text")
  $("#text-send").disabled = el.text.disabled

  const app = t?.status.currentApp
  el.hint.textContent = app
    ? `פועל כעת: ${app}`
    : "מקלדת: חיצים · Enter · Backspace לחזרה · רווח לנגן · Esc לסגירה"

  // Say out loud which half of the set gets what, so the routing is never a mystery.
  if (t?.type === "room" && t.source && t.display) {
    el.routing.hidden = false
    el.routing.textContent = `ניווט → ${t.source.name} · עוצמה ומסך → ${t.display.name}`
  } else {
    el.routing.hidden = true
  }
}

function renderPairing() {
  const t = current()
  if (!t?.pairing) return
  const needsPin = t.pairing.kind !== "confirm"
  const who = t.type === "room" ? [t.source, t.display].find((m) => m?.pairing)?.name ?? "" : t.name
  el.pairTitle.textContent = needsPin ? `הזן את הקוד מהמסך — ${who}` : `אשר את החיבור — ${who}`
  el.pairHelp.textContent = needsPin
    ? "על מסך הטלוויזיה מופיע קוד בן 6 תווים. הקלד אותו כאן. הצימוד נדרש פעם אחת בלבד."
    : "בטלוויזיה הופיעה בקשת אישור — אשר אותה עם השלט המקורי. פעם אחת בלבד."
  el.pinRow.hidden = !needsPin
  if (needsPin && document.activeElement !== el.pin) el.pin.focus()
}

async function refreshApps() {
  const t = current()
  el.apps.innerHTML = ""
  appGroups = []
  if (!t) {
    el.appsEmpty.hidden = true
    return
  }
  // A box's shortcuts are stored locally, so they are listed even while it is
  // offline; only a screen's live list needs a connection, and the hub omits it.
  try {
    appGroups = await window.tv.apps(t.id)
  } catch {
    return
  }

  const flat = appGroups.flatMap((g) => g.apps.map((a) => ({ ...a, deviceName: g.deviceName, live: g.live })))
  for (const entry of flat.slice(0, 9)) {
    const button = document.createElement("button")
    button.className = "pill"
    button.textContent = entry.label
    button.disabled = !t.status.connected
    button.title = entry.live ? `${entry.deviceName} · מותקן` : `${entry.deviceName} · ${entry.launch}`
    button.onclick = () => run(entry.cmd, entry.launch)
    el.apps.append(button)
  }
  el.appsEmpty.hidden = flat.length > 0
}

function flash(cmd) {
  const button = $(`#remote-view [data-cmd="${cmd}"]`)
  if (!button) return
  button.classList.add("flash")
  setTimeout(() => button.classList.remove("flash"), 120)
}

async function run(cmd, arg) {
  const t = current()
  if (!t) return
  flash(cmd)
  try {
    await window.tv.send(t.id, cmd, arg)
  } catch (err) {
    toast(err.message)
  }
}

/* ---------------- apps manager ---------------- */

async function renderAppsManager() {
  const t = current()
  if (!appGroups.length && t) await refreshApps()
  el.savedApps.innerHTML = ""
  el.suggestList.innerHTML = ""
  el.suggestBlock.hidden = true
  if (!t) return

  for (const group of appGroups) {
    for (const entry of group.apps) {
      const row = document.createElement("div")
      row.className = "device-row"
      row.innerHTML = `<span class="dot on"></span>
        <div><div class="name"></div><div class="meta"></div></div>
        <div class="actions"></div>`
      row.querySelector(".name").textContent = entry.label
      row.querySelector(".meta").textContent = group.live
        ? `${group.deviceName} · מותקן במסך`
        : `${group.deviceName} · ${entry.launch}`
      if (group.editable) {
        const remove = document.createElement("button")
        remove.className = "danger"
        remove.textContent = "הסר"
        remove.onclick = async () => {
          await guard(window.tv.removeApp(group.deviceId, entry.launch))
          await refreshApps()
          renderAppsManager()
        }
        row.querySelector(".actions").append(remove)
      }
      el.savedApps.append(row)
    }
  }

  const suggestions = await window.tv.suggested(t.id).catch(() => [])
  if (suggestions.length) {
    el.suggestBlock.hidden = false
    for (const s of suggestions) {
      const row = document.createElement("div")
      row.className = "device-row"
      row.innerHTML = `<span class="dot pairing"></span>
        <div><div class="name"></div><div class="meta"></div></div>
        <div class="actions"></div>`
      row.querySelector(".name").textContent = s.label
      row.querySelector(".meta").textContent = s.package
      const add = document.createElement("button")
      add.textContent = "שמור"
      add.onclick = async () => {
        await guard(window.tv.addApp(s.deviceId, { label: s.label, launch: s.launch, package: s.package }))
        await refreshApps()
        renderAppsManager()
      }
      row.querySelector(".actions").append(add)
      el.suggestList.append(row)
    }
  }
}

/* ---------------- settings ---------------- */

function renderSettings() {
  el.roomList.innerHTML = ""
  for (const room of snapshot.rooms) {
    const target = snapshot.targets.find((t) => t.id === room.id)
    const row = document.createElement("div")
    row.className = "device-row"
    row.innerHTML = `<span class="dot ${target?.status.allConnected ? "on" : "off"}"></span>
      <div><div class="name"></div><div class="meta"></div></div>
      <div class="actions"></div>`
    row.querySelector(".name").textContent = room.name
    row.querySelector(".meta").textContent =
      `${target?.source?.name ?? "—"} + ${target?.display?.name ?? "—"}`
    const remove = document.createElement("button")
    remove.className = "danger"
    remove.textContent = "פרק"
    remove.onclick = () => guard(window.tv.removeRoom(room.id))
    row.querySelector(".actions").append(remove)
    el.roomList.append(row)
  }

  const fill = (select, list, placeholder) => {
    select.innerHTML = ""
    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = placeholder
    select.append(blank)
    for (const d of list) {
      const option = document.createElement("option")
      option.value = d.id
      option.textContent = d.name
      select.append(option)
    }
  }
  fill(el.roomDisplay, snapshot.devices.filter((d) => d.isDisplay), "בחר מסך")
  fill(el.roomSource, snapshot.devices.filter((d) => !d.isDisplay), "בחר ממיר")

  el.deviceList.innerHTML = ""
  for (const d of snapshot.devices) {
    const row = document.createElement("div")
    row.className = "device-row"
    row.innerHTML = `<span class="dot ${d.status.connected ? "on" : "off"}"></span>
      <div><div class="name"></div><div class="meta"></div></div>
      <div class="actions">
        <button class="reconnect"></button><button class="danger remove">הסר</button>
      </div>`
    row.querySelector(".name").textContent = d.name
    row.querySelector(".meta").textContent = [
      d.kindShort,
      d.host,
      d.roomName ? `בסט "${d.roomName}"` : null,
      d.paired ? null : "לא מצומד",
    ].filter(Boolean).join(" · ")
    const connectBtn = row.querySelector(".reconnect")
    // An unpaired device is not "reconnecting" — pressing this starts pairing.
    connectBtn.textContent = d.paired ? "חבר" : "צמד"
    connectBtn.onclick = () => guard(window.tv.connect(d.id), d.paired ? `מתחבר ל${d.name}…` : `מתחיל צימוד…`)
    row.querySelector(".remove").onclick = () => guard(window.tv.remove(d.id))
    el.deviceList.append(row)
  }
}

/* ---------------- wiring ---------------- */

function render() {
  renderPicker()
  renderDots()
  renderRemote()
  renderPairing()
  paintView()
}

document.addEventListener("click", (event) => {
  const cmdButton = event.target.closest("#remote-view [data-cmd]")
  if (cmdButton && !cmdButton.disabled) return run(cmdButton.dataset.cmd)

  if (event.target.closest("[data-back]")) return goBack()

  const helpLink = event.target.closest("[data-help]")
  if (helpLink) {
    showView("help-view")
    const section = $(`#help-${helpLink.dataset.help}`)
    if (section) {
      section.open = true
      section.scrollIntoView({ block: "start" })
    }
  }
})

el.select.onchange = async () => {
  currentId = el.select.value
  window.tv.setSetting("lastTargetId", currentId)
  render()
  await refreshApps()
}

$("#power-btn").onclick = async () => {
  const t = current()
  if (!t) return
  const res = await guard(window.tv.power(t.id))
  if (res?.action === "on") toast("נשלח אות הדלקה", "info")
}

$("#pin-submit").onclick = async () => {
  const t = current()
  if (!t?.pairingDeviceId) return
  await guard(window.tv.pin(t.pairingDeviceId, el.pin.value))
  el.pin.value = ""
}
el.pin.onkeydown = (e) => {
  e.stopPropagation()
  if (e.key === "Enter") $("#pin-submit").click()
}

$("#text-send").onclick = () => {
  if (!el.text.value) return
  run("text", el.text.value)
  el.text.value = ""
}
el.text.onkeydown = (e) => {
  e.stopPropagation()
  if (e.key === "Enter") $("#text-send").click()
}

$("#settings-btn").onclick = () => showView("settings-view")

$("#about-btn").onclick = () => window.tv.about()

// Reflect the real login-item state rather than a remembered one: the user can
// change it in System Settings and the checkbox must not disagree.
const loginToggle = $("#open-at-login")
loginToggle.onchange = async () => {
  loginToggle.checked = await guard(window.tv.setOpenAtLogin(loginToggle.checked))
}
$("#help-btn").onclick = () => showView("help-view")
$("#manage-apps").onclick = () => showView("apps-view")

$("#room-save").onclick = async () => {
  const name = el.roomName.value.trim()
  const displayId = el.roomDisplay.value
  const sourceId = el.roomSource.value
  if (!name || !displayId || !sourceId) return toast("צריך שם, מסך וממיר")
  await guard(window.tv.saveRoom({ name, displayId, sourceId }))
  el.roomName.value = ""
  toast(`הסט "${name}" נוצר`, "info")
}

$("#app-add").onclick = async () => {
  const t = current()
  const deviceId = t?.source?.id
  if (!deviceId) return toast("אין ממיר ביעד הנוכחי")
  const label = $("#app-label").value.trim()
  const link = $("#app-link").value.trim()
  if (!label || !link) return toast("צריך שם ויעד")
  // A bare package name is not a URI; wrap it in the intent form the box expects.
  const launch = /^[a-z]+:/i.test(link) ? link : `intent:#Intent;package=${link};end`
  await guard(window.tv.addApp(deviceId, { label, launch }))
  $("#app-label").value = ""
  $("#app-link").value = ""
  await refreshApps()
  renderAppsManager()
}

$("#scan-btn").onclick = async () => {
  const button = $("#scan-btn")
  button.disabled = true
  button.textContent = "מחפש…"
  el.foundList.innerHTML = ""
  try {
    const found = await window.tv.discover({ sweep: $("#deep-scan").checked })
    if (!found.length) return toast("לא נמצאו מכשירים חדשים", "info")
    for (const device of found) {
      const row = document.createElement("div")
      row.className = "device-row"
      row.innerHTML = `<span class="dot"></span>
        <div><div class="name"></div><div class="meta"></div></div>
        <div class="actions"><button class="add">הוסף</button></div>`
      row.querySelector(".name").textContent = device.name
      row.querySelector(".meta").textContent = `${device.kindLabel} · ${device.host}`
      row.querySelector(".add").onclick = async () => {
        const added = await guard(window.tv.add(device))
        if (added) {
          row.remove()
          guard(window.tv.connect(added.id), "מתחבר…")
        }
      }
      el.foundList.append(row)
    }
  } finally {
    button.disabled = false
    button.textContent = "חפש מכשירים"
  }
}

document.addEventListener("keydown", (event) => {
  if (event.target.matches("input, select, textarea")) return
  if (event.metaKey || event.ctrlKey || event.altKey) return
  if (event.key === "Escape") {
    event.preventDefault()
    return viewStack.length > 1 ? goBack() : window.tv.hide()
  }
  if ($("#remote-view").hidden) return
  const cmd = KEYMAP[event.key]
  if (!cmd) return
  event.preventDefault()
  run(cmd)
})

let appsRefresh = null
window.tv.onDevices((next) => {
  const wasConnected = current()?.status.connected
  snapshot = next
  render()
  // Refresh the app list when a target comes online, coalescing bursts of events.
  if (!wasConnected && current()?.status.connected) {
    clearTimeout(appsRefresh)
    appsRefresh = setTimeout(refreshApps, 400)
  }
})
window.tv.onError(({ id, message }) => {
  const device = snapshot.devices.find((d) => d.id === id)
  toast(`${device?.name ?? "מכשיר"}: ${message}`)
})
window.tv.onShown(() => {
  if (current()?.pairing) el.pin.focus()
})

async function init() {
  const settings = await window.tv.getSettings()
  loginToggle.checked = await window.tv.openAtLogin().catch(() => false)
  snapshot = await window.tv.list()
  currentId = settings.lastTargetId ?? snapshot.targets[0]?.id ?? null
  render()
  await refreshApps()
  if (!snapshot.devices.length) showView("settings-view")
}

init()
