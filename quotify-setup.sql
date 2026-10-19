CREATE TABLE IF NOT EXISTS public.quotes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  device_id TEXT NOT NULL,
  client_id TEXT,
  staff_name TEXT,
  edited_by TEXT,
  quote_number TEXT,
  cust_name TEXT NOT NULL,
  cust_phone TEXT,
  cust_address TEXT,
  system_type TEXT,
  panel_type TEXT,
  panel_watt TEXT,
  inverter_phase TEXT,
  structure_type TEXT,
  num_floors INTEGER DEFAULT 1,
  size_input_mode TEXT,
  monthly_units NUMERIC,
  monthly_bill NUMERIC,
  direct_kw NUMERIC,
  actual_kw NUMERIC,
  panels NUMERIC,
  grand_total NUMERIC,
  subsidy NUMERIC DEFAULT 0,
  net_cost NUMERIC,
  bimonthly_save NUMERIC,
  annual_save NUMERIC,
  payback_yrs NUMERIC,
  net_benefit_30 NUMERIC,
  status TEXT DEFAULT 'draft'
);

-- Added later (team edits): safe to re-run on an existing table
ALTER TABLE public.quotes ADD COLUMN IF NOT EXISTS edited_by TEXT;

CREATE INDEX IF NOT EXISTS quotes_device_idx ON public.quotes (device_id);
CREATE INDEX IF NOT EXISTS quotes_client_idx ON public.quotes (client_id);

ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon select" ON public.quotes;
DROP POLICY IF EXISTS "anon insert" ON public.quotes;
DROP POLICY IF EXISTS "anon update" ON public.quotes;
DROP POLICY IF EXISTS "anon delete" ON public.quotes;

CREATE POLICY "anon select" ON public.quotes
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.quotes
  FOR INSERT TO anon
  WITH CHECK (true);

CREATE POLICY "anon update" ON public.quotes
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);

CREATE POLICY "anon delete" ON public.quotes
  FOR DELETE TO anon
  USING (true);

-- Staff quote-sharing switch (Settings > My Quote Sharing)
CREATE TABLE IF NOT EXISTS public.staff_settings (
  client_id TEXT NOT NULL,
  staff_name TEXT NOT NULL,
  allow_edit BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (client_id, staff_name)
);

ALTER TABLE public.staff_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon select" ON public.staff_settings;
DROP POLICY IF EXISTS "anon insert" ON public.staff_settings;
DROP POLICY IF EXISTS "anon update" ON public.staff_settings;

CREATE POLICY "anon select" ON public.staff_settings
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.staff_settings
  FOR INSERT TO anon
  WITH CHECK (true);

CREATE POLICY "anon update" ON public.staff_settings
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);


-- Quote revisions (R1, R2...): each revision links to its original
ALTER TABLE public.quotes ADD COLUMN IF NOT EXISTS parent_id UUID;
ALTER TABLE public.quotes ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS quotes_parent_idx ON public.quotes (parent_id);


-- Shared quote-number counter: one number per quote across all phones
CREATE TABLE IF NOT EXISTS public.quote_counters (
  client_id TEXT NOT NULL,
  series TEXT NOT NULL,
  last_no INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (client_id, series)
);

ALTER TABLE public.quote_counters ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.next_quote_no(p_client TEXT, p_series TEXT, p_start INTEGER DEFAULT 1)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.quote_counters (client_id, series, last_no)
  VALUES (p_client, p_series, p_start)
  ON CONFLICT (client_id, series)
  DO UPDATE SET last_no = public.quote_counters.last_no + 1
  RETURNING last_no;
$$;

REVOKE ALL ON FUNCTION public.next_quote_no(TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_quote_no(TEXT, TEXT, INTEGER) TO anon;


-- Staff list, managed by the owner in Admin View (removed staff kept with active = false)
CREATE TABLE IF NOT EXISTS public.staff (
  client_id TEXT NOT NULL,
  name TEXT NOT NULL,
  pin TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (client_id, name)
);

ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon select" ON public.staff;
DROP POLICY IF EXISTS "anon insert" ON public.staff;
DROP POLICY IF EXISTS "anon update" ON public.staff;

CREATE POLICY "anon select" ON public.staff
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.staff
  FOR INSERT TO anon
  WITH CHECK (true);

CREATE POLICY "anon update" ON public.staff
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);


