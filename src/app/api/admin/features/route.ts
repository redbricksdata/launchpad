import { NextResponse } from "next/server";
import {
  validateAdminApiKey,
  propagateFeatureFlagsToAll,
} from "@/lib/provisioning/tenant-upgrade";

/**
 * POST /api/admin/features — Propagate new feature flags to all active tenants.
 *
 * Body: { flags: Record<string, boolean> }
 *
 * Only ADDS flags that don't already exist on each tenant — never
 * overrides existing agent customizations.
 *
 * Updates both:
 * - Platform DB: tenants.feature_flags (central metadata)
 * - Tenant's own Supabase: site_config.features (runtime config)
 */
export async function POST(request: Request) {
  const adminKey = request.headers.get("x-admin-key");
  if (!validateAdminApiKey(adminKey)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: { flags?: Record<string, boolean> };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { error: "Invalid request body" },
      { status: 400 },
    );
  }

  const { flags } = body;

  if (!flags || typeof flags !== "object" || Object.keys(flags).length === 0) {
    return NextResponse.json(
      { error: "flags must be a non-empty object of { flagName: boolean }" },
      { status: 400 },
    );
  }

  // Validate all values are booleans
  for (const [key, value] of Object.entries(flags)) {
    if (typeof value !== "boolean") {
      return NextResponse.json(
        { error: `Flag "${key}" must be a boolean, got ${typeof value}` },
        { status: 400 },
      );
    }
  }

  try {
    const result = await propagateFeatureFlagsToAll(flags);

    return NextResponse.json({
      message: `Propagated ${Object.keys(flags).length} flag(s) to ${result.tenantsUpdated} tenant(s)`,
      ...result,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: `Feature propagation failed: ${
          error instanceof Error ? error.message : "unknown"
        }`,
      },
      { status: 500 },
    );
  }
}
