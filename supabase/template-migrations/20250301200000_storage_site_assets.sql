-- ================================================================
-- Create 'site-assets' storage bucket for image uploads
-- ================================================================
-- Public-read bucket for logos, hero images, blog images, etc.
-- Authenticated admins can upload; anyone can view.
-- ================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'site-assets',
  'site-assets',
  true,
  5242880,  -- 5MB
  ARRAY[
    'image/png',
    'image/jpeg',
    'image/svg+xml',
    'image/webp',
    'image/x-icon',
    'image/gif',
    'image/vnd.microsoft.icon'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- Anyone can read (public bucket)
CREATE POLICY "Public read access on site-assets"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'site-assets');

-- Authenticated users can upload
CREATE POLICY "Authenticated upload on site-assets"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'site-assets');

-- Authenticated users can update (overwrite)
CREATE POLICY "Authenticated update on site-assets"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'site-assets');

-- Authenticated users can delete
CREATE POLICY "Authenticated delete on site-assets"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'site-assets');
