-- 1. Add is_occupancy flag to client_unit_deposits
-- Occupancy deposits are floating payments tied to project closing,
-- not a fixed date. The due_date column stores the estimated occupancy
-- date for sorting purposes, but the UI shows "Occupancy" + expected year.
ALTER TABLE public.client_unit_deposits
  ADD COLUMN IF NOT EXISTS is_occupancy boolean NOT NULL DEFAULT false;

-- 2. Recreate import_deposit_schedule RPC to include is_occupancy
CREATE OR REPLACE FUNCTION public.import_deposit_schedule(
  p_unit_id uuid,
  p_deposit_data jsonb
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_count integer := 0;
  v_item jsonb;
BEGIN
  IF p_deposit_data IS NULL OR jsonb_typeof(p_deposit_data) != 'array' OR jsonb_array_length(p_deposit_data) = 0 THEN
    RETURN 0;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_deposit_data)
  LOOP
    INSERT INTO public.client_unit_deposits (unit_id, deposit_name, amount, due_date, is_occupancy)
    VALUES (
      p_unit_id,
      COALESCE(v_item->>'label', v_item->>'name', 'Deposit'),
      COALESCE((v_item->>'deposit_amount')::numeric, (v_item->>'amount')::numeric, 0),
      COALESCE(
        (v_item->>'deposit_due_on')::date,
        (v_item->>'due_date')::date,
        CURRENT_DATE + interval '30 days' * (v_count + 1)
      ),
      COALESCE((v_item->>'is_occupancy')::boolean, false)
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
