"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Link from "next/link";
import confetti from "canvas-confetti";
import type { LaunchConfig, TenantJobStep } from "@/types/tenant";

interface Props {
  config: LaunchConfig;
  jobId: string | null;
  setJobId: (id: string) => void;
  onBack: () => void;
}

interface LaunchStatus {
  jobId: string;
  status: "pending" | "running" | "completed" | "failed";
  steps: TenantJobStep[];
  error: string | null;
  tenant: {
    slug: string;
    status: string;
    displayName: string;
    url: string;
  } | null;
}

/** Terminal log messages mapped to each step */
const TERMINAL_LOGS: Record<string, string[]> = {
  "Creating database": [
    "Initializing Supabase project...",
    "Allocating PostgreSQL instance (us-east-1)",
    "Generating service credentials",
    "Database engine: PostgreSQL 15.4",
  ],
  "Running migrations": [
    "Running schema migrations...",
    "CREATE TABLE favorites",
    "CREATE TABLE likes",
    "CREATE TABLE blog_posts",
    "CREATE TABLE site_config",
    "CREATE TABLE site_api_keys",
    "Applying RLS policies",
    "Creating indexes",
  ],
  "Seeding configuration": [
    "Seeding site configuration...",
    "SET branding.siteName",
    "SET theme.preset",
    "SET features.flags",
    "Creating admin user",
  ],
  "Configuring domain": [
    "Configuring DNS...",
    "Adding domain to Vercel CDN",
    "Requesting SSL certificate",
    "Propagating edge network config",
  ],
  "Storing credentials": [
    "Encrypting credentials (AES-256-GCM)...",
    "Storing Supabase keys",
    "Storing service tokens",
    "Validation complete",
  ],
  "Activating site": [
    "Activating site...",
    "Clearing edge cache",
    "Running health check",
    "[SUCCESS] Site is live!",
  ],
};

function useTerminalLogs(status: LaunchStatus | null) {
  const [logs, setLogs] = useState<
    { text: string; type: "info" | "success" | "step" }[]
  >([]);
  const processedRef = useRef(new Set<string>());

  useEffect(() => {
    if (!status?.steps) return;

    for (const step of status.steps) {
      const key = `${step.name}-${step.status}`;
      if (processedRef.current.has(key)) continue;
      processedRef.current.add(key);

      if (step.status === "running") {
        setLogs((prev) => [
          ...prev,
          { text: `> ${step.name}`, type: "step" },
        ]);

        const subLogs = TERMINAL_LOGS[step.name] || [];
        subLogs.forEach((log, i) => {
          setTimeout(() => {
            setLogs((prev) => [
              ...prev,
              {
                text: `  ${log}`,
                type: log.startsWith("[SUCCESS]") ? "success" : "info",
              },
            ]);
          }, (i + 1) * 300);
        });
      }

      if (step.status === "completed") {
        setTimeout(() => {
          setLogs((prev) => [
            ...prev,
            { text: `  [DONE] ${step.name}`, type: "success" },
          ]);
        }, 200);
      }

      if (step.status === "failed") {
        setLogs((prev) => [
          ...prev,
          {
            text: `  [FAILED] ${step.name}: ${step.error || "Unknown error"}`,
            type: "info",
          },
        ]);
      }
    }
  }, [status?.steps]);

  return logs;
}

function fireConfetti() {
  const duration = 2000;
  const end = Date.now() + duration;

  (function frame() {
    confetti({
      particleCount: 3,
      angle: 60,
      spread: 55,
      origin: { x: 0 },
      colors: ["#1e40af", "#d97706", "#10b981"],
    });
    confetti({
      particleCount: 3,
      angle: 120,
      spread: 55,
      origin: { x: 1 },
      colors: ["#1e40af", "#d97706", "#10b981"],
    });

    if (Date.now() < end) {
      requestAnimationFrame(frame);
    }
  })();
}

