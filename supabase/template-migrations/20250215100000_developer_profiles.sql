-- Developer Profiles for marketplace widget developers
-- Stores company branding, logo, and contact info.

CREATE TABLE IF NOT EXISTS public.developer_profiles (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  company_name text NOT NULL,
  logo_url     text,
  website      text,
  bio          text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_dev_profiles_user ON public.developer_profiles(user_id);

ALTER TABLE public.developer_profiles ENABLE ROW LEVEL SECURITY;

-- Anyone can read developer profiles (needed on widget detail pages)
CREATE POLICY "Anyone can read developer profiles"
  ON public.developer_profiles FOR SELECT
  USING (true);

-- Users can create their own profile
CREATE POLICY "Users can create own profile"
  ON public.developer_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON public.developer_profiles FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own profile
CREATE POLICY "Users can delete own profile"
  ON public.developer_profiles FOR DELETE
  USING (auth.uid() = user_id);

-- Service role bypass for admin operations
CREATE POLICY "Service role can manage all profiles"
  ON public.developer_profiles FOR ALL
  USING (auth.role() = 'service_role');
