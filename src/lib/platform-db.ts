/**
 * Platform Supabase client for the Launchpad.
 * Uses the service_role key for full CRUD access to tenant data.
 *
 * Uses `any` for the Database generic because we don't have auto-generated
 * types from `supabase gen types`. Callers should cast query results to
 * the appropriate types from @/types/tenant.
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let client: SupabaseClient<any> | null = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function getPlatformClient(): SupabaseClient<any> {
  if (client) return client;

  const url = process.env.PLATFORM_SUPABASE_URL;
  const key = process.env.PLATFORM_SUPABASE_SERVICE_KEY;

  if (!url || !key) {
    throw new Error(
      "Platform Supabase not configured. Set PLATFORM_SUPABASE_URL and PLATFORM_SUPABASE_SERVICE_KEY.",
    );
  }

  client = createClient(url, key);
  return client;
}
