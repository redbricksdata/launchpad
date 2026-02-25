/**
 * Resend API key validator.
 * Performs a GET /api-keys request to verify the key is active.
 */

import type { ValidationResult } from "@/types/tenant";

const RESEND_API_URL = "https://api.resend.com";

export async function validateResendKey(
  apiKey: string,
): Promise<ValidationResult> {
  if (!apiKey || apiKey.trim().length < 10) {
    return { valid: false, message: "API key is too short" };
  }

  try {
    const res = await fetch(`${RESEND_API_URL}/api-keys`, {
      headers: {
        Authorization: `Bearer ${apiKey.trim()}`,
      },
    });

    if (res.ok) {
      return {
        valid: true,
        message: "Resend API key is active and working",
      };
    }

    if (res.status === 401) {
      return {
        valid: false,
        message: "Invalid API key. Check that it's correct.",
      };
    }

    if (res.status === 403) {
      return {
        valid: false,
        message: "API key does not have sufficient permissions.",
      };
    }

    if (res.status === 429) {
      return {
        valid: false,
        message: "Rate limit reached. Try again in a moment.",
      };
    }

    return {
      valid: false,
      message: `Resend API returned error (${res.status})`,
    };
  } catch (error) {
    return {
      valid: false,
      message: "Failed to reach Resend API. Check your network connection.",
      details: error instanceof Error ? error.message : undefined,
    };
  }
}
