-- HomeOps Complete Database Schema - Fresh Start
-- Run this in Supabase SQL Editor for a clean database setup
-- Combines all migrations (001-007) into a single script
--
-- Last Updated: 2026-02-03
-- Plan Pricing: Starter PKR 15,000 | Family PKR 25,000 | Premium PKR 35,000

-- ============================================
-- PART 1: CORE TABLES
-- ============================================

-- Households table (core entity)
CREATE TABLE IF NOT EXISTS households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  timezone TEXT DEFAULT 'Asia/Karachi',
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'cancelled')),
  address TEXT,
  language_pref TEXT DEFAULT 'en',
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Subscriber details (from migration 002)
  subscriber_name TEXT,
  subscriber_whatsapp TEXT,
  subscriber_email TEXT,
  subscribed_at TIMESTAMPTZ,

  -- Subscription management (from migration 002)
  subscription_status TEXT DEFAULT 'trial' CHECK (subscription_status IN ('trial', 'active', 'past_due', 'cancelled', 'expired')),
  subscription_plan TEXT CHECK (subscription_plan IN ('monthly', 'annual', NULL)),
  subscription_expires_at TIMESTAMPTZ,

  -- Payment tracking (from migration 002)
  last_payment_at TIMESTAMPTZ,
  last_payment_amount DECIMAL(10,2),
  payment_method TEXT,
  payment_provider TEXT,
  payment_provider_customer_id TEXT,

  -- Trial/Grace periods (from migration 002)
  trial_ends_at TIMESTAMPTZ,
  grace_period_ends_at TIMESTAMPTZ,

  -- Plan tier (from migration 005)
  plan_tier TEXT DEFAULT 'starter' CHECK (plan_tier IN ('starter', 'family', 'premium')),
  max_members INTEGER DEFAULT 3,
  stripe_subscription_id TEXT,
  onboarded_at TIMESTAMPTZ,
  onboarding_source TEXT DEFAULT 'whatsapp',

  -- Granular language preferences (from migration 009)
  tts_language_staff TEXT DEFAULT 'ur',      -- Voice notes for staff: en/ur
  tts_language_members TEXT DEFAULT 'en',    -- Voice notes for members: en/ur
  text_language_staff TEXT DEFAULT 'ur',     -- Text messages for staff: en/ur (Roman Urdu)
  text_language_members TEXT DEFAULT 'en',   -- Text messages for members: en/ur
  digest_language TEXT DEFAULT 'en'          -- Daily digest: en/ur
);

-- Members table (family members)
CREATE TABLE IF NOT EXISTS members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  whatsapp TEXT NOT NULL,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  language_pref TEXT DEFAULT NULL,  -- NULL = inherit from household (from migration 008)
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
  language_pref TEXT DEFAULT 'en',
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
  assignee_id UUID,
  assignee_member_id UUID REFERENCES members(id) ON DELETE SET NULL,
  assignee_staff_id UUID REFERENCES staff(id) ON DELETE SET NULL,
  due_at TIMESTAMPTZ,
  priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'acknowledged', 'in_progress', 'completed', 'problem', 'cancelled')),
  reminded_at TIMESTAMPTZ,
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
  escalated_at TIMESTAMPTZ,
  max_reminders INTEGER DEFAULT 3
);

-- Messages table (audit log)
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES households(id) ON DELETE SET NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  from_number TEXT NOT NULL,
  to_number TEXT NOT NULL,
  msg_type TEXT DEFAULT 'text' CHECK (msg_type IN ('text', 'audio', 'media')),
  category TEXT,
  media_url TEXT,
  transcript TEXT,
  payload_json JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
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
  plan TEXT CHECK (plan IN ('monthly', 'annual', 'starter', 'family', 'premium')),
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  failure_reason TEXT
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
  address TEXT,
  language_pref TEXT DEFAULT 'en',

  -- Members JSON: [{"name": "...", "whatsapp": "...", "role": "member|staff", "language_pref": "en|ur"}]
  members_json JSONB DEFAULT '[]'::JSONB,

  -- Granular language settings JSON (from migration 010)
  -- {"tts_language_staff": "ur", "tts_language_members": "en", "text_language_staff": "ur", "text_language_members": "en", "digest_language": "en"}
  language_settings_json JSONB DEFAULT NULL,

  -- Plan selection
  selected_plan TEXT NOT NULL CHECK (selected_plan IN ('starter', 'family', 'premium')),
  billing_cycle TEXT DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly')),

  -- Stripe tracking (for future Phase 3)
  stripe_session_id TEXT,
  stripe_customer_id TEXT,

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
CREATE INDEX IF NOT EXISTS idx_messages_household_id ON messages(household_id);
CREATE INDEX IF NOT EXISTS idx_pending_actions_from_number ON pending_actions(from_number);

-- Payment/subscription indexes
CREATE INDEX IF NOT EXISTS idx_payments_household_id ON payments(household_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at);
CREATE INDEX IF NOT EXISTS idx_households_subscription_status ON households(subscription_status);
CREATE INDEX IF NOT EXISTS idx_households_subscription_expires_at ON households(subscription_expires_at);
CREATE INDEX IF NOT EXISTS idx_households_stripe_subscription ON households(stripe_subscription_id);

