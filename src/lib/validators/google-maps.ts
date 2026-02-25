/**
 * Google Maps API key validator.
 * Performs a server-side Geocoding API call to verify the key is active.
 */

import type { ValidationResult } from "@/types/tenant";

const GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json";
const TEST_ADDRESS = "Toronto, ON, Canada";

export async function validateGoogleMapsKey(
  apiKey: string,
): Promise<ValidationResult> {
  if (!apiKey || apiKey.trim().length < 10) {
    return { valid: false, message: "API key is too short" };
  }

  try {
    const url = new URL(GEOCODE_URL);
    url.searchParams.set("address", TEST_ADDRESS);
    url.searchParams.set("key", apiKey.trim());

    const res = await fetch(url.toString());
    const data = await res.json();

    if (data.status === "OK") {
      return {
        valid: true,
        message: "Google Maps key is active and working",
      };
    }

    // Map Google API error statuses to user-friendly messages
    const errorMessages: Record<string, string> = {
      REQUEST_DENIED:
        "Invalid API key, or Geocoding API is not enabled. Enable it at console.cloud.google.com.",
      OVER_DAILY_LIMIT:
        "Quota exceeded. Check your billing account at console.cloud.google.com.",
      OVER_QUERY_LIMIT:
        "Rate limit reached. Try again in a moment.",
      INVALID_REQUEST:
        "Unexpected error — the test request was malformed.",
    };

    return {
      valid: false,
      message: errorMessages[data.status] || `API returned status: ${data.status}`,
      details: data.error_message,
    };
  } catch (error) {
    return {
      valid: false,
      message: "Failed to reach Google Maps API. Check your network connection.",
      details: error instanceof Error ? error.message : undefined,
    };
  }
}
