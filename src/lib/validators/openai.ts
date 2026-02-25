/**
 * OpenAI API key validator.
 * Performs a GET /v1/models request to verify the key is active.
 */

import type { ValidationResult } from "@/types/tenant";

export async function validateOpenAIKey(
  apiKey: string,
): Promise<ValidationResult> {
  if (!apiKey || apiKey.trim().length < 10) {
    return { valid: false, message: "API key is too short" };
  }

  try {
    const res = await fetch("https://api.openai.com/v1/models", {
      headers: {
        Authorization: `Bearer ${apiKey.trim()}`,
      },
    });

    if (res.ok) {
      return {
        valid: true,
        message: "OpenAI API key is active and working",
      };
    }

    if (res.status === 401) {
      return {
        valid: false,
        message:
          "Invalid API key. Check that it's correct and has billing credits.",
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
      message: `OpenAI API returned error (${res.status})`,
    };
  } catch (error) {
    return {
      valid: false,
      message: "Failed to reach OpenAI API. Check your network connection.",
      details: error instanceof Error ? error.message : undefined,
    };
  }
}
