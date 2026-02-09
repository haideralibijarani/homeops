-- Migration 019: Cost Tracking & Profitability Dashboard
-- Adds estimated_cost_usd to usage_daily, configurable cost rates,
-- admin_cost_dashboard() function, and updated subscription_dashboard view.

-- ============================================
-- 1. ADD COST COLUMN TO USAGE_DAILY
-- ============================================
ALTER TABLE usage_daily ADD COLUMN IF NOT EXISTS estimated_cost_usd DECIMAL(10,4) DEFAULT 0;
COMMENT ON COLUMN usage_daily.estimated_cost_usd IS 'Estimated API cost in USD calculated from usage rates (Twilio + OpenAI)';

-- ============================================
-- 2. SEED COST RATES INTO APP_CONFIG
-- ============================================
INSERT INTO app_config (key, value, description) VALUES
  ('cost_twilio_message_usd',      '0.005',    'Cost per Twilio WhatsApp message (inbound or outbound) in USD'),
  ('cost_openai_stt_per_min_usd',  '0.006',    'Cost per minute of OpenAI Whisper STT in USD'),
  ('cost_openai_tts_per_char_usd', '0.000015', 'Cost per character of OpenAI TTS in USD ($15/1M chars)'),
  ('cost_openai_ai_call_usd',      '0.001',    'Estimated cost per OpenAI GPT-4o-mini AI call in USD'),
  ('cost_exchange_rate_pkr_usd',   '278',      'Exchange rate: PKR per 1 USD'),
  ('admin_dashboard_secret',       'HomeOpsCostDash2026!', 'Secret for admin cost dashboard access')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- ============================================
-- 3. UPDATE SUBSCRIPTION_DASHBOARD VIEW
-- ============================================
DROP VIEW IF EXISTS subscription_dashboard;

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
  -- Cost columns (new)
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.household_id = h.id), 0) as all_time_cost_usd,
  COALESCE((SELECT SUM(ud.estimated_cost_usd) FROM usage_daily ud WHERE ud.household_id = h.id), 0) *
    COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_exchange_rate_pkr_usd'), '')::DECIMAL, 278) as all_time_cost_pkr
FROM households h;

GRANT SELECT ON subscription_dashboard TO authenticated;

-- ============================================
-- 4. CREATE ADMIN COST DASHBOARD FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION admin_cost_dashboard(admin_secret TEXT)
RETURNS JSON AS $$
DECLARE
  stored_secret TEXT;
  result JSON;
BEGIN
  -- Validate secret
  SELECT value INTO stored_secret FROM app_config WHERE key = 'admin_dashboard_secret';

  IF stored_secret IS NULL OR admin_secret IS DISTINCT FROM stored_secret THEN
    RETURN json_build_object('error', 'unauthorized', 'message', 'Invalid admin secret');
  END IF;

  -- Build the full dashboard dataset
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
      h.id,
      h.name,
      h.plan_tier,
      h.subscription_status,
      h.expected_monthly_amount,
      h.subscribed_at,
      h.created_at,
      (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as member_count,
      (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as staff_count,
      (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id AND s.voice_notes_enabled = true) as voice_staff_count,
      -- All-time totals from usage_daily
      COALESCE(SUM(ud.estimated_cost_usd), 0) as all_time_cost_usd,
      COALESCE(SUM(ud.messages_inbound), 0) as all_time_msgs_in,
      COALESCE(SUM(ud.messages_outbound), 0) as all_time_msgs_out,
      COALESCE(SUM(ud.tasks_created), 0) as all_time_tasks,
      COALESCE(SUM(ud.voice_notes_inbound), 0) as all_time_voice_in,
      COALESCE(SUM(ud.voice_notes_outbound), 0) as all_time_voice_out,
      COALESCE(SUM(ud.ai_calls), 0) as all_time_ai_calls,
      COALESCE(SUM(ud.stt_minutes), 0) as all_time_stt_minutes,
      COALESCE(SUM(ud.tts_characters), 0) as all_time_tts_characters,
      -- Current month
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_cost_usd,
      COALESCE(SUM(ud.messages_inbound + ud.messages_outbound) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_messages,
      COALESCE(SUM(ud.tasks_created) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_tasks,
      COALESCE(SUM(ud.ai_calls) FILTER (WHERE ud.date >= date_trunc('month', CURRENT_DATE)::DATE), 0) as month_ai_calls,
      -- Last 30 days
      COALESCE(SUM(ud.estimated_cost_usd) FILTER (WHERE ud.date >= CURRENT_DATE - 30), 0) as last_30d_cost_usd,
      -- Cost breakdown (all-time, calculated from counts * current rates)
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
          'id', hd.id,
          'name', hd.name,
          'plan_tier', hd.plan_tier,
          'subscription_status', hd.subscription_status,
          'member_count', hd.member_count,
          'staff_count', hd.staff_count,
          'voice_staff_count', hd.voice_staff_count,
          'subscribed_at', hd.subscribed_at,
          'created_at', hd.created_at,
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

-- Grant execute to anon and authenticated (for frontend RPC calls)
GRANT EXECUTE ON FUNCTION admin_cost_dashboard(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION admin_cost_dashboard(TEXT) TO authenticated;

-- ============================================
-- 5. BACKFILL EXISTING USAGE_DAILY ROWS
-- ============================================
DO $$
DECLARE
  v_twilio DECIMAL := COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_twilio_message_usd'), '')::DECIMAL, 0.005);
  v_stt DECIMAL := COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_openai_stt_per_min_usd'), '')::DECIMAL, 0.006);
  v_tts DECIMAL := COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_openai_tts_per_char_usd'), '')::DECIMAL, 0.000015);
  v_ai DECIMAL := COALESCE(NULLIF((SELECT value FROM app_config WHERE key = 'cost_openai_ai_call_usd'), '')::DECIMAL, 0.001);
BEGIN
  UPDATE usage_daily SET estimated_cost_usd =
    (messages_inbound + messages_outbound + voice_notes_inbound + voice_notes_outbound) * v_twilio +
    stt_minutes * v_stt +
    tts_characters * v_tts +
    ai_calls * v_ai
  WHERE estimated_cost_usd IS NULL OR estimated_cost_usd = 0;
END;
$$;
