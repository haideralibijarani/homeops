-- HomeOps Complete Database Schema - Fresh Start
-- Run this in Supabase SQL Editor for a clean database setup
-- Combines all migrations (001-019) into a single script
--
-- Last Updated: 2026-02-09
-- Pricing: Essential PKR 25K (5 ppl, 30 tasks/day) | Pro PKR 50K (8 ppl, 50 tasks/day) | Max PKR 100K (15 ppl, 100 tasks/day)

-- ============================================
-- PART 1: CORE TABLES
-- ============================================

-- Households table (core entity)
CREATE TABLE IF NOT EXISTS households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  timezone TEXT DEFAULT 'Asia/Karachi',
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Subscriber details (from migration 002)
  subscriber_name TEXT,
  subscriber_whatsapp TEXT,
  subscriber_email TEXT,
  subscribed_at TIMESTAMPTZ,

  -- Subscription management (from migration 002)
  subscription_status TEXT DEFAULT 'trial' CHECK (subscription_status IN ('trial', 'active', 'past_due', 'cancelled', 'expired')),
  subscription_expires_at TIMESTAMPTZ,

  -- Payment tracking (from migration 002)
  last_payment_at TIMESTAMPTZ,
  last_payment_amount DECIMAL(10,2),

  -- Trial/Grace periods (from migration 002)
  trial_ends_at TIMESTAMPTZ,
  grace_period_ends_at TIMESTAMPTZ,

  -- Plan tier (from migration 005, updated in 015 for Essential/Pro/Max)
  plan_tier TEXT DEFAULT 'essential' CHECK (plan_tier IN ('essential', 'pro', 'max', 'starter', 'family', 'premium', 'custom')),
  max_members INTEGER DEFAULT 5,

  -- Usage caps (from migration 015)
  cap_tasks_per_day INTEGER DEFAULT 30,
  cap_messages_per_month INTEGER DEFAULT 10000,
  cap_voice_notes_per_staff_month INTEGER DEFAULT 250,
  onboarded_at TIMESTAMPTZ,
  onboarding_source TEXT DEFAULT 'whatsapp',

  -- Voice note language for staff (from migration 009, simplified in 012)
  tts_language_staff TEXT DEFAULT 'ur',       -- Voice notes for staff: en/ur

  -- Expected monthly payment (from migration 018)
  expected_monthly_amount DECIMAL(10,2)      -- Base + extra people + voice add-ons
);

-- Members table (family members)
CREATE TABLE IF NOT EXISTS members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  whatsapp TEXT NOT NULL,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  opt_in_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Staff table (household workers)
CREATE TABLE IF NOT EXISTS staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT DEFAULT 'staff',
  whatsapp TEXT NOT NULL,
  language_pref TEXT DEFAULT 'en',        -- Per-staff TTS language (en/ur)
  voice_notes_enabled BOOLEAN DEFAULT false,  -- Premium opt-in: PKR 7,000/staff/month on Essential (migration 013)

  -- Voice payment tracking (from migration 017)
  voice_payment_pending BOOLEAN DEFAULT false,       -- Pending payment for voice activation
  voice_payment_ref TEXT,                            -- Payment reference from admin
  voice_payment_proof_url TEXT,                      -- Screenshot URL from Twilio MediaUrl
  voice_payment_requested_at TIMESTAMPTZ,            -- When activation was requested

  opt_in_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tasks table
CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  notes TEXT,
  assignee_type TEXT CHECK (assignee_type IN ('member', 'staff')),
  assignee_member_id UUID REFERENCES members(id) ON DELETE SET NULL,
  assignee_staff_id UUID REFERENCES staff(id) ON DELETE SET NULL,
  due_at TIMESTAMPTZ,
  priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'acknowledged', 'in_progress', 'completed', 'problem', 'cancelled')),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Problem tracking (from migration 003)
  problem_notes TEXT,
  created_by_type TEXT CHECK (created_by_type IN ('member', 'staff')),
  problem_reported_at TIMESTAMPTZ,

  -- Acknowledgment and reminders (from migration 004)
  acknowledged_at TIMESTAMPTZ,
  task_complexity TEXT DEFAULT 'complex' CHECK (task_complexity IN ('simple', 'complex')),
  reminder_count INTEGER DEFAULT 0,
  last_reminder_at TIMESTAMPTZ,
  max_reminders INTEGER DEFAULT 3
);