-- Archive (staff can't delete when tracking is on), saved-quote snapshot (View PDF), status history (who/when; insert-only)
ALTER TABLE public.quotes ADD COLUMN IF NOT EXISTS archived BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.quotes ADD COLUMN IF NOT EXISTS snapshot JSONB;

CREATE TABLE IF NOT EXISTS public.status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id UUID NOT NULL,
  client_id TEXT,
  from_status TEXT,
  to_status TEXT NOT NULL,
  changed_by TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS status_history_quote_idx ON public.status_history (quote_id);

ALTER TABLE public.status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon select" ON public.status_history;
DROP POLICY IF EXISTS "anon insert" ON public.status_history;

CREATE POLICY "anon select" ON public.status_history
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.status_history
  FOR INSERT TO anon
  WITH CHECK (true);


-- Admin PIN created/changed by each client in the app (config 'staffTracking': true). Reset a forgotten PIN with:
--   DELETE FROM public.business_settings WHERE client_id = '<Business Name>';
CREATE TABLE IF NOT EXISTS public.business_settings (
  client_id TEXT PRIMARY KEY,
  admin_pin TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.business_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon select" ON public.business_settings;
DROP POLICY IF EXISTS "anon insert" ON public.business_settings;
DROP POLICY IF EXISTS "anon update" ON public.business_settings;

CREATE POLICY "anon select" ON public.business_settings
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.business_settings
  FOR INSERT TO anon
  WITH CHECK (true);

CREATE POLICY "anon update" ON public.business_settings
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);


-- Visit Check-in (config 'visits': true). Every row carries the business (client_id); the app filters every query by it.
-- Check-ins are insert-only: a salesman can't edit or delete a check-in after it is recorded.
CREATE TABLE IF NOT EXISTS public.visits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id TEXT NOT NULL CHECK (client_id <> ''),
  cust_name TEXT NOT NULL,
  cust_phone TEXT,
  cust_address TEXT,
  maps_link TEXT,
  staff_name TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ NOT NULL,
  cust_lat DOUBLE PRECISION,
  cust_lng DOUBLE PRECISION,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS visits_client_idx ON public.visits (client_id, scheduled_at);

CREATE TABLE IF NOT EXISTS public.visit_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id UUID NOT NULL REFERENCES public.visits (id),
  client_id TEXT NOT NULL CHECK (client_id <> ''),
  staff_name TEXT,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  accuracy_m DOUBLE PRECISION,
  distance_m INTEGER,
  no_location BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS visit_checkins_client_idx ON public.visit_checkins (client_id, visit_id);

ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_checkins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon select" ON public.visits;
DROP POLICY IF EXISTS "anon insert" ON public.visits;
DROP POLICY IF EXISTS "anon update" ON public.visits;
DROP POLICY IF EXISTS "anon select" ON public.visit_checkins;
DROP POLICY IF EXISTS "anon insert" ON public.visit_checkins;

CREATE POLICY "anon select" ON public.visits
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.visits
  FOR INSERT TO anon
  WITH CHECK (true);

CREATE POLICY "anon update" ON public.visits
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);

CREATE POLICY "anon select" ON public.visit_checkins
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon insert" ON public.visit_checkins
  FOR INSERT TO anon
  WITH CHECK (true);


-- Visit location source (11 Oct 2026): 'map link' = pin from the customer's WhatsApp/Google Maps link (required for new
-- bookings); 'first check-in' = older visits whose location came from the salesman's first check-in (not verified).
ALTER TABLE public.visits ADD COLUMN IF NOT EXISTS loc_source TEXT;

-- 14 Oct 2026: cancel a visit (nothing is deleted; who + when are kept, Admin View shows it crossed out)
ALTER TABLE public.visits ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE public.visits ADD COLUMN IF NOT EXISTS cancelled_by text;
