/** Tenant record from the platform database */
export interface Tenant {
  id: string;
  team_id: number;
  slug: string;
  display_name: string;
  template: string;
  status: "provisioning" | "active" | "suspended" | "archived";
  theme_preset: string;
  feature_flags: Record<string, boolean>;
  admin_email: string;
  supabase_project_ref: string | null;
  schema_version: string | null;
  created_at: string;
  updated_at: string;
}

/** Domain mapping for a tenant */
export interface TenantDomain {
  id: string;
  tenant_id: string;
  hostname: string;
  is_primary: boolean;
  ssl_status: "pending" | "active" | "failed";
  verified_at: string | null;
  created_at: string;
}

/** Key types that can be stored per tenant */
export type TenantKeyType =
  | "supabase_url"
  | "supabase_anon_key"
  | "supabase_service_role"
  | "google_maps"
  | "gemini"
  | "openai"
  | "anthropic"
  | "resend"
  | "sendgrid"
  | "redbricks_token";

/** Supported AI providers */
export type AIProvider = "gemini" | "openai" | "anthropic";

/** Supported email providers */
export type EmailProvider = "resend" | "sendgrid";

/** Provisioning job */
export interface TenantJob {
  id: string;
  tenant_id: string;
  job_type: "launch" | "update_keys" | "add_domain" | "upgrade";
  status: "pending" | "running" | "completed" | "failed";
  steps: TenantJobStep[];
  error: string | null;
  created_at: string;
  completed_at: string | null;
}

export interface TenantJobStep {
  name: string;
  status: "pending" | "running" | "completed" | "failed";
  started_at?: string;
  completed_at?: string;
  error?: string;
}

/** Key validation result */
export interface ValidationResult {
  valid: boolean;
  message: string;
  details?: string;
}

/** Red Bricks team info returned from Laravel API */
export interface TeamInfo {
  id: number;
  name: string;
  tier: "free" | "pro" | "team";
  api_token: string;
  owner_email: string;
  owner_name: string;
}

/** Wizard form state */
export interface LaunchConfig {
  // Step 1: Identity
  slug: string;
  displayName: string;
  customDomain?: string;
  // Step 2: Keys
  googleMapsKey?: string;
  aiProvider?: AIProvider;
  aiKey?: string;
  emailProvider?: EmailProvider;
  emailKey?: string;
  /** @deprecated Use aiKey + aiProvider instead */
  geminiKey?: string;
  /** @deprecated Use emailKey + emailProvider instead */
  resendKey?: string;
  // Step 3: Blueprint
  template: string;
  themePreset: string;
  features: Record<string, boolean>;
}
