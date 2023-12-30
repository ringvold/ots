defmodule Ots.Repo do

  def insert(encrypted_bytes, expires_at, cipher) do
    id = generate_id(encrypted_bytes, expires_at, cipher)

    secret = {id, encrypted_bytes, expires_at, cipher}
    :ok = save(secret)
    id
  end

  def delete(id),
    do: Groot.set(id, nil)

  def save({id, _, _, _} = message),
    do: :ok = Groot.set(id, message)

  def read(id) do
    Groot.get(id)
  end

  def all() do
     Groot.all()
  end

  defp generate_id(encrypted_bytes, expires_at, cipher) do
    {
      encrypted_bytes,
      expires_at,
      cipher
    }
    |> :erlang.phash2()
    |> Integer.to_string()
    |> Base.encode64()
  end
end
