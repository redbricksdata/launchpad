import { redirect } from "next/navigation";
import { getAuthToken, getProfile, getSubscriptionStatus } from "@/lib/auth";
import { getPlatformClient } from "@/lib/platform-db";
import type { Tenant, TenantDomain } from "@/types/tenant";
import AppShell from "@/components/AppShell";
import StatusBadge from "@/components/StatusBadge";
import StatCard from "@/components/StatCard";

const RBOS_URL = process.env.NEXT_PUBLIC_RBOS_URL || "https://rbos.redbricksdata.com";

const THEME_COLORS: Record<string, string> = {
  "luxury-blue": "border-l-blue-600",
  "modern-green": "border-l-emerald-600",
  "warm-gold": "border-l-amber-600",
  "urban-dark": "border-l-slate-800",
};

function timeAgo(date: string): string {
  const seconds = Math.floor(
    (Date.now() - new Date(date).getTime()) / 1000,
  );
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  return `${months}mo ago`;
}

export default async function DashboardPage() {
  const token = await getAuthToken();
  if (!token) redirect("/login");

  let user;
  try {
    user = await getProfile(token);
  } catch {
    redirect("/login");
  }

  // Check for active RBOS subscription — redirect to RBOS subscribe page if none
  try {
    const { subscribed } = await getSubscriptionStatus(token);
    if (!subscribed) {
      redirect(`${RBOS_URL}/subscribe`);
    }
  } catch {
    // If subscription check fails, let them through (graceful degradation)
  }

  // Fetch agent's sites
  const db = getPlatformClient();
  const { data: tenants } = await db
    .from("tenants")
    .select("*, tenant_domains(*)")
    .eq("admin_email", user.email)
    .order("created_at", { ascending: false });

  const sites = (tenants || []) as (Tenant & { tenant_domains: TenantDomain[] })[];
  const baseDomain = process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "rbos.app";

  const activeSites = sites.filter((s) => s.status === "active");
  const provisioningSites = sites.filter((s) => s.status === "provisioning");

  const firstName = user.name?.split(" ")[0] || "there";

  return (
    <AppShell email={user.email}>
      {/* Heading + CTA */}
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[var(--color-text-primary)]">
            Welcome back, {firstName}
          </h1>
          <p className="mt-1 text-sm text-[var(--color-text-secondary)]">
            Manage your pre-construction real estate websites
          </p>
        </div>
        <a
          href="/launch"
          className="inline-flex items-center justify-center rounded-lg bg-[var(--color-primary)] px-5 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)] sm:w-auto"
        >
          + Launch New Site
        </a>
      </div>

      {/* Stats */}
      {sites.length > 0 && (
        <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <StatCard label="Total Sites" value={sites.length} />
          <StatCard label="Active" value={activeSites.length} />
          <StatCard
            label="Provisioning"
            value={provisioningSites.length}
            highlight={provisioningSites.length > 0}
          />
          <StatCard label="Template" value="v1" />
        </div>
      )}

      {sites.length === 0 ? (
        /* Empty state */
        <div className="rounded-2xl border-2 border-dashed border-[var(--color-border)] py-20 text-center">
          <div className="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-full bg-blue-50 text-[var(--color-primary)]">
            <svg className="h-10 w-10" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418" />
            </svg>
          </div>
          <h3 className="text-lg font-semibold text-[var(--color-text-primary)]">
            No sites yet
          </h3>
          <p className="mx-auto mt-2 max-w-sm text-sm text-[var(--color-text-secondary)]">
            Pick a theme, add your API keys, and launch your pre-construction
            real estate site in under 60 seconds.
          </p>
          <a
            href="/launch"
            className="mt-5 inline-block rounded-lg bg-[var(--color-primary)] px-6 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)]"
          >
            Launch Your First Site
          </a>
        </div>
      ) : (
        /* Site cards */
        <div className="grid gap-4">
          {sites.map((site) => {
            const primaryDomain = site.tenant_domains?.find(
              (d) => d.is_primary,
            );
            const hostname =
              primaryDomain?.hostname || `${site.slug}.${baseDomain}`;
            const url = `https://${hostname}`;
            const themeColor =
              THEME_COLORS[site.theme_preset] || "border-l-gray-400";
            const featureCount = site.feature_flags
              ? Object.values(site.feature_flags).filter(Boolean).length
              : 0;
            const domainCount = site.tenant_domains?.length || 0;

            return (
              <div
                key={site.id}
                className={`rounded-xl border border-[var(--color-border)] border-l-4 ${themeColor} bg-white p-5 transition hover:shadow-sm`}
              >
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="text-base font-semibold text-[var(--color-text-primary)]">
                        {site.display_name}
                      </h3>
                      <StatusBadge status={site.status} />
                    </div>
                    <a
                      href={url}
                      target="_blank"
                      rel="noopener"
                      className="mt-0.5 text-sm text-[var(--color-primary)] hover:underline"
                    >
                      {hostname}
                    </a>
                  </div>

                  <div className="flex gap-2">
                    {site.status === "active" && (
                      <a
                        href={`${url}/admin`}
                        target="_blank"
                        rel="noopener"
                        className="rounded-lg bg-[var(--color-primary)] px-3 py-1.5 text-xs font-medium text-white transition hover:bg-[var(--color-primary-dark)]"
                      >
                        Admin
                      </a>
                    )}
                    <a
                      href={`/sites/${site.id}`}
                      className="rounded-lg border border-[var(--color-border)] px-3 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
                    >
                      Details
                    </a>
                  </div>
                </div>

                <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-[var(--color-text-muted)]">
                  <span>
                    Theme:{" "}
                    {site.theme_preset
                      .replace("-", " ")
                      .replace(/\b\w/g, (c) => c.toUpperCase())}
                  </span>
                  {featureCount > 0 && (
                    <span>{featureCount} features</span>
                  )}
                  {domainCount > 0 && (
                    <span>
                      {domainCount} domain{domainCount !== 1 ? "s" : ""}
                    </span>
                  )}
                  <span>Created {timeAgo(site.created_at)}</span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}
