signing_salt = :crypto.strong_rand_bytes(8) |> Base.encode16()
secret_base = :crypto.strong_rand_bytes(32) |> Base.encode16()

host =
  if app = System.get_env("FLY_APP_NAME") do
    app <> ".fly.dev"
  else
    "localhost"
  end

url =
  if app = System.get_env("FLY_APP_NAME") do
    "https://" <> app <> ".fly.dev"
  else
    "http://localhost:4000"
  end

Application.put_env(:phoenix, :json_library, Jason)

Application.put_env(:ots, :url, url)

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
  {:phoenix_live_view, "~> 0.18.3"}
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

defmodule Ots.Layouts do
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title></title>
      <script src="https://cdn.tailwindcss.com"></script>
      <script src="https://cdn.jsdelivr.net/npm/phoenix@1.6.10/priv/static/phoenix.min.js">
      </script>
      <script
      src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.18.3/priv/static/phoenix_live_view.min.js"
      >
      </script>
      <script>
        let Hooks = {}
        Hooks.Decrypt = {
          mounted() {
            if(window.location.hash) {
              console.log("key",window.location.hash)
              this.pushEvent("decrypt", {key: window.location.hash.replace(/^\#/, "")})
            }
          }
        }
        let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {hooks: Hooks})
        liveSocket.connect()
      </script>
    </head>
    <body>
      <div class="container mx-auto px-4 text-center w-4/5 pt-10" >
        <%= @inner_content %>
      </div>
    </body>
    </html>
    """
  end
end

defmodule Ots.Store do
  @table :secrets

  def insert(encrypted_bytes, expires_at, cipher) do
    id = {
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

defmodule Ots.ApiController do
  use Phoenix.Controller,
    namespace: Ots,
    formats: [:json]

  import Plug.Conn
  import Jason.Helpers
  alias Ots.Store

  def index(conn, params) do
    encrypted_bytes = params["encryptedBytes"]
    cipher = parse_cipher(params["cipher"]) |> dbg
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
      _ -> :aes_256_gcm # Default to AES GCM to support ots cli
    end
  end
end

defmodule Ots.CreateLive do
  use Phoenix.LiveView
  alias Ots.Encryption
  alias Ots.Store

  @cipher :chacha20_poly1305

  def mount(_params, _session, socket) do
    {:ok, assign(socket, url: nil, loading: false)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-6xl mb-5 font-bold">One-time secrets</h1>
    <h1 class="text-3xl mb-5 font-bold">Share end-to-end encrypted secrets with others via a one-time URL</h1>
    <form phx-submit="encrypt">
      <textarea name="secret" class="bg-slate-800 p-5 mb-1 w-full h-60 border rounded shadow text-slate-100 placeholder:italic placeholder:text-slate-400"
        spellcheck="false"
        placeholder="→ Type or paste what you want to securely share here..."
      ><%= if @url do %>This is your one-time url:

<%= @url %>

This url will only work one time and expire by XXXX if not used.
<% end %></textarea>
      <%= unless @url do %>
        <button  class="bg-cyan-400 rounded shadow hover:shadow-lg w-full p-3 font-bold text-2xl disabled:bg-cyan-200 disabled:text-slate-500"
          type="submit"
          phx-disable-with="Encrypting..">
          Encrypt and create one-time URL
        </button>
      <% end %>
    </form>
    """
  end

  def handle_event("encrypt", %{"secret" => secret}, socket) do
    # Process.sleep 2000
    send(self(), {:encrypt, secret})
    {:noreply, assign(socket, loading: true)}
  end

  def handle_info({:encrypt, secret}, socket) do
    if not blank?(secret) do
      {encrypted, key} = Encryption.encrypt(secret)
      expires_at =
        DateTime.now!("Etc/UTC")
          |> DateTime.add(2, :hour)
          |> DateTime.to_unix()

      id = Store.insert(encrypted, expires_at, @cipher)
      {:noreply, assign(socket, loading: false, url: one_time_url(id, key))}
    else
      {:noreply, socket}
    end
  end

  def one_time_url(id, key) do
    key = Base.url_encode64(key)
    "#{Application.get_env(:ots, :url)}/view/#{id}?ref=web##{key}"
  end

  def blank?(val), do: is_nil(val) or val == ""

end

defmodule Ots.ViewLive do
  use Phoenix.LiveView
  alias Ots.Encryption
  alias Ots.Store

  @cipher :chacha20_poly1305

  def mount(%{"id" => id}, _session, socket) do
    case Store.read(id) do
      [] ->
        {:ok, assign(socket, id: nil, encrypted_secret: nil, decrypted_secret: nil, chiper: nil)}

      rest ->
        {id, encrypted, _expires_at, cipher} = hd(rest)
        if connected?(socket), do: :ets.delete(:secrets, id)
        {:ok, assign(socket, id: id, encrypted_secret: encrypted, decrypted_secret: nil, cipher: cipher)}
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-6xl mb-5">One-time secrets</h1>
    <p class="text-lg mb-5">Share end-to-end encrypted secrets with others via a one-time URL</p>
    <div id="secret" class="text-2xl" phx-hook="Decrypt">
      <span>Secret:</span> <span class="font-bold"><%= @decrypted_secret %></span>
    </div>
    """
  end

  def handle_event("decrypt", %{"key" => key}, socket) do
    if not blank?(key) and not blank?(socket.assigns.encrypted_secret) do
      key = Base.url_decode64!(key)
      decrypted = Encryption.decrypt(socket.assigns.encrypted_secret, key, socket.assigns.cipher)
      {:noreply, assign(socket, decrypted_secret: decrypted)}
    else
      {:noreply, socket}
    end
  end

  def blank?(val), do: is_nil(val) or val == ""
end

defmodule Ots.Encryption do
  @aad <<>>
  @nonce_size 12
  @tag_size 16

  def encrypt(val, cipher \\ :chacha20_poly1305) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)
    key = :crypto.strong_rand_bytes(32)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(cipher, key, nonce, to_string(val), @aad, @tag_size, true)

    {Base.encode64(nonce <> ciphertext <> tag), key}
  end

  def decrypt(ciphertext, key, cipher \\ :chacha20_poly1305) do
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
      fn {id, _, expire}, _acc ->
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
    plug :put_root_layout, {Ots.Layouts, :root}
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
