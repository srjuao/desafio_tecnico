// Minimal app.js to bootstrap LiveView if local build fails
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: window.liveHooks || {}
})

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", _info => console.log("Loading..."))
window.addEventListener("phx:page-loading-stop", _info => console.log("Loaded!"))

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for debugging
window.liveSocket = liveSocket
