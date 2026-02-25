-- Platform Database Schema
-- This schema lives in the Red Bricks "Platform" Supabase project (NOT agent databases).
-- It stores tenant metadata, encrypted keys, domain mappings, and provisioning jobs.

-- ── Tenants ────────────────────────────────────────────────
-- One row per agent site. Links to Red Bricks Laravel team_id.
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id BIGINT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  template TEXT NOT NULL DEFAULT 'preconstruction-v1',
  status TEXT NOT NULL DEFAULT 'provisioning'
    CHECK (status IN ('provisioning', 'active', 'suspended', 'archived')),
  theme_preset TEXT DEFAULT 'luxury-blue',
  feature_flags JSONB DEFAULT '{}',
  admin_email TEXT NOT NULL,
  supabase_project_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tenants_team_id ON tenants(team_id);
CREATE INDEX idx_tenants_status ON tenants(status);
CREATE INDEX idx_tenants_slug ON tenants(slug);

-- ── Tenant Domains ─────────────────────────────────────────
-- Supports both subdomains (*.red-bricks.app) and custom domains.
CREATE TABLE tenant_domains (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  hostname TEXT UNIQUE NOT NULL,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  ssl_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (ssl_status IN ('pending', 'active', 'failed')),
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tenant_domains_hostname ON tenant_domains(hostname);
CREATE INDEX idx_tenant_domains_tenant_id ON tenant_domains(tenant_id);

-- ── Tenant Keys ────────────────────────────────────────────
-- Encrypted API keys. Uses AES-256-GCM (format: base64(iv):base64(cipher):base64(tag)).
-- key_type is an enum-like text field for flexibility.
CREATE TABLE tenant_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  key_type TEXT NOT NULL
    CHECK (key_type IN (
      'supabase_url', 'supabase_anon_key', 'supabase_service_role',
      'google_maps', 'gemini', 'resend', 'redbricks_token'
    )),
  encrypted_value TEXT NOT NULL,
  validated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, key_type)
);

CREATE INDEX idx_tenant_keys_tenant_id ON tenant_keys(tenant_id);

-- ── Provisioning Jobs ──────────────────────────────────────
-- Tracks the multi-step launch/update process for the wizard's status tracker.
CREATE TABLE tenant_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  job_type TEXT NOT NULL
    CHECK (job_type IN ('launch', 'update_keys', 'add_domain')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'completed', 'failed')),
  steps JSONB NOT NULL DEFAULT '[]',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX idx_tenant_jobs_tenant_id ON tenant_jobs(tenant_id);
CREATE INDEX idx_tenant_jobs_status ON tenant_jobs(status);

-- ── RLS Policies ───────────────────────────────────────────
-- The Platform DB uses two access patterns:
-- 1. Launchpad app: service_role key (full access, bypasses RLS)
-- 2. Template middleware: restricted anon key (read-only on active tenants)

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_jobs ENABLE ROW LEVEL SECURITY;

-- Anon (template middleware): read-only on active tenants
CREATE POLICY "anon_read_active_tenants" ON tenants
  FOR SELECT TO anon
  USING (status = 'active');

CREATE POLICY "anon_read_domains" ON tenant_domains
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon_read_keys" ON tenant_keys
  FOR SELECT TO anon
  USING (true);

-- No anon access to jobs (only Launchpad via service_role)
CREATE POLICY "no_anon_jobs" ON tenant_jobs
  FOR SELECT TO anon
  USING (false);

-- ── Updated_at trigger ─────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tenants_updated_at
  BEFORE UPDATE ON tenants
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tenant_keys_updated_at
  BEFORE UPDATE ON tenant_keys
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
