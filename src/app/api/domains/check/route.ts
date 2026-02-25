import { NextResponse } from "next/server";
import { getAuthToken } from "@/lib/auth";
import { checkSubdomainAvailability } from "@/lib/vercel/domains";

/**
 * POST /api/domains/check — Check if a subdomain is available.
 *
 * Body: { slug: string }
 * Returns: { available: boolean, reason?: string }
 *
 * The checkSubdomainAvailability function handles:
 * - Slug format validation (length, characters, reserved names)
 * - Platform DB check (tenants + tenant_domains tables)
 * - Vercel domain check
 */
export async function POST(request: Request) {
  const token = await getAuthToken();
  if (!token) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  let body: { slug?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { available: false, reason: "Invalid request body" },
      { status: 400 },
    );
  }

  const { slug } = body;
  if (!slug) {
    return NextResponse.json(
      { available: false, reason: "Subdomain is required" },
      { status: 400 },
    );
  }

  const result = await checkSubdomainAvailability(slug);
  return NextResponse.json(result);
}
