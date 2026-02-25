"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

interface AppHeaderProps {
  email: string;
  isAdmin?: boolean;
}

export default function AppHeader({ email, isAdmin }: AppHeaderProps) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  const navLinks = [
    { href: "/", label: "Dashboard" },
    { href: "/settings", label: "Settings" },
  ];

  return (
    <header className="border-b border-[var(--color-border)] bg-white">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3">
        {/* Left: Logo */}
        <Link href="/" className="flex items-center gap-2.5">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--color-primary)] text-xs font-bold text-white">
            RB
          </div>
          <span className="text-lg font-semibold text-[var(--color-text-primary)]">
            Launchpad
          </span>
          {isAdmin && (
            <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-amber-700">
              Admin
            </span>
          )}
        </Link>

        {/* Desktop nav */}
        <div className="hidden items-center gap-6 md:flex">
          <nav className="flex items-center gap-1">
            {navLinks.map((link) => {
              const isActive =
                link.href === "/"
                  ? pathname === "/"
                  : pathname.startsWith(link.href);
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className={`rounded-md px-3 py-1.5 text-sm transition ${
                    isActive
                      ? "font-medium text-[var(--color-primary)] bg-blue-50"
                      : "text-[var(--color-text-muted)] hover:text-[var(--color-text-primary)] hover:bg-[var(--color-surface-secondary)]"
                  }`}
                >
                  {link.label}
                </Link>
              );
            })}
          </nav>

          <div className="h-5 w-px bg-[var(--color-border)]" />

          <span className="text-sm text-[var(--color-text-muted)]">
            {email}
          </span>

          <form action="/api/auth/logout" method="POST">
            <button
              type="submit"
              className="text-sm text-[var(--color-text-muted)] hover:text-[var(--color-text-primary)] transition"
            >
              Sign out
            </button>
          </form>
        </div>

        {/* Mobile hamburger */}
        <button
          onClick={() => setMobileOpen(!mobileOpen)}
          className="flex h-9 w-9 items-center justify-center rounded-lg border border-[var(--color-border)] md:hidden"
          aria-label="Toggle menu"
        >
          {mobileOpen ? (
            <svg className="h-5 w-5 text-[var(--color-text-secondary)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          ) : (
            <svg className="h-5 w-5 text-[var(--color-text-secondary)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          )}
        </button>
      </div>

      {/* Mobile drawer */}
      {mobileOpen && (
        <div className="border-t border-[var(--color-border)] bg-white px-4 py-3 md:hidden">
          <nav className="flex flex-col gap-1">
            {navLinks.map((link) => {
              const isActive =
                link.href === "/"
                  ? pathname === "/"
                  : pathname.startsWith(link.href);
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  onClick={() => setMobileOpen(false)}
                  className={`rounded-md px-3 py-2 text-sm transition ${
                    isActive
                      ? "font-medium text-[var(--color-primary)] bg-blue-50"
                      : "text-[var(--color-text-muted)] hover:bg-[var(--color-surface-secondary)]"
                  }`}
                >
                  {link.label}
                </Link>
              );
            })}
          </nav>

          <div className="mt-3 border-t border-[var(--color-border)] pt-3">
            <p className="px-3 text-xs text-[var(--color-text-muted)]">{email}</p>
            <form action="/api/auth/logout" method="POST" className="mt-2">
              <button
                type="submit"
                className="w-full rounded-md px-3 py-2 text-left text-sm text-[var(--color-text-muted)] hover:bg-[var(--color-surface-secondary)]"
              >
                Sign out
              </button>
            </form>
          </div>
        </div>
      )}
    </header>
  );
}
