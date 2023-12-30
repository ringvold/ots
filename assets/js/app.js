// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { encryptMessage, decryptMessage } from "./crypto.js"



// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())


let Hooks = {}
Hooks.Decrypt = {
  mounted() {
    if (window.location.hash) { // TODO: Make cipher more generic. Now it is tied to erlang implementation.
      const liveView = this
      const key = window.location.hash.replace(/^\#/, "")
      this.pushEvent("decrypt", { key })
    }
  }
}

Hooks.DecryptFrontend = {
  mounted() {
    const cipher = this.el.dataset.cipher
    const secretId = this.el.dataset.secretid
    if (window.location.hash && secretId && cipher == "aes_256_gcm") { // TODO: Make cipher more generic. Now it is tied to erlang implementation.
      const liveView = this
      const key = window.location.hash.replace(/^\#/, "")
      const secret = this.el.dataset.secret;

      const decrypt = async function () { // This async function is needed to be able to await decryptMessage
        const decryptedMessage = await decryptMessage(key, secret)
        window.decryptedMessage = decryptedMessage
        liveView.pushEvent("decrypted")
      }
      decrypt()
    }
  }
}

Hooks.ShowDecrypted = {
  mounted() {
    this.el.innerHTML = window.decryptedMessage
  }
}

Hooks.Encrypt = {
  message() { return this.el.value },
  mounted() {
    const liveView = this
    this.liveViewEncrypt = async function (e) {
      const encryptedMessage = await encryptMessage(liveView.message())
      liveView.pushEvent("encrypted", { encryptedBytes: encryptedMessage.encryptedBytes })
      window.shareUrlKey = encryptedMessage.key
    }
    window.addEventListener('js-encrypt',
      this.liveViewEncrypt)

  },
  destroyed() {
    window.removeEventListener('js-encrypt',
      this.liveViewEncrypt)
  }
}

Hooks.UpdateUrl = {
  mounted() {
    this.el.innerHTML = this.el.innerHTML.replace("key_placeholder", window.shareUrlKey)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

