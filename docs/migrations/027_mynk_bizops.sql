-- Migration 027: MYNK Dual-Service Expansion
-- Renames households → accounts, household_id → account_id
-- Adds service_type, currency, expanded language support
-- Removes legacy/custom plan tiers
-- Updates all functions for dual currency/service
-- Run in Supabase SQL Editor
--
-- IMPORTANT: Run AFTER all previous migrations (001-026)
-- This is an INCREMENTAL migration, not a fresh start

-- ============================================
-- STEP 0: DROP DEPENDENT OBJECTS
-- Must drop view and trigger before renaming table
-- ============================================

DROP VIEW IF EXISTS subscription_dashboard;
DROP TRIGGER IF EXISTS trigger_check_subscription ON households;

-- ============================================
-- STEP 1: RENAME TABLE households → accounts
-- ============================================

ALTER TABLE households RENAME TO accounts;

-- ============================================
-- STEP 2: RENAME FK COLUMNS household_id → account_id
-- ============================================

ALTER TABLE members RENAME COLUMN household_id TO account_id;
ALTER TABLE staff RENAME COLUMN household_id TO account_id;
ALTER TABLE tasks RENAME COLUMN household_id TO account_id;
ALTER TABLE pending_actions RENAME COLUMN household_id TO account_id;
ALTER TABLE payments RENAME COLUMN household_id TO account_id;
ALTER TABLE usage_events RENAME COLUMN household_id TO account_id;
ALTER TABLE usage_daily RENAME COLUMN household_id TO account_id;
ALTER TABLE message_history RENAME COLUMN household_id TO account_id;
ALTER TABLE reminders RENAME COLUMN household_id TO account_id;

-- ============================================
-- STEP 3: RENAME INDEXES
-- ============================================

-- Core table indexes
ALTER INDEX IF EXISTS idx_members_household_id RENAME TO idx_members_account_id;
ALTER INDEX IF EXISTS idx_staff_household_id RENAME TO idx_staff_account_id;
ALTER INDEX IF EXISTS idx_tasks_household_id RENAME TO idx_tasks_account_id;
ALTER INDEX IF EXISTS idx_payments_household_id RENAME TO idx_payments_account_id;

-- Usage tracking indexes
ALTER INDEX IF EXISTS idx_usage_events_household_date RENAME TO idx_usage_events_account_date;
ALTER INDEX IF EXISTS idx_usage_daily_household_date RENAME TO idx_usage_daily_account_date;

-- Message history
ALTER INDEX IF EXISTS idx_message_history_household RENAME TO idx_message_history_account;

-- Accounts table indexes (was households)
ALTER INDEX IF EXISTS idx_households_subscription_status RENAME TO idx_accounts_subscription_status;
ALTER INDEX IF EXISTS idx_households_subscription_expires_at RENAME TO idx_accounts_subscription_expires_at;

-- Reminders (from migration 026)
ALTER INDEX IF EXISTS idx_reminders_household RENAME TO idx_reminders_account;

-- ============================================
-- STEP 4: RENAME CONSTRAINTS
-- ============================================

-- FK constraints (auto-named as tablename_columnname_fkey)
-- Wrapped in DO/EXCEPTION blocks because constraint names may differ
DO $$ BEGIN
  ALTER TABLE members RENAME CONSTRAINT members_household_id_fkey TO members_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE staff RENAME CONSTRAINT staff_household_id_fkey TO staff_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE tasks RENAME CONSTRAINT tasks_household_id_fkey TO tasks_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE pending_actions RENAME CONSTRAINT pending_actions_household_id_fkey TO pending_actions_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE payments RENAME CONSTRAINT payments_household_id_fkey TO payments_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE usage_events RENAME CONSTRAINT usage_events_household_id_fkey TO usage_events_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE usage_daily RENAME CONSTRAINT usage_daily_household_id_fkey TO usage_daily_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE message_history RENAME CONSTRAINT message_history_household_id_fkey TO message_history_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE reminders RENAME CONSTRAINT reminders_household_id_fkey TO reminders_account_id_fkey;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- UNIQUE constraint
DO $$ BEGIN
  ALTER TABLE usage_daily RENAME CONSTRAINT usage_daily_household_id_date_key TO usage_daily_account_id_date_key;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- CHECK constraints on accounts (was households)
