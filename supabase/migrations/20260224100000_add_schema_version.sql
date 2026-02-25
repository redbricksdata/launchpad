-- Add schema_version to tenants table for tracking which template migrations
-- have been applied to each tenant's Supabase project.
-- This enables the Red Bricks OS upgrade system.

ALTER TABLE tenants ADD COLUMN schema_version TEXT;

CREATE INDEX idx_tenants_schema_version ON tenants(schema_version);

-- Also add 'upgrade' as a valid job_type for tenant_jobs
ALTER TABLE tenant_jobs DROP CONSTRAINT IF EXISTS tenant_jobs_job_type_check;
ALTER TABLE tenant_jobs ADD CONSTRAINT tenant_jobs_job_type_check
  CHECK (job_type IN ('launch', 'update_keys', 'add_domain', 'upgrade'));
