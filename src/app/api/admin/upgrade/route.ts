import { NextResponse } from "next/server";
import { getPlatformClient } from "@/lib/platform-db";
import {
  validateAdminApiKey,
  upgradeAllTenants,
  getUpgradeStatus,
  getLatestMigrationVersion,
} from "@/lib/provisioning/tenant-upgrade";
import type { TenantJobStep } from "@/types/tenant";

/**
 * GET /api/admin/upgrade — Check upgrade status for all tenants.
 *
 * Returns each tenant's current schema_version vs the latest available,
 * plus how many migrations are pending per tenant.
 */
export async function GET(request: Request) {
  const adminKey = request.headers.get("x-admin-key");
  if (!validateAdminApiKey(adminKey)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const status = await getUpgradeStatus();
    return NextResponse.json(status);
  } catch (error) {
    return NextResponse.json(
      {
        error: `Failed to get upgrade status: ${
          error instanceof Error ? error.message : "unknown"
        }`,
      },
      { status: 500 },
    );
  }
}

/**
 * POST /api/admin/upgrade — Trigger batch upgrade of all active tenants.
 *
 * Runs pending migrations on every active tenant sequentially.
 * Creates a tenant_jobs record for tracking.
 *
 * This is a long-running request — consider running from a script or
 * with a generous timeout rather than from a browser.
 */
export async function POST(request: Request) {
  const adminKey = request.headers.get("x-admin-key");
  if (!validateAdminApiKey(adminKey)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const db = getPlatformClient();
  const latestVersion = getLatestMigrationVersion();

  // Create a job record for tracking
  const { data: job } = await db
    .from("tenant_jobs")
    .insert({
      // Use a synthetic tenant_id for batch jobs — we need a valid UUID
      // In practice, batch upgrade jobs aren't tied to a single tenant
      tenant_id: "00000000-0000-0000-0000-000000000000",
      job_type: "upgrade",
      status: "running",
      steps: [
        {
          name: `Upgrading all tenants to ${latestVersion || "latest"}`,
          status: "running",
          started_at: new Date().toISOString(),
        },
      ] as TenantJobStep[],
    })
    .select()
    .single();

  const jobId = job?.id || null;

  try {
    const results = await upgradeAllTenants((result, index, total) => {
      // Update job steps as we go (fire and forget)
      if (jobId) {
        const stepName = `[${index + 1}/${total}] ${result.slug}: ${result.status}${
          result.migrationsRun > 0 ? ` (${result.migrationsRun} migrations)` : ""
        }`;
        db.from("tenant_jobs")
          .select("steps")
          .eq("id", jobId)
          .single()
          .then(({ data }) => {
            if (!data) return;
            const steps = data.steps as TenantJobStep[];
            steps.push({
              name: stepName,
              status: result.status === "failed" ? "failed" : "completed",
              completed_at: new Date().toISOString(),
            });
            db.from("tenant_jobs")
              .update({ steps })
              .eq("id", jobId)
              .then(() => {});
          });
      }
    });

    // Mark job as completed
    if (jobId) {
      await db
        .from("tenant_jobs")
        .update({
          status: results.failed > 0 ? "failed" : "completed",
          completed_at: new Date().toISOString(),
          error:
            results.failed > 0
              ? `${results.failed} tenant(s) failed to upgrade`
              : null,
        })
        .eq("id", jobId);
    }

    return NextResponse.json({
      jobId,
      latestVersion,
      ...results,
    });
  } catch (error) {
    if (jobId) {
      await db
        .from("tenant_jobs")
        .update({
          status: "failed",
          completed_at: new Date().toISOString(),
          error:
            error instanceof Error ? error.message : "Unknown batch upgrade error",
        })
        .eq("id", jobId);
    }

    return NextResponse.json(
      {
        error: `Batch upgrade failed: ${
          error instanceof Error ? error.message : "unknown"
        }`,
      },
      { status: 500 },
    );
  }
}
