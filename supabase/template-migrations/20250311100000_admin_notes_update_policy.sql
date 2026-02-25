-- Grant UPDATE permission on admin_notes (was missing from original migration).
-- Required for completing/reopening reminders via the CRM note checkboxes.
grant update on public.admin_notes to authenticated;

-- Allow admins to update their own notes (reminders, content, etc.)
create policy "Admins can update notes"
  on public.admin_notes for update
  using (public.is_admin())
  with check (public.is_admin());
