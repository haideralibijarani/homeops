-- MYNK Complete Database Schema - Fresh Start
-- Run this in Supabase SQL Editor for a clean database setup
-- Combines all migrations (001-027) into a single script
--
-- Last Updated: 2026-02-11
-- Services: HomeOps (households, PKR) | BizOps (organizations, PKR/USD)
-- Pricing PKR: Essential 25K (5 ppl) | Pro 50K (8 ppl) | Max 100K (15 ppl)
-- Pricing USD: Essential $89 (5 ppl) | Pro $179 (8 ppl) | Max $349 (15 ppl)
-- Languages: 59 supported (en, ur, hi, ar, fr, es, pt, de, ... see CHECK constraints)

-- ============================================
-- PART 1: CORE TABLES
-- ============================================

-- Accounts table (core entity - households for HomeOps, organizations for BizOps)
CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  timezone TEXT DEFAULT 'Asia/Karachi',
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Service type (from migration 027)
  service_type TEXT DEFAULT 'homeops' CHECK (service_type IN ('homeops', 'bizops')),
  currency TEXT DEFAULT 'PKR' CHECK (currency IN ('PKR', 'USD')),

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

  -- Plan tier (from migration 005, updated in 027 - legacy tiers removed)
  plan_tier TEXT DEFAULT 'essential' CHECK (plan_tier IN ('essential', 'pro', 'max')),
  max_members INTEGER DEFAULT 5,

  -- Usage caps (from migration 015, updated in 022 for monthly model)
  cap_tasks_per_month INTEGER DEFAULT 500,
  cap_messages_per_month INTEGER DEFAULT 5000,
  cap_voice_notes_per_month INTEGER DEFAULT 0,  -- Pool: Essential=0 (1200 with add-on), Pro=2500, Max=6000
  onboarded_at TIMESTAMPTZ,
  onboarding_source TEXT DEFAULT 'whatsapp',

  -- Voice note language for staff (from migration 009, expanded in 027 to 59 languages)
  tts_language_staff TEXT DEFAULT 'en' CHECK (tts_language_staff IN (
    'en', 'ur', 'hi', 'ar', 'fr', 'es', 'pt', 'de', 'it', 'nl',
    'ru', 'ja', 'ko', 'zh', 'tr', 'pl', 'sv', 'da', 'no', 'fi',
    'th', 'vi', 'id', 'ms', 'tl', 'bn', 'ta', 'te', 'pa', 'mr',
    'gu', 'kn', 'ml', 'sw', 'fa', 'he', 'uk', 'ro', 'cs', 'el',
    'hu', 'bg', 'sr', 'hr', 'sk', 'lt', 'lv', 'et', 'sl', 'my',
    'km', 'ne', 'si', 'am', 'zu', 'af', 'ca', 'gl', 'eu'
  )),

  -- Expected monthly payment in account currency (from migration 018)
  expected_monthly_amount DECIMAL(10,2),     -- Base + extra people + voice add-ons

  -- Location (from migration 020)
  city TEXT,                                 -- City where the account is located
  country TEXT DEFAULT 'Pakistan'            -- Country where the account is located
);

-- Members table (family members / team members)
CREATE TABLE IF NOT EXISTS members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  whatsapp TEXT NOT NULL,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  nicknames TEXT,                             -- Comma-separated nicknames for recognition (from migration 024)
  opt_in_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Staff table (household staff / organization employees)
CREATE TABLE IF NOT EXISTS staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT DEFAULT 'staff',
  whatsapp TEXT NOT NULL,
  language_pref TEXT DEFAULT 'en' CHECK (language_pref IN (
    'en', 'ur', 'hi', 'ar', 'fr', 'es', 'pt', 'de', 'it', 'nl',
    'ru', 'ja', 'ko', 'zh', 'tr', 'pl', 'sv', 'da', 'no', 'fi',
    'th', 'vi', 'id', 'ms', 'tl', 'bn', 'ta', 'te', 'pa', 'mr',
    'gu', 'kn', 'ml', 'sw', 'fa', 'he', 'uk', 'ro', 'cs', 'el',
    'hu', 'bg', 'sr', 'hr', 'sk', 'lt', 'lv', 'et', 'sl', 'my',
    'km', 'ne', 'si', 'am', 'zu', 'af', 'ca', 'gl', 'eu'
  )),  -- Per-staff TTS language (expanded in 027 to 59 languages)
  voice_notes_enabled BOOLEAN DEFAULT false,  -- Premium opt-in: PKR 7,000/staff/month on Essential (migration 013)
  nicknames TEXT,                             -- Comma-separated nicknames for recognition (from migration 024)

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
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
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
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  from_number TEXT NOT NULL,
  to_number TEXT,
  intent TEXT NOT NULL,
  draft_json JSONB,
  missing_fields TEXT[],
  thread_key TEXT,                           -- Thread identifier for lookup (from migration 025)
  clarifying_question TEXT,                  -- The question asked to the user (from migration 025)
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
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
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

  -- Account info
  account_name TEXT NOT NULL,
  timezone TEXT DEFAULT 'Asia/Karachi',
  city TEXT,                                  -- City from signup form
  country TEXT,                               -- Country from signup form

  -- Members JSON: [{"name": "...", "whatsapp": "...", "role": "member|staff"}]
  members_json JSONB DEFAULT '[]'::JSONB,

  -- Service type (from migration 027)
  service_type TEXT DEFAULT 'homeops' CHECK (service_type IN ('homeops', 'bizops')),
  currency TEXT DEFAULT 'PKR' CHECK (currency IN ('PKR', 'USD')),

  -- Plan selection (updated in 027 - legacy tiers removed)
  selected_plan TEXT NOT NULL CHECK (selected_plan IN ('essential', 'pro', 'max')),

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

-- Usage event log (from migration 015, updated in 026 for reminder events)
CREATE TABLE IF NOT EXISTS usage_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'message_inbound', 'message_outbound',
    'voice_note_inbound', 'voice_note_outbound',
    'task_created', 'task_completed',
    'reminder_created', 'reminder_sent', 'reminder_cancelled',
    'stt_transcription', 'tts_generation', 'ai_classification', 'ai_call'
  )),
  service TEXT NOT NULL CHECK (service IN ('twilio', 'openai', 'system')),
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Aggregated daily usage counts (from migration 015)
CREATE TABLE IF NOT EXISTS usage_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
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
  UNIQUE(account_id, date)
);

