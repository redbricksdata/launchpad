"use client";

import { useState } from "react";

interface Props {
  variant: "free" | "free-limited" | "paid";
  label: string;
  detail: string;
}

const VARIANT_STYLES: Record<string, string> = {
  free: "bg-green-50 text-green-700 border-green-200",
  "free-limited": "bg-blue-50 text-blue-700 border-blue-200",
  paid: "bg-amber-50 text-amber-700 border-amber-200",
};

export default function CostBadge({ variant, label, detail }: Props) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="mt-2">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium transition ${VARIANT_STYLES[variant]}`}
      >
        {variant === "free" && (
          <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        )}
        {variant === "free-limited" && (
          <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        )}
        {variant === "paid" && (
          <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        )}
        {label}
        <svg
          className={`h-3 w-3 transition ${expanded ? "rotate-180" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {expanded && (
        <p className="mt-1.5 text-[11px] leading-relaxed text-[var(--color-text-muted)]">
          {detail}
        </p>
      )}
    </div>
  );
}
