defmodule OtsWeb.CreateLive do
  use OtsWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Ots.Encryption
  alias Ots.Repo

  @default_cipher :aes_256_gcm

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       url: nil,
       loading: false,
       expiration: 5,
       expiration_unit: Application.get_env(:ots, :expiration_unit),
       timezone_offset: 0
     )}
  end

  def expiration_unit_to_plural(unit) do
    case unit do
      :minute -> :minutes
      :hour -> :hours
      :day -> :days
      :week -> :weeks
      :month -> :months
      :year -> :years
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-6xl mb-5 font-bold dark:text-slate-200">One-time secrets</h1>
    <h1 class="text-3xl mb-5 font-bold dark:text-slate-200">
      Share end-to-end encrypted secrets with others via a one-time URL
    </h1>

    <form>
      <%= if @url do %>
        <div class="bg-slate-800 dark:bg-slate-700
            break-all
            p-5 mb-1 w-full h-60
            rounded
            text-left text-slate-100 text-lg dark:text-slate-200">
          <div class="mb-5">This is your one-time url:</div>

          <div id="url" class="mb-5 font-bold" phx-hook="UpdateUrl"><%= @url %></div>

          <div class="mb-5">
            This url will only work one time and expire in <%= @expiration %> <%= expiration_unit_to_plural(
              @expiration_unit
            ) %> if not used, at approximately:
            <date datetime={Timex.format!(@expires_at, "{ISO:Basic}")}>
              <%= Timex.format!(
                Timex.shift(@expires_at, [
                  {expiration_unit_to_plural(@expiration_unit), @timezone_offset}
                ]),
                "{0D}.{0M}.{YYYY} {h24}:{m}"
              ) %>
            </date>.
          </div>
        </div>
        <button
          id="copyToClipboard"
          class="bg-cyan-400 mt-5 dark:bg-cyan-800 rounded shadow hover:shadow-lg w-full p-3 font-bold text-2xl disabled:bg-cyan-200 disabled:text-slate-500"
          type="button"
          phx-hook="CopyToClipboard"
        >
          Copy URL to clipboard
        </button>

        <.link
          class="mt-5 inline-block border rounded shadow hover:shadow-lg p-3 font-bold text-2xl"
          type="button"
          href={~p"/"}
        >
          Create a new secret
        </.link>
      <% else %>
        <textarea
          id="message"
          name="secret"
          phx-hook="Encrypt"
          class="bg-slate-800 dark:bg-slate-700
              p-5 mb-1 w-full h-60
              rounded shadow
              text-lg text-slate-100 dark:text-slate-200
              placeholder:italic placeholder:text-slate-400"
          spellcheck="false"
          placeholder="→ Type or paste what you want to securely share here..."
        ></textarea>
        <div class="m-5">
          <label
            for="default-range"
            class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
          >
            Secret expiration in <%= @expiration %> <%= @expiration_unit %>
          </label>
          <input
            id="expirationRange"
            name="expiration"
            class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer dark:bg-gray-700"
            type="range"
            min="1"
            max="60"
            value={@expiration}
            phx-change="expiration_change"
          />
        </div>
        <button
          class="bg-cyan-400 dark:bg-cyan-800 rounded shadow hover:shadow-lg w-full p-3 font-bold text-2xl disabled:bg-cyan-200 disabled:text-slate-500"
          type="button"
          phx-click={JS.dispatch("js-encrypt")}
          phx-disable-with="Encrypting.."
        >
          Encrypt and create one-time URL
        </button>
      <% end %>
    </form>
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
    if not blank?(encryptedBytes) do
      expires_at =
        DateTime.now!("Etc/UTC")
        |> DateTime.add(socket.assigns.expiration, socket.assigns.expiration_unit)

      id = Repo.insert(encryptedBytes, expires_at |> DateTime.to_unix(), @default_cipher)

      {:noreply,
       assign(socket,
         loading: false,
         # TODO: Fix when backend encryption/decryption
         url: one_time_url(id, "key_placeholder"),
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

      id = Repo.insert(encrypted, expires_at |> DateTime.to_unix(), @default_cipher)

      {:noreply,
       assign(socket,
         loading: false,
         url: one_time_url(id, Base.url_encode64(key)),
         expires_at: expires_at
       )}
    else
      {:noreply, socket}
    end
  end

  def one_time_url(id, key) do
    "#{Application.get_env(:ots, :url)}/view/#{id}?ref=web##{key}"
  end

  def blank?(val), do: is_nil(val) or val == ""
end
