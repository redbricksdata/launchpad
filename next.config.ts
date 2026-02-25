import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Launchpad is a standalone app — no rewrites to the template

  // Include the template migration SQL files in the production bundle.
  // These are read at runtime to provision new tenant databases.
  // Include template migration SQL files in the production bundle.
  // These are read at runtime for both initial provisioning and upgrades.
  outputFileTracingIncludes: {
    "/api/launch": ["./supabase/template-migrations/**/*.sql"],
    "/api/admin/upgrade": ["./supabase/template-migrations/**/*.sql"],
    "/api/admin/upgrade/[tenantId]": ["./supabase/template-migrations/**/*.sql"],
  },
};

export default nextConfig;
