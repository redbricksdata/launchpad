"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import type { LaunchConfig } from "@/types/tenant";

interface Props {
  config: Partial<LaunchConfig>;
  updateConfig: (updates: Partial<LaunchConfig>) => void;
  onNext: () => void;
  onBack?: () => void;
}

const THEMES = [
  {
    id: "luxury-blue",
    name: "Luxury Blue",
    primary: "#1e40af",
    accent: "#d97706",
    headerBg: "#1e3a5f",
    glow: "shadow-blue-500/25",
    description: "Elegant and professional",
  },
  {
    id: "modern-green",
    name: "Modern Green",
    primary: "#047857",
    accent: "#0284c7",
    headerBg: "#064e3b",
    glow: "shadow-emerald-500/25",
    description: "Fresh and contemporary",
  },
  {
    id: "warm-gold",
    name: "Warm Gold",
    primary: "#92400e",
    accent: "#b45309",
    headerBg: "#78350f",
    glow: "shadow-amber-500/25",
    description: "Warm and inviting",
  },
  {
    id: "urban-dark",
    name: "Urban Dark",
    primary: "#1e293b",
    accent: "#6366f1",
    headerBg: "#0f172a",
    glow: "shadow-indigo-500/25",
    description: "Bold and modern",
  },
];

const FEATURE_GROUPS = [
  {
    label: "Core Features",
    features: [
      { id: "search", name: "Property Search", default: true },
      { id: "map", name: "Map Explorer", default: true },
      { id: "floorplans", name: "Floorplan Details", default: true },
      { id: "favorites", name: "Favorites / Bookmarks", default: true },
      { id: "compare", name: "Property Comparison", default: true },
    ],
  },
  {
    label: "Engagement",
    features: [
      { id: "blog", name: "Blog / Content", default: true },
      { id: "chat", name: "Live Chat Widget", default: true },
      { id: "appointments", name: "Appointment Booking", default: true },
      { id: "contactForm", name: "Contact Form", default: true },
      { id: "notifications", name: "User Notifications", default: true },
    ],
  },
  {
    label: "Advanced",
    features: [
      { id: "crm", name: "CRM Dashboard", default: true },
      { id: "emailStudio", name: "Email Studio", default: true },
      { id: "analytics", name: "Visitor Analytics", default: true },
      { id: "portfolio", name: "Client Portfolio", default: false },
      { id: "mortgageCalculator", name: "Mortgage Calculator", default: true },
    ],
  },
];