-- Onboarding indexes
CREATE INDEX IF NOT EXISTS idx_pending_signups_whatsapp ON pending_signups(subscriber_whatsapp);
CREATE INDEX IF NOT EXISTS idx_pending_signups_stripe_session ON pending_signups(stripe_session_id);
CREATE INDEX IF NOT EXISTS idx_pending_signups_status ON pending_signups(status);
CREATE INDEX IF NOT EXISTS idx_pending_signups_expires_at ON pending_signups(expires_at);
CREATE INDEX IF NOT EXISTS idx_pending_signups_payment_method ON pending_signups(payment_method) WHERE status = 'awaiting_payment';
CREATE INDEX IF NOT EXISTS idx_pending_signups_awaiting ON pending_signups(created_at DESC) WHERE status = 'awaiting_payment';
CREATE INDEX IF NOT EXISTS idx_owner_whitelist_whatsapp ON owner_whitelist(whatsapp);

-- Reminder query index
CREATE INDEX IF NOT EXISTS idx_tasks_due_at_status ON tasks(due_at, status) WHERE due_at IS NOT NULL AND status NOT IN ('completed', 'cancelled', 'problem');

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

-- Get plan price in PKR (from migration 007)
CREATE OR REPLACE FUNCTION get_plan_price(plan_name TEXT)
RETURNS DECIMAL(10,2) AS $$
BEGIN
  RETURN CASE plan_name
    WHEN 'starter' THEN 15000.00
    WHEN 'family' THEN 25000.00
    WHEN 'premium' THEN 35000.00
    ELSE 0.00
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

GRANT EXECUTE ON FUNCTION get_plan_price(TEXT) TO authenticated;

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

-- Subscription dashboard view (from migration 002)
CREATE OR REPLACE VIEW subscription_dashboard AS
SELECT
  h.id,
  h.name as household_name,
  h.subscriber_name,
  h.subscriber_whatsapp,
  h.subscriber_email,
  h.subscription_status,
  h.subscription_plan,
  h.plan_tier,
  h.subscribed_at,
  h.subscription_expires_at,
  h.last_payment_at,
  h.last_payment_amount,
  h.trial_ends_at,
  h.grace_period_ends_at,
  CASE
    WHEN h.subscription_status = 'trial' THEN h.trial_ends_at - NOW()
    WHEN h.subscription_status IN ('active', 'past_due') THEN h.subscription_expires_at - NOW()
    ELSE INTERVAL '0 days'
  END as time_remaining,
  (SELECT COUNT(*) FROM tasks t WHERE t.household_id = h.id) as total_tasks,
  (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as total_members,
  (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as total_staff
FROM households h;

GRANT SELECT ON subscription_dashboard TO authenticated;

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
  ('payment_bank_title', 'Account Title', 'Bank account title')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- ============================================
-- PART 9: TABLE COMMENTS
-- ============================================

COMMENT ON TABLE households IS 'Core household entity with subscription and payment tracking';
COMMENT ON TABLE members IS 'Family members belonging to a household';
COMMENT ON TABLE staff IS 'Household staff/workers with language preferences';
COMMENT ON TABLE tasks IS 'Tasks assigned to members or staff with acknowledgment and reminder tracking';
COMMENT ON TABLE messages IS 'Audit log of all WhatsApp interactions';
COMMENT ON TABLE pending_actions IS 'Multi-turn conversation state for clarification flows';
COMMENT ON TABLE payments IS 'Payment history for household subscriptions';
COMMENT ON TABLE pending_signups IS 'Temporary storage for signups awaiting payment';
COMMENT ON TABLE owner_whitelist IS 'Phone numbers that auto-activate without payment (for testing/owner use)';
COMMENT ON TABLE app_config IS 'Application configuration and secrets';

COMMENT ON COLUMN households.plan_tier IS 'starter=3 people, family=6 people, premium=12 people';
COMMENT ON COLUMN households.max_members IS 'Maximum household people allowed by plan (combined members+staff)';
COMMENT ON COLUMN households.subscription_status IS 'trial=new, active=paid, past_due=grace period, cancelled=user cancelled, expired=payment failed';
COMMENT ON COLUMN pending_signups.members_json IS 'JSON array: [{"name": "...", "whatsapp": "...", "role": "member|staff", "language_pref": "en"}]';
COMMENT ON COLUMN pending_signups.status IS 'pending=form submitted, payment_started=redirected to payment, awaiting_payment=local payment pending, completed=household created, expired=timeout, cancelled=user cancelled';
COMMENT ON COLUMN pending_signups.payment_method IS 'Local payment method: jazzcash, easypaisa, or bank_transfer';
COMMENT ON COLUMN pending_signups.payment_reference IS 'Transaction ID provided by user for verification';
COMMENT ON COLUMN pending_signups.payment_amount IS 'Payment amount in PKR based on selected plan';
COMMENT ON COLUMN tasks.problem_notes IS 'Description of the problem reported by assignee';
COMMENT ON COLUMN tasks.task_complexity IS 'simple = auto-complete on ack, complex = needs explicit done';
COMMENT ON COLUMN tasks.reminder_count IS 'Number of reminders sent after due_at passed';
COMMENT ON FUNCTION is_whitelisted IS 'Check if a phone number is in the owner whitelist';
COMMENT ON FUNCTION get_config IS 'Get a configuration value by key';
COMMENT ON FUNCTION get_plan_price IS 'Get monthly price in PKR for a plan tier';

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
-- SELECT get_plan_price('starter'), get_plan_price('family'), get_plan_price('premium');

-- ============================================
-- DONE! Your HomeOps database is ready.
-- ============================================
