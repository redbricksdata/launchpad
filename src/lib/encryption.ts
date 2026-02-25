/**
 * AES-256-GCM encryption for tenant API keys.
 * Mirrors the template's src/lib/ai/encryption.ts exactly.
 * Format: base64(iv) + ":" + base64(ciphertext) + ":" + base64(authTag)
 *
 * Server-side only.
 */

import crypto from "crypto";

const ALGO = "aes-256-gcm";
const IV_LENGTH = 12; // GCM standard

function getKey(): Buffer {
  const hex = process.env.KEY_ENCRYPTION_SECRET;
  if (!hex || hex.length !== 64) {
    throw new Error(
      "KEY_ENCRYPTION_SECRET must be a 64-character hex string (32 bytes). " +
        'Generate one with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"',
    );
  }
  return Buffer.from(hex, "hex");
}

export function encrypt(plaintext: string): string {
  const key = getKey();
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGO, key, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return [
    iv.toString("base64"),
    encrypted.toString("base64"),
    tag.toString("base64"),
  ].join(":");
}

export function decrypt(encoded: string): string {
  const key = getKey();
  const [ivB64, cipherB64, tagB64] = encoded.split(":");
  if (!ivB64 || !cipherB64 || !tagB64) {
    throw new Error("Invalid encrypted key format");
  }

  const iv = Buffer.from(ivB64, "base64");
  const ciphertext = Buffer.from(cipherB64, "base64");
  const tag = Buffer.from(tagB64, "base64");

  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]);

  return decrypted.toString("utf8");
}
