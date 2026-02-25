"use client";

import { motion, AnimatePresence } from "framer-motion";
import type { ValidationResult } from "@/types/tenant";

interface Props {
  label: string;
  description: string;
  placeholder: string;
  value: string;
  result: ValidationResult | null;
  validating: boolean;
  required?: boolean;
  onChange: (value: string) => void;
  onValidate: () => void;
  helpUrl?: string;
  /** Render a CostBadge or other element below the description */
  costBadge?: React.ReactNode;
  /** Render a setup guide above the input field */
  guide?: React.ReactNode;
  /** Show a "Skip for now" link */
  onSkip?: () => void;
}

/** Animated circular progress used during key validation */
function ValidationSpinner() {
  return (
    <svg className="h-5 w-5" viewBox="0 0 20 20">
      <circle
        cx="10"
        cy="10"
        r="8"
        fill="none"
        stroke="var(--color-border)"
        strokeWidth="2"
      />
      <motion.circle
        cx="10"
        cy="10"
        r="8"
        fill="none"
        stroke="var(--color-primary)"
        strokeWidth="2"
        strokeLinecap="round"
        strokeDasharray="50.27"
        initial={{ strokeDashoffset: 50.27 }}
        animate={{ strokeDashoffset: 0, rotate: 360 }}
        transition={{
          strokeDashoffset: { duration: 2, ease: "easeInOut" },
          rotate: { duration: 1.5, repeat: Infinity, ease: "linear" },
        }}
        style={{ transformOrigin: "center" }}
      />
    </svg>
  );
}

export default function KeyValidator({
  label,
  description,
  placeholder,
  value,
  result,
  validating,
  required,
  onChange,
  onValidate,
  helpUrl,
  costBadge,
  guide,
  onSkip,
}: Props) {
  const hasValue = value.trim().length > 0;
  const isValid = !validating && result?.valid === true;
  const isInvalid = !validating && result?.valid === false;

  return (
    <motion.div
      layout
      className={`rounded-xl border p-4 transition-colors duration-300 ${
        isValid
          ? "border-green-200 bg-green-50/30"
          : isInvalid
            ? "border-red-200 bg-red-50/30"
            : "border-[var(--color-border)] bg-white"
      }`}
    >
      <div className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-[var(--color-text-primary)]">
            {label}
          </span>
          {required && (
            <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-amber-700">
              Required
            </span>
          )}
        </div>
        {/* Animated status indicator */}
        <AnimatePresence mode="wait">
          {validating && (
            <motion.div
              key="spinner"
              initial={{ opacity: 0, scale: 0.5 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.5 }}
            >
              <ValidationSpinner />
            </motion.div>
          )}
          {isValid && (
            <motion.span
              key="valid"
              initial={{ opacity: 0, scale: 0 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: "spring", stiffness: 300, damping: 20 }}
              className="flex h-6 w-6 items-center justify-center rounded-full bg-green-100 text-green-600"
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
                  strokeWidth={2.5}
                  d="M5 13l4 4L19 7"
                />
              </svg>
            </motion.span>
          )}
          {isInvalid && (
            <motion.span
              key="invalid"
              initial={{ opacity: 0, scale: 0 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: "spring", stiffness: 300, damping: 20 }}
              className="flex h-6 w-6 items-center justify-center rounded-full bg-red-100 text-red-600"
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
                  strokeWidth={2.5}
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </motion.span>
          )}
        </AnimatePresence>
      </div>

      <p className="mb-1 text-xs text-[var(--color-text-muted)]">
        {description}
      </p>

      {/* Cost badge slot */}
      {costBadge && <div className="mb-3">{costBadge}</div>}
      {!costBadge && <div className="mb-2" />}

      {/* Setup guide slot */}
      {guide}

      {/* Input row */}
      <div className="flex gap-2">
        <div className="relative flex-1">
          <input
            type="password"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder}
            className={`w-full rounded-lg border px-3 py-2 text-sm font-mono outline-none transition ${
              isValid
                ? "border-green-300 focus:border-green-400 focus:ring-2 focus:ring-green-400/20"
                : isInvalid
                  ? "border-red-300 focus:border-red-400 focus:ring-2 focus:ring-red-400/20"
                  : "border-[var(--color-border)] focus:border-[var(--color-primary)] focus:ring-2 focus:ring-[var(--color-primary)]/20"
            }`}
          />
          {/* Inline validation progress bar */}
          {validating && (
            <motion.div
              className="absolute bottom-0 left-0 h-0.5 rounded-full bg-[var(--color-primary)]"
              initial={{ width: "0%" }}
              animate={{ width: "85%" }}
              transition={{ duration: 2, ease: "easeOut" }}
            />
          )}
        </div>
        <motion.button
          onClick={onValidate}
          disabled={!hasValue || validating}
          whileHover={hasValue && !validating ? { scale: 1.03 } : {}}
          whileTap={hasValue && !validating ? { scale: 0.97 } : {}}
          className={`shrink-0 rounded-lg px-4 py-2 text-sm font-medium transition ${
            validating
              ? "cursor-wait border border-[var(--color-primary)]/30 bg-[var(--color-primary)]/5 text-[var(--color-primary)]"
              : hasValue
                ? "border border-[var(--color-primary)] bg-[var(--color-primary)]/5 text-[var(--color-primary)] hover:bg-[var(--color-primary)]/10"
                : "cursor-not-allowed border border-[var(--color-border)] text-[var(--color-text-muted)] opacity-40"
          }`}
        >
          {validating ? (
            <span className="flex items-center gap-1.5">
              <svg
                className="h-3.5 w-3.5 animate-spin"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                />
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                />
              </svg>
              Verifying
            </span>
          ) : (
            "Verify"
          )}
        </motion.button>
      </div>

      {/* Animated result message */}
      <AnimatePresence>
        {result && (
          <motion.div
            initial={{ opacity: 0, height: 0, marginTop: 0 }}
            animate={{ opacity: 1, height: "auto", marginTop: 8 }}
            exit={{ opacity: 0, height: 0, marginTop: 0 }}
            className={`overflow-hidden rounded-md px-3 py-2 text-xs ${
              result.valid
                ? "bg-green-50 text-green-700"
                : "bg-red-50 text-red-700"
            }`}
          >
            <div className="flex items-start gap-2">
              {result.valid ? (
                <svg
                  className="mt-0.5 h-3 w-3 shrink-0"
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
                <svg
                  className="mt-0.5 h-3 w-3 shrink-0"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2.5}
                    d="M12 9v2m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              )}
              <div>
                {result.message}
                {result.details && (
                  <span className="ml-1 opacity-70">({result.details})</span>
                )}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Help link and skip */}
      <div className="mt-2 flex items-center justify-between">
        {helpUrl ? (
          <a
            href={helpUrl}
            target="_blank"
            rel="noopener"
            className="inline-flex items-center gap-1 text-xs text-[var(--color-primary)] hover:underline"
          >
            Get a key
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
        ) : (
          <span />
        )}
        {onSkip && (
          <button
            type="button"
            onClick={onSkip}
            className="text-xs text-[var(--color-text-muted)] hover:text-[var(--color-text-secondary)] hover:underline"
          >
            Skip for now &rarr;
          </button>
        )}
      </div>
    </motion.div>
  );
}
