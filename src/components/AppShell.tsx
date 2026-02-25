import Link from "next/link";
import AppHeader from "./AppHeader";

interface Breadcrumb {
  label: string;
  href?: string;
}

interface AppShellProps {
  children: React.ReactNode;
  email: string;
  isAdmin?: boolean;
  breadcrumbs?: Breadcrumb[];
}

export default function AppShell({
  children,
  email,
  isAdmin,
  breadcrumbs,
}: AppShellProps) {
  return (
    <div className="min-h-screen bg-[var(--color-surface-secondary)] flex flex-col">
      <AppHeader email={email} isAdmin={isAdmin} />

      {/* Breadcrumbs */}
      {breadcrumbs && breadcrumbs.length > 0 && (
        <div className="border-b border-[var(--color-border)] bg-white">
          <nav className="mx-auto flex max-w-5xl items-center gap-2 px-4 py-2 text-sm">
            {breadcrumbs.map((crumb, i) => (
              <span key={i} className="flex items-center gap-2">
                {i > 0 && (
                  <span className="text-[var(--color-border)]">/</span>
                )}
                {crumb.href ? (
                  <Link
                    href={crumb.href}
                    className="text-[var(--color-text-muted)] hover:text-[var(--color-text-primary)] transition"
                  >
                    {crumb.label}
                  </Link>
                ) : (
                  <span className="font-medium text-[var(--color-text-primary)]">
                    {crumb.label}
                  </span>
                )}
              </span>
            ))}
          </nav>
        </div>
      )}

      {/* Main content */}
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-8">
        {children}
      </main>

      {/* Footer */}
      <footer className="border-t border-[var(--color-border)] bg-white">
        <div className="mx-auto max-w-5xl px-4 py-4">
          <p className="text-xs text-[var(--color-text-muted)]">
            &copy; {new Date().getFullYear()} Red Bricks Data Inc.
          </p>
        </div>
      </footer>
    </div>
  );
}
