/**
 * Red Bricks OS — Tenant Upgrade System
 *
 * Handles upgrading existing tenant databases when new template migrations
 * are added. Each tenant tracks a `schema_version` (the timestamp of the
 * last applied migration). This module finds and runs only NEW migrations
 * on each tenant's Supabase project via the Management API.
 *
 * Also handles propagating new feature flags to existing tenants without
 * overriding any agent customizations.
 */

import { readFileSync, readdirSync } from "fs";
import { join } from "path";
import { getPlatformClient } from "@/lib/platform-db";
import { decrypt } from "@/lib/encryption";
import { runSqlViaApi } from "./supabase-project";

// ─── Types ─────────────────────────────────────────────────

export interface MigrationFile {
  /** The timestamp portion of the filename, e.g. "20260223200000" */
  version: string;
  /** Full filename, e.g. "20260223200000_cancellation_analyses.sql" */
  filename: string;
  /** Full filesystem path */
  path: string;
}

export interface TenantUpgradeResult {
  tenantId: string;
  slug: string;
  previousVersion: string | null;
  newVersion: string | null;
  migrationsRun: number;
  status: "upgraded" | "skipped" | "failed";
  error?: string;
}

export interface BatchUpgradeResult {
  upgraded: number;
  skipped: number;
  failed: number;
  details: TenantUpgradeResult[];
}

// ─── Migration Discovery ───────────────────────────────────

/**
 * Resolve the template migrations directory.
 * Same logic as supabase-project.ts but exported for reuse.
 */
function resolveTemplateMigrationsDir(): string | null {
  const candidates = [
    join(process.cwd(), "supabase/template-migrations"),
    join(process.cwd(), "../../supabase/migrations"),
    join(process.cwd(), "../supabase/migrations"),
  ];

  for (const dir of candidates) {
    try {
      const files = readdirSync(dir);
      if (files.some((f) => f.endsWith(".sql"))) {
        return dir;
      }
    } catch {
      // Directory doesn't exist, try next
    }
  }

  return null;
}

/** Extract the timestamp version from a migration filename */
function extractVersion(filename: string): string | null {
  const match = filename.match(/^(\d{14})_/);
  return match ? match[1] : null;
}

/**
 * Get all available template migration files, sorted by version.
 */
