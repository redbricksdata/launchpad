import { NextResponse } from "next/server";
import { getAuthToken } from "@/lib/auth";
import { validateGeminiKey } from "@/lib/validators/ai-api";
import { validateOpenAIKey } from "@/lib/validators/openai";
import { validateAnthropicKey } from "@/lib/validators/anthropic";

export async function POST(request: Request) {
  const token = await getAuthToken();
  if (!token) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { apiKey, provider = "gemini" } = await request.json();
  if (!apiKey) {
    return NextResponse.json(
      { valid: false, message: "API key is required" },
      { status: 400 },
    );
  }

  const validators: Record<
    string,
    (key: string) => Promise<{ valid: boolean; message: string; details?: string }>
  > = {
    gemini: validateGeminiKey,
    openai: validateOpenAIKey,
    anthropic: validateAnthropicKey,
  };

  const validate = validators[provider];
  if (!validate) {
    return NextResponse.json(
      { valid: false, message: `Unknown AI provider: ${provider}` },
      { status: 400 },
    );
  }

  const result = await validate(apiKey);
  return NextResponse.json(result);
}
