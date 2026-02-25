"use client";

import type { AIProvider, EmailProvider } from "@/types/tenant";

interface ProviderOption {
  id: string;
  name: string;
  freeTier: string;
  paidTier: string;
  recommended?: boolean;
}

const AI_PROVIDERS: ProviderOption[] = [
  {
    id: "gemini",
    name: "Google Gemini",
    freeTier: "1,000 req/day — no credit card needed",
    paidTier: "$0.30 / million input tokens",
    recommended: true,
  },
  {
    id: "openai",
    name: "OpenAI",
    freeTier: "No free tier — prepaid credits required",
    paidTier: "~$2.50 / million input tokens (GPT-4o-mini)",
  },
  {
    id: "anthropic",
    name: "Anthropic Claude",
    freeTier: "No free tier — prepaid credits required",
    paidTier: "~$0.80 / million input tokens (Haiku)",
  },
];

const EMAIL_PROVIDERS: ProviderOption[] = [
  {
    id: "resend",
    name: "Resend",
    freeTier: "100 emails/day (3,000/month) free",
    paidTier: "From $20/month for 50,000 emails",
    recommended: true,
  },
  {
    id: "sendgrid",
    name: "SendGrid",
    freeTier: "100 emails/day free forever",
    paidTier: "From $20/month for higher volume",
  },
];

interface Props {
  type: "ai" | "email";
  selected: string;
  onSelect: (provider: string) => void;
}

export default function ProviderPicker({ type, selected, onSelect }: Props) {
  const providers = type === "ai" ? AI_PROVIDERS : EMAIL_PROVIDERS;

  return (
    <div className="mb-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
      {providers.map((p) => {
        const isSelected = selected === p.id;
        return (
          <button
            key={p.id}
            type="button"
            onClick={() => onSelect(p.id)}
            className={`relative rounded-lg border p-3 text-left transition ${
              isSelected
                ? "border-[var(--color-primary)] bg-[var(--color-primary)]/5 ring-1 ring-[var(--color-primary)]/20"
                : "border-[var(--color-border)] hover:border-[var(--color-primary)]/40"
            }`}
          >
            {/* Radio dot */}
            <div className="flex items-start gap-2.5">
              <div
                className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border-2 transition ${
                  isSelected
                    ? "border-[var(--color-primary)] bg-[var(--color-primary)]"
                    : "border-gray-300"
                }`}
              >
                {isSelected && <div className="h-1.5 w-1.5 rounded-full bg-white" />}
              </div>

              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-[var(--color-text-primary)]">
                    {p.name}
                  </span>
                  {p.recommended && (
                    <span className="rounded bg-[var(--color-primary)]/10 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-[var(--color-primary)]">
                      Recommended
                    </span>
                  )}
                </div>
                <p className="mt-0.5 text-[11px] text-green-700">{p.freeTier}</p>
                <p className="text-[11px] text-[var(--color-text-muted)]">
                  Paid: {p.paidTier}
                </p>
              </div>
            </div>
          </button>
        );
      })}
    </div>
  );
}