-- These may have different names depending on Postgres version; use IF EXISTS pattern
DO $$ BEGIN
  ALTER TABLE accounts RENAME CONSTRAINT households_status_check TO accounts_status_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE accounts RENAME CONSTRAINT households_subscription_status_check TO accounts_subscription_status_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE accounts RENAME CONSTRAINT households_plan_tier_check TO accounts_plan_tier_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- ============================================
-- STEP 5: ADD service_type AND currency COLUMNS
-- ============================================

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS service_type TEXT DEFAULT 'homeops'
    CHECK (service_type IN ('homeops', 'bizops')),
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'PKR'
    CHECK (currency IN ('PKR', 'USD'));

ALTER TABLE pending_signups
  ADD COLUMN IF NOT EXISTS service_type TEXT DEFAULT 'homeops'
    CHECK (service_type IN ('homeops', 'bizops')),
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'PKR'
    CHECK (currency IN ('PKR', 'USD'));

-- Index for filtering by service
CREATE INDEX IF NOT EXISTS idx_accounts_service_type ON accounts(service_type);

-- ============================================
-- STEP 6: EXPAND LANGUAGE SUPPORT
-- 59 languages (was just en/ur) - all major global languages
-- ============================================

-- Drop old CHECK and add expanded
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_tts_language_staff_check;
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS households_tts_language_staff_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_tts_language_staff_check
  CHECK (tts_language_staff IN (
    'en', 'ur', 'hi', 'ar', 'fr', 'es', 'pt', 'de', 'it', 'nl',
    'ru', 'ja', 'ko', 'zh', 'tr', 'pl', 'sv', 'da', 'no', 'fi',
    'th', 'vi', 'id', 'ms', 'tl', 'bn', 'ta', 'te', 'pa', 'mr',
    'gu', 'kn', 'ml', 'sw', 'fa', 'he', 'uk', 'ro', 'cs', 'el',
    'hu', 'bg', 'sr', 'hr', 'sk', 'lt', 'lv', 'et', 'sl', 'my',
    'km', 'ne', 'si', 'am', 'zu', 'af', 'ca', 'gl', 'eu'
  ));

-- Update default from 'ur' to 'en' for new accounts
ALTER TABLE accounts ALTER COLUMN tts_language_staff SET DEFAULT 'en';

-- Staff language_pref
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_language_pref_check;
ALTER TABLE staff ADD CONSTRAINT staff_language_pref_check
  CHECK (language_pref IN (
    'en', 'ur', 'hi', 'ar', 'fr', 'es', 'pt', 'de', 'it', 'nl',
    'ru', 'ja', 'ko', 'zh', 'tr', 'pl', 'sv', 'da', 'no', 'fi',
    'th', 'vi', 'id', 'ms', 'tl', 'bn', 'ta', 'te', 'pa', 'mr',
    'gu', 'kn', 'ml', 'sw', 'fa', 'he', 'uk', 'ro', 'cs', 'el',
    'hu', 'bg', 'sr', 'hr', 'sk', 'lt', 'lv', 'et', 'sl', 'my',
    'km', 'ne', 'si', 'am', 'zu', 'af', 'ca', 'gl', 'eu'
  ));

-- ============================================
-- STEP 7: REMOVE LEGACY/CUSTOM PLAN TIERS
-- ============================================

-- Migrate existing legacy plans to closest current tier
UPDATE accounts SET plan_tier = 'essential' WHERE plan_tier IN ('starter', 'family', 'custom');
UPDATE accounts SET plan_tier = 'pro' WHERE plan_tier = 'premium';

-- Drop old CHECK and add clean one
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_plan_tier_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_plan_tier_check
  CHECK (plan_tier IN ('essential', 'pro', 'max'));

-- Rename pending_signups.household_name to account_name
ALTER TABLE pending_signups RENAME COLUMN household_name TO account_name;

-- Pending signups plan tiers
UPDATE pending_signups SET selected_plan = 'essential' WHERE selected_plan IN ('starter', 'family', 'custom');
UPDATE pending_signups SET selected_plan = 'pro' WHERE selected_plan = 'premium';
ALTER TABLE pending_signups DROP CONSTRAINT IF EXISTS pending_signups_selected_plan_check;
ALTER TABLE pending_signups ADD CONSTRAINT pending_signups_selected_plan_check
  CHECK (selected_plan IN ('essential', 'pro', 'max'));

