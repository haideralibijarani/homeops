-- Migration 022: Pricing Revision + ai_call Fix
-- Run in Supabase SQL Editor
--
-- Changes:
-- 1. Fix ai_call CHECK constraint on usage_events (was blocking batch inserts)
-- 2. Switch task caps from per-day to per-month
-- 3. Switch voice note caps from per-staff to shared pool per-month
-- 4. Update message caps to new tier values
-- 5. Update functions and views
--
-- New Pricing:
--   Essential: PKR 25K | 5 members | 500 tasks/mo | 5K msgs/mo | 1,200 voice pool (only with add-on)
--   Pro:       PKR 50K | 8 members | 1K tasks/mo  | 12K msgs/mo | 2,500 voice pool
--   Max:       PKR 100K | 15 members | 2K tasks/mo | 25K msgs/mo | 6,000 voice pool
--   Extra members: +PKR 5K/member
--   Voice add-on (Essential only): +PKR 7K/staff/mo
--   Essential voice pool activated ONLY when voice add-on is purchased

-- ============================================
-- FIX 1: Add ai_call to usage_events CHECK constraint
-- ============================================
-- This was causing Extract Assignee Message and Extract Multi Notification
-- batch inserts to fail silently (atomic PostgREST inserts roll back entirely)

ALTER TABLE usage_events DROP CONSTRAINT IF EXISTS usage_events_event_type_check;
ALTER TABLE usage_events ADD CONSTRAINT usage_events_event_type_check
  CHECK (event_type IN (
    'message_inbound', 'message_outbound',
    'voice_note_inbound', 'voice_note_outbound',
    'task_created', 'task_completed',
    'stt_transcription', 'tts_generation',
    'ai_classification', 'ai_call'
  ));

-- ============================================
-- FIX 2: Drop dependent view BEFORE dropping columns
-- ============================================

DROP VIEW IF EXISTS subscription_dashboard;

-- ============================================
-- FIX 3: New cap columns (per-month model)
-- ============================================

-- Add new monthly task cap (replaces daily)
ALTER TABLE households ADD COLUMN IF NOT EXISTS cap_tasks_per_month INTEGER DEFAULT 500;

-- Add new voice notes pool (replaces per-staff)
ALTER TABLE households ADD COLUMN IF NOT EXISTS cap_voice_notes_per_month INTEGER DEFAULT 0;

-- Migrate existing households to new tier values
UPDATE households SET
  cap_tasks_per_month = CASE plan_tier
    WHEN 'essential' THEN 500
    WHEN 'pro' THEN 1000
    WHEN 'max' THEN 2000
    ELSE 500  -- legacy/custom get Essential-level
  END,
  cap_messages_per_month = CASE plan_tier
    WHEN 'essential' THEN 5000
    WHEN 'pro' THEN 12000
    WHEN 'max' THEN 25000
    ELSE cap_messages_per_month  -- keep existing for legacy
  END,
  cap_voice_notes_per_month = CASE plan_tier
    WHEN 'pro' THEN 2500
    WHEN 'max' THEN 6000
    WHEN 'essential' THEN
      -- Only activate pool if household has voice-enabled staff
      CASE WHEN EXISTS (
        SELECT 1 FROM staff s
        WHERE s.household_id = households.id
        AND (s.voice_notes_enabled = true OR s.voice_payment_pending = true)
      ) THEN 1200 ELSE 0 END
    ELSE 0  -- legacy/custom
  END;

-- Drop old columns (view already dropped above)
ALTER TABLE households DROP COLUMN IF EXISTS cap_tasks_per_day;
ALTER TABLE households DROP COLUMN IF EXISTS cap_voice_notes_per_staff_month;

-- ============================================
-- FIX 4: Recreate subscription_dashboard view with new columns
-- ============================================

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
  h.cap_tasks_per_month,
  h.cap_messages_per_month,
  h.cap_voice_notes_per_month,
  h.expected_monthly_amount,
  CASE
    WHEN h.subscription_status = 'trial' THEN h.trial_ends_at - NOW()
    WHEN h.subscription_status IN ('active', 'past_due') THEN h.subscription_expires_at - NOW()
    ELSE INTERVAL '0 days'
  END as time_remaining,
  (SELECT COUNT(*) FROM tasks t WHERE t.household_id = h.id) as total_tasks,
  (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as total_members,
  (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as total_staff,
  (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id AND s.voice_notes_enabled = true) as voice_staff_count,
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.household_id = h.id), 0) as all_time_cost_usd,
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.household_id = h.id), 0) *
    COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_exchange_rate_pkr_usd'), '')::DECIMAL, 278) as all_time_cost_pkr
FROM households h;

GRANT SELECT ON subscription_dashboard TO authenticated;

-- ============================================
-- FIX 5: Update table comments
-- ============================================

COMMENT ON COLUMN households.plan_tier IS 'Plan tier: essential (25K, 500 tasks/mo) | pro (50K, 1K tasks/mo) | max (100K, 2K tasks/mo)';
COMMENT ON COLUMN households.cap_tasks_per_month IS 'Max tasks per month. Essential=500, Pro=1000, Max=2000';
COMMENT ON COLUMN households.cap_messages_per_month IS 'Max messages per month. Essential=5000, Pro=12000, Max=25000';
COMMENT ON COLUMN households.cap_voice_notes_per_month IS 'Voice notes pool per month. Essential=0 (1200 with add-on), Pro=2500, Max=6000';

-- ============================================
-- DONE
-- ============================================
-- After running this migration:
-- 1. ai_call events will now be accepted by usage_events table
-- 2. Task caps are now per-month (not per-day)
-- 3. Voice note caps are now a shared pool (not per-staff)
-- 4. Essential tier voice pool only activates with voice add-on
-- 5. Workflow WF2 and WF6 need updating to use new column names
