import { Socket } from "./phoenix.mjs"
import { LiveSocket } from "./phoenix_live_view.esm.js"

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "")
  })
})

// Copy Vault-Tag to clipboard with brief visual feedback.
// Dispatched from the Slug row on the Projekt show page.
window.addEventListener("ratsprojekte:copy-tag", (event) => {
  const btn = event.target.closest(".copy-tag-btn")
  if (!btn) return
  const tag = btn.getAttribute("data-tag")
  if (!tag) return

  const fallback = () => {
    const ta = document.createElement("textarea")
    ta.value = tag
    ta.setAttribute("readonly", "")
    ta.style.position = "absolute"
    ta.style.left = "-9999px"
    document.body.appendChild(ta)
    ta.select()
    try { document.execCommand("copy") } catch (_e) {}
    document.body.removeChild(ta)
  }

  const done = () => {
    btn.classList.add("copied")
    window.setTimeout(() => btn.classList.remove("copied"), 2000)
  }

  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(tag).then(done).catch(() => { fallback(); done() })
  } else {
    fallback()
    done()
  }
})
