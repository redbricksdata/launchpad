"use client";

import { useState, useEffect, useCallback } from "react";

interface TenantStatus {
  id: string;
  slug: string;
  schemaVersion: string | null;
  pendingMigrations: number;
  status: string;
}

interface UpgradeStatus {
  latestVersion: string | null;
  totalMigrations: number;
  tenants: TenantStatus[];
}

interface UpgradeResult {
  upgraded: number;
  skipped: number;
  failed: number;
  details: Array<{
    tenantId: string;
    slug: string;
    previousVersion: string | null;
    newVersion: string | null;
    migrationsRun: number;
    status: "upgraded" | "skipped" | "failed";
    error?: string;
  }>;
}

export default function AdminDashboard() {
  const [adminKey, setAdminKey] = useState("");
  const [authenticated, setAuthenticated] = useState(false);
  const [status, setStatus] = useState<UpgradeStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [upgrading, setUpgrading] = useState(false);
  const [upgradeResult, setUpgradeResult] = useState<UpgradeResult | null>(null);
  const [error, setError] = useState("");

  // Feature flag propagation
  const [flagsInput, setFlagsInput] = useState("");
  const [propagating, setPropagating] = useState(false);
  const [flagResult, setFlagResult] = useState<string | null>(null);

  // Restore admin key from sessionStorage
  useEffect(() => {
    const stored = sessionStorage.getItem("rb_admin_key");
    if (stored) {
      setAdminKey(stored);
      setAuthenticated(true);
    }
  }, []);

  const fetchStatus = useCallback(async () => {
    if (!adminKey) return;
    setLoading(true);
    setError("");

    try {
      const res = await fetch("/api/admin/upgrade", {
        headers: { "x-admin-key": adminKey },
      });

      if (res.status === 401) {
        setAuthenticated(false);
        sessionStorage.removeItem("rb_admin_key");
        setError("Invalid admin key");
        setLoading(false);
        return;
      }

      if (!res.ok) {
        const data = await res.json();
        setError(data.error || "Failed to fetch status");
        setLoading(false);
        return;
      }

      const data: UpgradeStatus = await res.json();
      setStatus(data);
      setAuthenticated(true);
      sessionStorage.setItem("rb_admin_key", adminKey);
    } catch {
      setError("Network error");
    } finally {
      setLoading(false);
    }
  }, [adminKey]);

  // Auto-fetch on auth
  useEffect(() => {
    if (authenticated && adminKey) {
      fetchStatus();
    }
  }, [authenticated, adminKey, fetchStatus]);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    await fetchStatus();
  }

  async function handleUpgradeAll() {
    setUpgrading(true);
    setUpgradeResult(null);
    setError("");

    try {
      const res = await fetch("/api/admin/upgrade", {
        method: "POST",
        headers: { "x-admin-key": adminKey },
      });

      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Upgrade failed");
      } else {
        setUpgradeResult(data);
        // Refresh status
        await fetchStatus();
      }
    } catch {
      setError("Network error during upgrade");
    } finally {
      setUpgrading(false);
    }
  }

  async function handleUpgradeSingle(tenantId: string) {
    setError("");
    try {
      const res = await fetch(`/api/admin/upgrade/${tenantId}`, {
        method: "POST",
        headers: { "x-admin-key": adminKey },
      });

      const data = await res.json();
      if (!res.ok) {
        setError(`Upgrade failed for tenant: ${data.error || "unknown"}`);
      }
      await fetchStatus();
    } catch {
      setError("Network error");
    }
  }

  async function handlePropagateFlags() {
    setPropagating(true);
    setFlagResult(null);
    setError("");

    let flags: Record<string, boolean>;
    try {
      flags = JSON.parse(flagsInput);
    } catch {
      setError("Invalid JSON. Use format: {\"featureName\": true}");
      setPropagating(false);
      return;
    }

    try {
      const res = await fetch("/api/admin/features", {
        method: "POST",
        headers: {
          "x-admin-key": adminKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ flags }),
      });

      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Feature propagation failed");
      } else {
        setFlagResult(data.message);
      }
    } catch {
      setError("Network error");
    } finally {
      setPropagating(false);
    }
  }

  const totalPending = status?.tenants.reduce((sum, t) => sum + t.pendingMigrations, 0) || 0;

  // ── Auth screen ───────────────────────────────────────
  if (!authenticated) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[var(--color-surface-secondary)]">
        <form
          onSubmit={handleLogin}
          className="w-full max-w-sm rounded-2xl border border-[var(--color-border)] bg-white p-8 shadow-sm"
        >
          <div className="mb-6 flex items-center gap-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--color-primary)] text-xs font-bold text-white">
              RB
            </div>
            <span className="text-lg font-semibold text-[var(--color-text-primary)]">
              Admin Console
            </span>
          </div>

          <label className="mb-2 block text-sm font-medium text-[var(--color-text-secondary)]">
            Admin API Key
          </label>
          <input
            type="password"
            value={adminKey}
            onChange={(e) => setAdminKey(e.target.value)}
            placeholder="Enter your admin key"
            className="mb-4 w-full rounded-lg border border-[var(--color-border)] px-4 py-2.5 text-sm focus:border-[var(--color-primary)] focus:outline-none focus:ring-1 focus:ring-[var(--color-primary)]"
          />

          {error && (
            <p className="mb-4 text-sm text-red-600">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading || !adminKey}
            className="w-full rounded-lg bg-[var(--color-primary)] px-4 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)] disabled:opacity-50"
          >
            {loading ? "Verifying..." : "Sign In"}
          </button>
        </form>
      </div>
    );
  }

  // ── Dashboard ─────────────────────────────────────────
  return (
    <div className="min-h-screen bg-[var(--color-surface-secondary)]">
      {/* Header */}
      <header className="border-b border-[var(--color-border)] bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--color-primary)] text-xs font-bold text-white">
              RB
            </div>
            <span className="text-lg font-semibold text-[var(--color-text-primary)]">
              Red Bricks OS — Admin
            </span>
          </div>
          <div className="flex items-center gap-4">
            <button
              onClick={fetchStatus}
              disabled={loading}
              className="text-sm text-[var(--color-primary)] hover:underline disabled:opacity-50"
            >
              {loading ? "Refreshing..." : "Refresh"}
            </button>
            <button
              onClick={() => {
                setAuthenticated(false);
                sessionStorage.removeItem("rb_admin_key");
              }}
              className="text-sm text-[var(--color-text-muted)] hover:text-[var(--color-text-primary)]"
            >
              Sign out
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-8">
        {error && (
          <div className="mb-6 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
            <button
              onClick={() => setError("")}
              className="ml-2 font-medium underline"
            >
              Dismiss
            </button>
          </div>
        )}

        {/* ── Overview Cards ──────────────────────────── */}
        <div className="mb-8 grid grid-cols-4 gap-4">
          <StatCard
            label="Total Tenants"
            value={status?.tenants.length ?? "—"}
          />
          <StatCard
            label="Template Version"
            value={status?.latestVersion ? formatVersion(status.latestVersion) : "—"}
          />
          <StatCard
            label="Total Migrations"
            value={status?.totalMigrations ?? "—"}
          />
          <StatCard
            label="Pending Upgrades"
            value={totalPending}
            highlight={totalPending > 0}
          />
        </div>

        {/* ── Upgrade All ─────────────────────────────── */}
        {totalPending > 0 && (
          <div className="mb-8 rounded-xl border border-amber-200 bg-amber-50 p-5">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-base font-semibold text-amber-900">
                  {totalPending} migration{totalPending !== 1 ? "s" : ""} pending
                  across {status?.tenants.filter((t) => t.pendingMigrations > 0).length} tenant{(status?.tenants.filter((t) => t.pendingMigrations > 0).length ?? 0) !== 1 ? "s" : ""}
                </h2>
                <p className="mt-1 text-sm text-amber-700">
                  Run all pending migrations to bring every tenant up to date.
                </p>
              </div>
              <button
                onClick={handleUpgradeAll}
                disabled={upgrading}
                className="rounded-lg bg-amber-600 px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-amber-700 disabled:opacity-50"
              >
                {upgrading ? "Upgrading..." : "Upgrade All Tenants"}
              </button>
            </div>
          </div>
        )}

        {/* ── Upgrade Results ─────────────────────────── */}
        {upgradeResult && (
          <div className="mb-8 rounded-xl border border-[var(--color-border)] bg-white p-5">
            <h3 className="mb-3 text-sm font-semibold text-[var(--color-text-primary)]">
              Upgrade Results
            </h3>
            <div className="mb-4 flex gap-4 text-sm">
              <span className="rounded-full bg-green-100 px-3 py-1 text-green-700">
                {upgradeResult.upgraded} upgraded
              </span>
              <span className="rounded-full bg-gray-100 px-3 py-1 text-gray-600">
                {upgradeResult.skipped} skipped
              </span>
              {upgradeResult.failed > 0 && (
                <span className="rounded-full bg-red-100 px-3 py-1 text-red-700">
                  {upgradeResult.failed} failed
                </span>
              )}
            </div>
            <div className="max-h-60 overflow-y-auto">
              {upgradeResult.details.map((d) => (
                <div
                  key={d.tenantId}
                  className="flex items-center justify-between border-t border-[var(--color-border)] py-2 text-sm"
                >
                  <span className="font-medium text-[var(--color-text-primary)]">
                    {d.slug}
                  </span>
                  <span className="flex items-center gap-2">
                    {d.migrationsRun > 0 && (
                      <span className="text-[var(--color-text-muted)]">
                        {d.migrationsRun} migration{d.migrationsRun !== 1 ? "s" : ""}
                      </span>
                    )}
                    <ResultBadge status={d.status} />
                    {d.error && (
                      <span className="max-w-xs truncate text-xs text-red-500" title={d.error}>
                        {d.error}
                      </span>
                    )}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ── Tenant Table ────────────────────────────── */}
        <div className="mb-8 rounded-xl border border-[var(--color-border)] bg-white">
          <div className="border-b border-[var(--color-border)] px-5 py-4">
            <h2 className="text-base font-semibold text-[var(--color-text-primary)]">
              Tenant Database Versions
            </h2>
          </div>

          {!status || status.tenants.length === 0 ? (
            <div className="px-5 py-8 text-center text-sm text-[var(--color-text-muted)]">
              {loading ? "Loading..." : "No active tenants found."}
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--color-border)] text-left text-xs font-medium uppercase text-[var(--color-text-muted)]">
                  <th className="px-5 py-3">Tenant</th>
                  <th className="px-5 py-3">Schema Version</th>
                  <th className="px-5 py-3">Pending</th>
                  <th className="px-5 py-3">Status</th>
                  <th className="px-5 py-3 text-right">Action</th>
                </tr>
              </thead>
              <tbody>
                {status.tenants.map((tenant) => (
                  <tr
                    key={tenant.id}
                    className="border-b border-[var(--color-border)] last:border-0"
                  >
                    <td className="px-5 py-3 font-medium text-[var(--color-text-primary)]">
                      {tenant.slug}
                    </td>
                    <td className="px-5 py-3 font-mono text-xs text-[var(--color-text-muted)]">
                      {tenant.schemaVersion
                        ? formatVersion(tenant.schemaVersion)
                        : "—"}
                    </td>
                    <td className="px-5 py-3">
                      {tenant.pendingMigrations > 0 ? (
                        <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-700">
                          {tenant.pendingMigrations}
                        </span>
                      ) : (
                        <span className="rounded-full bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-700">
                          Current
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      <StatusBadge status={tenant.status} />
                    </td>
                    <td className="px-5 py-3 text-right">
                      {tenant.pendingMigrations > 0 && (
                        <button
                          onClick={() => handleUpgradeSingle(tenant.id)}
                          className="rounded-lg border border-[var(--color-border)] px-3 py-1 text-xs font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
                        >
                          Upgrade
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* ── Feature Flag Propagation ─────────────────── */}
        <div className="rounded-xl border border-[var(--color-border)] bg-white p-5">
          <h2 className="mb-1 text-base font-semibold text-[var(--color-text-primary)]">
            Propagate Feature Flags
          </h2>
          <p className="mb-4 text-sm text-[var(--color-text-muted)]">
            Push new default feature flags to all tenants. Only adds flags that
            don&apos;t already exist — never overrides agent customizations.
          </p>

          <div className="flex gap-3">
            <input
              type="text"
              value={flagsInput}
              onChange={(e) => setFlagsInput(e.target.value)}
              placeholder='{"newFeature": true, "betaWidget": false}'
              className="flex-1 rounded-lg border border-[var(--color-border)] px-4 py-2.5 font-mono text-sm focus:border-[var(--color-primary)] focus:outline-none focus:ring-1 focus:ring-[var(--color-primary)]"
            />
            <button
              onClick={handlePropagateFlags}
              disabled={propagating || !flagsInput.trim()}
              className="rounded-lg bg-[var(--color-primary)] px-6 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)] disabled:opacity-50"
            >
              {propagating ? "Propagating..." : "Propagate"}
            </button>
          </div>

          {flagResult && (
            <p className="mt-3 text-sm text-green-600">{flagResult}</p>
          )}
        </div>
      </main>
    </div>
  );
}

// ── Helper components ───────────────────────────────────

function StatCard({
  label,
  value,
  highlight,
}: {
  label: string;
  value: string | number;
  highlight?: boolean;
}) {
  return (
    <div className="rounded-xl border border-[var(--color-border)] bg-white p-4">
      <p className="text-xs font-medium uppercase text-[var(--color-text-muted)]">
        {label}
      </p>
      <p
        className={`mt-1 text-2xl font-bold ${
          highlight ? "text-amber-600" : "text-[var(--color-text-primary)]"
        }`}
      >
        {value}
      </p>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    active: "bg-green-100 text-green-700",
    provisioning: "bg-blue-100 text-blue-700",
    suspended: "bg-red-100 text-red-700",
    archived: "bg-gray-100 text-gray-600",
  };

  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${
        styles[status] || styles.archived
      }`}
    >
      {status}
    </span>
  );
}

function ResultBadge({ status }: { status: "upgraded" | "skipped" | "failed" }) {
  const styles = {
    upgraded: "bg-green-100 text-green-700",
    skipped: "bg-gray-100 text-gray-600",
    failed: "bg-red-100 text-red-700",
  };

  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${styles[status]}`}
    >
      {status}
    </span>
  );
}

/** Format a migration version timestamp for display */
function formatVersion(version: string): string {
  // "20260223200000" → "2026-02-23"
  if (version.length >= 8) {
    return `${version.slice(0, 4)}-${version.slice(4, 6)}-${version.slice(6, 8)}`;
  }
  return version;
}
