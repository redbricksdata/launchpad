"use client";

interface Props {
  onReady: () => void;
}

const SERVICES = [
  {
    name: "Google Maps",
    required: true,
    description: "Powers your interactive map, address search, and project location pages.",
    free: "10,000 loads/month free",
    time: "~3 min",
    icon: (
      <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
        />
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
        />
      </svg>
    ),
  },
  {
    name: "AI Service",
    required: false,
    description: "Generates smart project highlights and descriptions. Multiple providers available.",
    free: "Free tier available (Gemini)",
    time: "~2 min",
    icon: (
      <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
        />
      </svg>
    ),
  },
  {
    name: "Email Service",
    required: false,
    description: "Sends contact form submissions directly to your inbox. Add a domain later for branded emails.",
    free: "100 emails/day free",
    time: "~3 min",
    icon: (
      <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
        />
      </svg>
    ),
  },
];

export default function KeyPrepScreen({ onReady }: Props) {
  return (
    <div>
      <h2 className="mb-1 text-xl font-bold text-[var(--color-text-primary)]">
        Before you get started
      </h2>
      <p className="mb-2 text-sm text-[var(--color-text-secondary)]">
        You&apos;ll need a few API keys to power your site. Don&apos;t worry — most have
        generous free tiers and we&apos;ll walk you through getting each one.
      </p>
      <p className="mb-6 text-xs text-[var(--color-text-muted)]">
        Estimated time: ~10 minutes for all three. Only Google Maps is required to launch.
      </p>

      <div className="space-y-3">
        {SERVICES.map((svc) => (
          <div
            key={svc.name}
            className="flex items-start gap-4 rounded-lg border border-[var(--color-border)] p-4"
          >
            {/* Icon */}
            <div
              className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-lg ${
                svc.required
                  ? "bg-[var(--color-primary)]/10 text-[var(--color-primary)]"
                  : "bg-gray-100 text-gray-500"
              }`}
            >
              {svc.icon}
            </div>

            {/* Content */}
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold text-[var(--color-text-primary)]">
                  {svc.name}
                </span>
                {svc.required ? (
                  <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-amber-700">
                    Required
                  </span>
                ) : (
                  <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-gray-500">
                    Add later
                  </span>
                )}
              </div>
              <p className="mt-0.5 text-xs text-[var(--color-text-secondary)]">
                {svc.description}
              </p>
              <div className="mt-2 flex items-center gap-4">
                <span className="flex items-center gap-1 text-[11px] font-medium text-green-700">
                  <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                  </svg>
                  {svc.free}
                </span>
                <span className="flex items-center gap-1 text-[11px] text-[var(--color-text-muted)]">
                  <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  {svc.time}
                </span>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Auto-provisioned notice */}
      <div className="mt-4 flex items-start gap-3 rounded-lg border border-blue-200 bg-blue-50 p-3">
        <svg className="mt-0.5 h-4 w-4 shrink-0 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <p className="text-xs text-blue-800">
          <strong>Database &amp; Red Bricks API token</strong> are handled automatically — no setup needed from you.
        </p>
      </div>

      <button
        onClick={onReady}
        className="mt-6 w-full rounded-lg bg-[var(--color-primary)] px-6 py-3 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)]"
      >
        I&apos;m ready, let&apos;s go
      </button>
    </div>
  );
}