export default function StepPropagation({
  config,
  jobId,
  setJobId,
  onBack,
}: Props) {
  const [launching, setLaunching] = useState(false);
  const [status, setStatus] = useState<LaunchStatus | null>(null);
  const [launchError, setLaunchError] = useState("");
  const [celebrated, setCelebrated] = useState(false);
  const terminalRef = useRef<HTMLDivElement>(null);
  const logs = useTerminalLogs(status);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [logs]);

  async function handleLaunch() {
    setLaunching(true);
    setLaunchError("");

    try {
      const res = await fetch("/api/launch", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(config),
      });

      const data = await res.json();

      if (!res.ok) {
        setLaunchError(data.error || "Launch failed");
        setLaunching(false);
        return;
      }

      setJobId(data.jobId);
    } catch {
      setLaunchError("Network error. Please try again.");
      setLaunching(false);
    }
  }

  const pollStatus = useCallback(async () => {
    if (!jobId) return;

    try {
      const res = await fetch(`/api/launch/status?jobId=${jobId}`);
      if (res.ok) {
        const data: LaunchStatus = await res.json();
        setStatus(data);
        return data.status;
      }
    } catch {
      // Silently retry on next poll
    }
    return null;
  }, [jobId]);

  useEffect(() => {
    if (!jobId) return;

    pollStatus();

    const interval = setInterval(async () => {
      const result = await pollStatus();
      if (result === "completed" || result === "failed") {
        clearInterval(interval);
        setLaunching(false);
      }
    }, 2000);

    return () => clearInterval(interval);
  }, [jobId, pollStatus]);

  const isComplete = status?.status === "completed";
  const isFailed = status?.status === "failed";

  // Fire confetti once
  useEffect(() => {
    if (isComplete && !celebrated) {
      setCelebrated(true);
      fireConfetti();
    }
  }, [isComplete, celebrated]);

  const completedSteps =
    status?.steps?.filter((s) => s.status === "completed").length ?? 0;
  const totalSteps = status?.steps?.length ?? 6;
  const progress = totalSteps > 0 ? (completedSteps / totalSteps) * 100 : 0;

  const baseDomain = process.env.NEXT_PUBLIC_TEMPLATE_DOMAIN || "rbos.app";
  const siteUrl =
    status?.tenant?.url || `https://${config.slug}.${baseDomain}`;

  return (
    <div>
      <AnimatePresence mode="wait">
        {!jobId && !launching ? (
          <motion.div
            key="review"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
          >
            <h2 className="mb-1 text-xl font-bold text-[var(--color-text-primary)]">
              Ready to Launch
            </h2>
            <p className="mb-6 text-sm text-[var(--color-text-secondary)]">
              Review your configuration and launch your site.
            </p>

            <div className="mb-6 space-y-2">
              {[
                { label: "Site", value: config.displayName },
                {
                  label: "URL",
                  value: config.customDomain
                    ? `https://${config.customDomain}`
                    : `https://${config.slug}.${baseDomain}`,
                  sub: config.customDomain
                    ? `https://${config.slug}.${baseDomain}`
                    : undefined,
                },
                {
                  label: "Theme",
                  value: config.themePreset
                    .replace("-", " ")
                    .replace(/\b\w/g, (c) => c.toUpperCase()),
                },
                {
                  label: "Google Maps",
                  value: config.googleMapsKey ? "Verified" : "Not set",
                  green: !!config.googleMapsKey,
                },
              ].map((row) => (
                <div
                  key={row.label}
                  className="flex items-center justify-between rounded-lg border border-white/10 bg-[var(--color-surface-secondary)] px-4 py-3"
                >
                  <span className="text-sm text-[var(--color-text-muted)]">
                    {row.label}
                  </span>
                  <div className="text-right">
                    <span
                      className={`text-sm font-medium ${
                        "green" in row && row.green
                          ? "text-green-600"
                          : "text-[var(--color-text-primary)]"
                      }`}
                    >
                      {row.value}
                    </span>
                    {"sub" in row && row.sub && (
                      <span className="block text-xs text-[var(--color-text-muted)]">
                        Also: {row.sub}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>

            {launchError && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700"
              >
                {launchError}
              </motion.div>
            )}

            <div className="flex justify-between">
              <button
                onClick={onBack}
                className="rounded-lg border border-[var(--color-border)] px-6 py-2.5 text-sm font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
              >
                Back
              </button>
              <motion.button
                onClick={handleLaunch}
                whileHover={{ scale: 1.03 }}
                whileTap={{ scale: 0.97 }}
                className="group relative overflow-hidden rounded-lg bg-green-600 px-8 py-2.5 text-sm font-semibold text-white transition hover:bg-green-700"
              >
                <span className="relative z-10 flex items-center gap-2">
                  <svg
                    className="h-4 w-4 transition-transform group-hover:-translate-y-0.5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M5 10l7-7m0 0l7 7m-7-7v18"
                    />
                  </svg>
                  Launch Site
                </span>
              </motion.button>
            </div>
          </motion.div>
        ) : (
          <motion.div
            key="terminal"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
          >
            {/* Header */}
            <div className="mb-4 flex items-center justify-between">
              <div>
                <h2 className="text-lg font-bold text-[var(--color-text-primary)]">
                  {isComplete
                    ? "Launch Complete"
                    : isFailed
                      ? "Launch Failed"
                      : "Deploying RBOS..."}
                </h2>
                <p className="text-xs text-[var(--color-text-muted)]">
                  {config.slug}.{baseDomain}
                </p>
              </div>
              {!isComplete && !isFailed && (
                <span className="text-2xl font-bold tabular-nums text-[var(--color-primary)]">
                  {Math.round(progress)}%
                </span>
              )}
            </div>

            {/* Progress bar */}
            {!isComplete && !isFailed && (
              <div className="mb-4 h-1.5 overflow-hidden rounded-full bg-[var(--color-border)]">
                <motion.div
                  className="h-full rounded-full bg-[var(--color-primary)]"
                  initial={{ width: 0 }}
                  animate={{ width: `${progress}%` }}
                  transition={{ duration: 0.5, ease: "easeOut" }}
                />
              </div>
            )}

            {/* Terminal + steps split */}
            <div className="grid gap-4 md:grid-cols-2">
              {/* Terminal */}
              <div className="overflow-hidden rounded-lg border border-gray-800 bg-gray-950">
                <div className="flex items-center gap-1.5 border-b border-gray-800 bg-gray-900 px-3 py-2">
                  <div className="h-2.5 w-2.5 rounded-full bg-red-500/80" />
                  <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/80" />
                  <div className="h-2.5 w-2.5 rounded-full bg-green-500/80" />
                  <span className="ml-2 text-[10px] font-medium text-gray-500">
                    rbos-deploy
                  </span>
                </div>
                <div
                  ref={terminalRef}
                  className="h-64 overflow-y-auto p-3 font-mono text-xs leading-relaxed"
                >
                  <div className="text-gray-500">
                    $ rbos deploy --slug {config.slug}
                  </div>
                  {logs.map((log, i) => (
                    <motion.div
                      key={i}
                      initial={{ opacity: 0, x: -5 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ duration: 0.15 }}
                      className={
                        log.type === "success"
                          ? "text-green-400"
                          : log.type === "step"
                            ? "mt-1 font-semibold text-blue-400"
                            : "text-gray-400"
                      }
                    >
                      {log.text}
                    </motion.div>
                  ))}
                  {!isComplete && !isFailed && (
                    <span className="inline-block h-3.5 w-1.5 animate-pulse bg-green-400" />
                  )}
                </div>
              </div>

              {/* Step tracker */}
              <div className="space-y-2">
                {status?.steps?.map((step, i) => (
                  <motion.div
                    key={i}
                    initial={{ opacity: 0, y: 5 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: i * 0.05 }}
                    className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm ${
                      step.status === "completed"
                        ? "bg-green-50/80"
                        : step.status === "running"
                          ? "bg-blue-50/80"
                          : step.status === "failed"
                            ? "bg-red-50/80"
                            : "bg-gray-50/50"
                    }`}
                  >
                    {step.status === "completed" && (
                      <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-green-200 text-green-700">
                        <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                        </svg>
                      </span>
                    )}
                    {step.status === "running" && (
                      <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-blue-200 text-blue-700">
                        <svg className="h-3 w-3 animate-spin" fill="none" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                        </svg>
                      </span>
                    )}
                    {step.status === "failed" && (
                      <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-red-200 text-red-700">
                        <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </span>
                    )}
                    {step.status === "pending" && (
                      <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-gray-200">
                        <span className="h-1.5 w-1.5 rounded-full bg-gray-400" />
                      </span>
                    )}
                    <span
                      className={`font-medium ${
                        step.status === "completed"
                          ? "text-green-800"
                          : step.status === "running"
                            ? "text-blue-800"
                            : step.status === "failed"
                              ? "text-red-800"
                              : "text-gray-400"
                      }`}
                    >
                      {step.name}
                    </span>
                  </motion.div>
                )) || (
                  Array.from({ length: 6 }).map((_, i) => (
                    <div
                      key={i}
                      className="flex items-center gap-3 rounded-lg bg-gray-50/50 px-3 py-2.5"
                    >
                      <div className="h-5 w-5 animate-pulse rounded-full bg-gray-200" />
                      <div className="h-3 w-28 animate-pulse rounded bg-gray-200" />
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Success celebration */}
            <AnimatePresence>
              {isComplete && status?.tenant && (
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.3, duration: 0.5 }}
                  className="mt-6 rounded-xl border border-green-200 bg-gradient-to-br from-green-50 to-emerald-50 p-6 text-center"
                >
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{
                      type: "spring",
                      stiffness: 200,
                      damping: 15,
                      delay: 0.5,
                    }}
                    className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-full bg-green-100"
                  >
                    <svg
                      className="h-7 w-7 text-green-600"
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
                  </motion.div>
                  <h3 className="text-lg font-bold text-gray-900">
                    {config.displayName} is live!
                  </h3>
                  <p className="mt-1 text-sm text-gray-600">
                    Your site is ready at{" "}
                    <a
                      href={siteUrl}
                      target="_blank"
                      rel="noopener"
                      className="font-medium text-[var(--color-primary)] hover:underline"
                    >
                      {siteUrl.replace("https://", "")}
                    </a>
                  </p>

                  <div className="mt-5 flex flex-col items-center justify-center gap-3 sm:flex-row">
                    <motion.a
                      href={siteUrl}
                      target="_blank"
                      rel="noopener"
                      whileHover={{ scale: 1.03 }}
                      whileTap={{ scale: 0.97 }}
                      className="inline-flex items-center gap-2 rounded-lg bg-[var(--color-primary)] px-6 py-2.5 text-sm font-semibold text-white shadow-lg shadow-blue-500/20 transition hover:bg-[var(--color-primary-dark)]"
                    >
                      Visit Your Site
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
                          d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                        />
                      </svg>
                    </motion.a>
                    <motion.a
                      href={`${siteUrl}/admin`}
                      target="_blank"
                      rel="noopener"
                      whileHover={{ scale: 1.03 }}
                      whileTap={{ scale: 0.97 }}
                      className="inline-flex items-center gap-2 rounded-lg border border-[var(--color-border)] bg-white px-6 py-2.5 text-sm font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
                    >
                      Open Admin Panel
                    </motion.a>
                    <Link
                      href="/"
                      className="text-sm text-[var(--color-text-muted)] hover:underline"
                    >
                      Back to Dashboard
                    </Link>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Failure state */}
            {isFailed && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="mt-6 rounded-xl border border-red-200 bg-red-50 p-5 text-center"
              >
                <p className="text-sm font-medium text-red-800">
                  {status?.error || "An error occurred during deployment."}
                </p>
                <p className="mt-2 text-xs text-red-600">
                  Check the terminal output above for details. You can try again
                  or contact support.
                </p>
                <button
                  onClick={onBack}
                  className="mt-4 rounded-lg border border-red-300 px-5 py-2 text-sm font-medium text-red-700 transition hover:bg-red-100"
                >
                  Go Back & Retry
                </button>
              </motion.div>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}