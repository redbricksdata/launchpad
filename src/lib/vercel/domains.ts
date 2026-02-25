/**
 * Vercel Domains API client for managing agent site domains.
 *
 * Handles:
 * - Adding subdomain aliases (*.red-bricks.app)
 * - Adding custom domains with DNS verification
 * - Checking domain availability (platform DB + Vercel)
 *
 * Note: Vercel uses per-endpoint API versioning, so different
 * version prefixes (v6, v9, v10) are intentional and correct.
 */

import { getPlatformClient } from "@/lib/platform-db";

const VERCEL_API = "https://api.vercel.com";

/** Valid slug format: 2-63 chars, lowercase alphanumeric + hyphens, no leading/trailing hyphen */
const SLUG_REGEX = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

/** Reserved slugs that cannot be used */
const RESERVED_SLUGS = new Set([
  "www",
  "api",
  "app",
  "admin",
  "mail",
  "ftp",
  "ns1",
  "ns2",
  "blog",
  "help",
  "support",
  "status",
  "docs",
  "cdn",
  "static",
  "assets",
  "media",
  "test",
  "staging",
  "dev",
  "demo",
  "launchpad",
  "platform",
  "dashboard",
]);

/** Check if Vercel credentials are configured */
function isVercelConfigured(): boolean {
  return !!(process.env.VERCEL_TOKEN && process.env.VERCEL_PROJECT_ID);
}

function getHeaders() {
  const token = process.env.VERCEL_TOKEN;
  if (!token) throw new Error("VERCEL_TOKEN is required");
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
}

function getTeamParam(): string {
  const teamId = process.env.VERCEL_TEAM_ID;
  return teamId ? `?teamId=${teamId}` : "";
}

function getProjectId(): string {
  const projectId = process.env.VERCEL_PROJECT_ID;
  if (!projectId) throw new Error("VERCEL_PROJECT_ID is required");
  return projectId;
}

/**
 * Validate a slug format.
 */
export function validateSlugFormat(slug: string): {
  valid: boolean;
  reason?: string;
} {
  if (slug.length < 2) {
    return { valid: false, reason: "Must be at least 2 characters" };
  }
  if (slug.length > 63) {
    return { valid: false, reason: "Must be 63 characters or fewer" };
  }
  if (!SLUG_REGEX.test(slug)) {
    return {
      valid: false,
      reason:
        "Only lowercase letters, numbers, and hyphens allowed. Cannot start or end with a hyphen.",
    };
  }
  if (RESERVED_SLUGS.has(slug)) {
    return { valid: false, reason: "This subdomain is reserved" };
  }
  return { valid: true };
}

/**
 * Add a domain to the Vercel project (the multi-tenant template deployment).
 */
export async function addDomain(domain: string): Promise<{
  success: boolean;
  verified: boolean;
  skipped?: boolean;
  error?: string;
}> {
  // Gracefully skip if Vercel credentials aren't configured (e.g., local dev, domain not purchased yet)
  if (!isVercelConfigured()) {
    console.warn(`[Vercel] Skipping domain setup for "${domain}" — VERCEL_TOKEN or VERCEL_PROJECT_ID not set`);
    return { success: true, verified: false, skipped: true };
  }

  const projectId = getProjectId();

  const res = await fetch(
    `${VERCEL_API}/v10/projects/${projectId}/domains${getTeamParam()}`,
    {
      method: "POST",
      headers: getHeaders(),
      body: JSON.stringify({ name: domain }),
    },
  );

  if (res.ok) {
    const data = await res.json();
    return {
      success: true,
      verified: data.verified || false,
    };
  }

  const body = await res.json().catch(() => ({}));

  // Domain already exists on this project — that's fine
  if (body?.error?.code === "domain_already_in_use") {
    return { success: true, verified: true };
  }

  return {
    success: false,
    verified: false,
    error: body?.error?.message || `Failed to add domain (${res.status})`,
  };
}

/**
 * Remove a domain from the Vercel project.
 */
export async function removeDomain(domain: string): Promise<boolean> {
  const projectId = getProjectId();

  const res = await fetch(
    `${VERCEL_API}/v9/projects/${projectId}/domains/${encodeURIComponent(domain)}${getTeamParam()}`,
    {
      method: "DELETE",
      headers: getHeaders(),
    },
  );

  return res.ok;
}

/**
 * Check if a subdomain is available.
 *
 * Checks BOTH:
 * 1. Platform DB (tenant_domains + tenants tables) — catches claimed slugs even if Vercel setup failed
 * 2. Vercel project domains — catches domains added outside the platform
 */
export async function checkSubdomainAvailability(
  slug: string,
): Promise<{ available: boolean; reason?: string }> {
  // 1. Validate the slug format first
  const formatCheck = validateSlugFormat(slug);
  if (!formatCheck.valid) {
    return { available: false, reason: formatCheck.reason };
  }

  const baseDomain =
    process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "red-bricks.app";
  const fullDomain = `${slug}.${baseDomain}`;

  // 2. Check platform DB — this is the source of truth
  const db = getPlatformClient();

  // Check tenants table for the slug
  const { data: existingTenant } = await db
    .from("tenants")
    .select("id, status")
    .eq("slug", slug)
    .not("status", "eq", "archived")
    .maybeSingle();

  if (existingTenant) {
    return { available: false, reason: "Subdomain is already taken" };
  }

  // Check tenant_domains for the full hostname
  const { data: existingDomain } = await db
    .from("tenant_domains")
    .select("id")
    .eq("hostname", fullDomain)
    .maybeSingle();

  if (existingDomain) {
    return { available: false, reason: "Subdomain is already taken" };
  }

  // 3. Check Vercel as a secondary confirmation (skip if not configured)
  if (isVercelConfigured()) {
    const projectId = getProjectId();

    const res = await fetch(
      `${VERCEL_API}/v9/projects/${projectId}/domains/${encodeURIComponent(fullDomain)}${getTeamParam()}`,
      { headers: getHeaders() },
    );

    if (res.ok) {
      // Domain exists in Vercel but not in our DB — probably an orphan,
      // but still treat as unavailable to be safe
      return { available: false, reason: "Subdomain is already taken" };
    }
  }

  return { available: true };
}

/**
 * Get the DNS verification record for a custom domain.
 * Uses the Vercel global domains config endpoint (v6).
 */
export async function getDomainConfig(
  domain: string,
): Promise<{ verified: boolean; cname?: string; txtRecord?: string }> {
  const res = await fetch(
    `${VERCEL_API}/v6/domains/${encodeURIComponent(domain)}/config${getTeamParam()}`,
    { headers: getHeaders() },
  );

  if (!res.ok) {
    return { verified: false };
  }

  const data = await res.json();
  return {
    verified: !data.misconfigured,
    cname: data.cnames?.[0],
    txtRecord: data.txtRecord,
  };
}