-- Payments: keep legacy values in CHECK since they are historical records
-- No change to payments.plan CHECK

-- ============================================
-- STEP 8: BACKFILL existing accounts
-- ============================================

UPDATE accounts SET service_type = 'homeops' WHERE service_type IS NULL;
UPDATE accounts SET currency = 'PKR' WHERE currency IS NULL;

-- ============================================
-- STEP 9: UPDATE get_plan_price() FOR DUAL CURRENCY
-- ============================================

-- Must drop first because signature changes (adding parameter)
DROP FUNCTION IF EXISTS get_plan_price(TEXT);

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

-- ============================================
-- STEP 10: UPDATE calculate_expected_amount() FOR DUAL CURRENCY
-- ============================================

-- Must drop: return type changes (added account_currency column)
DROP FUNCTION IF EXISTS calculate_expected_amount(UUID);

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

-- ============================================
-- STEP 11: UPDATE recalculate_and_store_expected_amount()
-- ============================================

DROP FUNCTION IF EXISTS recalculate_and_store_expected_amount(UUID);

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

-- ============================================
-- STEP 12: RECREATE check_subscription_status TRIGGER
-- ============================================

-- Function stays the same (uses NEW record, no table references)
-- Just recreate the trigger on renamed table
CREATE TRIGGER trigger_check_subscription
  BEFORE UPDATE ON accounts
  FOR EACH ROW
  EXECUTE FUNCTION check_subscription_status();

-- ============================================
-- STEP 13: RECREATE subscription_dashboard VIEW
-- ============================================

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

-- ============================================
-- STEP 14: BACKWARD-COMPAT households VIEW
-- For any external queries that still reference households
-- ============================================

CREATE OR REPLACE VIEW households AS
  SELECT * FROM accounts WHERE service_type = 'homeops';
GRANT SELECT ON households TO authenticated;

-- Organizations view (BizOps only)
CREATE OR REPLACE VIEW organizations AS
  SELECT * FROM accounts WHERE service_type = 'bizops';
GRANT SELECT ON organizations TO authenticated;

-- ============================================
-- STEP 15: UPDATE admin_cost_dashboard()
-- Adds service_type, currency, currency-aware revenue
-- Renames all household refs to account
-- ============================================

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
  -- Today's real-time events (not yet aggregated into usage_daily)
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
      -- Current month (PKT): usage_daily from month start + today's events
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
      -- Last 30 days (PKT)
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= pkt_today - 30), 0) + (
        (COALESCE(te.msgs_in, 0) + COALESCE(te.msgs_out, 0) + COALESCE(te.voice_in, 0) + COALESCE(te.voice_out, 0)) * (SELECT twilio_msg FROM cost_rates) +
        COALESCE(te.stt_minutes, 0) * (SELECT stt_min FROM cost_rates) +
        COALESCE(te.tts_characters, 0) * (SELECT tts_char FROM cost_rates) +
        COALESCE(te.ai_calls, 0) * (SELECT ai_call FROM cost_rates)
      ) as last_30d_cost_usd,
      -- Cost breakdown (all-time, including today)
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

-- ============================================
-- STEP 16: UPDATE admin_daily_usage()
-- Renames household refs to account, adds service_type
-- ============================================

-- Must drop first because parameter name changes (p_household_id → p_account_id)
DROP FUNCTION IF EXISTS admin_daily_usage(TEXT, UUID, TEXT);

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
-- STEP 17: UPDATE TABLE COMMENTS
-- ============================================

COMMENT ON TABLE accounts IS 'Core account entity (household or organization) with subscription and payment tracking';
COMMENT ON COLUMN accounts.service_type IS 'Service type: homeops (household) or bizops (business)';
COMMENT ON COLUMN accounts.currency IS 'Billing currency: PKR or USD';
COMMENT ON COLUMN accounts.plan_tier IS 'Plan tier: essential, pro, max';
COMMENT ON COLUMN accounts.tts_language_staff IS 'Default TTS language for staff voice notes (ISO 639-1 code)';
COMMENT ON COLUMN accounts.expected_monthly_amount IS 'Expected monthly payment in account currency (PKR or USD)';

