signing_salt = :crypto.strong_rand_bytes(8) |> Base.encode16()
secret_base = :crypto.strong_rand_bytes(32) |> Base.encode16()

host =
  if app = System.get_env("FLY_APP_NAME") do
    app <> ".fly.dev"
  else
    "localhost"
  end

Application.put_env(
  :ots,
  :url,
  if app = System.get_env("FLY_APP_NAME") do
    "https://" <> app <> ".fly.dev"
  else
    "http://localhost:4000"
  end
)

Application.put_env(:phoenix, :json_library, Jason)

Application.put_env(:ots, Ots.Endpoint,
  url: [host: host],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  server: true,
  live_view: [signing_salt: signing_salt],
  secret_key_base: secret_base
)

Mix.install([
  {:plug_cowboy, "~> 2.5"},
  {:jason, "~> 1.0"},
  {:phoenix, "~> 1.6.10"},
  {:phoenix_live_view, "~> 0.18.3"},
  {:timex, "~> 3.7"}
])

:ets.new(:secrets, [:set, :public, :named_table])

defmodule Ots.ErrorView do
  use Phoenix.View, root: ""

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule Ots.ErrorJSON do
  use Phoenix.View, root: ""

  def render(template, _assigns, _) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

defmodule Ots.ApiController do
  use Phoenix.Controller,
    namespace: Ots,
    formats: [:json]

  import Plug.Conn
  import Jason.Helpers
  alias Ots.Store

  def index(conn, params) do
    encrypted_bytes = params["encryptedBytes"]
    cipher = parse_cipher(params["cipher"])

    expires_at =
      DateTime.now!("Etc/UTC")
      |> DateTime.add(params["expiresIn"], :second)
      |> DateTime.to_unix()

    id = Store.insert(encrypted_bytes, expires_at, cipher)

    conn
    |> put_status(200)
    |> put_resp_header("X-View-Url", "#{Application.get_env(:ots, :url)}/view/#{id}")
    |> json(json_map(id: id, expiresAt: expires_at))
  end

  def parse_cipher(cipher_param) do
    case cipher_param do
      "chapoly" -> :chacha20_poly1305
      "chacha20_poly1305" -> :chacha20_poly1305
      "aes_256_gcm" -> :aes_256_gcm
      "aes_gcm" -> :aes_256_gcm
      # Default to AES GCM to support ots cli
      _ -> :aes_256_gcm
    end
  end
end

