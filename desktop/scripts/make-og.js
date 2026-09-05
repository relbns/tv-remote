/**
 * Render the link-preview card that WhatsApp, Telegram and Slack show.
 *
 * Without an image those cards are a line of grey text; with one they are the
 * first impression of the product. Drawn as HTML and captured, so the card uses
 * the same type and palette as the site rather than a separate approximation.
 */
import { app, BrowserWindow } from "electron"
import { writeFileSync, readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const out = join(root, "..", "docs", "og.png")
const icon = readFileSync(join(root, "assets", "appicon-1024.png")).toString("base64")

const page = `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;700&display=swap">
<style>
  *{margin:0;box-sizing:border-box}
  body{width:1200px;height:630px;display:flex;align-items:center;gap:56px;
    justify-content:center;
    padding:0 88px;background:#0B0E14;color:#F3F4F7;
    font-family:Rubik,-apple-system,sans-serif;overflow:hidden;position:relative}
  /* A single amber bloom behind the mark, echoing the OK ring in the app. */
  body::before{content:"";position:absolute;inset:auto -180px -320px auto;
    width:760px;height:760px;border-radius:50%;
    background:radial-gradient(circle,rgba(233,169,63,.16),transparent 62%)}
  img{width:212px;height:212px;flex:none;position:relative}
  /* Fill the row, or the text huddles against the mark and leaves the far
     side of the card empty. */
  /* Sized to its own text and centred with the mark, so the card is not a
     block of content pushed against one edge. */
  .copy{position:relative;min-width:0}
  h1{font-size:92px;font-weight:700;letter-spacing:-.02em;line-height:1}
  p{font-size:31px;line-height:1.5;color:#A8ADBA;margin-top:20px;max-width:21ch}
  .foot{margin-top:30px;display:flex;align-items:center;gap:14px;
    font-size:23px;color:#E9A93F;font-weight:500}
  .dot{width:9px;height:9px;border-radius:50%;background:#E9A93F;opacity:.55}
</style></head><body>
  <img src="data:image/png;base64,${icon}" alt="">
  <div class="copy">
    <h1>Orbit</h1>
    <p>שלט לממירי Android TV ולטלוויזיות חכמות, מהטלפון ומהמק.</p>
    <div class="foot">הכל ברשת הביתית<span class="dot"></span>בלי ענן, בלי חשבון</div>
  </div>
</body></html>`

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    width: 1200,
    height: 630,
    show: false,
    webPreferences: { offscreen: true },
  })
  await win.loadURL("data:text/html;charset=utf-8," + encodeURIComponent(page))
  // Give the webfont a moment; a card rendered in the fallback face is the
  // exact failure this script exists to avoid.
  await win.webContents.executeJavaScript("document.fonts.ready.then(() => true)")
  await new Promise((r) => setTimeout(r, 700))
  // The display is retina, so the capture comes back at 2x. Link previews are
  // size-capped and some clients skip an image that is too heavy, so it is
  // resized down to the 1200x630 the platforms actually ask for.
  const shot = await win.webContents.capturePage()
  writeFileSync(out, shot.resize({ width: 1200, height: 630 }).toPNG())
  console.log("✓ " + out)
  app.exit(0)
})
