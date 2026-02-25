/**
 * Supabase Management API client for auto-provisioning agent databases.
 *
 * Creates a new Supabase project per agent, waits for it to be ready,
 * runs template migrations, seeds config, and returns credentials.
 */

import crypto from "crypto";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";

const MANAGEMENT_URL = "https://api.supabase.com/v1";

/** Maximum time to wait for a project to become active (2 minutes) */
const PROJECT_READY_TIMEOUT_MS = 120_000;
const POLL_INTERVAL_MS = 3_000;

interface SupabaseProjectResult {
  ref: string;
  apiUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  dbUrl: string;
}

function getManagementToken(): string {
  const token = process.env.SUPABASE_MANAGEMENT_TOKEN;
  if (!token) throw new Error("SUPABASE_MANAGEMENT_TOKEN is required");
  return token;
}

/**
 * Create a new Supabase project for a tenant.
 */
export async function createSupabaseProject(
  slug: string,
): Promise<SupabaseProjectResult> {
  const token = getManagementToken();
  const orgId = process.env.SUPABASE_ORG_ID;
  const region = process.env.SUPABASE_DEFAULT_REGION || "us-east-1";

  if (!orgId) {
    throw new Error("SUPABASE_ORG_ID is required for provisioning.");
  }

  // Generate a strong random DB password
  const dbPassword = crypto.randomBytes(24).toString("base64url");

  const createRes = await fetch(`${MANAGEMENT_URL}/projects`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name: `rb-${slug}`,
      organization_id: orgId,
      region,
      db_pass: dbPassword,
      plan: "free",
    }),
  });

  if (!createRes.ok) {
    const body = await createRes.text().catch(() => "");
    throw new Error(
      `Failed to create Supabase project (${createRes.status}): ${body}`,
    );
  }

  const project = await createRes.json();
  const ref = project.id;

  // Wait for the project to become active
  const startTime = Date.now();

  while (Date.now() - startTime < PROJECT_READY_TIMEOUT_MS) {
    await sleep(POLL_INTERVAL_MS);

    const statusRes = await fetch(`${MANAGEMENT_URL}/projects/${ref}`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (statusRes.ok) {
      const statusData = await statusRes.json();
      if (statusData.status === "ACTIVE_HEALTHY") {
        break;
      }
      if (
        statusData.status === "INACTIVE" ||
        statusData.status === "REMOVED"
      ) {
        throw new Error(
          `Supabase project creation failed: ${statusData.status}`,
        );
      }
    }

    // Check timeout
    if (Date.now() - startTime >= PROJECT_READY_TIMEOUT_MS) {
      throw new Error(
        "Supabase project creation timed out after 2 minutes. The project may still be provisioning — check the Supabase dashboard.",
      );
    }
  }

  // Fetch the API keys
  const keysRes = await fetch(
    `${MANAGEMENT_URL}/projects/${ref}/api-keys`,
    { headers: { Authorization: `Bearer ${token}` } },
  );

  if (!keysRes.ok) {
    throw new Error(`Failed to fetch API keys for project ${ref}`);
  }

  const keys = await keysRes.json();
  const anonKey = keys.find(
    (k: { name: string }) => k.name === "anon",
  )?.api_key;
  const serviceRoleKey = keys.find(
    (k: { name: string }) => k.name === "service_role",
  )?.api_key;

  if (!anonKey || !serviceRoleKey) {
    throw new Error(
      "Failed to retrieve API keys from new Supabase project. Keys found: " +
        keys.map((k: { name: string }) => k.name).join(", "),
    );
  }

  return {
    ref,
    apiUrl: `https://${ref}.supabase.co`,
    anonKey,
    serviceRoleKey,
    dbUrl: `postgresql://postgres:${encodeURIComponent(dbPassword)}@db.${ref}.supabase.co:5432/postgres`,
  };
}

/**
 * Run SQL on a Supabase project via the Management API.
 */
export async function runSqlViaApi(
  projectRef: string,
  sql: string,
): Promise<void> {
  const token = getManagementToken();

  const res = await fetch(
    `${MANAGEMENT_URL}/projects/${projectRef}/database/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query: sql }),
    },
  );

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`SQL execution failed (${res.status}): ${body}`);
  }
}

/**
 * Read and run all template migrations on a new tenant project.
 *
 * Reads migration files from the template's supabase/migrations/ directory
 * and runs them in order via the Management API.
 */
export async function runTemplateMigrations(
  projectRef: string,
): Promise<void> {
  const migrationsDir = resolveTemplateMigrationsDir();

  if (!migrationsDir) {
    console.warn(
      "Template migrations directory not found. Skipping migrations. " +
        "Tenant database will need migrations run manually.",
    );
    return;
  }

  // Read all migration files, sorted by filename (timestamp order)
  const files = readdirSync(migrationsDir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  if (files.length === 0) {
    console.warn("No migration files found in", migrationsDir);
    return;
  }

  // Enable required extensions first
  await runSqlViaApi(
    projectRef,
    "CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS pg_trgm;",
  );

  // Run each migration in order
  for (const file of files) {
    const sql = readFileSync(join(migrationsDir, file), "utf-8");
    try {
      await runSqlViaApi(projectRef, sql);
    } catch (error) {
      throw new Error(
        `Migration ${file} failed: ${error instanceof Error ? error.message : "unknown error"}`,
      );
    }
  }
}

/**
 * Resolve the path to the template's migrations directory.
 *
 * Checks multiple locations to work in both dev and production:
 * 1. Bundled: supabase/template-migrations/ in the Launchpad app (for Vercel deploy)
 * 2. Monorepo: ../../supabase/migrations/ from apps/launchpad/ (for local dev)
 * 3. Fallback: relative to this source file
 */
function resolveTemplateMigrationsDir(): string | null {
  const candidates = [
    // Production: bundled template migrations (copied at build time)
    join(process.cwd(), "supabase/template-migrations"),
    // Dev: monorepo structure (apps/launchpad/ → ../../supabase/migrations/)
    join(process.cwd(), "../../supabase/migrations"),
    // Alt dev: different cwd
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

/**
 * Seed a new tenant's Supabase with initial config.
 * Uses parameterized values via Supabase JS client to prevent SQL injection.
 */
export async function seedTenantDatabase(
  projectRef: string,
  supabaseUrl: string,
  serviceRoleKey: string,
  config: {
    siteName: string;
    themePreset: string;
    adminEmail: string;
    features: Record<string, boolean>;
  },
): Promise<void> {
  // Use the Supabase JS client with service_role key for safe inserts
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient(supabaseUrl, serviceRoleKey);

  // Insert site config rows
  const configRows = [
    {
      key: "branding",
      value: JSON.stringify({
        siteName: config.siteName,
        logoUrl: null,
        faviconUrl: null,
      }),
    },
    {
      key: "theme",
      value: JSON.stringify({ preset: config.themePreset }),
    },
    {
      key: "features",
      value: JSON.stringify(config.features),
    },
  ];

  const { error: configError } = await client
    .from("site_config")
    .upsert(configRows, { onConflict: "key" });

  if (configError) {
    throw new Error(`Failed to seed site_config: ${configError.message}`);
  }

  // Insert admin
  const { error: adminError } = await client
    .from("admins")
    .upsert(
      { email: config.adminEmail },
      { onConflict: "email" },
    );

  if (adminError) {
    throw new Error(`Failed to seed admin: ${adminError.message}`);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
