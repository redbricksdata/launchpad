/**
 * Supabase database type definitions for the Platform DB.
 *
 * These types match the schema in:
 * apps/launchpad/supabase/migrations/20260224000000_platform_schema.sql
 *
 * NOTE: In a production setup, these would be auto-generated via
 * `npx supabase gen types typescript`. For now, hand-maintained.
 */

type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export interface PlatformDatabase {
  public: {
    Tables: {
      tenants: {
        Row: {
          id: string;
          team_id: number;
          slug: string;
          display_name: string;
          template: string;
          status: string;
          theme_preset: string;
          feature_flags: Json;
          admin_email: string;
          supabase_project_ref: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          team_id: number;
          slug: string;
          display_name: string;
          template?: string;
          status?: string;
          theme_preset?: string;
          feature_flags?: Json;
          admin_email: string;
          supabase_project_ref?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          team_id?: number;
          slug?: string;
          display_name?: string;
          template?: string;
          status?: string;
          theme_preset?: string;
          feature_flags?: Json;
          admin_email?: string;
          supabase_project_ref?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      tenant_domains: {
        Row: {
          id: string;
          tenant_id: string;
          hostname: string;
          is_primary: boolean;
          ssl_status: string;
          verified_at: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          tenant_id: string;
          hostname: string;
          is_primary?: boolean;
          ssl_status?: string;
          verified_at?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          tenant_id?: string;
          hostname?: string;
          is_primary?: boolean;
          ssl_status?: string;
          verified_at?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      tenant_keys: {
        Row: {
          id: string;
          tenant_id: string;
          key_type: string;
          encrypted_value: string;
          validated_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          tenant_id: string;
          key_type: string;
          encrypted_value: string;
          validated_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          tenant_id?: string;
          key_type?: string;
          encrypted_value?: string;
          validated_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      tenant_jobs: {
        Row: {
          id: string;
          tenant_id: string;
          job_type: string;
          status: string;
          steps: Json;
          error: string | null;
          created_at: string;
          completed_at: string | null;
        };
        Insert: {
          id?: string;
          tenant_id: string;
          job_type: string;
          status?: string;
          steps?: Json;
          error?: string | null;
          created_at?: string;
          completed_at?: string | null;
        };
        Update: {
          id?: string;
          tenant_id?: string;
          job_type?: string;
          status?: string;
          steps?: Json;
          error?: string | null;
          created_at?: string;
          completed_at?: string | null;
        };
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
}
