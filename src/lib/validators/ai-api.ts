/**
 * AI API key validator.
 * Performs a minimal-token request to verify the key is active.
 * Supports Google Gemini.
 */

import type { ValidationResult } from "@/types/tenant";

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

export async function validateGeminiKey(
  apiKey: string,
): Promise<ValidationResult> {
  if (!apiKey || apiKey.trim().length < 10) {
    return { valid: false, message: "API key is too short" };
  }

  try {
    const url = `${GEMINI_URL}?key=${encodeURIComponent(apiKey.trim())}`;

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [{ text: "Reply with exactly: OK" }],
          },
        ],
        generationConfig: {
          maxOutputTokens: 5,
        },
      }),
    });

    if (res.ok) {
      return {
        valid: true,
        message: "Gemini API key is active and working",
      };
    }

    const data = await res.json().catch(() => ({}));
    const errorStatus = data?.error?.status;
    const errorMessage = data?.error?.message || "";

    if (res.status === 400 && errorMessage.includes("API_KEY_INVALID")) {
      return {
        valid: false,
        message: "Invalid API key. Check that it's correct.",
      };
    }

    if (res.status === 403) {
      return {
        valid: false,
        message:
          "API key is restricted or Generative Language API is not enabled. Enable it at console.cloud.google.com.",
      };
    }

    if (res.status === 429 || errorStatus === "RESOURCE_EXHAUSTED") {
      return {
        valid: false,
        message:
          "Quota exceeded. Check your billing at console.cloud.google.com.",
      };
    }

    return {
      valid: false,
      message: `API returned error (${res.status}): ${errorMessage || "Unknown error"}`,
    };
  } catch (error) {
    return {
      valid: false,
      message: "Failed to reach Gemini API. Check your network connection.",
      details: error instanceof Error ? error.message : undefined,
    };
  }
}
