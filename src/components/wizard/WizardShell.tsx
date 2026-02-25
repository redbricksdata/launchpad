"use client";

import { useState, useCallback } from "react";
import { AnimatePresence, motion } from "framer-motion";
import type { LaunchConfig } from "@/types/tenant";
import StepIdentity from "./StepIdentity";
import StepKeys from "./StepKeys";
import StepBlueprint from "./StepBlueprint";
import StepPropagation from "./StepPropagation";

const STEPS = [
  { id: "blueprint", label: "Design", icon: "1" },
  { id: "keys", label: "Services", icon: "2" },
  { id: "identity", label: "Name & Domain", icon: "3" },
  { id: "launch", label: "Launch", icon: "4" },
] as const;

const slideVariants = {
  enter: (direction: number) => ({
    x: direction > 0 ? 80 : -80,
    opacity: 0,
  }),
  center: {
    x: 0,
    opacity: 1,
  },
  exit: (direction: number) => ({
    x: direction > 0 ? -80 : 80,
    opacity: 0,
  }),
};

export default function WizardShell() {
  const [step, setStep] = useState(0);
  const [direction, setDirection] = useState(0);
  const [config, setConfig] = useState<Partial<LaunchConfig>>({
    template: "preconstruction-v1",
    themePreset: "luxury-blue",
    features: {},
  });
  const [jobId, setJobId] = useState<string | null>(null);

  const updateConfig = useCallback(
    (updates: Partial<LaunchConfig>) => {
      setConfig((prev) => ({ ...prev, ...updates }));
    },
    [],
  );

  const goNext = useCallback(() => {
    setDirection(1);
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  }, []);

  const goBack = useCallback(() => {
    setDirection(-1);
    setStep((s) => Math.max(s - 1, 0));
  }, []);

  return (
    <div className="mx-auto max-w-3xl">
      {/* Step indicator */}
      <nav className="mb-8">
        <ol className="flex items-center">
          {STEPS.map((s, i) => (
            <li key={s.id} className="flex flex-1 items-center">
              <div className="flex flex-col items-center">
                <motion.div
                  initial={false}
                  animate={{
                    scale: i === step ? 1.08 : 1,
                    transition: { type: "spring", stiffness: 400, damping: 25 },
                  }}
                  className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold transition-colors duration-300 sm:h-10 sm:w-10 ${
                    i < step
                      ? "bg-[var(--color-success)] text-white"
                      : i === step
                        ? "bg-[var(--color-primary)] text-white ring-4 ring-[var(--color-primary)]/20"
                        : "bg-[var(--color-border)] text-[var(--color-text-muted)]"
                  }`}
                >
                  {i < step ? (
                    <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                    </svg>
                  ) : (
                    s.icon
                  )}
                </motion.div>
                <span
                  className={`mt-1.5 text-[11px] font-medium sm:text-xs ${
                    i <= step
                      ? "text-[var(--color-text-primary)]"
                      : "text-[var(--color-text-muted)]"
                  }`}
                >
                  {s.label}
                </span>
              </div>
              {/* Animated connector line */}
              {i < STEPS.length - 1 && (
                <div className="relative mx-1 mb-5 h-0.5 w-full overflow-hidden rounded-full bg-[var(--color-border)] sm:mx-2">
                  <motion.div
                    initial={false}
                    animate={{ width: i < step ? "100%" : "0%" }}
                    transition={{ duration: 0.4, ease: "easeInOut" }}
                    className="absolute inset-y-0 left-0 bg-[var(--color-success)]"
                  />
                </div>
              )}
            </li>
          ))}
        </ol>
      </nav>

      {/* Step content — glass card */}
      <div className="relative overflow-hidden rounded-2xl border border-white/20 bg-white/80 p-6 shadow-lg shadow-black/[0.03] backdrop-blur-md sm:p-8">
        <div className="pointer-events-none absolute -inset-px rounded-2xl bg-gradient-to-b from-[var(--color-primary)]/5 via-transparent to-transparent" />

        <AnimatePresence mode="wait" custom={direction}>
          <motion.div
            key={step}
            custom={direction}
            variants={slideVariants}
            initial="enter"
            animate="center"
            exit="exit"
            transition={{ duration: 0.25, ease: [0.4, 0, 0.2, 1] }}
          >
            {step === 0 && (
              <StepBlueprint
                config={config}
                updateConfig={updateConfig}
                onNext={goNext}
              />
            )}
            {step === 1 && (
              <StepKeys
                config={config}
                updateConfig={updateConfig}
                onNext={goNext}
                onBack={goBack}
              />
            )}
            {step === 2 && (
              <StepIdentity
                config={config}
                updateConfig={updateConfig}
                onNext={goNext}
                onBack={goBack}
              />
            )}
            {step === 3 && (
              <StepPropagation
                config={config as LaunchConfig}
                jobId={jobId}
                setJobId={setJobId}
                onBack={goBack}
              />
            )}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
