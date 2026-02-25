import { redirect, notFound } from "next/navigation";
import { getAuthToken, getProfile } from "@/lib/auth";
import { getPlatformClient } from "@/lib/platform-db";
import type { Tenant, TenantDomain } from "@/types/tenant";
import AppShell from "@/components/AppShell";
import StatusBadge from "@/components/StatusBadge";

interface Props {
  params: Promise<{ siteId: string }>;
}

export default async function SiteDetailPage({ params }: Props) {
  const { siteId } = await params;
  const token = await getAuthToken();
  if (!token) redirect("/login");

  let user;
  try {
    user = await getProfile(token);
  } catch {
    redirect("/login");
  }

  const db = getPlatformClient();
  const { data: tenant } = await db
    .from("tenants")
    .select("*, tenant_domains(*)")
    .eq("id", siteId)
    .eq("admin_email", user.email)
    .single();

  if (!tenant) notFound();

  const site = tenant as Tenant & { tenant_domains: TenantDomain[] };
  const baseDomain = process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "rbos.app";
  const primaryDomain =
    site.tenant_domains?.find((d) => d.is_primary)?.hostname ||
    `${site.slug}.${baseDomain}`;
  const siteUrl = `https://${primaryDomain}`;
  const adminUrl = `${siteUrl}/admin`;

  // Fetch key status (without exposing values)
  const { data: keys } = await db
    .from("tenant_keys")
    .select("key_type, validated_at, updated_at")
    .eq("tenant_id", siteId);

  const keyStatus = (keys || []).map((k) => ({
    type: k.key_type as string,
    validated: !!k.validated_at,
    updatedAt: k.updated_at,
  }));

  // Classify keys into user-facing vs internal
  const userKeys = keyStatus.filter((k) =>
    ["google_maps", "gemini", "openai", "anthropic", "resend", "sendgrid"].includes(k.type),
  );
  const internalKeys = keyStatus.filter(
    (k) => !["google_maps", "gemini", "openai", "anthropic", "resend", "sendgrid"].includes(k.type),
  );

  return (
    <AppShell
      email={user.email}
      breadcrumbs={[
        { label: "Dashboard", href: "/" },
        { label: site.display_name },
      ]}
    >
      {/* Page header */}
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold text-[var(--color-text-primary)]">
              {site.display_name}
            </h1>
            <StatusBadge status={site.status} />
          </div>
          <a
            href={siteUrl}
            target="_blank"
            rel="noopener"
            className="mt-1 text-sm text-[var(--color-primary)] hover:underline"
          >
            {primaryDomain}
          </a>
        </div>
        <div className="flex gap-2">
          <a
            href={adminUrl}
            target="_blank"
            rel="noopener"
            className="inline-flex items-center justify-center gap-2 rounded-lg bg-[var(--color-primary)] px-5 py-2.5 text-sm font-semibold text-white shadow-lg shadow-blue-500/10 transition hover:bg-[var(--color-primary-dark)]"
          >
            <svg
              className="h-4 w-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
            Open Admin Panel
          </a>
          <a
            href={siteUrl}
            target="_blank"
            rel="noopener"
            className="inline-flex items-center justify-center rounded-lg border border-[var(--color-border)] px-4 py-2.5 text-sm font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
          >
            Visit Site
            <svg
              className="ml-1.5 h-4 w-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
              />
            </svg>
          </a>
        </div>
      </div>

      {/* Admin callout banner */}
      <div className="mb-6 flex items-center gap-3 rounded-xl border border-blue-100 bg-gradient-to-r from-blue-50 to-indigo-50 px-5 py-4">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-100 text-blue-600">
          <svg
            className="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </div>
        <div className="flex-1">
          <p className="text-sm font-medium text-gray-900">
            Manage your site from the admin panel
          </p>
          <p className="text-xs text-gray-600">
            Theme, branding, API keys, blog, CRM, analytics, and all other
            settings are managed from your site&apos;s built-in admin dashboard.
          </p>
        </div>
        <a
          href={adminUrl}
          target="_blank"
          rel="noopener"
          className="shrink-0 text-sm font-medium text-[var(--color-primary)] hover:underline"
        >
          Open &rarr;
        </a>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        {/* Site Info */}
        <div className="rounded-xl border border-[var(--color-border)] bg-white p-6">
          <h2 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--color-text-muted)]">
            Site Info
          </h2>
          <dl className="space-y-3">
            <div className="flex justify-between">
              <dt className="text-sm text-[var(--color-text-muted)]">Status</dt>
              <dd>
                <StatusBadge status={site.status} />
              </dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-sm text-[var(--color-text-muted)]">Theme</dt>
              <dd className="text-sm font-medium text-[var(--color-text-primary)]">
                {site.theme_preset
                  .replace("-", " ")
                  .replace(/\b\w/g, (c) => c.toUpperCase())}
              </dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-sm text-[var(--color-text-muted)]">
                Template
              </dt>
              <dd className="text-sm font-medium text-[var(--color-text-primary)]">
                {site.template}
              </dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-sm text-[var(--color-text-muted)]">
                Created
              </dt>
              <dd className="text-sm text-[var(--color-text-primary)]">
                {new Date(site.created_at).toLocaleDateString()}
              </dd>
            </div>
          </dl>
        </div>

        {/* Domains */}
        <div className="rounded-xl border border-[var(--color-border)] bg-white p-6">
          <h2 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--color-text-muted)]">
            Domains
          </h2>
          {site.tenant_domains?.length > 0 ? (
            <div className="space-y-2">
              {site.tenant_domains.map((d) => (
                <div
                  key={d.id}
                  className="flex items-center justify-between rounded-lg border border-[var(--color-border)] px-3 py-2.5"
                >
                  <span className="text-sm text-[var(--color-text-primary)]">
                    {d.hostname}
                  </span>
                  <div className="flex items-center gap-2">
                    {d.is_primary && (
                      <span className="rounded bg-blue-100 px-1.5 py-0.5 text-[10px] font-semibold text-blue-700">
                        Primary
                      </span>
                    )}
                    <div className="flex items-center gap-1">
                      <span
                        className={`h-2 w-2 rounded-full ${
                          d.ssl_status === "active"
                            ? "bg-green-500"
                            : d.ssl_status === "pending"
                              ? "bg-yellow-500 animate-pulse"
                              : "bg-red-500"
                        }`}
                      />
                      <span className="text-[10px] text-[var(--color-text-muted)]">
                        {d.ssl_status === "active"
                          ? "SSL Active"
                          : d.ssl_status === "pending"
                            ? "SSL Pending"
                            : "SSL Error"}
                      </span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-[var(--color-text-muted)]">
              No domains configured.
            </p>
          )}
        </div>

        {/* API Keys Status — user-facing keys */}
        {userKeys.length > 0 && (
          <div className="rounded-xl border border-[var(--color-border)] bg-white p-6 md:col-span-2">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-sm font-semibold uppercase tracking-wider text-[var(--color-text-muted)]">
                Service Keys
              </h2>
              <a
                href={`${adminUrl}/settings`}
                target="_blank"
                rel="noopener"
                className="text-xs text-[var(--color-primary)] hover:underline"
              >
                Manage in admin &rarr;
              </a>
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {userKeys.map((k) => (
                <div
                  key={k.type}
                  className={`flex items-center justify-between rounded-lg border px-4 py-3 ${
                    k.validated
                      ? "border-green-100 bg-green-50/30"
                      : "border-[var(--color-border)]"
                  }`}
                >
                  <span className="text-sm text-[var(--color-text-primary)]">
                    {formatKeyType(k.type)}
                  </span>
                  <span
                    className={`flex h-5 w-5 items-center justify-center rounded-full ${
                      k.validated
                        ? "bg-green-100 text-green-600"
                        : "bg-gray-100 text-gray-400"
                    }`}
                  >
                    {k.validated ? (
                      <svg
                        className="h-3.5 w-3.5"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2.5}
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                    ) : (
                      <span className="h-2 w-2 rounded-full bg-current" />
                    )}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Internal keys (collapsed) */}
        {internalKeys.length > 0 && (
          <div className="rounded-xl border border-[var(--color-border)] bg-white p-6 md:col-span-2">
            <h2 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--color-text-muted)]">
              Infrastructure
            </h2>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {internalKeys.map((k) => (
                <div
                  key={k.type}
                  className="flex items-center justify-between rounded-lg border border-[var(--color-border)] px-4 py-3"
                >
                  <span className="text-sm text-[var(--color-text-primary)]">
                    {formatKeyType(k.type)}
                  </span>
                  <span
                    className={`flex h-5 w-5 items-center justify-center rounded-full ${
                      k.validated
                        ? "bg-green-100 text-green-600"
                        : "bg-yellow-100 text-yellow-600"
                    }`}
                  >
                    {k.validated ? (
                      <svg
                        className="h-3.5 w-3.5"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2.5}
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                    ) : (
                      <span className="h-2 w-2 rounded-full bg-current" />
                    )}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function formatKeyType(type: string): string {
  const names: Record<string, string> = {
    supabase_url: "Supabase URL",
    supabase_anon_key: "Supabase Anon Key",
    supabase_service_role: "Supabase Service Role",
    google_maps: "Google Maps",
    gemini: "Gemini AI",
    openai: "OpenAI",
    anthropic: "Anthropic Claude",
    resend: "Resend Email",
    sendgrid: "SendGrid Email",
    redbricks_token: "Red Bricks API",
  };
  return names[type] || type;
}
