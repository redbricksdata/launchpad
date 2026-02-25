import { NextRequest, NextResponse } from "next/server";
import { exchangeOneTimeToken, setAuthCookie } from "@/lib/auth";

export async function POST(req: NextRequest) {
  try {
    const { token } = await req.json();

    if (!token || typeof token !== "string") {
      return NextResponse.json(
        { error: "Token is required" },
        { status: 400 },
      );
    }

    const result = await exchangeOneTimeToken(token);
    await setAuthCookie(result.token);

    return NextResponse.json({
      user: result.user,
      team: result.team,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Token exchange failed";
    return NextResponse.json({ error: message }, { status: 401 });
  }
}