export function getAvailableMigrations(): MigrationFile[] {
  const dir = resolveTemplateMigrationsDir();
  if (!dir) return [];

  const files = readdirSync(dir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  return files
    .map((filename) => {
      const version = extractVersion(filename);
      if (!version) return null;
      return {
        version,
        filename,
        path: join(dir, filename),
      };
    })
    .filter((m): m is MigrationFile => m !== null);
}

/**
 * Get migrations that are newer than a given version.
 * If version is null, returns ALL migrations (for tenants that have never
 * tracked their version — shouldn't happen for new launches but handles legacy).
 */
export function getMigrationsSince(
  version: string | null,
): MigrationFile[] {
  const all = getAvailableMigrations();
  if (!version) return all;
  return all.filter((m) => m.version > version);
}

/**
 * Get the version string of the latest available migration.
 * Returns null if no migrations are found.
 */
export function getLatestMigrationVersion(): string | null {
  const all = getAvailableMigrations();
  if (all.length === 0) return null;
  return all[all.length - 1].version;
}

// ─── Admin Auth ────────────────────────────────────────────

/**
 * Validate the admin API key from the x-admin-key header.
 * Returns true if the key matches ADMIN_API_KEY env var.
 */
export function validateAdminApiKey(key: string | null): boolean {
  const expected = process.env.ADMIN_API_KEY;
  if (!expected || !key) return false;

  // Constant-time comparison to prevent timing attacks
  if (key.length !== expected.length) return false;
  let mismatch = 0;
  for (let i = 0; i < key.length; i++) {
    mismatch |= key.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return mismatch === 0;
}

// ─── Single Tenant Upgrade ─────────────────────────────────

/**
 * Upgrade a single tenant's database to the latest schema version.
 *
 * 1. Reads the tenant's current schema_version
 * 2. Finds all migrations newer than that version
 * 3. Runs them sequentially via the Supabase Management API
 * 4. Updates schema_version after EACH migration (crash recovery)
 *
 * Returns the upgrade result.
 */
export async function upgradeTenant(
  tenantId: string,
): Promise<TenantUpgradeResult> {
  const db = getPlatformClient();

  // Fetch tenant
  const { data: tenant, error: tenantError } = await db
    .from("tenants")
    .select("id, slug, supabase_project_ref, schema_version, status")
    .eq("id", tenantId)
    .single();

  if (tenantError || !tenant) {
    return {
      tenantId,
      slug: "unknown",
      previousVersion: null,
      newVersion: null,
      migrationsRun: 0,
      status: "failed",
      error: `Tenant not found: ${tenantError?.message || "no data"}`,
    };
  }

  if (!tenant.supabase_project_ref) {
    return {
      tenantId,
      slug: tenant.slug,
      previousVersion: tenant.schema_version,
      newVersion: tenant.schema_version,
      migrationsRun: 0,
      status: "failed",
      error: "Tenant has no Supabase project ref — may still be provisioning",
    };
  }

  // Find pending migrations
  const pending = getMigrationsSince(tenant.schema_version);

  if (pending.length === 0) {
    return {
      tenantId,
      slug: tenant.slug,
      previousVersion: tenant.schema_version,
      newVersion: tenant.schema_version,
      migrationsRun: 0,
      status: "skipped",
    };
  }

  const previousVersion = tenant.schema_version;
  let lastAppliedVersion = previousVersion;
  let migrationsRun = 0;

  // Run each migration sequentially
  for (const migration of pending) {
    const sql = readFileSync(migration.path, "utf-8");

    try {
      await runSqlViaApi(tenant.supabase_project_ref, sql);
    } catch (error) {
      // Update version to last successful migration before failing
      if (lastAppliedVersion !== previousVersion) {
        await db
          .from("tenants")
          .update({ schema_version: lastAppliedVersion })
          .eq("id", tenantId);
      }

      return {
        tenantId,
        slug: tenant.slug,
        previousVersion,
        newVersion: lastAppliedVersion,
        migrationsRun,
        status: "failed",
        error: `Migration ${migration.filename} failed: ${
          error instanceof Error ? error.message : "unknown error"
        }`,
      };
    }

    // Update schema_version after each successful migration (crash recovery)
    lastAppliedVersion = migration.version;
    migrationsRun++;

    await db
      .from("tenants")
      .update({ schema_version: migration.version })
      .eq("id", tenantId);
  }

  return {
    tenantId,
    slug: tenant.slug,
    previousVersion,
    newVersion: lastAppliedVersion,
    migrationsRun,
    status: "upgraded",
  };
}

// ─── Batch Upgrade ─────────────────────────────────────────

/**
 * Upgrade all active tenants to the latest schema version.
 * Processes sequentially to respect Supabase Management API rate limits.
 *
 * Optional onProgress callback for real-time status updates.
 */
export async function upgradeAllTenants(
  onProgress?: (result: TenantUpgradeResult, index: number, total: number) => void,
): Promise<BatchUpgradeResult> {
  const db = getPlatformClient();

  // Fetch all active tenants with a Supabase project
  const { data: tenants, error } = await db
    .from("tenants")
    .select("id, slug, schema_version")
    .eq("status", "active")
    .not("supabase_project_ref", "is", null)
    .order("created_at", { ascending: true });

  if (error || !tenants) {
    return {
      upgraded: 0,
      skipped: 0,
      failed: 1,
      details: [
        {
          tenantId: "batch",
          slug: "batch",
          previousVersion: null,
          newVersion: null,
          migrationsRun: 0,
          status: "failed",
          error: `Failed to fetch tenants: ${error?.message || "no data"}`,
        },
      ],
    };
  }

  const results: TenantUpgradeResult[] = [];
  let upgraded = 0;
  let skipped = 0;
  let failed = 0;

  for (let i = 0; i < tenants.length; i++) {
    const tenant = tenants[i];
    const result = await upgradeTenant(tenant.id);

    switch (result.status) {
      case "upgraded":
        upgraded++;
        break;
      case "skipped":
        skipped++;
        break;
      case "failed":
        failed++;
        break;
    }

    results.push(result);
    onProgress?.(result, i, tenants.length);
  }

  return { upgraded, skipped, failed, details: results };
}

// ─── Feature Flag Propagation ──────────────────────────────

/**
 * Propagate new feature flags to a single tenant.
 *
 * Only ADDS flags that don't already exist on the tenant — never
 * overwrites existing customizations. This respects agent choices.
 *
 * Updates both:
 * 1. Platform DB: tenants.feature_flags (central metadata)
 * 2. Tenant's Supabase: site_config.features (runtime config)
 */
export async function propagateFeatureFlags(
  tenantId: string,
  newDefaults: Record<string, boolean>,
): Promise<{ added: string[]; skipped: string[]; error?: string }> {
  const db = getPlatformClient();

  // Fetch current tenant flags
  const { data: tenant, error: tenantError } = await db
    .from("tenants")
    .select("id, slug, feature_flags, supabase_project_ref")
    .eq("id", tenantId)
    .single();

  if (tenantError || !tenant) {
    return {
      added: [],
      skipped: [],
      error: `Tenant not found: ${tenantError?.message || "no data"}`,
    };
  }

  const existingFlags: Record<string, boolean> = tenant.feature_flags || {};
  const added: string[] = [];
  const skipped: string[] = [];
  const mergedFlags = { ...existingFlags };

  for (const [flag, defaultValue] of Object.entries(newDefaults)) {
    if (flag in existingFlags) {
      // Already has this flag — don't override
      skipped.push(flag);
    } else {
      mergedFlags[flag] = defaultValue;
      added.push(flag);
    }
  }

  if (added.length === 0) {
    return { added, skipped };
  }

  // Update Platform DB
  const { error: updateError } = await db
    .from("tenants")
    .update({ feature_flags: mergedFlags })
    .eq("id", tenantId);

  if (updateError) {
    return {
      added: [],
      skipped,
      error: `Failed to update platform DB: ${updateError.message}`,
    };
  }

  // Update tenant's own Supabase site_config if they have a project
  if (tenant.supabase_project_ref) {
    try {
      await updateTenantSiteConfigFeatures(tenantId, mergedFlags);
    } catch (error) {
      return {
        added,
        skipped,
        error: `Platform DB updated but tenant site_config failed: ${
          error instanceof Error ? error.message : "unknown"
        }`,
      };
    }
  }

  return { added, skipped };
}

/**
 * Propagate new feature flags to ALL active tenants.
 */
export async function propagateFeatureFlagsToAll(
  newDefaults: Record<string, boolean>,
): Promise<{
  totalTenants: number;
  tenantsUpdated: number;
  totalFlagsAdded: number;
  errors: Array<{ tenantId: string; slug: string; error: string }>;
}> {
  const db = getPlatformClient();

  const { data: tenants, error } = await db
    .from("tenants")
    .select("id, slug")
    .eq("status", "active")
    .order("created_at", { ascending: true });

  if (error || !tenants) {
    return {
      totalTenants: 0,
      tenantsUpdated: 0,
      totalFlagsAdded: 0,
      errors: [
        {
          tenantId: "batch",
          slug: "batch",
          error: `Failed to fetch tenants: ${error?.message || "no data"}`,
        },
      ],
    };
  }

  let tenantsUpdated = 0;
  let totalFlagsAdded = 0;
  const errors: Array<{ tenantId: string; slug: string; error: string }> = [];

  for (const tenant of tenants) {
    const result = await propagateFeatureFlags(tenant.id, newDefaults);

    if (result.error) {
      errors.push({
        tenantId: tenant.id,
        slug: tenant.slug,
        error: result.error,
      });
    }

    if (result.added.length > 0) {
      tenantsUpdated++;
      totalFlagsAdded += result.added.length;
    }
  }

  return {
    totalTenants: tenants.length,
    tenantsUpdated,
    totalFlagsAdded,
    errors,
  };
}

// ─── Helpers ───────────────────────────────────────────────

/**
 * Update a tenant's site_config.features in their own Supabase DB.
 * Uses the tenant's service_role key (decrypted from Platform DB).
 */
async function updateTenantSiteConfigFeatures(
  tenantId: string,
  features: Record<string, boolean>,
): Promise<void> {
  const db = getPlatformClient();

  // Get the tenant's Supabase credentials
  const { data: keys } = await db
    .from("tenant_keys")
    .select("key_type, encrypted_value")
    .eq("tenant_id", tenantId)
    .in("key_type", ["supabase_url", "supabase_service_role"]);

  if (!keys || keys.length < 2) {
    throw new Error("Missing Supabase credentials for tenant");
  }

  const urlKey = keys.find(
    (k: { key_type: string }) => k.key_type === "supabase_url",
  );
  const serviceKey = keys.find(
    (k: { key_type: string }) => k.key_type === "supabase_service_role",
  );

  if (!urlKey || !serviceKey) {
    throw new Error("Missing Supabase URL or service role key");
  }

  const supabaseUrl = decrypt(urlKey.encrypted_value);
  const serviceRoleKey = decrypt(serviceKey.encrypted_value);

  // Connect to the tenant's Supabase and update site_config
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient(supabaseUrl, serviceRoleKey);

  const { error } = await client
    .from("site_config")
    .upsert(
      { key: "features", value: JSON.stringify(features) },
      { onConflict: "key" },
    );

  if (error) {
    throw new Error(`Failed to update site_config: ${error.message}`);
  }
}

// ─── Status Helpers ────────────────────────────────────────

/**
 * Get upgrade status for all active tenants.
 * Shows current version vs latest available.
 */
export async function getUpgradeStatus(): Promise<{
  latestVersion: string | null;
  totalMigrations: number;
  tenants: Array<{
    id: string;
    slug: string;
    schemaVersion: string | null;
    pendingMigrations: number;
    status: string;
  }>;
}> {
  const db = getPlatformClient();
  const latestVersion = getLatestMigrationVersion();
  const allMigrations = getAvailableMigrations();

  const { data: tenants } = await db
    .from("tenants")
    .select("id, slug, schema_version, status")
    .eq("status", "active")
    .not("supabase_project_ref", "is", null)
    .order("slug", { ascending: true });

  return {
    latestVersion,
    totalMigrations: allMigrations.length,
    tenants: (tenants || []).map(
      (t: { id: string; slug: string; schema_version: string | null; status: string }) => ({
        id: t.id,
        slug: t.slug,
        schemaVersion: t.schema_version,
        pendingMigrations: getMigrationsSince(t.schema_version).length,
        status: t.status,
      }),
    ),
  };
}
