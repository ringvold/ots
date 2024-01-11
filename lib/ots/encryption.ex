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
