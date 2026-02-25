import { NextResponse } from "next/server";
import { getAuthToken, getProfile } from "@/lib/auth";
import { getPlatformClient } from "@/lib/platform-db";
/**
 * GET /api/launch/status?jobId=xxx — Poll for launch job progress.
 *
 * Only the tenant's admin can poll their own jobs (ownership check).
 */
export async function GET(request: Request) {
  const token = await getAuthToken();
  if (!token) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const jobId = searchParams.get("jobId");

  if (!jobId) {
    return NextResponse.json(
      { error: "jobId is required" },
      { status: 400 },
    );
  }

  // Validate jobId format (UUID)
  const UUID_REGEX =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID_REGEX.test(jobId)) {
    return NextResponse.json({ error: "Invalid jobId format" }, { status: 400 });
  }

  // Get the authenticated user
  let user;
  try {
    user = await getProfile(token);
  } catch {
    return NextResponse.json(
      { error: "Session expired. Please log in again." },
      { status: 401 },
    );
  }

  const db = getPlatformClient();

  // Fetch job — query jobs and tenant separately to avoid
  // complex joined type inference issues
  const { data: job, error } = await db
    .from("tenant_jobs")
    .select("*")
    .eq("id", jobId)
    .single();

  if (error || !job) {
    return NextResponse.json({ error: "Job not found" }, { status: 404 });
  }

  // Fetch the associated tenant for ownership check + response data
  const { data: tenant } = await db
    .from("tenants")
    .select("slug, status, display_name, admin_email")
    .eq("id", job.tenant_id)
    .single();

  // Ownership check: only the tenant's admin can view this job
  if (!tenant || tenant.admin_email !== user.email) {
    return NextResponse.json({ error: "Job not found" }, { status: 404 });
  }

  const baseDomain =
    process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "red-bricks.app";

  return NextResponse.json({
    jobId: job.id,
    status: job.status,
    steps: job.steps,
    error: job.error,
    tenant: {
      slug: tenant.slug,
      status: tenant.status,
      displayName: tenant.display_name,
      url: `https://${tenant.slug}.${baseDomain}`,
    },
  });
}