/** Mini wireframe preview showing header + content colored by theme */
function ThemePreview({
  headerBg,
  primary,
  accent,
}: {
  headerBg: string;
  primary: string;
  accent: string;
}) {
  return (
    <div className="mb-3 overflow-hidden rounded-md border border-black/5">
      {/* Header bar */}
      <div
        className="flex items-center gap-1.5 px-2 py-1.5"
        style={{ backgroundColor: headerBg }}
      >
        <div className="h-1.5 w-5 rounded-sm bg-white/80" />
        <div className="ml-auto flex gap-1">
          <div className="h-1.5 w-4 rounded-sm bg-white/40" />
          <div className="h-1.5 w-4 rounded-sm bg-white/40" />
          <div className="h-1.5 w-4 rounded-sm bg-white/40" />
        </div>
      </div>
      {/* Content area */}
      <div className="bg-gray-50/80 px-2 py-2">
        <div className="mb-1.5 h-1.5 w-3/4 rounded-sm bg-gray-300" />
        <div className="mb-2 h-1 w-1/2 rounded-sm bg-gray-200" />
        <div
          className="mb-2 h-2.5 w-10 rounded-sm"
          style={{ backgroundColor: primary }}
        />
        <div className="flex gap-1">
          <div className="flex-1 rounded-sm border border-gray-200 bg-white p-1">
            <div className="mb-1 h-3 rounded-sm bg-gray-100" />
            <div
              className="h-1 w-2/3 rounded-sm"
              style={{ backgroundColor: accent, opacity: 0.5 }}
            />
          </div>
          <div className="flex-1 rounded-sm border border-gray-200 bg-white p-1">
            <div className="mb-1 h-3 rounded-sm bg-gray-100" />
            <div
              className="h-1 w-2/3 rounded-sm"
              style={{ backgroundColor: accent, opacity: 0.5 }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

/** CSS-only toggle switch */
function ToggleSwitch({
  checked,
  onChange,
}: {
  checked: boolean;
  onChange: () => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={onChange}
      className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ${
        checked ? "bg-[var(--color-primary)]" : "bg-gray-200"
      }`}
    >
      <motion.span
        layout
        transition={{ type: "spring", stiffness: 500, damping: 30 }}
        className="pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow-sm"
        style={{ marginLeft: checked ? 16 : 0 }}
      />
    </button>
  );
}

export default function StepBlueprint({
  config,
  updateConfig,
  onNext,
  onBack,
}: Props) {
  const [selectedTheme, setSelectedTheme] = useState(
    config.themePreset || "luxury-blue",
  );
  const [features, setFeatures] = useState<Record<string, boolean>>(() => {
    const defaults: Record<string, boolean> = {};
    for (const group of FEATURE_GROUPS) {
      for (const f of group.features) {
        defaults[f.id] = config.features?.[f.id] ?? f.default;
      }
    }
    return defaults;
  });

  function toggleFeature(id: string) {
    setFeatures((prev) => ({ ...prev, [id]: !prev[id] }));
  }

  function handleNext() {
    updateConfig({
      themePreset: selectedTheme,
      features,
    });
    onNext();
  }

  return (
    <div>
      <h2 className="mb-1 text-xl font-bold text-[var(--color-text-primary)]">
        Design Your Site
      </h2>
      <p className="mb-6 text-sm text-[var(--color-text-secondary)]">
        Pick a theme and choose the features you want. Everything can be
        changed later from your site&apos;s admin panel.
      </p>

      {/* Theme Selection */}
      <div className="mb-8">
        <h3 className="mb-3 text-sm font-semibold text-[var(--color-text-primary)]">
          Theme
        </h3>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {THEMES.map((theme) => {
            const isSelected = selectedTheme === theme.id;
            return (
              <motion.button
                key={theme.id}
                onClick={() => setSelectedTheme(theme.id)}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                animate={
                  isSelected
                    ? { scale: 1.02 }
                    : { scale: 1 }
                }
                transition={{ type: "spring", stiffness: 400, damping: 25 }}
                className={`relative rounded-xl border-2 p-3 text-left transition-shadow duration-300 ${
                  isSelected
                    ? `border-transparent shadow-xl ${theme.glow}`
                    : "border-[var(--color-border)] shadow-sm hover:border-[var(--color-primary)]/30"
                }`}
              >
                {/* Active glow ring */}
                {isSelected && (
                  <motion.div
                    layoutId="theme-glow"
                    className="absolute -inset-px rounded-xl"
                    style={{
                      border: `2px solid ${theme.primary}`,
                      boxShadow: `0 0 20px ${theme.primary}33, 0 0 40px ${theme.primary}11`,
                    }}
                    transition={{ type: "spring", stiffness: 300, damping: 30 }}
                  />
                )}

                <ThemePreview
                  headerBg={theme.headerBg}
                  primary={theme.primary}
                  accent={theme.accent}
                />
                <p className="text-sm font-medium text-[var(--color-text-primary)]">
                  {theme.name}
                </p>
                <p className="text-xs text-[var(--color-text-muted)]">
                  {theme.description}
                </p>
              </motion.button>
            );
          })}
        </div>
      </div>

      {/* Feature Toggles */}
      <div>
        <div className="mb-3 flex items-center justify-between">
          <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
            Features
          </h3>
          <span className="text-xs text-[var(--color-text-muted)]">
            {Object.values(features).filter(Boolean).length} enabled
          </span>
        </div>
        <div className="space-y-4">
          {FEATURE_GROUPS.map((group) => (
            <div key={group.label}>
              <p className="mb-2 text-xs font-medium uppercase tracking-wider text-[var(--color-text-muted)]">
                {group.label}
              </p>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {group.features.map((f) => (
                  <motion.label
                    key={f.id}
                    whileHover={{ scale: 1.01 }}
                    whileTap={{ scale: 0.99 }}
                    className={`flex cursor-pointer items-center justify-between rounded-lg border px-3 py-2.5 transition-colors duration-150 ${
                      features[f.id]
                        ? "border-[var(--color-primary)]/20 bg-[var(--color-primary)]/[0.03]"
                        : "border-[var(--color-border)] hover:bg-[var(--color-surface-secondary)]"
                    }`}
                  >
                    <span className="text-sm text-[var(--color-text-primary)]">
                      {f.name}
                    </span>
                    <ToggleSwitch
                      checked={features[f.id]}
                      onChange={() => toggleFeature(f.id)}
                    />
                  </motion.label>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Navigation */}
      <div
        className={`mt-8 flex ${onBack ? "justify-between" : "justify-end"}`}
      >
        {onBack && (
          <button
            onClick={onBack}
            className="rounded-lg border border-[var(--color-border)] px-6 py-2.5 text-sm font-medium text-[var(--color-text-secondary)] transition hover:bg-[var(--color-surface-secondary)]"
          >
            Back
          </button>
        )}
        <motion.button
          onClick={handleNext}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.97 }}
          className="rounded-lg bg-[var(--color-primary)] px-6 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-primary-dark)]"
        >
          Continue
        </motion.button>
      </div>
    </div>
  );
}
