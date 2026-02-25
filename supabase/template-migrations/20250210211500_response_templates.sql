-- Migration 018: Response Templates
-- Pre-built email/message templates for agent efficiency.

CREATE TABLE public.response_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  subject text NOT NULL,
  body_html text NOT NULL,
  category text DEFAULT 'general',
  sort_order int DEFAULT 0,
  created_at timestamptz DEFAULT now() NOT NULL
);

ALTER TABLE public.response_templates ENABLE ROW LEVEL SECURITY;

-- Admin-only: read, insert, update, delete
CREATE POLICY "Admins can manage response templates"
  ON public.response_templates
  FOR ALL
  USING (public.is_admin());

-- Seed default templates
INSERT INTO public.response_templates (name, subject, body_html, category, sort_order) VALUES
(
  'Thank You for Your Interest',
  'Thank you for your interest in {{project_name}}',
  '<p>Hi {{name}},</p><p>Thank you for your interest in <strong>{{project_name}}</strong>. I''d love to help you explore this opportunity further.</p><p>This project offers some fantastic options, and I can provide you with detailed pricing, floorplans, and any other information you need to make an informed decision.</p><p>Would you like to schedule a time to chat? I''m available at your convenience.</p><p>Best regards,<br>{{agent_name}}<br>{{site_name}}</p>',
  'follow_up',
  1
),
(
  'Floorplan Details',
  'Floorplan details for {{floorplan_name}} at {{project_name}}',
  '<p>Hi {{name}},</p><p>Here are the details for the <strong>{{floorplan_name}}</strong> floorplan at <strong>{{project_name}}</strong> that you were interested in.</p><p>I''ve attached all the relevant information. If you''d like to discuss pricing, availability, or compare this with other options, I''m happy to help.</p><p>Feel free to reach out anytime — I''m here to assist!</p><p>Best regards,<br>{{agent_name}}<br>{{site_name}}</p>',
  'follow_up',
  2
),
(
  'Appointment Confirmation',
  'Your appointment is confirmed — {{preferred_date}}',
  '<p>Hi {{name}},</p><p>This is to confirm your upcoming <strong>{{appointment_type}}</strong> scheduled for <strong>{{preferred_date}}</strong> at <strong>{{preferred_time}}</strong>.</p><p>We''ll be discussing <strong>{{project_name}}</strong> and any questions you may have about pre-construction opportunities.</p><p>If you need to reschedule, just reply to this email and we''ll find a time that works.</p><p>Looking forward to speaking with you!</p><p>Best regards,<br>{{agent_name}}<br>{{site_name}}</p>',
  'appointment',
  3
),
(
  'Follow-Up: Next Steps',
  'Next steps for {{project_name}}',
  '<p>Hi {{name}},</p><p>It was great connecting with you! I wanted to follow up on our conversation about <strong>{{project_name}}</strong>.</p><p>Here are the next steps I''d recommend:</p><ul><li>Review the floorplans and pricing I shared</li><li>Let me know which units interest you most</li><li>We can schedule a visit to the sales centre if you''d like</li></ul><p>The pre-construction market moves quickly, so don''t hesitate to reach out if you have any questions.</p><p>Best regards,<br>{{agent_name}}<br>{{site_name}}</p>',
  'follow_up',
  4
),
(
  'General Follow-Up',
  'Following up on your inquiry',
  '<p>Hi {{name}},</p><p>I wanted to check in and see if you had any questions about the pre-construction projects we discussed.</p><p>Whether you''re still in the research phase or ready to take the next step, I''m here to help. I can provide updated pricing, arrange viewings, or walk you through the buying process.</p><p>Looking forward to hearing from you!</p><p>Best regards,<br>{{agent_name}}<br>{{site_name}}</p>',
  'general',
  5
);
