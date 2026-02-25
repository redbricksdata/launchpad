import { NextResponse } from "next/server";
import { getAuthToken } from "@/lib/auth";
import { validateResendKey } from "@/lib/validators/resend";
import { validateSendGridKey } from "@/lib/validators/sendgrid";

export async function POST(request: Request) {
  const token = await getAuthToken();
  if (!token) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { apiKey, provider = "resend" } = await request.json();
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
    resend: validateResendKey,
    sendgrid: validateSendGridKey,
  };

  const validate = validators[provider];
  if (!validate) {
    return NextResponse.json(
      { valid: false, message: `Unknown email provider: ${provider}` },
      { status: 400 },
    );
  }

  const result = await validate(apiKey);
  return NextResponse.json(result);
}
