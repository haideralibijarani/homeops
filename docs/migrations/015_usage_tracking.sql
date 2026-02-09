-- Migration 015: Usage tracking, cap enforcement, and tier-based pricing
-- Adds usage_events and usage_daily tables for tracking billable actions.
-- Adds cap columns to households for per-plan enforcement.
-- Updates plan_tier CHECK constraints for Essential/Pro/Max tiers.

-- ============================================
-- 1. USAGE EVENT LOG
-- ============================================

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
  details JSONB,          -- Optional: {duration_seconds, character_count, etc.}
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_usage_events_household_date
  ON usage_events(household_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_type
  ON usage_events(event_type, created_at DESC);

COMMENT ON TABLE usage_events IS 'Log of every billable action per household for usage tracking and cap enforcement';

-- ============================================
-- 2. AGGREGATED DAILY COUNTS
-- ============================================

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
  UNIQUE(household_id, date)
);

CREATE INDEX IF NOT EXISTS idx_usage_daily_household_date
  ON usage_daily(household_id, date DESC);

COMMENT ON TABLE usage_daily IS 'Aggregated daily usage counts per household (populated nightly by WF6)';

-- ============================================
-- 3. CAP COLUMNS ON HOUSEHOLDS
-- ============================================

-- Defaults = Essential plan caps
ALTER TABLE households ADD COLUMN IF NOT EXISTS
  cap_tasks_per_day INTEGER DEFAULT 30;
ALTER TABLE households ADD COLUMN IF NOT EXISTS
  cap_messages_per_month INTEGER DEFAULT 10000;
ALTER TABLE households ADD COLUMN IF NOT EXISTS
  cap_voice_notes_per_staff_month INTEGER DEFAULT 250;

COMMENT ON COLUMN households.cap_tasks_per_day IS 'Max tasks per day. Essential=30, Pro=50, Max=100';
COMMENT ON COLUMN households.cap_messages_per_month IS 'Max messages per month. Essential=10000, Pro=20000, Max=40000';
COMMENT ON COLUMN households.cap_voice_notes_per_staff_month IS 'Max voice notes per staff per month. All plans=250';

-- ============================================
-- 4. UPDATE PLAN TIER CONSTRAINTS
-- ============================================

-- households.plan_tier: add essential, pro, max
ALTER TABLE households DROP CONSTRAINT IF EXISTS households_plan_tier_check;
ALTER TABLE households ADD CONSTRAINT households_plan_tier_check
  CHECK (plan_tier IN ('essential', 'pro', 'max', 'starter', 'family', 'premium', 'custom'));

-- pending_signups.selected_plan: add essential, pro, max
ALTER TABLE pending_signups DROP CONSTRAINT IF EXISTS pending_signups_selected_plan_check;
ALTER TABLE pending_signups ADD CONSTRAINT pending_signups_selected_plan_check
  CHECK (selected_plan IN ('essential', 'pro', 'max', 'starter', 'family', 'premium', 'custom'));

-- payments.plan: add essential, pro, max
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_plan_check;
ALTER TABLE payments ADD CONSTRAINT payments_plan_check
  CHECK (plan IN ('monthly', 'annual', 'essential', 'pro', 'max', 'starter', 'family', 'premium', 'custom'));

-- ============================================
-- 5. UPDATE get_plan_price FUNCTION
-- ============================================

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

-- ============================================
-- 6. GRANT PERMISSIONS
-- ============================================

GRANT ALL ON usage_events TO authenticated;
GRANT ALL ON usage_daily TO authenticated;

-- ============================================
-- 7. COMMENTS
-- ============================================

COMMENT ON COLUMN households.plan_tier IS 'Plan tier: essential (25K, 30 tasks/day), pro (50K, 50 tasks/day), max (100K, 100 tasks/day), or legacy tiers';
