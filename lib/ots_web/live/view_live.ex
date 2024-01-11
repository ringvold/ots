defmodule OtsWeb.ViewLive do
  use Phoenix.LiveView
  alias Ots.Encryption
  alias Ots.Repo

  def mount(%{"id" => id}, _session, socket) do
    case Repo.read(id) do
      nil ->
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

      value ->
        {id, encrypted, _expires_at, cipher} = value
        if connected?(socket), do: Repo.delete(id)

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
      <div
        id="secret"
        class="text-2xl"
        phx-hook="DecryptFrontend"
        data-secretId={@id}
        data-cipher={@cipher}
        data-secret={@encrypted_secret}
      >
        <%= if @loading do %>
          Loading..
        <% end %>
        <%= if @decrypted do %>
          <h2 class="mb-3">Secret:</h2>
          <textarea
            id="decrypted"
            name="secret"
            phx-hook="ShowDecrypted"
            class="bg-slate-800 dark:bg-slate-700 p-5 mb-1 w-full h-60 rounded
              shadow font-bold text-lg text-slate-100 dark:text-slate-200"
            spellcheck="false"
            disabled
          ></textarea>
        <% end %>
      </div>
    <% else %>
      <div id="secret" class="text-2xl" phx-hook="Decrypt">
        <%= if @loading do %>
          Loading..
        <% end %>
        <%= if @encrypted_secret do %>
          <h2 class="mb-3">Secret:</h2>
          <textarea
            id="decrypted"
            name="secret"
            class="bg-slate-800 dark:bg-slate-700
                p-5 mb-1 w-full h-60
                rounded shadow
                font-bold
                text-lg text-slate-100 dark:text-slate-200"
            spellcheck="false"
            disabled
          ><%= @decrypted_secret %></textarea>
        <% else %>
          <div class="mb-5">This one-time secret cannot be viewed</div>

          <div class="mb-5">This secret may have expired or has been read already</div>

          <div class="mb-5">
            Reminder: Once secrets have been read once, they are permanently destroyed 💥
          </div>
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
