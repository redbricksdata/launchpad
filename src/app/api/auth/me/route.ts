import { NextResponse } from "next/server";
import { getAuthToken, getProfile } from "@/lib/auth";

export async function GET() {
  try {
    const token = await getAuthToken();
    if (!token) {
      return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
    }

    const user = await getProfile(token);
    return NextResponse.json({ user });
  } catch {
    return NextResponse.json({ error: "Session expired" }, { status: 401 });
  }
}
