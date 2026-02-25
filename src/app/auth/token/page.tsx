"use client";

import { useEffect, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";

type Step = "exchanging" | "success" | "error";

export default function TokenExchangePage() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [step, setStep] = useState<Step>("exchanging");
  const [error, setError] = useState("");

  useEffect(() => {
    const token = searchParams.get("token");

    if (!token) {
      setStep("error");
      setError("No authentication token provided.");
      return;
    }

    async function exchangeToken() {
      try {
        const res = await fetch("/api/auth/exchange-token", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ token }),
        });

        if (!res.ok) {
          const data = await res.json();
          throw new Error(data.error || "Authentication failed");
        }

        setStep("success");

        // Brief pause so user sees the success state
        await new Promise((r) => setTimeout(r, 1000));
        router.push("/");
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Something went wrong");
      }
    }

    exchangeToken();
  }, [searchParams, router]);

  return (
    <div className="min-h-screen flex items-center justify-center px-6 bg-[var(--color-surface-secondary)]">
      <div className="w-full max-w-md text-center">
        {/* Logo */}
        <div className="mb-12 flex items-center justify-center gap-2">
          <div className="w-10 h-10 bg-[var(--color-primary)] rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-sm">RB</span>
          </div>
          <span className="font-semibold text-xl text-[var(--color-text-primary)]">
            Launchpad
          </span>
        </div>

        <div className="bg-white rounded-2xl shadow-sm border border-[var(--color-border)] p-8">
          {step === "error" ? (
            <>
              <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-red-50 flex items-center justify-center">
                <svg className="w-8 h-8 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </div>
              <h1 className="text-xl font-bold text-[var(--color-text-primary)] mb-2">
                Authentication Failed
              </h1>
              <p className="text-sm text-[var(--color-text-secondary)] mb-6">
                {error}
              </p>
              <a
                href="/login"
                className="inline-block px-6 py-3 text-sm font-semibold text-white bg-[var(--color-primary)] hover:bg-[var(--color-primary-dark)] rounded-lg transition-all"
              >
                Go to Login
              </a>
            </>
          ) : step === "success" ? (
            <>
              <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-green-50 flex items-center justify-center">
                <svg className="w-8 h-8 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <h1 className="text-xl font-bold text-[var(--color-text-primary)] mb-2">
                Welcome to Launchpad!
              </h1>
              <p className="text-sm text-[var(--color-text-secondary)]">
                Redirecting to your dashboard...
              </p>
            </>
          ) : (
            <>
              <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-blue-50 flex items-center justify-center">
                <div className="w-6 h-6 border-2 border-[var(--color-primary)] border-t-transparent rounded-full animate-spin" />
              </div>
              <h1 className="text-xl font-bold text-[var(--color-text-primary)] mb-2">
                Signing you in...
              </h1>
              <p className="text-sm text-[var(--color-text-secondary)]">
                Setting up your Launchpad session.
              </p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
