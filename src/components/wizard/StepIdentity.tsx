"use client";

import { useState, useEffect, useCallback } from "react";
import type { LaunchConfig } from "@/types/tenant";

interface Props {
  config: Partial<LaunchConfig>;
  updateConfig: (updates: Partial<LaunchConfig>) => void;
  onNext: () => void;
  onBack: () => void;
}

const NAMECHEAP_URL =
  process.env.NEXT_PUBLIC_NAMECHEAP_AFFILIATE_URL ||
  "https://www.namecheap.com/domains/registration/results/";

export default function StepIdentity({
  config,
  updateConfig,
  onNext,
  onBack,
}: Props) {
  const [slug, setSlug] = useState(config.slug || "");
  const [displayName, setDisplayName] = useState(config.displayName || "");
  const [checking, setChecking] = useState(false);
  const [available, setAvailable] = useState<boolean | null>(null);
  const [reason, setReason] = useState("");

  // Custom domain
  const [showCustomDomain, setShowCustomDomain] = useState(
    !!config.customDomain,
  );
  const [customDomain, setCustomDomain] = useState(config.customDomain || "");

  const baseDomain = process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "rbos.app";

  // Debounced availability check
  const checkAvailability = useCallback(async (value: string) => {
    if (value.length < 2) {
      setAvailable(null);
      return;
    }

    setChecking(true);
    try {
      const res = await fetch("/api/domains/check", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ slug: value }),
      });
      const data = await res.json();
      setAvailable(data.available);
      setReason(data.reason || "");
    } catch {
      setAvailable(null);
    } finally {
      setChecking(false);
    }
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      if (slug) checkAvailability(slug);
    }, 500);
    return () => clearTimeout(timer);
  }, [slug, checkAvailability]);

  function handleSlugChange(value: string) {
    const formatted = value
      .toLowerCase()
      .replace(/\s+/g, "-")
      .replace(/[^a-z0-9-]/g, "");
    setSlug(formatted);
    setAvailable(null);
  }

  function handleCustomDomainChange(value: string) {
    setCustomDomain(
      value
        .toLowerCase()
        .replace(/\s+/g, "")
        .replace(/[^a-z0-9.-]/g, ""),
    );
  }

  const isValidCustomDomain =
    !showCustomDomain ||
    !customDomain ||
    (customDomain.includes(".") && customDomain.length >= 4);

  function handleNext() {
    if (!slug || !displayName || !available) return;
    updateConfig({
      slug,
      displayName,
      customDomain: showCustomDomain && customDomain ? customDomain : undefined,
    });
    onNext();
  }

  const isValid =
    slug.length >= 2 &&
    displayName.length >= 1 &&
    available === true &&
    isValidCustomDomain;

  return (
    <div>
      <h2 className="mb-1 text-xl font-bold text-[var(--color-text-primary)]">
        Name & Domain
      </h2>
      <p className="mb-6 text-sm text-[var(--color-text-secondary)]">
        Choose a name and subdomain for your site. You can also connect a custom
        domain.
      </p>

      <div className="space-y-5">
        {/* Site name */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-[var(--color-text-primary)]">
            Site Name
          </label>
          <input
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Acme Realty"
            className="w-full rounded-lg border border-[var(--color-border)] px-3.5 py-2.5 text-sm outline-none transition focus:border-[var(--color-primary)] focus:ring-2 focus:ring-[var(--color-primary)]/20"
          />
        </div>

        {/* Subdomain picker */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-[var(--color-text-primary)]">
            Subdomain
            <span className="ml-1.5 rounded bg-green-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-green-700">
              Free
            </span>
          </label>
          <div className="flex items-center gap-0">
            <input
              type="text"
              value={slug}
              onChange={(e) => handleSlugChange(e.target.value)}
              placeholder="acme-realty"
              className="w-full rounded-l-lg border border-r-0 border-[var(--color-border)] px-3.5 py-2.5 text-sm outline-none transition focus:border-[var(--color-primary)] focus:ring-2 focus:ring-[var(--color-primary)]/20"
            />
            <span className="flex items-center rounded-r-lg border border-[var(--color-border)] bg-[var(--color-surface-secondary)] px-3.5 py-2.5 text-sm text-[var(--color-text-muted)]">
              .{baseDomain}
            </span>
          </div>

          {/* Availability indicator */}
          {slug.length >= 2 && (
            <div className="mt-2 flex items-center gap-2 text-sm">
              {checking ? (
                <span className="text-[var(--color-text-muted)]">
                  Checking availability...
                </span>
              ) : available === true ? (
                <>
                  <span className="flex h-5 w-5 items-center justify-center rounded-full bg-green-100 text-green-600">
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
                  </span>
                  <span className="text-green-700">
                    {slug}.{baseDomain} is available
                  </span>
                </>
              ) : available === false ? (
                <>
                  <span className="flex h-5 w-5 items-center justify-center rounded-full bg-red-100 text-red-600">
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
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </span>
                  <span className="text-red-700">
                    {reason || "Not available"}
                  </span>
                </>
              ) : null}
            </div>
          )}
        </div>

        {/* ── Custom Domain (Optional) ── */}
        <div className="rounded-lg border border-[var(--color-border)] p-4">
          <div className="flex items-center justify-between">
            <div>
              <span className="text-sm font-medium text-[var(--color-text-primary)]">
                Custom Domain
              </span>
              <span className="ml-1.5 rounded bg-gray-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-gray-500">
                Optional
              </span>
            </div>
            {/* Toggle */}
            <button
              type="button"
              role="switch"
              aria-checked={showCustomDomain}
              onClick={() => {
                setShowCustomDomain(!showCustomDomain);
                if (showCustomDomain) setCustomDomain("");
              }}
              className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${
                showCustomDomain
                  ? "bg-[var(--color-primary)]"
                  : "bg-gray-200"
              }`}
            >
              <span
                className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow transition-transform ${
                  showCustomDomain ? "translate-x-5" : "translate-x-0"
                }`}
              />
            </button>
          </div>
          <p className="mt-1 text-xs text-[var(--color-text-muted)]">
            Connect your own domain like condos.youragency.com
          </p>

          {showCustomDomain && (
            <div className="mt-4 space-y-4">
              {/* Domain input */}
              <div>
                <label className="mb-1.5 block text-xs font-medium text-[var(--color-text-secondary)]">
                  Your domain
                </label>
                <input
                  type="text"
                  value={customDomain}
                  onChange={(e) => handleCustomDomainChange(e.target.value)}
                  placeholder="condos.youragency.com"
                  className="w-full rounded-lg border border-[var(--color-border)] px-3.5 py-2.5 text-sm outline-none transition focus:border-[var(--color-primary)] focus:ring-2 focus:ring-[var(--color-primary)]/20"
                />
              </div>

              {/* DNS Instructions */}
              {customDomain && customDomain.includes(".") && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 p-3">
                  <p className="mb-2 text-xs font-medium text-amber-900">
                    Add this DNS record at your domain registrar:
                  </p>
                  <div className="overflow-x-auto rounded border border-amber-200 bg-white">
                    <table className="w-full text-xs">
                      <thead>
                        <tr className="border-b border-amber-100 text-left text-[var(--color-text-muted)]">
                          <th className="px-3 py-1.5 font-medium">Type</th>
                          <th className="px-3 py-1.5 font-medium">Name</th>
                          <th className="px-3 py-1.5 font-medium">Value</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr className="font-mono text-amber-900">
                          <td className="px-3 py-1.5">CNAME</td>
                          <td className="px-3 py-1.5">
                            {customDomain.split(".")[0]}
                          </td>
                          <td className="px-3 py-1.5">cname.vercel-dns.com</td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <p className="mt-2 text-[11px] text-amber-700">
                    DNS changes can take up to 24 hours to propagate. Your free
                    subdomain will work immediately.
                  </p>
                </div>
              )}

              {/* Namecheap affiliate CTA */}
              <div className="rounded-lg border border-dashed border-[var(--color-border)] bg-[var(--color-surface-secondary)] p-4">
                <div className="flex items-start gap-3">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-orange-100 text-orange-600">
                    <svg
                      className="h-5 w-5"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={1.5}
                        d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"
                      />
                    </svg>
                  </div>
                  <div>
                    <p className="text-sm font-medium text-[var(--color-text-primary)]">
                      Need a domain?
                    </p>
                    <p className="mt-0.5 text-xs text-[var(--color-text-muted)]">
                      Get a custom .com domain from ~$10/year. Your free .
                      {baseDomain} subdomain works either way.
                    </p>
                    <a
                      href={`${NAMECHEAP_URL}?domain=${slug || "mysite"}`}
                      target="_blank"
                      rel="noopener"
                      className="mt-2 inline-flex items-center gap-1.5 rounded-lg border border-orange-200 bg-orange-50 px-3 py-1.5 text-xs font-medium text-orange-700 transition hover:bg-orange-100"
                    >
                      Search for a domain on Namecheap
                      <svg
                        className="h-3 w-3"
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
              </div>
            </div>
          )}
        </div>

        {/* Preview */}
        {slug && (
          <div className="rounded-lg border border-dashed border-[var(--color-border)] bg-[var(--color-surface-secondary)] p-4">
            <p className="text-xs font-medium uppercase tracking-wider text-[var(--color-text-muted)]">
              Your site will be at
            </p>
            {showCustomDomain && customDomain && customDomain.includes(".") ? (
              <div className="mt-1">
                <p className="text-lg font-semibold text-[var(--color-primary)]">
                  https://{customDomain}
                </p>
                <p className="mt-0.5 text-xs text-[var(--color-text-muted)]">
                  Also available at: https://{slug}.{baseDomain}
                </p>
              </div>
            ) : (
              <p className="mt-1 text-lg font-semibold text-[var(--color-primary)]">
                https://{slug}.{baseDomain}
              </p>
            )}
          </div>
        )}
      </div>

      {/* Navigation */}
      <div className="mt-8 flex justify-between">
        <button
          onClick={onBack}
          className="rounded-lg border border-[var(--color-border)] px-6 py-2.5 text-sm font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
        >
          Back
        </button>
        <button
          onClick={handleNext}
          disabled={!isValid}
          className="rounded-lg bg-[var(--color-primary)] px-6 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          Review & Launch
        </button>
      </div>
    </div>
  );
}