defmodule Ots.Layouts do
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>One Time Secret</title>
      <script src="https://cdn.tailwindcss.com"></script>
      <script src="https://cdn.jsdelivr.net/npm/phoenix@1.6.10/priv/static/phoenix.min.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.18.3/priv/static/phoenix_live_view.min.js"></script>
      <script>
        /**
         * Converts an Uint8Array directly to base64, and visa versa.
         *
         * https://developer.mozilla.org/en-US/docs/Glossary/Base64#appendix_decode_a_base64_string_to_uint8array_or_arraybuffer
         */

        /* Array of bytes to Base64 string decoding */
        function b64ToUint6(nChr) {
          return nChr > 64 && nChr < 91
            ? nChr - 65
            : nChr > 96 && nChr < 123
            ? nChr - 71
            : nChr > 47 && nChr < 58
            ? nChr + 4
            : nChr === 43
            ? 62
            : nChr === 47
            ? 63
            : 0;
        }

        function base64DecToArr(sBase64, nBlocksSize) {
          const sB64Enc = sBase64.replace(/[^A-Za-z0-9+/]/g, ""); // Remove any non-base64 characters, such as trailing "=", whitespace, and more.
          const nInLen = sB64Enc.length;
          const nOutLen = nBlocksSize
            ? Math.ceil(((nInLen * 3 + 1) >> 2) / nBlocksSize) * nBlocksSize
            : (nInLen * 3 + 1) >> 2;
          const taBytes = new Uint8Array(nOutLen);

          let nMod3;
          let nMod4;
          let nUint24 = 0;
          let nOutIdx = 0;
          for (let nInIdx = 0; nInIdx < nInLen; nInIdx++) {
            nMod4 = nInIdx & 3;
            nUint24 |= b64ToUint6(sB64Enc.charCodeAt(nInIdx)) << (6 * (3 - nMod4));
            if (nMod4 === 3 || nInLen - nInIdx === 1) {
              nMod3 = 0;
              while (nMod3 < 3 && nOutIdx < nOutLen) {
                taBytes[nOutIdx] = (nUint24 >>> ((16 >>> nMod3) & 24)) & 255;
                nMod3++;
                nOutIdx++;
              }
              nUint24 = 0;
            }
          }

          return taBytes;
        }

        /* Base64 string to array encoding */
        function uint6ToB64(nUint6) {
          return nUint6 < 26
            ? nUint6 + 65
            : nUint6 < 52
            ? nUint6 + 71
            : nUint6 < 62
            ? nUint6 - 4
            : nUint6 === 62
            ? 43
            : nUint6 === 63
            ? 47
            : 65;
        }

        function base64EncArr(aBytes) {
          let nMod3 = 2;
          let sB64Enc = "";

          const nLen = aBytes.length;
          let nUint24 = 0;
          for (let nIdx = 0; nIdx < nLen; nIdx++) {
            nMod3 = nIdx % 3;
            // To break your base64 into several 80-character lines, add:
            //   if (nIdx > 0 && ((nIdx * 4) / 3) % 76 === 0) {
            //      sB64Enc += "\r\n";
            //    }

            nUint24 |= aBytes[nIdx] << ((16 >>> nMod3) & 24);
            if (nMod3 === 2 || aBytes.length - nIdx === 1) {
              sB64Enc += String.fromCodePoint(
                uint6ToB64((nUint24 >>> 18) & 63),
                uint6ToB64((nUint24 >>> 12) & 63),
                uint6ToB64((nUint24 >>> 6) & 63),
                uint6ToB64(nUint24 & 63)
              );
              nUint24 = 0;
            }
          }
          return (
            sB64Enc.substring(0, sB64Enc.length - 2 + nMod3) +
            (nMod3 === 2 ? "" : nMod3 === 1 ? "=" : "==")
          );
        }

        /**
         * Converts a string into a Uint8Array containing UTF-8 encoded text.
         */
        function getBytes(string) {
          const textEncoder = new TextEncoder()
          const encoded = textEncoder.encode(string)

          return encoded
        }

        /**
         * Concatinate a list of Uint8Array
         */
        function concat(arrays) {
          // sum of individual array lengths
          let totalLength = arrays.reduce((acc, value) => acc + value.length, 0);

          let result = new Uint8Array(totalLength);

          if (!arrays.length) return result;

          // for each array - copy it over result
          // next array is copied right after the previous one
          let length = 0;
          for(let array of arrays) {
            result.set(array, length);
            length += array.length;
          }

          return result;
        }

        async function importKey(rawKey) {
          return window.crypto.subtle.importKey("raw", rawKey, "AES-GCM", true, [
            "encrypt",
            "decrypt",
          ])
        }

        async function generateKey(rawKey) {
          return window.crypto.subtle.generateKey(
            {
              name: "AES-GCM",
              length: 256,
            },
            true,
            ["encrypt", "decrypt"]
          )
        }

        async function exportKey(key) {
          const exported = await window.crypto.subtle.exportKey("raw", key);
          return new Uint8Array(exported);
        }

        /**
         * Encrypts secret message using AES in Galois/Counter Mode.
         *
         * See https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/encrypt#aes-gcm.
         */
        async function encryptMessage(secret) {
          const key = await generateKey()

          const encoded = getBytes(secret)
          const iv = window.crypto.getRandomValues(new Uint8Array(12))
          const ciphertext = await window.crypto.subtle.encrypt(
            {
              name: "AES-GCM",
              iv,
            },
            key,
            encoded,
          )

          const sealedSecret = concat([iv, new Uint8Array(ciphertext)])
          const encryptedBytes = base64EncArr(sealedSecret)
          const rawKey = await exportKey(key)
          const base64UrlKey = base64EncArr(rawKey)

          return { key: base64UrlKey, encryptedBytes }
        }

        async function decryptMessage(key, encryptedBytes) {
          const ivLength = 12
          const rawKey = base64DecToArr(key)
          const secretKey = await importKey(rawKey)
          const sealedSecret = base64DecToArr(encryptedBytes)
          const iv = sealedSecret.slice(0, ivLength)

          const ciphertext = sealedSecret.slice(ivLength, sealedSecret.length)
          const decrypted = await window.crypto.subtle.decrypt(
            {
              name: "AES-GCM",
              iv,
            },
            secretKey,
            ciphertext,
          )
          return new TextDecoder().decode(decrypted)
        }

        let Hooks = {}
        Hooks.Decrypt = {
          mounted() {
            const cipher = this.el.dataset.cipher
            const secretId = this.el.dataset.secretid
            if(window.location.hash && secretId && cipher == "aes_256_gcm") { // TODO: Make cipher more generic. Now it is tied to erlang implementation.
              const liveView = this
              const key = window.location.hash.replace(/^\#/, "")
              const secret = this.el.dataset.secret;

              const decrypt = async function() { // This async function is needed to be able to await decryptMessage
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
            this.liveViewEncrypt = async function(e) {
              const encryptedMessage = await encryptMessage(liveView.message())
              liveView.pushEvent("encrypted", {encryptedBytes: encryptedMessage.encryptedBytes})
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

        let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket,
          {
            hooks: Hooks,
            dom: {
              onBeforeElUpdated(from, to) {
                if (from._x_dataStack) {
                  window.Alpine.clone(from, to)
                }
              }
            }
        })
        liveSocket.connect()
      </script>
    </head>
    <body class="dark:bg-slate-800 dark:text-slate-200">
      <div class="container mx-auto px-4 text-center w-4/5 pt-10" >
        <%= @inner_content %>
      </div>
    </body>
    </html>
    """
  end
end

defmodule Ots.CreateLive do
  use Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias Ots.Encryption
  alias Ots.Store

  @default_cipher :aes_256_gcm

  def mount(_params, _session, socket) do
    {:ok, assign(socket, url: nil, loading: false, expiration: 2, backend_encryption: false)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-6xl mb-5 font-bold dark:text-slate-200">One-time secrets</h1>
    <h1 class="text-3xl mb-5 font-bold dark:text-slate-200">Share end-to-end encrypted secrets with others via a one-time URL</h1>

    <%= if @backend_encryption do %>
      <!-- TODO: Handle backend encryption  -->
    <% else %>
      <form>
       <!-- Frontend encryption -->
        <%= if @url do %>
          <div class="bg-slate-800 dark:bg-slate-700
            break-all
            p-5 mb-1 w-full h-60
            rounded
            text-left text-slate-100 text-lg dark:text-slate-200">
            <div class="mb-5">This is your one-time url:</div>

            <div id="url" class="mb-5 font-bold" phx-hook="UpdateUrl"><%= @url %></div>

            <div class="mb-5">This url will only work one time and expire approximately <%= Timex.format!(@expires_at, "{D}.{0M}.{YYYY} {h24}:{m}") %> UTC if not used.</div>
          </div>
        <% else %>
          <textarea id="message" name="secret" phx-hook="Encrypt"
            class="bg-slate-800 dark:bg-slate-700
              p-5 mb-1 w-full h-60
              rounded shadow
              text-lg text-slate-100 dark:text-slate-200
              placeholder:italic placeholder:text-slate-400"
            spellcheck="false"
            placeholder="→ Type or paste what you want to securely share here..."
          ></textarea>
          <div class="m-5">
            <label for="default-range" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">Secret expiration in <%= @expiration %> hours</label>
            <input id="expirationRange" name="expiration"
              class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer dark:bg-gray-700"
              type="range" min="1" max="96" value={@expiration} phx-change="expiration_change">
          </div>
          <button  class="bg-cyan-400 dark:bg-cyan-800 rounded shadow hover:shadow-lg w-full p-3 font-bold text-2xl disabled:bg-cyan-200 disabled:text-slate-500"
            type="button"
            phx-click={JS.dispatch("js-encrypt")}
            phx-disable-with="Encrypting..">
            Encrypt and create one-time URL
          </button>
        <% end %>
      </form>
    <% end %>
    """
  end

  def handle_event("encrypt", %{"secret" => secret}, socket) do
    if socket.assigns.backed_encryption do
      send(self(), {:encrypt, secret})
      {:noreply, assign(socket, loading: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("encrypted", %{"encryptedBytes" => encryptedBytes}, socket) do
    send(self(), {:store_encrypted, encryptedBytes})
    {:noreply, assign(socket, loading: true)}
  end

  def handle_event("expiration_change", %{"expiration" => expiration}, socket) do
    {:noreply, assign(socket, expiration: String.to_integer(expiration))}
  end

  def handle_info({:store_encrypted, encryptedBytes}, socket) do
    dbg(encryptedBytes)

    if not blank?(encryptedBytes) do
      expires_at =
        DateTime.now!("Etc/UTC")
        |> DateTime.add(socket.assigns.expiration, :hour)

      id = Store.insert(encryptedBytes, expires_at |> DateTime.to_unix(), @default_cipher)
      {:noreply,
       assign(socket,
         loading: false,
         url: one_time_url(id, "key_placeholder"), # TODO: Fix when backend encryption/decryption
         expires_at: expires_at
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:encrypt, secret}, socket) do
    if not blank?(secret) do
      {encrypted, key} = Encryption.encrypt(secret)

      expires_at =
        DateTime.now!("Etc/UTC")
        |> DateTime.add(socket.assigns.expiration, :hour)

      id = Store.insert(encrypted, expires_at |> DateTime.to_unix(), @default_cipher)

      {:noreply,
       assign(socket, loading: false, url: one_time_url(id, Base.url_encode64(key)), expires_at: expires_at)}
    else
      {:noreply, socket}
    end
  end

  def one_time_url(id, key) do
    "#{Application.get_env(:ots, :url)}/view/#{id}?ref=web##{key}"
  end

  def blank?(val), do: is_nil(val) or val == ""
end

defmodule Ots.ViewLive do
  use Phoenix.LiveView
  alias Ots.Encryption
  alias Ots.Store

  def mount(%{"id" => id}, _session, socket) do
    case Store.read(id) do
      [] ->
        {:ok,
         assign(socket,
           id: nil,
           encrypted_secret: nil,
           decrypted_secret: nil,
           cipher: nil,
           loading: false,
           decrypted: false,
           frontend_decryption: false
         )}

      rest ->
        {id, encrypted, _expires_at, cipher} = hd(rest)
        if connected?(socket), do: :ets.delete(:secrets, id)
        dbg cipher
        {:ok,
         assign(socket,
           id: id,
           encrypted_secret: encrypted,
           decrypted_secret: nil,
           cipher: cipher,
           loading: true,
           decrypted: false,
           frontend_decryption: cipher == :aes_256_gcm
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-6xl mb-5">One-time secrets</h1>
    <p class="text-lg mb-5">Share end-to-end encrypted secrets with others via a one-time URL</p>

      <%= if @frontend_decryption do %>
        <div id="secret" class="text-2xl" phx-hook="Decrypt"
          data-secretId={@id} data-cipher={@cipher} data-secret={@encrypted_secret}>
          <%= if @loading do %>
            Loading..
          <% end %>
          <%= if @decrypted do %>
          <h2 class="mb-3">Secret:</h2>
          <textarea id="decrypted" name="secret" phx-hook="ShowDecrypted"
            class="bg-slate-800 dark:bg-slate-700 p-5 mb-1 w-full h-60 rounded
              shadow font-bold text-lg text-slate-100 dark:text-slate-200"
            spellcheck="false" disabled
          ></textarea>
          <% end %>
        </div>

      <% else %>
        <div id="secret" class="text-2xl">
          <%= if @loading do %>
            Loading..
          <% end %>
          <%= if @encrypted_secret do %>
            <h2 class="mb-3">Secret:</h2>
            <textarea id="decrypted" name="secret"
              class="bg-slate-800 dark:bg-slate-700
                p-5 mb-1 w-full h-60
                rounded shadow
                font-bold
                text-lg text-slate-100 dark:text-slate-200"
              spellcheck="false" disabled
            ><%= @decrypted_secret %></textarea>
          <% else %>
            <div class="mb-5">This one-time secret cannot be viewed</div>

            <div class="mb-5">This secret may have expired or has been read already</div>

            <div class="mb-5">Reminder: Once secrets have been read once, they are permanently destroyed 💥</div>
          <% end %>
        </div>
      <% end %>


    """
  end

  def handle_event("decrypt", %{"key" => key}, socket) do
    if not blank?(key) and not blank?(socket.assigns.encrypted_secret) do
      key = Base.url_decode64!(key)
      decrypted = Encryption.decrypt(socket.assigns.encrypted_secret, key, socket.assigns.cipher)
      {:noreply, assign(socket, decrypted_secret: decrypted, loading: false)}
    else
      {:noreply, assign(socket, loading: false)}
    end
  end

  def handle_event("decrypted", _params, socket) do
    {:noreply, assign(socket, loading: false, decrypted: true)}
  end

  def blank?(val), do: is_nil(val) or val == ""
end

defmodule Ots.Store do
  @table :secrets

  def insert(encrypted_bytes, expires_at, cipher) do
    id =
      {
        encrypted_bytes,
        expires_at,
        cipher
      }
      |> :erlang.phash2()
      |> Integer.to_string()
      |> Base.encode64()

    :ets.insert(@table, {id, encrypted_bytes, expires_at, cipher})
    id
  end

  def read(id) do
    :ets.lookup(@table, id)
  end
end

defmodule Ots.Encryption do
  @aad <<>>
  @nonce_size 12
  @tag_size 16

  def encrypt(val, cipher \\ :aes_256_gcm) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)
    key = :crypto.strong_rand_bytes(32)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(cipher, key, nonce, to_string(val), @aad, @tag_size, true)

    {Base.encode64(nonce <> ciphertext <> tag), key}
  end

  def decrypt(ciphertext, key, cipher \\ :aes_256_gcm) do
    <<nonce::binary-@nonce_size, ciphertext::binary>> = decode(ciphertext)
    tag = binary_slice(ciphertext, -@tag_size..-1)
    ciphertext_length = byte_size(ciphertext) - @tag_size
    ciphertext = binary_slice(ciphertext, 0, ciphertext_length)
    :crypto.crypto_one_time_aead(cipher, key, nonce, ciphertext, @aad, tag, false)
  end

  def decode(key) do
    Base.decode64!(key)
  end


end

defmodule Ots.ExpirationChecker do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    # Schedule work to be performed at some point
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    IO.puts("Starting expiry check...")

    :ets.foldl(
      fn {id, _, expire, _cipher}, _acc ->
        now = DateTime.now!("Etc/UTC") |> DateTime.to_unix()

        if now > expire do
          IO.puts("Secret #{id} expired. Deleting..")
          :ets.delete(:secrets, id)
        end

        :ok
      end,
      nil,
      :secrets
    )

    IO.puts("Expiry check finished")

    # Reschedule once more
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    # In 3 minutes
    Process.send_after(self(), :work, 3 * 60 * 1000)
  end
end

defmodule Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:put_root_layout, {Ots.Layouts, :root})
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", Ots do
    pipe_through(:browser)

    live("/", CreateLive, :index)
    live("/view/:id", ViewLive, :index)
  end

  scope "/api", Ots do
    pipe_through(:api)

    post("/", ApiController, :index)
  end
end

defmodule Ots.Endpoint do
  use Phoenix.Endpoint, otp_app: :ots
  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Router)
end

# Dry run for copying cached mix install from builder to runner
if System.get_env("EXS_DRY_RUN") == "true" do
  System.halt(0)
else
  {:ok, _} = Supervisor.start_link([Ots.Endpoint, Ots.ExpirationChecker], strategy: :one_for_one)
  Process.sleep(:infinity)
end
