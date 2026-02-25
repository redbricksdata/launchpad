import { NextResponse } from "next/server";
import { getPlatformClient } from "@/lib/platform-db";
import {
  validateAdminApiKey,
  upgradeTenant,
  getMigrationsSince,
  getLatestMigrationVersion,
} from "@/lib/provisioning/tenant-upgrade";

/**
 * GET /api/admin/upgrade/[tenantId] — Check a single tenant's upgrade status.
 */
export async function GET(
  request: Request,
  { params }: { params: Promise<{ tenantId: string }> },
) {
  const adminKey = request.headers.get("x-admin-key");
  if (!validateAdminApiKey(adminKey)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { tenantId } = await params;

  // Validate UUID format
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tenantId)) {
    return NextResponse.json({ error: "Invalid tenant ID format" }, { status: 400 });
  }

  const db = getPlatformClient();

  const { data: tenant, error } = await db
    .from("tenants")
    .select("id, slug, display_name, status, schema_version, supabase_project_ref, created_at")
    .eq("id", tenantId)
    .single();

  if (error || !tenant) {
    return NextResponse.json({ error: "Tenant not found" }, { status: 404 });
  }

  const latestVersion = getLatestMigrationVersion();
  const pendingMigrations = getMigrationsSince(tenant.schema_version);

  return NextResponse.json({
    tenant: {
      id: tenant.id,
      slug: tenant.slug,
      displayName: tenant.display_name,
      status: tenant.status,
      schemaVersion: tenant.schema_version,
      hasSupabaseProject: !!tenant.supabase_project_ref,
      createdAt: tenant.created_at,
    },
    latestVersion,
    pendingMigrations: pendingMigrations.length,
    pendingMigrationFiles: pendingMigrations.map((m) => m.filename),
    isUpToDate: pendingMigrations.length === 0,
  });
}

/**
 * POST /api/admin/upgrade/[tenantId] — Upgrade a single tenant.
 *
 * Useful for retrying after a failure or upgrading a specific tenant.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ tenantId: string }> },
) {
  const adminKey = request.headers.get("x-admin-key");
  if (!validateAdminApiKey(adminKey)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { tenantId } = await params;

  // Validate UUID format
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tenantId)) {
    return NextResponse.json({ error: "Invalid tenant ID format" }, { status: 400 });
  }

  try {
    const result = await upgradeTenant(tenantId);

    const statusCode = result.status === "failed" ? 500 : 200;
    return NextResponse.json(result, { status: statusCode });
  } catch (error) {
    return NextResponse.json(
      {
        error: `Upgrade failed: ${
          error instanceof Error ? error.message : "unknown"
        }`,
      },
      { status: 500 },
    );
  }
}
