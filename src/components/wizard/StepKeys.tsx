"use client";

import { useState, useCallback } from "react";
import type {
  LaunchConfig,
  ValidationResult,
  AIProvider,
  EmailProvider,
} from "@/types/tenant";
import KeyValidator from "../KeyValidator";
import KeyPrepScreen from "./KeyPrepScreen";
import ProviderPicker from "./ProviderPicker";
import KeySetupGuide from "./KeySetupGuide";
import CostBadge from "./CostBadge";

interface Props {
  config: Partial<LaunchConfig>;
  updateConfig: (updates: Partial<LaunchConfig>) => void;
  onNext: () => void;
  onBack: () => void;
}

interface KeyState {
  value: string;
  result: ValidationResult | null;
  validating: boolean;
}

/* ---------- Provider metadata ---------- */

const AI_META: Record<
  AIProvider,
  { placeholder: string; helpUrl: string; costVariant: "free" | "paid"; costLabel: string; costDetail: string }
> = {
  gemini: {
    placeholder: "AIzaSy...",
    helpUrl: "https://aistudio.google.com/apikey",
    costVariant: "free",
    costLabel: "Free tier — no credit card needed",
    costDetail:
      "Google Gemini offers 1,000 requests/day free. Your site typically uses 5-20 requests/day for AI highlights. You're unlikely to hit the limit. Paid tier is $0.30 per million input tokens if you ever need more.",
  },
  openai: {
    placeholder: "sk-...",
    helpUrl: "https://platform.openai.com/api-keys",
    costVariant: "paid",
    costLabel: "Requires billing — ~$5 to start",
    costDetail:
      "OpenAI requires prepaid credits ($5 minimum). Uses GPT-4o-mini at ~$2.50 per million input tokens. Your site uses very few tokens — $5 could last several months of normal use.",
  },
  anthropic: {
    placeholder: "sk-ant-...",
    helpUrl: "https://console.anthropic.com/",
    costVariant: "paid",
    costLabel: "Requires billing — ~$5 to start",
    costDetail:
      "Anthropic requires prepaid credits ($5 minimum). Uses Claude Haiku at ~$0.80 per million input tokens. Your site uses very few tokens — $5 could last several months.",
  },
};

const EMAIL_META: Record<
  EmailProvider,
  { placeholder: string; helpUrl: string; costVariant: "free-limited"; costLabel: string; costDetail: string }
> = {
  resend: {
    placeholder: "re_...",
    helpUrl: "https://resend.com/api-keys",
    costVariant: "free-limited",
    costLabel: "Free — 100 emails/day",
    costDetail:
      "Resend's free tier includes 100 emails/day (about 3,000/month). That's plenty for contact form submissions. Paid plans start at $20/month for 50,000 emails if you ever need more.",
  },
  sendgrid: {
    placeholder: "SG...",
    helpUrl: "https://app.sendgrid.com/settings/api_keys",
    costVariant: "free-limited",
    costLabel: "Free — 100 emails/day",
    costDetail:
      "SendGrid's free tier includes 100 emails/day forever. That's plenty for contact form submissions. Paid plans start at $20/month for higher volume.",
  },
};

/* ---------- Component ---------- */