-- Message history for conversation context (from migration 021)
CREATE TABLE IF NOT EXISTS message_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  user_number TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  content TEXT,
  message_type TEXT DEFAULT 'text',
  intent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Reminders table (from migration 026)
CREATE TABLE IF NOT EXISTS reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,

  -- What to remind about
  title TEXT NOT NULL,
  notes TEXT,

  -- Who to remind (the target person)
  target_type TEXT NOT NULL CHECK (target_type IN ('member', 'staff')),
  target_member_id UUID REFERENCES members(id) ON DELETE SET NULL,
  target_staff_id UUID REFERENCES staff(id) ON DELETE SET NULL,
  target_name TEXT NOT NULL,

  -- When to remind
  remind_at TIMESTAMPTZ NOT NULL,
  recurrence TEXT DEFAULT 'once' CHECK (recurrence IN ('once', 'daily')),

  -- Lifecycle
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'sent', 'acknowledged', 'cancelled')),

  -- Delivery tracking
  last_sent_at TIMESTAMPTZ,
  send_count INTEGER DEFAULT 0,
  acknowledged_at TIMESTAMPTZ,

  -- Follow-up nudges (for sent but unacknowledged one-time reminders)
  nudge_count INTEGER DEFAULT 0,
  last_nudge_at TIMESTAMPTZ,
  max_nudges INTEGER DEFAULT 2,

  -- Who created it
  created_by UUID NOT NULL,
  created_by_name TEXT,
  created_by_type TEXT CHECK (created_by_type IN ('member', 'staff')),

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  cancelled_at TIMESTAMPTZ,
  cancelled_by UUID
);

-- ============================================
-- PART 4: INDEXES
-- ============================================