-- Pending actions table (multi-turn conversation state)
CREATE TABLE IF NOT EXISTS pending_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES households(id) ON DELETE CASCADE,
  from_number TEXT NOT NULL,
  to_number TEXT,
  intent TEXT NOT NULL,
  draft_json JSONB,
  missing_fields TEXT[],
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 minutes'),
  completed_at TIMESTAMPTZ
);

-- ============================================
-- PART 2: PAYMENTS TABLE (from migration 002)
-- ============================================

CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'PKR',
  status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  payment_method TEXT,
  payment_provider TEXT,
  provider_payment_id TEXT,
  provider_response JSONB,
  plan TEXT CHECK (plan IN ('monthly', 'annual', 'essential', 'pro', 'max', 'starter', 'family', 'premium', 'custom')),
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  failure_reason TEXT,

  -- Payment verification (from migration 018)
  expected_amount DECIMAL(10,2),
  payment_classification TEXT CHECK (payment_classification IN ('full', 'base_only', 'partial', 'overpayment', 'unknown')),
  addons_activated JSONB,
  proof_url TEXT
);

-- ============================================
-- PART 3: ONBOARDING TABLES (from migration 005-006)
-- ============================================

-- Pending signups (registration before payment)
CREATE TABLE IF NOT EXISTS pending_signups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Subscriber info
  subscriber_name TEXT NOT NULL,
  subscriber_whatsapp TEXT NOT NULL,
  subscriber_email TEXT NOT NULL,

  -- Household info
  household_name TEXT NOT NULL,
  timezone TEXT DEFAULT 'Asia/Karachi',

  -- Members JSON: [{"name": "...", "whatsapp": "...", "role": "member|staff"}]
  members_json JSONB DEFAULT '[]'::JSONB,

  -- Plan selection (updated in 015 for Essential/Pro/Max)
  selected_plan TEXT NOT NULL CHECK (selected_plan IN ('essential', 'pro', 'max', 'starter', 'family', 'premium', 'custom')),

  -- Local payment tracking (from migration 007)
  payment_method TEXT CHECK (payment_method IN ('jazzcash', 'easypaisa', 'bank_transfer', NULL)),
  payment_reference TEXT,
  payment_amount DECIMAL(10,2),
  payment_confirmed_at TIMESTAMPTZ,
  admin_notes TEXT,

  -- Status tracking
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'payment_started', 'awaiting_payment', 'completed', 'expired', 'cancelled')),

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days'),
  completed_at TIMESTAMPTZ
);

-- Owner whitelist (for testing - auto-activation without payment)
CREATE TABLE IF NOT EXISTS owner_whitelist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whatsapp TEXT NOT NULL UNIQUE,
  name TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- App config (admin secrets, payment account numbers)
CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Usage event log (from migration 015)
CREATE TABLE IF NOT EXISTS usage_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'message_inbound', 'message_outbound',
    'voice_note_inbound', 'voice_note_outbound',
    'task_created', 'task_completed',
    'stt_transcription', 'tts_generation', 'ai_classification'
  )),
  service TEXT NOT NULL CHECK (service IN ('twilio', 'openai', 'system')),
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Aggregated daily usage counts (from migration 015)
CREATE TABLE IF NOT EXISTS usage_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  tasks_created INTEGER DEFAULT 0,
  messages_inbound INTEGER DEFAULT 0,
  messages_outbound INTEGER DEFAULT 0,
  voice_notes_inbound INTEGER DEFAULT 0,
  voice_notes_outbound INTEGER DEFAULT 0,
  stt_minutes DECIMAL(8,2) DEFAULT 0,
  tts_characters INTEGER DEFAULT 0,
  ai_calls INTEGER DEFAULT 0,
  estimated_cost_usd DECIMAL(10,4) DEFAULT 0,
  UNIQUE(household_id, date)
);

-- ============================================
-- PART 4: INDEXES
-- ============================================

