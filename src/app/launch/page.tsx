import { redirect } from "next/navigation";
import { getAuthToken, getProfile } from "@/lib/auth";
import AppShell from "@/components/AppShell";
import WizardShell from "@/components/wizard/WizardShell";

export default async function LaunchPage() {
  const token = await getAuthToken();
  if (!token) redirect("/login");

  let user;
  try {
    user = await getProfile(token);
  } catch {
    redirect("/login");
  }

  return (
    <AppShell
      email={user.email}
      breadcrumbs={[
        { label: "Dashboard", href: "/" },
        { label: "Launch New Site" },
      ]}
    >
      <div className="mb-8 text-center">
        <h1 className="text-3xl font-bold text-[var(--color-text-primary)]">
          Launch Your Site
        </h1>
        <p className="mt-2 text-sm text-[var(--color-text-secondary)]">
          Four steps to your pre-construction real estate website
        </p>
      </div>

      <WizardShell />
    </AppShell>
  );
}
