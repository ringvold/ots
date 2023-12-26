defmodule OtsWeb.ApiController do
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
      "aes256gcm" -> :aes_256_gcm
      # Default to AES GCM to support ots cli
      _ -> :aes_256_gcm
    end
  end
end