-- Core indexes
CREATE INDEX IF NOT EXISTS idx_members_household_id ON members(household_id);
CREATE INDEX IF NOT EXISTS idx_members_whatsapp ON members(whatsapp);
CREATE INDEX IF NOT EXISTS idx_staff_household_id ON staff(household_id);
CREATE INDEX IF NOT EXISTS idx_staff_whatsapp ON staff(whatsapp);
CREATE INDEX IF NOT EXISTS idx_tasks_household_id ON tasks(household_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_member_id ON tasks(assignee_member_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_staff_id ON tasks(assignee_staff_id);
CREATE INDEX IF NOT EXISTS idx_pending_actions_from_number ON pending_actions(from_number);

-- Payment/subscription indexes
CREATE INDEX IF NOT EXISTS idx_payments_household_id ON payments(household_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at);
CREATE INDEX IF NOT EXISTS idx_households_subscription_status ON households(subscription_status);
CREATE INDEX IF NOT EXISTS idx_households_subscription_expires_at ON households(subscription_expires_at);
-- Onboarding indexes
CREATE INDEX IF NOT EXISTS idx_pending_signups_whatsapp ON pending_signups(subscriber_whatsapp);
CREATE INDEX IF NOT EXISTS idx_pending_signups_status ON pending_signups(status);
CREATE INDEX IF NOT EXISTS idx_pending_signups_expires_at ON pending_signups(expires_at);
CREATE INDEX IF NOT EXISTS idx_pending_signups_payment_method ON pending_signups(payment_method) WHERE status = 'awaiting_payment';
CREATE INDEX IF NOT EXISTS idx_pending_signups_awaiting ON pending_signups(created_at DESC) WHERE status = 'awaiting_payment';
CREATE INDEX IF NOT EXISTS idx_owner_whitelist_whatsapp ON owner_whitelist(whatsapp);

-- Reminder query index
CREATE INDEX IF NOT EXISTS idx_tasks_due_at_status ON tasks(due_at, status) WHERE due_at IS NOT NULL AND status NOT IN ('completed', 'cancelled', 'problem');

-- Usage tracking indexes (from migration 015)
CREATE INDEX IF NOT EXISTS idx_usage_events_household_date ON usage_events(household_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_type ON usage_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_daily_household_date ON usage_daily(household_id, date DESC);

-- ============================================
-- PART 5: ROW LEVEL SECURITY
-- ============================================

-- Enable RLS on sensitive tables
ALTER TABLE owner_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to allow re-running this script)
DROP POLICY IF EXISTS "Service role only for whitelist" ON owner_whitelist;
DROP POLICY IF EXISTS "Service role only for config" ON app_config;

-- Service role only policies
CREATE POLICY "Service role only for whitelist" ON owner_whitelist FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role only for config" ON app_config FOR ALL USING (auth.role() = 'service_role');

-- Grant to authenticated for n8n access via service key
GRANT ALL ON owner_whitelist TO authenticated;
GRANT ALL ON app_config TO authenticated;
GRANT ALL ON pending_signups TO authenticated;
GRANT ALL ON payments TO authenticated;
GRANT ALL ON usage_events TO authenticated;
GRANT ALL ON usage_daily TO authenticated;

-- ============================================
-- PART 6: HELPER FUNCTIONS
-- ============================================

-- Check if phone is whitelisted (from migration 006)
CREATE OR REPLACE FUNCTION is_whitelisted(phone_number TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM owner_whitelist
    WHERE whatsapp = phone_number
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION is_whitelisted(TEXT) TO authenticated;

-- Get config value (from migration 006)
CREATE OR REPLACE FUNCTION get_config(config_key TEXT)
RETURNS TEXT AS $$
DECLARE
  config_value TEXT;
BEGIN
  SELECT value INTO config_value
  FROM app_config
  WHERE key = config_key;
  RETURN config_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_config(TEXT) TO authenticated;

-- Get plan base price in PKR (from migration 007, updated in 015)
CREATE OR REPLACE FUNCTION get_plan_price(plan_name TEXT)
RETURNS DECIMAL(10,2) AS $$
BEGIN
  RETURN CASE plan_name
    WHEN 'essential' THEN 25000.00
    WHEN 'pro' THEN 50000.00
    WHEN 'max' THEN 100000.00
    WHEN 'starter' THEN 15000.00   -- Legacy
    WHEN 'family' THEN 25000.00    -- Legacy
    WHEN 'premium' THEN 35000.00   -- Legacy
    WHEN 'custom' THEN 15000.00    -- Legacy
    ELSE 0.00
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

GRANT EXECUTE ON FUNCTION get_plan_price(TEXT) TO authenticated;

-- Calculate expected monthly amount breakdown (from migration 018)
CREATE OR REPLACE FUNCTION calculate_expected_amount(p_household_id UUID)
RETURNS TABLE (
  base_amount DECIMAL(10,2),
  extra_people_count INTEGER,
  extra_people_cost DECIMAL(10,2),
  voice_staff_count INTEGER,
  voice_cost DECIMAL(10,2),
  total_amount DECIMAL(10,2),
  breakdown TEXT
) AS $$
DECLARE
  v_plan_tier TEXT;
  v_base_price DECIMAL(10,2);
  v_included_people INTEGER;
  v_total_people INTEGER;
  v_member_count INTEGER;
  v_staff_count INTEGER;
  v_extra_people INTEGER;
  v_extra_cost DECIMAL(10,2);
  v_voice_count INTEGER;
  v_voice_price DECIMAL(10,2);
  v_voice_included BOOLEAN;
  v_total DECIMAL(10,2);
  v_parts TEXT[];
BEGIN
  SELECT h.plan_tier INTO v_plan_tier
  FROM households h WHERE h.id = p_household_id;

  IF v_plan_tier IS NULL THEN
    RETURN QUERY SELECT 0::DECIMAL(10,2), 0, 0::DECIMAL(10,2), 0, 0::DECIMAL(10,2), 0::DECIMAL(10,2), 'Household not found'::TEXT;
    RETURN;
  END IF;

  v_base_price := get_plan_price(v_plan_tier);

  CASE v_plan_tier
    WHEN 'essential' THEN v_included_people := 5; v_voice_included := false; v_voice_price := 7000.00;
    WHEN 'pro' THEN v_included_people := 8; v_voice_included := true; v_voice_price := 0.00;
    WHEN 'max' THEN v_included_people := 15; v_voice_included := true; v_voice_price := 0.00;
    ELSE v_included_people := 5; v_voice_included := false; v_voice_price := 7000.00;
  END CASE;

  SELECT COUNT(*) INTO v_member_count FROM members m WHERE m.household_id = p_household_id;
  SELECT COUNT(*) INTO v_staff_count FROM staff s WHERE s.household_id = p_household_id;
  v_total_people := v_member_count + v_staff_count;

  v_extra_people := GREATEST(0, v_total_people - v_included_people);
  v_extra_cost := v_extra_people * 5000.00;

  IF v_voice_included THEN
    v_voice_count := 0;
  ELSE
    SELECT COUNT(*) INTO v_voice_count FROM staff s
    WHERE s.household_id = p_household_id AND (s.voice_notes_enabled = true OR s.voice_payment_pending = true);
  END IF;

  v_total := v_base_price + v_extra_cost + (v_voice_count * v_voice_price);

  v_parts := ARRAY['Base ' || v_base_price::INTEGER::TEXT];
  IF v_extra_people > 0 THEN
    v_parts := v_parts || (v_extra_people || ' extra ' || CASE WHEN v_extra_people = 1 THEN 'person' ELSE 'people' END || ': ' || v_extra_cost::INTEGER::TEXT);
  END IF;
  IF v_voice_count > 0 THEN
    v_parts := v_parts || (v_voice_count || ' voice staff: ' || (v_voice_count * v_voice_price::INTEGER)::TEXT);
  END IF;

  RETURN QUERY SELECT v_base_price, v_extra_people, v_extra_cost, v_voice_count, (v_voice_count * v_voice_price), v_total, array_to_string(v_parts, ' + ');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION calculate_expected_amount(UUID) TO authenticated;

-- Recalculate and persist expected amount (from migration 018)
CREATE OR REPLACE FUNCTION recalculate_and_store_expected_amount(p_household_id UUID)
RETURNS DECIMAL(10,2) AS $$
DECLARE
  v_total DECIMAL(10,2);
BEGIN
  SELECT cea.total_amount INTO v_total FROM calculate_expected_amount(p_household_id) cea;
  UPDATE households SET expected_monthly_amount = v_total WHERE id = p_household_id;
  RETURN v_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION recalculate_and_store_expected_amount(UUID) TO authenticated;

-- Expire old signups (from migration 005)
CREATE OR REPLACE FUNCTION expire_old_signups()
RETURNS INTEGER AS $$
DECLARE
  expired_count INTEGER;
BEGIN
  UPDATE pending_signups
  SET status = 'expired'
  WHERE status IN ('pending', 'payment_started', 'awaiting_payment')
    AND expires_at < NOW();
  GET DIAGNOSTICS expired_count = ROW_COUNT;
  RETURN expired_count;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION expire_old_signups() TO authenticated;

-- Get overdue tasks for reminders (from migration 004)
CREATE OR REPLACE FUNCTION get_overdue_tasks()
RETURNS SETOF tasks AS $$
  SELECT * FROM tasks
  WHERE due_at IS NOT NULL
    AND due_at < NOW()
    AND status IN ('pending', 'acknowledged')
    AND reminder_count < max_reminders
    AND (last_reminder_at IS NULL OR last_reminder_at < NOW() - INTERVAL '30 minutes')
  ORDER BY due_at ASC
  LIMIT 50;
$$ LANGUAGE sql SECURITY DEFINER;

-- Check subscription status trigger (from migration 002)
CREATE OR REPLACE FUNCTION check_subscription_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.subscription_expires_at < NOW() AND
     (NEW.grace_period_ends_at IS NULL OR NEW.grace_period_ends_at < NOW()) THEN
    NEW.subscription_status := 'expired';
  ELSIF NEW.subscription_expires_at < NOW() AND
        NEW.grace_period_ends_at IS NOT NULL AND
        NEW.grace_period_ends_at >= NOW() THEN
    NEW.subscription_status := 'past_due';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_subscription ON households;
CREATE TRIGGER trigger_check_subscription
  BEFORE UPDATE ON households
  FOR EACH ROW
  EXECUTE FUNCTION check_subscription_status();

-- ============================================
-- PART 7: VIEWS
-- ============================================

-- Drop existing view if it has different structure
DROP VIEW IF EXISTS subscription_dashboard;

-- Subscription dashboard view (from migration 002, updated in 019 for costs)
CREATE OR REPLACE VIEW subscription_dashboard AS
SELECT
  h.id,
  h.name as household_name,
  h.subscriber_name,
  h.subscriber_whatsapp,
  h.subscriber_email,
  h.subscription_status,
  h.plan_tier,
  h.subscribed_at,
  h.subscription_expires_at,
  h.last_payment_at,
  h.last_payment_amount,
  h.trial_ends_at,
  h.grace_period_ends_at,
  h.cap_tasks_per_day,
  h.cap_messages_per_month,
  h.expected_monthly_amount,
  CASE
    WHEN h.subscription_status = 'trial' THEN h.trial_ends_at - NOW()
    WHEN h.subscription_status IN ('active', 'past_due') THEN h.subscription_expires_at - NOW()
    ELSE INTERVAL '0 days'
  END as time_remaining,
  (SELECT COUNT(*) FROM tasks t WHERE t.household_id = h.id) as total_tasks,
  (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as total_members,
  (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as total_staff,
  -- Cost columns (from migration 019)
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.household_id = h.id), 0) as all_time_cost_usd,
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.household_id = h.id), 0) *
    COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_exchange_rate_pkr_usd'), '')::DECIMAL, 278) as all_time_cost_pkr
FROM households h;

GRANT SELECT ON subscription_dashboard TO authenticated;

-- Admin cost dashboard function (from migration 019)
CREATE OR REPLACE FUNCTION admin_cost_dashboard(admin_secret TEXT)
RETURNS JSON AS $$
DECLARE
  stored_secret TEXT;
  result JSON;
BEGIN
  SELECT value INTO stored_secret FROM app_config WHERE key = 'admin_dashboard_secret';
  IF stored_secret IS NULL OR admin_secret IS DISTINCT FROM stored_secret THEN
    RETURN json_build_object('error', 'unauthorized', 'message', 'Invalid admin secret');
  END IF;

  WITH exchange AS (
    SELECT COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_exchange_rate_pkr_usd'), '')::DECIMAL, 278) as rate
  ),
  cost_rates AS (
    SELECT
      COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_twilio_message_usd'), '')::DECIMAL, 0.005) as twilio_msg,
      COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_openai_stt_per_min_usd'), '')::DECIMAL, 0.006) as stt_min,
      COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_openai_tts_per_char_usd'), '')::DECIMAL, 0.000015) as tts_char,
      COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_openai_ai_call_usd'), '')::DECIMAL, 0.001) as ai_call
  ),
  household_data AS (
    SELECT
      h.id, h.name, h.plan_tier, h.subscription_status, h.expected_monthly_amount, h.subscribed_at, h.created_at,
      (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as member_count,
      (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as staff_count,
      (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id AND s.voice_notes_enabled = true) as voice_staff_count,
      COALESCE(SUM(ud.estimated_cost_usd), 0) as all_time_cost_usd,
      COALESCE(SUM(ud.messages_inbound), 0) as all_time_msgs_in,
      COALESCE(SUM(ud.messages_outbound), 0) as all_time_msgs_out,
      COALESCE(SUM(ud.tasks_created), 0) as all_time_tasks,
      COALESCE(SUM(ud.voice_notes_inbound), 0) as all_time_voice_in,
      COALESCE(SUM(ud.voice_notes_outbound), 0) as all_time_voice_out,
      COALESCE(SUM(ud.ai_calls), 0) as all_time_ai_calls,
      COALESCE(SUM(ud.stt_minutes), 0) as all_time_stt_minutes,
      COALESCE(SUM(ud.tts_characters), 0) as all_time_tts_characters,
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_cost_usd,
      COALESCE(SUM(ud.messages_inbound + ud.messages_outbound) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_messages,
      COALESCE(SUM(ud.tasks_created) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_tasks,
      COALESCE(SUM(ud.ai_calls) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_ai_calls,
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= CURRENT_DATE - 30), 0) as last_30d_cost_usd,
      COALESCE(SUM(ud.messages_inbound + ud.messages_outbound + ud.voice_notes_inbound + ud.voice_notes_outbound), 0) * (SELECT twilio_msg FROM cost_rates) as breakdown_twilio,
      COALESCE(SUM(ud.stt_minutes), 0) * (SELECT stt_min FROM cost_rates) as breakdown_stt,
      COALESCE(SUM(ud.tts_characters), 0) * (SELECT tts_char FROM cost_rates) as breakdown_tts,
      COALESCE(SUM(ud.ai_calls), 0) * (SELECT ai_call FROM cost_rates) as breakdown_ai
    FROM households h
    LEFT JOIN usage_daily ud ON ud.household_id = h.id
    GROUP BY h.id, h.name, h.plan_tier, h.subscription_status, h.expected_monthly_amount, h.subscribed_at, h.created_at
  )
  SELECT json_build_object(
    'success', true,
    'generated_at', NOW(),
    'exchange_rate', (SELECT rate FROM exchange),
    'cost_rates', json_build_object(
      'twilio_message', (SELECT twilio_msg FROM cost_rates),
      'stt_per_minute', (SELECT stt_min FROM cost_rates),
      'tts_per_character', (SELECT tts_char FROM cost_rates),
      'ai_call', (SELECT ai_call FROM cost_rates)
    ),
    'households', COALESCE((
      SELECT json_agg(row_data ORDER BY (row_data->>'month_cost_usd')::DECIMAL DESC)
      FROM (
        SELECT json_build_object(
          'id', hd.id, 'name', hd.name, 'plan_tier', hd.plan_tier,
          'subscription_status', hd.subscription_status,
          'member_count', hd.member_count, 'staff_count', hd.staff_count,
          'voice_staff_count', hd.voice_staff_count,
          'subscribed_at', hd.subscribed_at, 'created_at', hd.created_at,
          'revenue', json_build_object(
            'monthly_pkr', COALESCE(hd.expected_monthly_amount, 0),
            'monthly_usd', ROUND(COALESCE(hd.expected_monthly_amount, 0) / (SELECT rate FROM exchange), 2)
          ),
          'costs', json_build_object(
            'all_time_usd', ROUND(hd.all_time_cost_usd::NUMERIC, 4),
            'all_time_pkr', ROUND((hd.all_time_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2),
            'current_month_usd', ROUND(hd.month_cost_usd::NUMERIC, 4),
            'current_month_pkr', ROUND((hd.month_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2),
            'last_30d_usd', ROUND(hd.last_30d_cost_usd::NUMERIC, 4),
            'last_30d_pkr', ROUND((hd.last_30d_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2)
          ),
          'margin', json_build_object(
            'monthly_margin_pkr', ROUND((COALESCE(hd.expected_monthly_amount, 0) - hd.month_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2),
            'monthly_margin_usd', ROUND((COALESCE(hd.expected_monthly_amount, 0) / (SELECT rate FROM exchange) - hd.month_cost_usd)::NUMERIC, 2),
            'margin_pct', CASE
              WHEN COALESCE(hd.expected_monthly_amount, 0) > 0
              THEN ROUND(((COALESCE(hd.expected_monthly_amount, 0) - hd.month_cost_usd * (SELECT rate FROM exchange)) / hd.expected_monthly_amount * 100)::NUMERIC, 1)
              ELSE 0
            END
          ),
          'usage', json_build_object(
            'all_time_messages', hd.all_time_msgs_in + hd.all_time_msgs_out,
            'all_time_tasks', hd.all_time_tasks,
            'all_time_voice_notes', hd.all_time_voice_in + hd.all_time_voice_out,
            'all_time_ai_calls', hd.all_time_ai_calls,
            'all_time_stt_minutes', ROUND(hd.all_time_stt_minutes::NUMERIC, 2),
            'all_time_tts_characters', hd.all_time_tts_characters,
            'current_month_messages', hd.month_messages,
            'current_month_tasks', hd.month_tasks,
            'current_month_ai_calls', hd.month_ai_calls
          ),
          'cost_breakdown', json_build_object(
            'twilio_usd', ROUND(hd.breakdown_twilio::NUMERIC, 4),
            'stt_usd', ROUND(hd.breakdown_stt::NUMERIC, 4),
            'tts_usd', ROUND(hd.breakdown_tts::NUMERIC, 4),
            'ai_usd', ROUND(hd.breakdown_ai::NUMERIC, 4)
          )
        ) as row_data
        FROM household_data hd
      ) sub
    ), '[]'::JSON),
    'totals', json_build_object(
      'total_households', (SELECT COUNT(*) FROM household_data),
      'total_revenue_monthly_pkr', (SELECT COALESCE(SUM(expected_monthly_amount), 0) FROM household_data),
      'total_revenue_monthly_usd', ROUND((SELECT COALESCE(SUM(expected_monthly_amount), 0) FROM household_data) / (SELECT rate FROM exchange), 2),
      'total_cost_current_month_usd', ROUND((SELECT COALESCE(SUM(month_cost_usd), 0) FROM household_data)::NUMERIC, 4),
      'total_cost_all_time_usd', ROUND((SELECT COALESCE(SUM(all_time_cost_usd), 0) FROM household_data)::NUMERIC, 4),
      'total_margin_monthly_pkr', ROUND((
        (SELECT COALESCE(SUM(expected_monthly_amount), 0) FROM household_data) -
        (SELECT COALESCE(SUM(month_cost_usd), 0) FROM household_data) * (SELECT rate FROM exchange)
      )::NUMERIC, 2)
    )
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_cost_dashboard(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION admin_cost_dashboard(TEXT) TO authenticated;

-- ============================================
-- PART 8: INITIAL DATA
-- ============================================

-- Insert app config with admin secret and payment details
INSERT INTO app_config (key, value, description) VALUES
  ('admin_activate_secret', 'ZazaBazooka1!2020', 'Secret key for admin activation endpoint'),
  ('payment_jazzcash', '03XX-XXXXXXX', 'JazzCash account number for payments'),
  ('payment_easypaisa', '03XX-XXXXXXX', 'EasyPaisa account number for payments'),
  ('payment_bank_name', 'Bank Name', 'Bank name for transfers'),
  ('payment_bank_account', 'XXXX-XXXXXXXXXX', 'Bank account number'),
  ('payment_bank_title', 'Account Title', 'Bank account title'),
  -- Cost tracking rates (from migration 019)
  ('cost_twilio_message_usd',      '0.005',    'Cost per Twilio WhatsApp message (inbound or outbound) in USD'),
  ('cost_openai_stt_per_min_usd',  '0.006',    'Cost per minute of OpenAI Whisper STT in USD'),
  ('cost_openai_tts_per_char_usd', '0.000015', 'Cost per character of OpenAI TTS in USD ($15/1M chars)'),
  ('cost_openai_ai_call_usd',      '0.001',    'Estimated cost per OpenAI GPT-4o-mini AI call in USD'),
  ('cost_exchange_rate_pkr_usd',   '278',      'Exchange rate: PKR per 1 USD'),
  ('admin_dashboard_secret',       'HomeOpsCostDash2026!', 'Secret for admin cost dashboard access')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- ============================================
-- PART 9: TABLE COMMENTS
-- ============================================

COMMENT ON TABLE households IS 'Core household entity with subscription and payment tracking';
COMMENT ON TABLE members IS 'Family members belonging to a household';
COMMENT ON TABLE staff IS 'Household staff/workers with language preferences';
COMMENT ON TABLE tasks IS 'Tasks assigned to members or staff with acknowledgment and reminder tracking';

COMMENT ON TABLE pending_actions IS 'Multi-turn conversation state for clarification flows';
COMMENT ON TABLE payments IS 'Payment history for household subscriptions';
COMMENT ON TABLE pending_signups IS 'Temporary storage for signups awaiting payment';
COMMENT ON TABLE owner_whitelist IS 'Phone numbers that auto-activate without payment (for testing/owner use)';
COMMENT ON TABLE app_config IS 'Application configuration and secrets';

COMMENT ON COLUMN households.plan_tier IS 'Plan tier: essential (25K, 30/day), pro (50K, 50/day), max (100K, 100/day), or legacy tiers';
COMMENT ON COLUMN households.max_members IS 'Max people. Essential=5, Pro=8, Max=15';
COMMENT ON COLUMN households.cap_tasks_per_day IS 'Max tasks per day. Essential=30, Pro=50, Max=100';
COMMENT ON COLUMN households.cap_messages_per_month IS 'Max messages per month. Essential=10000, Pro=20000, Max=40000';
COMMENT ON COLUMN households.cap_voice_notes_per_staff_month IS 'Max voice notes per staff per month. All plans=250';
COMMENT ON TABLE usage_events IS 'Log of every billable action per household for usage tracking and cap enforcement';
COMMENT ON TABLE usage_daily IS 'Aggregated daily usage counts and costs per household (populated nightly by WF8)';
COMMENT ON COLUMN usage_daily.estimated_cost_usd IS 'Estimated API cost in USD calculated from usage rates (Twilio + OpenAI)';
COMMENT ON COLUMN households.subscription_status IS 'trial=new, active=paid, past_due=grace period, cancelled=user cancelled, expired=payment failed';
COMMENT ON COLUMN pending_signups.members_json IS 'JSON array: [{"name": "...", "whatsapp": "...", "role": "member|staff"}]';
COMMENT ON COLUMN pending_signups.status IS 'pending=form submitted, payment_started=redirected to payment, awaiting_payment=local payment pending, completed=household created, expired=timeout, cancelled=user cancelled';
COMMENT ON COLUMN pending_signups.payment_method IS 'Local payment method: jazzcash, easypaisa, or bank_transfer';
COMMENT ON COLUMN pending_signups.payment_reference IS 'Transaction ID provided by user for verification';
COMMENT ON COLUMN pending_signups.payment_amount IS 'Payment amount in PKR based on selected plan';
COMMENT ON COLUMN tasks.problem_notes IS 'Description of the problem reported by assignee';
COMMENT ON COLUMN tasks.task_complexity IS 'simple = auto-complete on ack, complex = needs explicit done';
COMMENT ON COLUMN tasks.reminder_count IS 'Number of reminders sent after due_at passed';
COMMENT ON COLUMN staff.voice_payment_pending IS 'True when admin requested voice on Essential plan but payment not yet verified';
COMMENT ON COLUMN staff.voice_payment_ref IS 'Payment reference number provided by admin';
COMMENT ON COLUMN staff.voice_payment_proof_url IS 'URL of payment proof screenshot from Twilio MediaUrl';
COMMENT ON COLUMN staff.voice_payment_requested_at IS 'When voice activation was requested';
COMMENT ON FUNCTION is_whitelisted IS 'Check if a phone number is in the owner whitelist';
COMMENT ON FUNCTION get_config IS 'Get a configuration value by key';
COMMENT ON FUNCTION get_plan_price IS 'Get monthly price in PKR for a plan tier';
COMMENT ON FUNCTION calculate_expected_amount IS 'Calculate expected monthly payment breakdown (base + extra people + voice add-ons)';
COMMENT ON FUNCTION recalculate_and_store_expected_amount IS 'Calculate and persist expected_monthly_amount on households table';
COMMENT ON COLUMN households.expected_monthly_amount IS 'Expected monthly payment including base plan + add-ons';
COMMENT ON COLUMN payments.expected_amount IS 'Expected monthly amount at time of payment for audit trail';
COMMENT ON COLUMN payments.payment_classification IS 'full=covers all, base_only=plan only, partial=incomplete, overpayment=exceeds expected';
COMMENT ON COLUMN payments.addons_activated IS 'JSON record of add-ons activated by this payment';
COMMENT ON COLUMN payments.proof_url IS 'URL of payment proof screenshot from WhatsApp MediaUrl';
COMMENT ON FUNCTION admin_cost_dashboard IS 'Password-protected admin dashboard returning household cost/profitability data as JSON';

-- ============================================
-- VERIFICATION QUERIES (uncomment to test)
-- ============================================

-- List all tables:
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;

-- Check app_config:
-- SELECT * FROM app_config;

-- Test functions:
-- SELECT is_whitelisted('+923001234567');
-- SELECT get_config('admin_activate_secret');
-- SELECT get_plan_price('essential'), get_plan_price('pro'), get_plan_price('max');

-- ============================================
-- DONE! Your HomeOps database is ready.
-- ============================================
