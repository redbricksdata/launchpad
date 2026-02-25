import { NextResponse } from "next/server";
import { getAuthToken, getProfile, getTeamInfo } from "@/lib/auth";
import { getPlatformClient } from "@/lib/platform-db";
import { encrypt } from "@/lib/encryption";
import {
  createSupabaseProject,
  runTemplateMigrations,
  seedTenantDatabase,
} from "@/lib/provisioning/supabase-project";
import { getLatestMigrationVersion } from "@/lib/provisioning/tenant-upgrade";
import { addDomain, validateSlugFormat } from "@/lib/vercel/domains";
import type { LaunchConfig, TenantJobStep } from "@/types/tenant";

/**
 * POST /api/launch — Full launch orchestration.
 *
 * Creates a tenant, provisions Supabase, configures domain, stores encrypted keys.
 * Returns a job ID that the client polls for progress.
 */
export async function POST(request: Request) {
  const authToken = await getAuthToken();
  if (!authToken) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  let config: LaunchConfig;
  try {
    config = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { slug, displayName, template, themePreset, features } = config;

  // --- Input validation ---
  if (!slug || !displayName) {
    return NextResponse.json(
      { error: "slug and displayName are required" },
      { status: 400 },
    );
  }

  // Validate slug format
  const slugCheck = validateSlugFormat(slug);
  if (!slugCheck.valid) {
    return NextResponse.json(
      { error: slugCheck.reason || "Invalid slug format" },
      { status: 400 },
    );
  }

  // Validate displayName length
  if (displayName.length > 100) {
    return NextResponse.json(
      { error: "Display name must be 100 characters or fewer" },
      { status: 400 },
    );
  }

  const db = getPlatformClient();

  // Get the authenticated user's team info
  let user;
  let teamInfo;
  try {
    user = await getProfile(authToken);
    teamInfo = await getTeamInfo(authToken);
  } catch {
    return NextResponse.json(
      { error: "Failed to verify your account. Please log in again." },
      { status: 401 },
    );
  }

  // Create tenant record
  const { data: tenant, error: tenantError } = await db
    .from("tenants")
    .insert({
      team_id: teamInfo.id,
      slug,
      display_name: displayName,
      template: template || "preconstruction-v1",
      status: "provisioning",
      theme_preset: themePreset || "luxury-blue",
      feature_flags: features || {},
      admin_email: user.email,
    })
    .select()
    .single();

  if (tenantError || !tenant) {
    const msg = tenantError?.code === "23505"
      ? "This subdomain is already taken"
      : tenantError?.message || "Failed to create tenant";
    return NextResponse.json({ error: msg }, { status: 400 });
  }

  // Create the job tracker
  const initialSteps: TenantJobStep[] = [
    { name: "Creating database", status: "pending" },
    { name: "Running migrations", status: "pending" },
    { name: "Seeding configuration", status: "pending" },
    { name: "Configuring domain", status: "pending" },
    { name: "Storing credentials", status: "pending" },
    { name: "Activating site", status: "pending" },
  ];

  const { data: job } = await db
    .from("tenant_jobs")
    .insert({
      tenant_id: tenant.id,
      job_type: "launch",
      status: "running",
      steps: initialSteps,
    })
    .select()
    .single();

  if (!job) {
    // Clean up the tenant record if we can't create a job
    await db.from("tenants").delete().eq("id", tenant.id);
    return NextResponse.json(
      { error: "Failed to create job tracker" },
      { status: 500 },
    );
  }

  // Run the provisioning pipeline asynchronously
  // We return the job ID immediately and the client polls for status
  runLaunchPipeline(tenant.id, job.id, config, teamInfo, user.email).catch(
    (err) => console.error("Launch pipeline error:", err),
  );

  return NextResponse.json({
    tenantId: tenant.id,
    jobId: job.id,
  });
}

/**
 * Asynchronous launch pipeline — runs each step and updates the job tracker.
 */
async function runLaunchPipeline(
  tenantId: string,
  jobId: string,
  config: LaunchConfig,
  teamInfo: { id: number; name: string; apiToken: string | null },
  adminEmail: string,
) {
  const db = getPlatformClient();
  const baseDomain =
    process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "red-bricks.app";

  async function updateStep(
    stepIndex: number,
    status: TenantJobStep["status"],
    error?: string,
  ) {
    // Fetch current steps, update the specific one
    const { data: currentJob } = await db
      .from("tenant_jobs")
      .select("steps")
      .eq("id", jobId)
      .single();

    if (!currentJob) return;

    const steps = currentJob.steps as TenantJobStep[];
    steps[stepIndex] = {
      ...steps[stepIndex],
      status,
      ...(status === "running" ? { started_at: new Date().toISOString() } : {}),
      ...(status === "completed" || status === "failed"
        ? { completed_at: new Date().toISOString() }
        : {}),
      ...(error ? { error } : {}),
    };

    await db
      .from("tenant_jobs")
      .update({ steps })
      .eq("id", jobId);
  }

  async function failJob(error: string) {
    await db
      .from("tenant_jobs")
      .update({ status: "failed", error, completed_at: new Date().toISOString() })
      .eq("id", jobId);

    await db
      .from("tenants")
      .update({ status: "suspended" })
      .eq("id", tenantId);
  }

  try {
    // Step 0: Create Supabase project
    await updateStep(0, "running");
    const supabase = await createSupabaseProject(config.slug);
    await db
      .from("tenants")
      .update({ supabase_project_ref: supabase.ref })
      .eq("id", tenantId);
    await updateStep(0, "completed");

    // Step 1: Run migrations on the new tenant database
    await updateStep(1, "running");
    try {
      await runTemplateMigrations(supabase.ref);
    } catch (migrationError) {
      const msg =
        migrationError instanceof Error
          ? migrationError.message
          : "Unknown migration error";
      await updateStep(1, "failed", msg);
      await failJob(`Migration failed: ${msg}`);
      return;
    }
    await updateStep(1, "completed");

    // Record the schema version so upgrades know where this tenant starts
    const latestVersion = getLatestMigrationVersion();
    if (latestVersion) {
      await db
        .from("tenants")
        .update({ schema_version: latestVersion })
        .eq("id", tenantId);
    }

    // Step 2: Seed configuration using the Supabase JS client (no SQL injection risk)
    await updateStep(2, "running");
    await seedTenantDatabase(supabase.ref, supabase.apiUrl, supabase.serviceRoleKey, {
      siteName: config.displayName,
      themePreset: config.themePreset || "luxury-blue",
      adminEmail,
      features: config.features || {},
    });
    await updateStep(2, "completed");

    // Step 3: Configure domain in Vercel
    await updateStep(3, "running");
    const hostname = `${config.slug}.${baseDomain}`;
    const domainResult = await addDomain(hostname);

    if (!domainResult.success) {
      await updateStep(3, "failed", domainResult.error);
      await failJob(`Domain configuration failed: ${domainResult.error}`);
      return;
    }

    // Record the subdomain mapping
    const hasCustomDomain = !!config.customDomain;
    await db.from("tenant_domains").insert({
      tenant_id: tenantId,
      hostname,
      is_primary: !hasCustomDomain,
      ssl_status: domainResult.verified ? "active" : "pending",
    });

    // If user provided a custom domain, add it too
    if (config.customDomain) {
      const customResult = await addDomain(config.customDomain);
      // Custom domain failure is non-fatal — subdomain still works
      await db.from("tenant_domains").insert({
        tenant_id: tenantId,
        hostname: config.customDomain,
        is_primary: true,
        ssl_status: customResult.success && customResult.verified ? "active" : "pending",
      });
    }

    await updateStep(3, "completed");

    // Step 4: Store encrypted credentials (batch upsert)
    await updateStep(4, "running");
    const keysToStore: { tenant_id: string; key_type: string; encrypted_value: string; validated_at: string }[] = [];

    const now = new Date().toISOString();

    // Core Supabase keys (always present — we just created them)
    keysToStore.push(
      { tenant_id: tenantId, key_type: "supabase_url", encrypted_value: encrypt(supabase.apiUrl), validated_at: now },
      { tenant_id: tenantId, key_type: "supabase_anon_key", encrypted_value: encrypt(supabase.anonKey), validated_at: now },
      { tenant_id: tenantId, key_type: "supabase_service_role", encrypted_value: encrypt(supabase.serviceRoleKey), validated_at: now },
    );

    // Red Bricks API token from the team
    if (teamInfo.apiToken) {
      keysToStore.push({
        tenant_id: tenantId,
        key_type: "redbricks_token",
        encrypted_value: encrypt(teamInfo.apiToken),
        validated_at: now,
      });
    }

    // Optional keys from the wizard
    if (config.googleMapsKey) {
      keysToStore.push({
        tenant_id: tenantId,
        key_type: "google_maps",
        encrypted_value: encrypt(config.googleMapsKey),
        validated_at: now,
      });
    }

    // AI key — stored under the selected provider type
    const aiKey = config.aiKey || config.geminiKey;
    const aiKeyType = config.aiProvider || "gemini";
    if (aiKey) {
      keysToStore.push({
        tenant_id: tenantId,
        key_type: aiKeyType,
        encrypted_value: encrypt(aiKey),
        validated_at: now,
      });
    }

    // Email key — stored under the selected provider type
    const emailKey = config.emailKey || config.resendKey;
    const emailKeyType = config.emailProvider || "resend";
    if (emailKey) {
      keysToStore.push({
        tenant_id: tenantId,
        key_type: emailKeyType,
        encrypted_value: encrypt(emailKey),
        validated_at: now,
      });
    }

    // Batch upsert all keys in one query
    const { error: keysError } = await db
      .from("tenant_keys")
      .upsert(keysToStore, { onConflict: "tenant_id,key_type" });

    if (keysError) {
      await updateStep(4, "failed", keysError.message);
      await failJob(`Failed to store credentials: ${keysError.message}`);
      return;
    }
    await updateStep(4, "completed");

    // Step 5: Activate the site
    await updateStep(5, "running");
    await db
      .from("tenants")
      .update({ status: "active" })
      .eq("id", tenantId);
    await updateStep(5, "completed");

    // Mark job as completed
    await db
      .from("tenant_jobs")
      .update({
        status: "completed",
        completed_at: new Date().toISOString(),
      })
      .eq("id", jobId);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Unknown error during launch";
    await failJob(message);
  }
}
