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
