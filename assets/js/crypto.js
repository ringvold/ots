import {base64EncArr, base64DecToArr, getBytes, concat} from "./utils.js";


/**
 * Encrypts secret message using AES in Galois/Counter Mode.
 *
 * See https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/encrypt#aes-gcm.
 */
export async function encryptMessage(secret) {
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

export async function decryptMessage(key, encryptedBytes) {
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