-- Core indexes
CREATE INDEX IF NOT EXISTS idx_members_account_id ON members(account_id);
CREATE INDEX IF NOT EXISTS idx_members_whatsapp ON members(whatsapp);
CREATE INDEX IF NOT EXISTS idx_staff_account_id ON staff(account_id);
CREATE INDEX IF NOT EXISTS idx_staff_whatsapp ON staff(whatsapp);
CREATE INDEX IF NOT EXISTS idx_tasks_account_id ON tasks(account_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_member_id ON tasks(assignee_member_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_staff_id ON tasks(assignee_staff_id);
CREATE INDEX IF NOT EXISTS idx_pending_actions_from_number ON pending_actions(from_number);

-- Pending actions indexes (from migration 025)
CREATE INDEX IF NOT EXISTS idx_pending_actions_thread_status ON pending_actions(thread_key, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_pending_actions_expires ON pending_actions(expires_at) WHERE status = 'pending';

-- Payment/subscription indexes
CREATE INDEX IF NOT EXISTS idx_payments_account_id ON payments(account_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at);
CREATE INDEX IF NOT EXISTS idx_accounts_subscription_status ON accounts(subscription_status);
CREATE INDEX IF NOT EXISTS idx_accounts_subscription_expires_at ON accounts(subscription_expires_at);
CREATE INDEX IF NOT EXISTS idx_accounts_service_type ON accounts(service_type);

-- Onboarding indexes
CREATE INDEX IF NOT EXISTS idx_pending_signups_whatsapp ON pending_signups(subscriber_whatsapp);
CREATE INDEX IF NOT EXISTS idx_pending_signups_status ON pending_signups(status);
CREATE INDEX IF NOT EXISTS idx_pending_signups_expires_at ON pending_signups(expires_at);
CREATE INDEX IF NOT EXISTS idx_pending_signups_payment_method ON pending_signups(payment_method) WHERE status = 'awaiting_payment';
CREATE INDEX IF NOT EXISTS idx_pending_signups_awaiting ON pending_signups(created_at DESC) WHERE status = 'awaiting_payment';
CREATE INDEX IF NOT EXISTS idx_owner_whitelist_whatsapp ON owner_whitelist(whatsapp);

-- Task reminder query index
CREATE INDEX IF NOT EXISTS idx_tasks_due_at_status ON tasks(due_at, status) WHERE due_at IS NOT NULL AND status NOT IN ('completed', 'cancelled', 'problem');

-- Usage tracking indexes (from migration 015)
CREATE INDEX IF NOT EXISTS idx_usage_events_account_date ON usage_events(account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_type ON usage_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_daily_account_date ON usage_daily(account_id, date DESC);

-- Message history indexes (from migration 021)
CREATE INDEX IF NOT EXISTS idx_message_history_user_recent ON message_history(user_number, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_history_account ON message_history(account_id, created_at DESC);

-- Reminder indexes (from migration 026)
CREATE INDEX IF NOT EXISTS idx_reminders_account ON reminders(account_id);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON reminders(status);
CREATE INDEX IF NOT EXISTS idx_reminders_fire ON reminders(remind_at, status) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_reminders_nudge ON reminders(status, last_sent_at) WHERE status = 'sent';
CREATE INDEX IF NOT EXISTS idx_reminders_target_member ON reminders(target_member_id);
CREATE INDEX IF NOT EXISTS idx_reminders_target_staff ON reminders(target_staff_id);

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
GRANT ALL ON message_history TO authenticated;
GRANT ALL ON reminders TO authenticated;

-- Message history RLS (from migration 021)
ALTER TABLE message_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON message_history FOR ALL USING (true) WITH CHECK (true);

-- Reminders RLS (from migration 026)
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role_all_reminders" ON reminders;
CREATE POLICY "service_role_all_reminders" ON reminders FOR ALL USING (true) WITH CHECK (true);

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

-- Get plan base price in specified currency (from migration 007, updated in 027 for dual currency)
CREATE OR REPLACE FUNCTION get_plan_price(plan_name TEXT, p_currency TEXT DEFAULT 'PKR')
RETURNS DECIMAL(10,2) AS $$
BEGIN
  IF p_currency = 'USD' THEN
    RETURN CASE plan_name
      WHEN 'essential' THEN 89.00
      WHEN 'pro' THEN 179.00
      WHEN 'max' THEN 349.00
      ELSE 0.00
    END;
  ELSE -- PKR
    RETURN CASE plan_name
      WHEN 'essential' THEN 25000.00
      WHEN 'pro' THEN 50000.00
      WHEN 'max' THEN 100000.00
      ELSE 0.00
    END;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

GRANT EXECUTE ON FUNCTION get_plan_price(TEXT, TEXT) TO authenticated;

-- Calculate expected monthly amount breakdown with dual currency (from migration 018, updated in 027)
CREATE OR REPLACE FUNCTION calculate_expected_amount(p_account_id UUID)
RETURNS TABLE (
  base_amount DECIMAL(10,2),
  extra_people_count INTEGER,
  extra_people_cost DECIMAL(10,2),
  voice_staff_count INTEGER,
  voice_cost DECIMAL(10,2),
  total_amount DECIMAL(10,2),
  breakdown TEXT,
  account_currency TEXT
) AS $$
DECLARE
  v_plan_tier TEXT;
  v_currency TEXT;
  v_base_price DECIMAL(10,2);
  v_included_people INTEGER;
  v_total_people INTEGER;
  v_member_count INTEGER;
  v_staff_count INTEGER;
  v_extra_people INTEGER;
  v_extra_cost_per_person DECIMAL(10,2);
  v_extra_cost DECIMAL(10,2);
  v_voice_count INTEGER;
  v_voice_price DECIMAL(10,2);
  v_voice_included BOOLEAN;
  v_total DECIMAL(10,2);
  v_parts TEXT[];
  v_sym TEXT;
BEGIN
  SELECT a.plan_tier, COALESCE(a.currency, 'PKR')
  INTO v_plan_tier, v_currency
  FROM accounts a WHERE a.id = p_account_id;

  IF v_plan_tier IS NULL THEN
    RETURN QUERY SELECT 0::DECIMAL(10,2), 0, 0::DECIMAL(10,2), 0, 0::DECIMAL(10,2),
                        0::DECIMAL(10,2), 'Account not found'::TEXT, 'PKR'::TEXT;
    RETURN;
  END IF;

  v_base_price := get_plan_price(v_plan_tier, v_currency);
  v_sym := CASE v_currency WHEN 'USD' THEN '$' ELSE 'PKR ' END;
  v_extra_cost_per_person := CASE v_currency WHEN 'USD' THEN 19.00 ELSE 5000.00 END;

  CASE v_plan_tier
    WHEN 'essential' THEN
      v_included_people := 5;
      v_voice_included := false;
      v_voice_price := CASE v_currency WHEN 'USD' THEN 25.00 ELSE 7000.00 END;
    WHEN 'pro' THEN
      v_included_people := 8;
      v_voice_included := true;
      v_voice_price := 0.00;
    WHEN 'max' THEN
      v_included_people := 15;
      v_voice_included := true;
      v_voice_price := 0.00;
    ELSE
      v_included_people := 5;
      v_voice_included := false;
      v_voice_price := CASE v_currency WHEN 'USD' THEN 25.00 ELSE 7000.00 END;
  END CASE;

  SELECT COUNT(*) INTO v_member_count FROM members m WHERE m.account_id = p_account_id;
  SELECT COUNT(*) INTO v_staff_count FROM staff s WHERE s.account_id = p_account_id;
  v_total_people := v_member_count + v_staff_count;

  v_extra_people := GREATEST(0, v_total_people - v_included_people);
  v_extra_cost := v_extra_people * v_extra_cost_per_person;

  IF v_voice_included THEN
    v_voice_count := 0;
  ELSE
    SELECT COUNT(*) INTO v_voice_count FROM staff s
    WHERE s.account_id = p_account_id AND (s.voice_notes_enabled = true OR s.voice_payment_pending = true);
  END IF;

  v_total := v_base_price + v_extra_cost + (v_voice_count * v_voice_price);

  v_parts := ARRAY['Base ' || v_sym || v_base_price::TEXT];
  IF v_extra_people > 0 THEN
    v_parts := v_parts || (v_extra_people || ' extra ' ||
      CASE WHEN v_extra_people = 1 THEN 'person' ELSE 'people' END ||
      ': ' || v_sym || v_extra_cost::TEXT);
  END IF;
  IF v_voice_count > 0 THEN
    v_parts := v_parts || (v_voice_count || ' voice staff: ' || v_sym || (v_voice_count * v_voice_price)::TEXT);
  END IF;

  RETURN QUERY SELECT v_base_price, v_extra_people, v_extra_cost, v_voice_count,
                      (v_voice_count * v_voice_price), v_total,
                      array_to_string(v_parts, ' + '), v_currency;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION calculate_expected_amount(UUID) TO authenticated;

-- Recalculate and persist expected amount (from migration 018)
CREATE OR REPLACE FUNCTION recalculate_and_store_expected_amount(p_account_id UUID)
RETURNS DECIMAL(10,2) AS $$
DECLARE
  v_total DECIMAL(10,2);
BEGIN
  SELECT cea.total_amount INTO v_total FROM calculate_expected_amount(p_account_id) cea;
  UPDATE accounts SET expected_monthly_amount = v_total WHERE id = p_account_id;
  RETURN v_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION recalculate_and_store_expected_amount(UUID) TO authenticated;

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

-- Get due reminders (from migration 026)
CREATE OR REPLACE FUNCTION get_due_reminders()
RETURNS SETOF reminders AS $$
  SELECT * FROM reminders
  WHERE status = 'scheduled'
    AND remind_at <= NOW()
  ORDER BY remind_at ASC
  LIMIT 50;
$$ LANGUAGE sql SECURITY DEFINER;

-- Get unacknowledged reminders needing nudges (from migration 026)
CREATE OR REPLACE FUNCTION get_unacked_reminders()
RETURNS SETOF reminders AS $$
  SELECT * FROM reminders
  WHERE status = 'sent'
    AND recurrence = 'once'
    AND nudge_count < max_nudges
    AND (last_nudge_at IS NULL OR last_nudge_at < NOW() - INTERVAL '30 minutes')
    AND last_sent_at < NOW() - INTERVAL '15 minutes'
  ORDER BY last_sent_at ASC
  LIMIT 50;
$$ LANGUAGE sql SECURITY DEFINER;

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

DROP TRIGGER IF EXISTS trigger_check_subscription ON accounts;
CREATE TRIGGER trigger_check_subscription
  BEFORE UPDATE ON accounts
  FOR EACH ROW
  EXECUTE FUNCTION check_subscription_status();

-- Cleanup function for old messages (from migration 021)
CREATE OR REPLACE FUNCTION cleanup_old_messages()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM message_history WHERE created_at < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cleanup_old_messages() TO authenticated;

-- ============================================
-- PART 7: VIEWS
-- ============================================

-- Drop existing view if it has different structure
DROP VIEW IF EXISTS subscription_dashboard;

-- Subscription dashboard view (from migration 002, updated in 027 for accounts)
CREATE OR REPLACE VIEW subscription_dashboard AS
SELECT
  a.id,
  a.name as account_name,
  a.service_type,
  a.currency,
  a.subscriber_name,
  a.subscriber_whatsapp,
  a.subscriber_email,
  a.subscription_status,
  a.plan_tier,
  a.subscribed_at,
  a.subscription_expires_at,
  a.last_payment_at,
  a.last_payment_amount,
  a.trial_ends_at,
  a.grace_period_ends_at,
  a.cap_tasks_per_month,
  a.cap_messages_per_month,
  a.cap_voice_notes_per_month,
  a.expected_monthly_amount,
  CASE
    WHEN a.subscription_status = 'trial' THEN a.trial_ends_at - NOW()
    WHEN a.subscription_status IN ('active', 'past_due') THEN a.subscription_expires_at - NOW()
    ELSE INTERVAL '0 days'
  END as time_remaining,
  (SELECT COUNT(*) FROM tasks t WHERE t.account_id = a.id) as total_tasks,
  (SELECT COUNT(*) FROM members m WHERE m.account_id = a.id) as total_members,
  (SELECT COUNT(*) FROM staff s WHERE s.account_id = a.id) as total_staff,
  (SELECT COUNT(*) FROM staff s WHERE s.account_id = a.id AND s.voice_notes_enabled = true) as voice_staff_count,
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.account_id = a.id), 0) as all_time_cost_usd,
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.account_id = a.id), 0) *
    COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_exchange_rate_pkr_usd'), '')::DECIMAL, 278) as all_time_cost_pkr
FROM accounts a;

GRANT SELECT ON subscription_dashboard TO authenticated;

-- Backward-compat view: HomeOps accounts only
CREATE OR REPLACE VIEW households AS
  SELECT * FROM accounts WHERE service_type = 'homeops';
GRANT SELECT ON households TO authenticated;

-- Organizations view: BizOps accounts only
CREATE OR REPLACE VIEW organizations AS
  SELECT * FROM accounts WHERE service_type = 'bizops';
GRANT SELECT ON organizations TO authenticated;

-- ============================================
-- PART 8: ADMIN FUNCTIONS
-- ============================================

-- Admin cost dashboard (from migration 019, updated in 027 for dual service/currency)
CREATE OR REPLACE FUNCTION admin_cost_dashboard(admin_secret TEXT)
RETURNS JSON AS $$
DECLARE
  stored_secret TEXT;
  result JSON;
  pkt_today DATE;
  pkt_month_start DATE;
  pkt_today_start TIMESTAMPTZ;
BEGIN
  -- Validate secret
  SELECT value INTO stored_secret FROM app_config WHERE key = 'admin_dashboard_secret';
  IF stored_secret IS NULL OR admin_secret IS DISTINCT FROM stored_secret THEN
    RETURN json_build_object('error', 'unauthorized', 'message', 'Invalid admin secret');
  END IF;

  -- PKT date boundaries (UTC+5)
  pkt_today := (NOW() AT TIME ZONE 'Asia/Karachi')::DATE;
  pkt_month_start := date_trunc('month', pkt_today)::DATE;
  pkt_today_start := (pkt_today::TEXT || ' 00:00:00+05:00')::TIMESTAMPTZ;

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
  today_events AS (
    SELECT
      account_id,
      COUNT(*) FILTER (WHERE event_type = 'message_inbound') as msgs_in,
      COUNT(*) FILTER (WHERE event_type = 'message_outbound') as msgs_out,
      COUNT(*) FILTER (WHERE event_type = 'task_created') as tasks_created,
      COUNT(*) FILTER (WHERE event_type = 'voice_note_inbound') as voice_in,
      COUNT(*) FILTER (WHERE event_type = 'voice_note_outbound') as voice_out,
      COUNT(*) FILTER (WHERE event_type IN ('ai_classification', 'ai_call')) as ai_calls,
      COALESCE(SUM(COALESCE((details->>'duration_seconds')::DECIMAL, 0) / 60.0) FILTER (WHERE event_type = 'stt_transcription'), 0) as stt_minutes,
      COALESCE(SUM(COALESCE((details->>'character_count')::INTEGER, 0)) FILTER (WHERE event_type = 'tts_generation'), 0) as tts_characters
    FROM usage_events
    WHERE created_at >= pkt_today_start
    GROUP BY account_id
  ),
  account_data AS (
    SELECT
      a.id, a.name, a.plan_tier, a.subscription_status, a.expected_monthly_amount,
      a.subscribed_at, a.created_at, a.city, a.country,
      a.service_type, a.currency,
      a.cap_voice_notes_per_month, a.cap_tasks_per_month, a.cap_messages_per_month,
      -- Months active (for estimated all-time revenue)
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (NOW() - COALESCE(a.subscribed_at, a.created_at))) / 2592000.0)) as months_active,
      COALESCE(a.expected_monthly_amount, 0) *
        GREATEST(1, CEIL(EXTRACT(EPOCH FROM (NOW() - COALESCE(a.subscribed_at, a.created_at))) / 2592000.0)) as estimated_revenue_all_time_native,
      -- Revenue normalized to USD for aggregation
      CASE WHEN COALESCE(a.currency, 'PKR') = 'USD'
        THEN COALESCE(a.expected_monthly_amount, 0)
        ELSE COALESCE(a.expected_monthly_amount, 0) / (SELECT rate FROM exchange)
      END as monthly_revenue_usd,
      (SELECT COUNT(*) FROM members m WHERE m.account_id = a.id) as member_count,
      (SELECT COUNT(*) FROM staff s WHERE s.account_id = a.id) as staff_count,
      (SELECT COUNT(*) FROM staff s WHERE s.account_id = a.id AND s.voice_notes_enabled = true) as voice_staff_count,
      -- All-time: usage_daily + today's real-time events
      COALESCE(SUM(ud.estimated_cost_usd), 0) + (
        (COALESCE(te.msgs_in, 0) + COALESCE(te.msgs_out, 0) + COALESCE(te.voice_in, 0) + COALESCE(te.voice_out, 0)) * (SELECT twilio_msg FROM cost_rates) +
        COALESCE(te.stt_minutes, 0) * (SELECT stt_min FROM cost_rates) +
        COALESCE(te.tts_characters, 0) * (SELECT tts_char FROM cost_rates) +
        COALESCE(te.ai_calls, 0) * (SELECT ai_call FROM cost_rates)
      ) as all_time_cost_usd,
      COALESCE(SUM(ud.messages_inbound), 0) + COALESCE(te.msgs_in, 0) as all_time_msgs_in,
      COALESCE(SUM(ud.messages_outbound), 0) + COALESCE(te.msgs_out, 0) as all_time_msgs_out,
      COALESCE(SUM(ud.tasks_created), 0) + COALESCE(te.tasks_created, 0) as all_time_tasks,
      COALESCE(SUM(ud.voice_notes_inbound), 0) + COALESCE(te.voice_in, 0) as all_time_voice_in,
      COALESCE(SUM(ud.voice_notes_outbound), 0) + COALESCE(te.voice_out, 0) as all_time_voice_out,
      COALESCE(SUM(ud.ai_calls), 0) + COALESCE(te.ai_calls, 0) as all_time_ai_calls,
      COALESCE(SUM(ud.stt_minutes), 0) + COALESCE(te.stt_minutes, 0) as all_time_stt_minutes,
      COALESCE(SUM(ud.tts_characters), 0) + COALESCE(te.tts_characters, 0) as all_time_tts_characters,
      -- Current month
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= pkt_month_start), 0) + (
        (COALESCE(te.msgs_in, 0) + COALESCE(te.msgs_out, 0) + COALESCE(te.voice_in, 0) + COALESCE(te.voice_out, 0)) * (SELECT twilio_msg FROM cost_rates) +
        COALESCE(te.stt_minutes, 0) * (SELECT stt_min FROM cost_rates) +
        COALESCE(te.tts_characters, 0) * (SELECT tts_char FROM cost_rates) +
        COALESCE(te.ai_calls, 0) * (SELECT ai_call FROM cost_rates)
      ) as month_cost_usd,
      COALESCE(SUM(ud.messages_inbound + ud.messages_outbound) FILTER (WHERE ud.date >= pkt_month_start), 0) + COALESCE(te.msgs_in, 0) + COALESCE(te.msgs_out, 0) as month_messages,
      COALESCE(SUM(ud.tasks_created) FILTER (WHERE ud.date >= pkt_month_start), 0) + COALESCE(te.tasks_created, 0) as month_tasks,
      COALESCE(SUM(ud.ai_calls) FILTER (WHERE ud.date >= pkt_month_start), 0) + COALESCE(te.ai_calls, 0) as month_ai_calls,
      COALESCE(SUM(ud.voice_notes_inbound) FILTER (WHERE ud.date >= pkt_month_start), 0) + COALESCE(te.voice_in, 0) as month_voice_inbound,
      COALESCE(SUM(ud.voice_notes_outbound) FILTER (WHERE ud.date >= pkt_month_start), 0) + COALESCE(te.voice_out, 0) as month_voice_outbound,
      -- Last 30 days
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= pkt_today - 30), 0) + (
        (COALESCE(te.msgs_in, 0) + COALESCE(te.msgs_out, 0) + COALESCE(te.voice_in, 0) + COALESCE(te.voice_out, 0)) * (SELECT twilio_msg FROM cost_rates) +
        COALESCE(te.stt_minutes, 0) * (SELECT stt_min FROM cost_rates) +
        COALESCE(te.tts_characters, 0) * (SELECT tts_char FROM cost_rates) +
        COALESCE(te.ai_calls, 0) * (SELECT ai_call FROM cost_rates)
      ) as last_30d_cost_usd,
      -- Cost breakdown
      (COALESCE(SUM(ud.messages_inbound + ud.messages_outbound + ud.voice_notes_inbound + ud.voice_notes_outbound), 0) + COALESCE(te.msgs_in, 0) + COALESCE(te.msgs_out, 0) + COALESCE(te.voice_in, 0) + COALESCE(te.voice_out, 0)) * (SELECT twilio_msg FROM cost_rates) as breakdown_twilio,
      (COALESCE(SUM(ud.stt_minutes), 0) + COALESCE(te.stt_minutes, 0)) * (SELECT stt_min FROM cost_rates) as breakdown_stt,
      (COALESCE(SUM(ud.tts_characters), 0) + COALESCE(te.tts_characters, 0)) * (SELECT tts_char FROM cost_rates) as breakdown_tts,
      (COALESCE(SUM(ud.ai_calls), 0) + COALESCE(te.ai_calls, 0)) * (SELECT ai_call FROM cost_rates) as breakdown_ai
    FROM accounts a
    LEFT JOIN usage_daily ud ON ud.account_id = a.id
    LEFT JOIN today_events te ON te.account_id = a.id
    GROUP BY a.id, a.name, a.plan_tier, a.subscription_status, a.expected_monthly_amount,
             a.subscribed_at, a.created_at, a.city, a.country, a.service_type, a.currency,
             a.cap_voice_notes_per_month, a.cap_tasks_per_month, a.cap_messages_per_month,
             te.msgs_in, te.msgs_out, te.tasks_created, te.voice_in, te.voice_out,
             te.ai_calls, te.stt_minutes, te.tts_characters
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
    'accounts', COALESCE((
      SELECT json_agg(row_data ORDER BY (row_data->>'month_cost_usd')::DECIMAL DESC)
      FROM (
        SELECT json_build_object(
          'id', ad.id, 'name', ad.name, 'plan_tier', ad.plan_tier,
          'service_type', ad.service_type, 'currency', ad.currency,
          'subscription_status', ad.subscription_status,
          'city', ad.city, 'country', ad.country,
          'member_count', ad.member_count, 'staff_count', ad.staff_count,
          'voice_staff_count', ad.voice_staff_count,
          'subscribed_at', ad.subscribed_at, 'created_at', ad.created_at,
          'revenue', json_build_object(
            'monthly_native', COALESCE(ad.expected_monthly_amount, 0),
            'monthly_usd', ROUND(ad.monthly_revenue_usd::NUMERIC, 2),
            'monthly_pkr', CASE WHEN COALESCE(ad.currency, 'PKR') = 'USD'
              THEN ROUND((ad.monthly_revenue_usd * (SELECT rate FROM exchange))::NUMERIC, 2)
              ELSE COALESCE(ad.expected_monthly_amount, 0)
            END,
            'all_time_native', ad.estimated_revenue_all_time_native,
            'all_time_usd', ROUND((ad.monthly_revenue_usd * ad.months_active)::NUMERIC, 2),
            'months_active', ad.months_active
          ),
          'costs', json_build_object(
            'all_time_usd', ROUND(ad.all_time_cost_usd::NUMERIC, 4),
            'all_time_pkr', ROUND((ad.all_time_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2),
            'current_month_usd', ROUND(ad.month_cost_usd::NUMERIC, 4),
            'current_month_pkr', ROUND((ad.month_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2),
            'last_30d_usd', ROUND(ad.last_30d_cost_usd::NUMERIC, 4),
            'last_30d_pkr', ROUND((ad.last_30d_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2)
          ),
          'margin', json_build_object(
            'monthly_margin_usd', ROUND((ad.monthly_revenue_usd - ad.month_cost_usd)::NUMERIC, 2),
            'monthly_margin_pkr', ROUND(((ad.monthly_revenue_usd - ad.month_cost_usd) * (SELECT rate FROM exchange))::NUMERIC, 2),
            'margin_pct', CASE
              WHEN ad.monthly_revenue_usd > 0
              THEN ROUND(((ad.monthly_revenue_usd - ad.month_cost_usd) / ad.monthly_revenue_usd * 100)::NUMERIC, 1)
              ELSE 0
            END
          ),
          'usage', json_build_object(
            'all_time_messages', ad.all_time_msgs_in + ad.all_time_msgs_out,
            'all_time_tasks', ad.all_time_tasks,
            'all_time_voice_inbound', ad.all_time_voice_in,
            'all_time_voice_outbound', ad.all_time_voice_out,
            'all_time_ai_calls', ad.all_time_ai_calls,
            'all_time_stt_minutes', ROUND(ad.all_time_stt_minutes::NUMERIC, 2),
            'all_time_tts_characters', ad.all_time_tts_characters,
            'current_month_messages', ad.month_messages,
            'current_month_tasks', ad.month_tasks,
            'current_month_ai_calls', ad.month_ai_calls,
            'current_month_voice_inbound', ad.month_voice_inbound,
            'current_month_voice_outbound', ad.month_voice_outbound,
            'voice_outbound_cap', COALESCE(ad.cap_voice_notes_per_month, 0),
            'tasks_cap', COALESCE(ad.cap_tasks_per_month, 500),
            'messages_cap', COALESCE(ad.cap_messages_per_month, 5000)
          ),
          'cost_breakdown', json_build_object(
            'twilio_usd', ROUND(ad.breakdown_twilio::NUMERIC, 4),
            'stt_usd', ROUND(ad.breakdown_stt::NUMERIC, 4),
            'tts_usd', ROUND(ad.breakdown_tts::NUMERIC, 4),
            'ai_usd', ROUND(ad.breakdown_ai::NUMERIC, 4)
          )
        ) as row_data
        FROM account_data ad
      ) sub
    ), '[]'::JSON),
    'totals', json_build_object(
      'total_accounts', (SELECT COUNT(*) FROM account_data),
      'total_homeops', (SELECT COUNT(*) FROM account_data WHERE service_type = 'homeops'),
      'total_bizops', (SELECT COUNT(*) FROM account_data WHERE service_type = 'bizops'),
      'total_revenue_monthly_usd', ROUND((SELECT COALESCE(SUM(monthly_revenue_usd), 0) FROM account_data)::NUMERIC, 2),
      'total_revenue_monthly_pkr', ROUND((SELECT COALESCE(SUM(monthly_revenue_usd), 0) FROM account_data)::NUMERIC * (SELECT rate FROM exchange), 2),
      'total_cost_current_month_usd', ROUND((SELECT COALESCE(SUM(month_cost_usd), 0) FROM account_data)::NUMERIC, 4),
      'total_cost_all_time_usd', ROUND((SELECT COALESCE(SUM(all_time_cost_usd), 0) FROM account_data)::NUMERIC, 4),
      'total_cost_all_time_pkr', ROUND((SELECT COALESCE(SUM(all_time_cost_usd), 0) FROM account_data)::NUMERIC * (SELECT rate FROM exchange), 2),
      'total_revenue_all_time_usd', ROUND((SELECT COALESCE(SUM(monthly_revenue_usd * months_active), 0) FROM account_data)::NUMERIC, 2),
      'total_revenue_all_time_pkr', ROUND((SELECT COALESCE(SUM(monthly_revenue_usd * months_active), 0) FROM account_data)::NUMERIC * (SELECT rate FROM exchange), 2),
      'total_profit_all_time_usd', ROUND((
        (SELECT COALESCE(SUM(monthly_revenue_usd * months_active), 0) FROM account_data) -
        (SELECT COALESCE(SUM(all_time_cost_usd), 0) FROM account_data)
      )::NUMERIC, 2),
      'total_margin_monthly_usd', ROUND((
        (SELECT COALESCE(SUM(monthly_revenue_usd), 0) FROM account_data) -
        (SELECT COALESCE(SUM(month_cost_usd), 0) FROM account_data)
      )::NUMERIC, 2),
      'total_margin_monthly_pkr', ROUND((
        (SELECT COALESCE(SUM(monthly_revenue_usd), 0) FROM account_data) -
        (SELECT COALESCE(SUM(month_cost_usd), 0) FROM account_data)
      )::NUMERIC * (SELECT rate FROM exchange), 2)
    )
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_cost_dashboard(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION admin_cost_dashboard(TEXT) TO authenticated;

-- Admin daily usage breakdown (from migration 027)
CREATE OR REPLACE FUNCTION admin_daily_usage(
  admin_secret TEXT,
  p_account_id UUID DEFAULT NULL,
  p_period TEXT DEFAULT 'month'
)
RETURNS JSON AS $$
DECLARE
  stored_secret TEXT;
  result JSON;
  pkt_today DATE;
  pkt_today_start TIMESTAMPTZ;
  date_from DATE;
BEGIN
  SELECT value INTO stored_secret FROM app_config WHERE key = 'admin_dashboard_secret';
  IF stored_secret IS NULL OR admin_secret IS DISTINCT FROM stored_secret THEN
    RETURN json_build_object('error', 'unauthorized');
  END IF;

  pkt_today := (NOW() AT TIME ZONE 'Asia/Karachi')::DATE;
  pkt_today_start := (pkt_today::TEXT || ' 00:00:00+05:00')::TIMESTAMPTZ;

  IF p_period = '30d' THEN date_from := pkt_today - 30;
  ELSIF p_period = 'all' THEN date_from := '2020-01-01'::DATE;
  ELSE date_from := date_trunc('month', pkt_today)::DATE;
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
  daily_rows AS (
    SELECT
      ud.account_id, a.name as account_name, a.service_type, a.city, a.country,
      ud.date, ud.messages_inbound, ud.messages_outbound,
      ud.tasks_created, ud.voice_notes_inbound, ud.voice_notes_outbound,
      ud.ai_calls, ud.stt_minutes, ud.tts_characters, ud.estimated_cost_usd
    FROM usage_daily ud
    JOIN accounts a ON a.id = ud.account_id
    WHERE ud.date >= date_from AND ud.date < pkt_today
      AND (p_account_id IS NULL OR ud.account_id = p_account_id)
  ),
  today_rows AS (
    SELECT
      ue.account_id, a.name as account_name, a.service_type, a.city, a.country,
      pkt_today as date,
      COUNT(*) FILTER (WHERE event_type = 'message_inbound') as messages_inbound,
      COUNT(*) FILTER (WHERE event_type = 'message_outbound') as messages_outbound,
      COUNT(*) FILTER (WHERE event_type = 'task_created') as tasks_created,
      COUNT(*) FILTER (WHERE event_type = 'voice_note_inbound') as voice_notes_inbound,
      COUNT(*) FILTER (WHERE event_type = 'voice_note_outbound') as voice_notes_outbound,
      COUNT(*) FILTER (WHERE event_type IN ('ai_classification', 'ai_call')) as ai_calls,
      COALESCE(SUM(COALESCE((details->>'duration_seconds')::DECIMAL, 0) / 60.0) FILTER (WHERE event_type = 'stt_transcription'), 0) as stt_minutes,
      COALESCE(SUM(COALESCE((details->>'character_count')::INTEGER, 0)) FILTER (WHERE event_type = 'tts_generation'), 0) as tts_characters,
      (
        COUNT(*) FILTER (WHERE event_type IN ('message_inbound', 'message_outbound', 'voice_note_inbound', 'voice_note_outbound')) * (SELECT twilio_msg FROM cost_rates) +
        COALESCE(SUM(COALESCE((details->>'duration_seconds')::DECIMAL, 0) / 60.0) FILTER (WHERE event_type = 'stt_transcription'), 0) * (SELECT stt_min FROM cost_rates) +
        COALESCE(SUM(COALESCE((details->>'character_count')::INTEGER, 0)) FILTER (WHERE event_type = 'tts_generation'), 0) * (SELECT tts_char FROM cost_rates) +
        COUNT(*) FILTER (WHERE event_type IN ('ai_classification', 'ai_call')) * (SELECT ai_call FROM cost_rates)
      ) as estimated_cost_usd
    FROM usage_events ue
    JOIN accounts a ON a.id = ue.account_id
    WHERE ue.created_at >= pkt_today_start
      AND (p_account_id IS NULL OR ue.account_id = p_account_id)
    GROUP BY ue.account_id, a.name, a.service_type, a.city, a.country
  ),
  all_rows AS (
    SELECT * FROM daily_rows UNION ALL SELECT * FROM today_rows
  )
  SELECT json_build_object(
    'success', true,
    'period', p_period,
    'date_from', date_from,
    'date_to', pkt_today,
    'exchange_rate', (SELECT rate FROM exchange),
    'rows', COALESCE((
      SELECT json_agg(json_build_object(
        'account_id', r.account_id,
        'account_name', r.account_name,
        'service_type', r.service_type,
        'city', r.city, 'country', r.country,
        'date', r.date,
        'messages_in', r.messages_inbound,
        'messages_out', r.messages_outbound,
        'tasks', r.tasks_created,
        'voice_in', r.voice_notes_inbound,
        'voice_out', r.voice_notes_outbound,
        'ai_calls', r.ai_calls,
        'stt_minutes', ROUND(r.stt_minutes::NUMERIC, 2),
        'tts_characters', r.tts_characters,
        'cost_usd', ROUND(r.estimated_cost_usd::NUMERIC, 4),
        'cost_pkr', ROUND((r.estimated_cost_usd * (SELECT rate FROM exchange))::NUMERIC, 2),
        'is_today', (r.date = pkt_today)
      ) ORDER BY r.date DESC, r.account_name)
      FROM all_rows r
    ), '[]'::JSON)
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_daily_usage(TEXT, UUID, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION admin_daily_usage(TEXT, UUID, TEXT) TO authenticated;

-- ============================================
-- PART 9: INITIAL DATA
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
-- PART 10: TABLE COMMENTS
-- ============================================

COMMENT ON TABLE accounts IS 'Core account entity (household or organization) with subscription and payment tracking';
COMMENT ON TABLE members IS 'Family members or team members belonging to an account';
COMMENT ON TABLE staff IS 'Staff/employees with language preferences and voice note settings';
COMMENT ON TABLE tasks IS 'Tasks assigned to members or staff with acknowledgment and reminder tracking';
COMMENT ON TABLE reminders IS 'Scheduled reminders with delivery tracking and nudge follow-ups';

COMMENT ON TABLE pending_actions IS 'Multi-turn conversation state for clarification flows';
COMMENT ON TABLE payments IS 'Payment history for account subscriptions';
COMMENT ON TABLE pending_signups IS 'Temporary storage for signups awaiting payment';
COMMENT ON TABLE owner_whitelist IS 'Phone numbers that auto-activate without payment (for testing/owner use)';
COMMENT ON TABLE app_config IS 'Application configuration and secrets';

COMMENT ON COLUMN accounts.service_type IS 'Service type: homeops (household) or bizops (business)';
COMMENT ON COLUMN accounts.currency IS 'Billing currency: PKR or USD';
COMMENT ON COLUMN accounts.plan_tier IS 'Plan tier: essential, pro, max';
COMMENT ON COLUMN accounts.max_members IS 'Max people. Essential=5, Pro=8, Max=15';
COMMENT ON COLUMN accounts.cap_tasks_per_month IS 'Max tasks per month. Essential=500, Pro=1000, Max=2000';
COMMENT ON COLUMN accounts.cap_messages_per_month IS 'Max messages per month. Essential=5000, Pro=12000, Max=25000';
COMMENT ON COLUMN accounts.cap_voice_notes_per_month IS 'Voice notes pool per month. Essential=0 (1200 with add-on), Pro=2500, Max=6000';
COMMENT ON COLUMN accounts.tts_language_staff IS 'Default TTS language for staff voice notes (ISO 639-1, 59 supported)';
COMMENT ON COLUMN accounts.expected_monthly_amount IS 'Expected monthly payment in account currency (PKR or USD)';
COMMENT ON COLUMN accounts.subscription_status IS 'trial=new, active=paid, past_due=grace period, cancelled=user cancelled, expired=payment failed';

COMMENT ON COLUMN members.nicknames IS 'Comma-separated nicknames for recognition (e.g., "Babu, Bashu"). Optional.';
COMMENT ON COLUMN staff.nicknames IS 'Comma-separated nicknames for recognition (e.g., "Babu, Bashu"). Optional.';
COMMENT ON COLUMN staff.voice_payment_pending IS 'True when admin requested voice on Essential plan but payment not yet verified';
COMMENT ON COLUMN staff.voice_payment_ref IS 'Payment reference number provided by admin';
COMMENT ON COLUMN staff.voice_payment_proof_url IS 'URL of payment proof screenshot from Twilio MediaUrl';
COMMENT ON COLUMN staff.voice_payment_requested_at IS 'When voice activation was requested';

COMMENT ON COLUMN tasks.problem_notes IS 'Description of the problem reported by assignee';
COMMENT ON COLUMN tasks.task_complexity IS 'simple = auto-complete on ack, complex = needs explicit done';
COMMENT ON COLUMN tasks.reminder_count IS 'Number of reminders sent after due_at passed';

COMMENT ON TABLE usage_events IS 'Log of every billable action per account for usage tracking and cap enforcement';
COMMENT ON TABLE usage_daily IS 'Aggregated daily usage counts and costs per account (populated nightly by WF8)';
COMMENT ON COLUMN usage_daily.estimated_cost_usd IS 'Estimated API cost in USD calculated from usage rates (Twilio + OpenAI)';

COMMENT ON COLUMN pending_signups.members_json IS 'JSON array: [{"name": "...", "whatsapp": "...", "role": "member|staff"}]';
COMMENT ON COLUMN pending_signups.status IS 'pending=form submitted, payment_started=redirected to payment, awaiting_payment=local payment pending, completed=account created, expired=timeout, cancelled=user cancelled';
COMMENT ON COLUMN pending_signups.payment_method IS 'Local payment method: jazzcash, easypaisa, or bank_transfer';
COMMENT ON COLUMN pending_signups.payment_reference IS 'Transaction ID provided by user for verification';
COMMENT ON COLUMN pending_signups.payment_amount IS 'Payment amount based on selected plan and currency';

COMMENT ON COLUMN payments.expected_amount IS 'Expected monthly amount at time of payment for audit trail';
COMMENT ON COLUMN payments.payment_classification IS 'full=covers all, base_only=plan only, partial=incomplete, overpayment=exceeds expected';
COMMENT ON COLUMN payments.addons_activated IS 'JSON record of add-ons activated by this payment';
COMMENT ON COLUMN payments.proof_url IS 'URL of payment proof screenshot from WhatsApp MediaUrl';

COMMENT ON TABLE message_history IS 'Recent message history per user for AI conversation context (auto-cleaned after 24h)';
COMMENT ON COLUMN message_history.user_number IS 'WhatsApp number of the human user (not MYNK number)';
COMMENT ON COLUMN message_history.direction IS 'inbound = user to MYNK, outbound = MYNK to user';
COMMENT ON COLUMN message_history.content IS 'Message text content (truncated to 500 chars for context)';
COMMENT ON COLUMN message_history.intent IS 'AI-classified intent for context';

COMMENT ON FUNCTION is_whitelisted IS 'Check if a phone number is in the owner whitelist';
COMMENT ON FUNCTION get_config IS 'Get a configuration value by key';
COMMENT ON FUNCTION get_plan_price IS 'Get monthly price for a plan tier in specified currency (PKR or USD)';
COMMENT ON FUNCTION calculate_expected_amount IS 'Calculate expected monthly payment breakdown with currency-aware pricing';
COMMENT ON FUNCTION recalculate_and_store_expected_amount IS 'Calculate and persist expected_monthly_amount on accounts table';
COMMENT ON FUNCTION admin_cost_dashboard IS 'Password-protected admin dashboard returning account cost/profitability data with service_type and currency support';
COMMENT ON FUNCTION admin_daily_usage IS 'Password-protected daily usage breakdown with service_type support';
COMMENT ON FUNCTION get_due_reminders IS 'Get scheduled reminders whose fire time has arrived (limit 50)';
COMMENT ON FUNCTION get_unacked_reminders IS 'Get sent one-time reminders needing follow-up nudges (limit 50)';

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
-- SELECT get_plan_price('essential', 'PKR'), get_plan_price('essential', 'USD');
-- SELECT get_plan_price('pro', 'PKR'), get_plan_price('pro', 'USD');
-- SELECT get_plan_price('max', 'PKR'), get_plan_price('max', 'USD');

-- Check views:
-- SELECT COUNT(*) FROM households;  -- HomeOps only
-- SELECT COUNT(*) FROM organizations;  -- BizOps only

-- ============================================
-- DONE! Your MYNK database is ready.
-- Supports both HomeOps (households) and BizOps (organizations).
-- ============================================