COMMENT ON FUNCTION get_plan_price(TEXT, TEXT) IS 'Get monthly price for a plan tier in specified currency (PKR or USD)';
COMMENT ON FUNCTION calculate_expected_amount(UUID) IS 'Calculate expected monthly payment breakdown with currency-aware pricing';
COMMENT ON FUNCTION recalculate_and_store_expected_amount(UUID) IS 'Calculate and persist expected_monthly_amount on accounts table';
COMMENT ON FUNCTION admin_cost_dashboard(TEXT) IS 'Password-protected admin dashboard returning account cost/profitability data with service_type and currency support';

-- ============================================
-- VERIFICATION QUERIES (uncomment to test)
-- ============================================

-- Check table rename:
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('accounts', 'households') ORDER BY table_name;

-- Check column rename:
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'members' AND column_name = 'account_id';

-- Check new columns:
-- SELECT service_type, currency, COUNT(*) FROM accounts GROUP BY 1, 2;

-- Check dual currency pricing:
-- SELECT get_plan_price('essential', 'PKR'), get_plan_price('essential', 'USD');
-- SELECT get_plan_price('pro', 'PKR'), get_plan_price('pro', 'USD');
-- SELECT get_plan_price('max', 'PKR'), get_plan_price('max', 'USD');

-- Check language expansion:
-- SELECT DISTINCT tts_language_staff FROM accounts;

-- Check backward-compat view:
-- SELECT COUNT(*) FROM households;

-- ============================================
-- STEP 18: EXPAND LANGUAGE CHECK CONSTRAINTS (SUPPLEMENTARY)
-- Run this if Step 6 already ran with only 5 languages (en, ur, hi, ar, fr).
-- This expands to all 59 supported languages.
-- Safe to run even if Step 6 already has the expanded list (DROP IF EXISTS).
-- ============================================

ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_tts_language_staff_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_tts_language_staff_check
  CHECK (tts_language_staff IN (
    'en', 'ur', 'hi', 'ar', 'fr', 'es', 'pt', 'de', 'it', 'nl',
    'ru', 'ja', 'ko', 'zh', 'tr', 'pl', 'sv', 'da', 'no', 'fi',
    'th', 'vi', 'id', 'ms', 'tl', 'bn', 'ta', 'te', 'pa', 'mr',
    'gu', 'kn', 'ml', 'sw', 'fa', 'he', 'uk', 'ro', 'cs', 'el',
    'hu', 'bg', 'sr', 'hr', 'sk', 'lt', 'lv', 'et', 'sl', 'my',
    'km', 'ne', 'si', 'am', 'zu', 'af', 'ca', 'gl', 'eu'
  ));

ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_language_pref_check;
ALTER TABLE staff ADD CONSTRAINT staff_language_pref_check
  CHECK (language_pref IN (
    'en', 'ur', 'hi', 'ar', 'fr', 'es', 'pt', 'de', 'it', 'nl',
    'ru', 'ja', 'ko', 'zh', 'tr', 'pl', 'sv', 'da', 'no', 'fi',
    'th', 'vi', 'id', 'ms', 'tl', 'bn', 'ta', 'te', 'pa', 'mr',
    'gu', 'kn', 'ml', 'sw', 'fa', 'he', 'uk', 'ro', 'cs', 'el',
    'hu', 'bg', 'sr', 'hr', 'sk', 'lt', 'lv', 'et', 'sl', 'my',
    'km', 'ne', 'si', 'am', 'zu', 'af', 'ca', 'gl', 'eu'
  ));

-- ============================================
-- DONE!
-- ============================================
-- After running this migration:
-- 1. Table 'households' renamed to 'accounts', backward-compat views created (households + organizations)
-- 2. All 'household_id' columns renamed to 'account_id' (9 tables)
-- 3. service_type (homeops/bizops) and currency (PKR/USD) added
-- 4. TTS language expanded: 59 languages (default: en)
-- 5. Legacy plan tiers removed (starter/family/premium/custom → essential/pro)
-- 6. get_plan_price() supports dual currency
-- 7. calculate_expected_amount() supports dual currency
-- 8. admin_cost_dashboard() includes service_type, currency, normalized revenue
-- 9. admin_daily_usage() updated with account_id and service_type
-- 10. subscription_dashboard view recreated with new schema
--
-- NEXT STEPS:
-- Update n8n workflows to use 'account_id' instead of 'household_id'
-- Update n8n workflows to use 'accounts' instead of 'households'
-- Update signup form with service_type selector
-- Update admin dashboard frontend
