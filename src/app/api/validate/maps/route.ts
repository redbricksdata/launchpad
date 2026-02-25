import { NextResponse } from "next/server";
import { getAuthToken } from "@/lib/auth";
import { validateGoogleMapsKey } from "@/lib/validators/google-maps";

export async function POST(request: Request) {
  const token = await getAuthToken();
  if (!token) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { apiKey } = await request.json();
  if (!apiKey) {
    return NextResponse.json(
      { valid: false, message: "API key is required" },
      { status: 400 },
    );
  }

  const result = await validateGoogleMapsKey(apiKey);
  return NextResponse.json(result);
}
