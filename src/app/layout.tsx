import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Launchpad — Red Bricks",
  description: "Deploy your pre-construction real estate site in seconds",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-[var(--color-surface-secondary)]">
        {children}
      </body>
    </html>
  );
}