export default function StepKeys({
  config,
  updateConfig,
  onNext,
  onBack,
}: Props) {
  // Show prep screen first
  const [showPrep, setShowPrep] = useState(true);

  // Provider selection
  const [aiProvider, setAiProvider] = useState<AIProvider>(
    config.aiProvider || "gemini",
  );
  const [emailProvider, setEmailProvider] = useState<EmailProvider>(
    config.emailProvider || "resend",
  );

  // Which guide is expanded
  const [expandedGuide, setExpandedGuide] = useState<string | null>(null);

  // Key states
  const [keys, setKeys] = useState<Record<string, KeyState>>({
    google_maps: {
      value: config.googleMapsKey || "",
      result: null,
      validating: false,
    },
    ai: {
      value: config.aiKey || config.geminiKey || "",
      result: null,
      validating: false,
    },
    email: {
      value: config.emailKey || config.resendKey || "",
      result: null,
      validating: false,
    },
  });

  const validate = useCallback(
    async (keyType: string, value: string) => {
      if (!value.trim()) {
        setKeys((prev) => ({
          ...prev,
          [keyType]: { ...prev[keyType], result: null, validating: false },
        }));
        return;
      }

      setKeys((prev) => ({
        ...prev,
        [keyType]: { ...prev[keyType], validating: true },
      }));

      // Build endpoint + body
      let endpoint: string;
      let body: Record<string, string>;

      if (keyType === "google_maps") {
        endpoint = "/api/validate/maps";
        body = { apiKey: value };
      } else if (keyType === "ai") {
        endpoint = "/api/validate/ai";
        body = { apiKey: value, provider: aiProvider };
      } else {
        endpoint = "/api/validate/email";
        body = { apiKey: value, provider: emailProvider };
      }

      try {
        const res = await fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const result = await res.json();
        setKeys((prev) => ({
          ...prev,
          [keyType]: { ...prev[keyType], result, validating: false },
        }));
      } catch {
        setKeys((prev) => ({
          ...prev,
          [keyType]: {
            ...prev[keyType],
            result: { valid: false, message: "Validation request failed" },
            validating: false,
          },
        }));
      }
    },
    [aiProvider, emailProvider],
  );

  function handleKeyChange(keyType: string, value: string) {
    setKeys((prev) => ({
      ...prev,
      [keyType]: { value, result: null, validating: false },
    }));
  }

  // When switching providers, reset that key's validation
  function handleAiProviderChange(provider: string) {
    setAiProvider(provider as AIProvider);
    setKeys((prev) => ({
      ...prev,
      ai: { value: "", result: null, validating: false },
    }));
    setExpandedGuide(null);
  }

  function handleEmailProviderChange(provider: string) {
    setEmailProvider(provider as EmailProvider);
    setKeys((prev) => ({
      ...prev,
      email: { value: "", result: null, validating: false },
    }));
    setExpandedGuide(null);
  }

  function handleNext() {
    if (!keys.google_maps.result?.valid) return;

    updateConfig({
      googleMapsKey: keys.google_maps.value || undefined,
      aiProvider,
      aiKey: keys.ai.value || undefined,
      emailProvider,
      emailKey: keys.email.value || undefined,
      // Backward compat — also set old fields
      geminiKey: aiProvider === "gemini" ? keys.ai.value || undefined : undefined,
      resendKey: emailProvider === "resend" ? keys.email.value || undefined : undefined,
    });
    onNext();
  }

  const mapsValid = keys.google_maps.result?.valid === true;
  const canContinue = mapsValid;

  // Prep screen
  if (showPrep) {
    return <KeyPrepScreen onReady={() => setShowPrep(false)} />;
  }

  const aiMeta = AI_META[aiProvider];
  const emailMeta = EMAIL_META[emailProvider];

  return (
    <div>
      <h2 className="mb-1 text-xl font-bold text-[var(--color-text-primary)]">
        Security & Keys
      </h2>
      <p className="mb-6 text-sm text-[var(--color-text-secondary)]">
        Add your API keys below. We&apos;ll validate each one before launch.
        Follow the step-by-step guides if this is your first time.
      </p>

      <div className="space-y-6">
        {/* ── Google Maps — Required ── */}
        <div>
          <h3 className="mb-2 flex items-center gap-2 text-sm font-semibold text-[var(--color-text-primary)]">
            <svg className="h-4 w-4 text-[var(--color-primary)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            Google Maps
          </h3>
          <KeyValidator
            label="Google Maps API Key"
            description="Powers your interactive map, address search, and project locations. Enable Geocoding, Maps JavaScript, and Places APIs."
            placeholder="AIzaSy..."
            required
            value={keys.google_maps.value}
            result={keys.google_maps.result}
            validating={keys.google_maps.validating}
            onChange={(v) => handleKeyChange("google_maps", v)}
            onValidate={() => validate("google_maps", keys.google_maps.value)}
            helpUrl="https://console.cloud.google.com/apis/credentials"
            costBadge={
              <CostBadge
                variant="free"
                label="Free — 10,000 loads/month"
                detail="Google Maps provides 10,000 free map loads per SKU each month. Most real estate agent sites use 500-2,000 loads/month — well within the free tier. You won't be charged unless traffic grows significantly."
              />
            }
            guide={
              <KeySetupGuide
                provider="google_maps"
                expanded={expandedGuide === "google_maps"}
                onToggle={() =>
                  setExpandedGuide(expandedGuide === "google_maps" ? null : "google_maps")
                }
              />
            }
          />
        </div>

        {/* ── AI Service — Optional ── */}
        <div>
          <div className="mb-2 flex items-center justify-between">
            <h3 className="flex items-center gap-2 text-sm font-semibold text-[var(--color-text-primary)]">
              <svg className="h-4 w-4 text-[var(--color-primary)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
              </svg>
              AI Service
            </h3>
            <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-gray-500">
              Optional
            </span>
          </div>

          <ProviderPicker
            type="ai"
            selected={aiProvider}
            onSelect={handleAiProviderChange}
          />

          <KeyValidator
            label={`${aiProvider === "gemini" ? "Google Gemini" : aiProvider === "openai" ? "OpenAI" : "Anthropic Claude"} API Key`}
            description="Powers AI-generated project highlights and smart descriptions on your site."
            placeholder={aiMeta.placeholder}
            value={keys.ai.value}
            result={keys.ai.result}
            validating={keys.ai.validating}
            onChange={(v) => handleKeyChange("ai", v)}
            onValidate={() => validate("ai", keys.ai.value)}
            helpUrl={aiMeta.helpUrl}
            onSkip={() => {
              setKeys((prev) => ({
                ...prev,
                ai: { value: "", result: null, validating: false },
              }));
            }}
            costBadge={
              <CostBadge
                variant={aiMeta.costVariant}
                label={aiMeta.costLabel}
                detail={aiMeta.costDetail}
              />
            }
            guide={
              <KeySetupGuide
                provider={aiProvider}
                expanded={expandedGuide === "ai"}
                onToggle={() =>
                  setExpandedGuide(expandedGuide === "ai" ? null : "ai")
                }
              />
            }
          />
        </div>

        {/* ── Email Service — Optional ── */}
        <div>
          <div className="mb-2 flex items-center justify-between">
            <h3 className="flex items-center gap-2 text-sm font-semibold text-[var(--color-text-primary)]">
              <svg className="h-4 w-4 text-[var(--color-primary)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              Email Service
            </h3>
            <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-gray-500">
              Optional
            </span>
          </div>

          <ProviderPicker
            type="email"
            selected={emailProvider}
            onSelect={handleEmailProviderChange}
          />

          <KeyValidator
            label={`${emailProvider === "resend" ? "Resend" : "SendGrid"} API Key`}
            description="Sends contact form submissions and lead notifications directly to your inbox."
            placeholder={emailMeta.placeholder}
            value={keys.email.value}
            result={keys.email.result}
            validating={keys.email.validating}
            onChange={(v) => handleKeyChange("email", v)}
            onValidate={() => validate("email", keys.email.value)}
            helpUrl={emailMeta.helpUrl}
            onSkip={() => {
              setKeys((prev) => ({
                ...prev,
                email: { value: "", result: null, validating: false },
              }));
            }}
            costBadge={
              <CostBadge
                variant={emailMeta.costVariant}
                label={emailMeta.costLabel}
                detail={emailMeta.costDetail}
              />
            }
            guide={
              <KeySetupGuide
                provider={emailProvider}
                expanded={expandedGuide === "email"}
                onToggle={() =>
                  setExpandedGuide(expandedGuide === "email" ? null : "email")
                }
              />
            }
          />
        </div>
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
          disabled={!canContinue}
          className="rounded-lg bg-[var(--color-primary)] px-6 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          Continue
        </button>
      </div>
    </div>
  );
}
