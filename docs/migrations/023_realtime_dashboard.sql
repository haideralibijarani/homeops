-- Migration 023: Real-time Admin Dashboard + PKT Timezone Fix
-- Run in Supabase SQL Editor
--
-- Changes:
-- 1. Fix timezone: use PKT (Asia/Karachi) instead of UTC for date boundaries
-- 2. Include today's real-time events from usage_events (not yet in usage_daily)
-- 3. Split voice notes into inbound/outbound with cap in usage output
-- 4. Dashboard data now matches WhatsApp usage report accuracy

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
      household_id,
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
    GROUP BY household_id
  ),
  household_data AS (
    SELECT
      h.id, h.name, h.plan_tier, h.subscription_status, h.expected_monthly_amount,
      h.subscribed_at, h.created_at, h.city, h.country,
      h.cap_voice_notes_per_month, h.cap_tasks_per_month, h.cap_messages_per_month,
      (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as member_count,
      (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as staff_count,
      (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id AND s.voice_notes_enabled = true) as voice_staff_count,
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
    FROM households h
    LEFT JOIN usage_daily ud ON ud.household_id = h.id
    LEFT JOIN today_events te ON te.household_id = h.id
    GROUP BY h.id, h.name, h.plan_tier, h.subscription_status, h.expected_monthly_amount,
             h.subscribed_at, h.created_at, h.city, h.country, h.cap_voice_notes_per_month, h.cap_tasks_per_month, h.cap_messages_per_month,
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
    'households', COALESCE((
      SELECT json_agg(row_data ORDER BY (row_data->>'month_cost_usd')::DECIMAL DESC)
      FROM (
        SELECT json_build_object(
          'id', hd.id, 'name', hd.name, 'plan_tier', hd.plan_tier,
          'subscription_status', hd.subscription_status,
          'city', hd.city, 'country', hd.country,
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
            'all_time_voice_inbound', hd.all_time_voice_in,
            'all_time_voice_outbound', hd.all_time_voice_out,
            'all_time_ai_calls', hd.all_time_ai_calls,
            'all_time_stt_minutes', ROUND(hd.all_time_stt_minutes::NUMERIC, 2),
            'all_time_tts_characters', hd.all_time_tts_characters,
            'current_month_messages', hd.month_messages,
            'current_month_tasks', hd.month_tasks,
            'current_month_ai_calls', hd.month_ai_calls,
            'current_month_voice_inbound', hd.month_voice_inbound,
            'current_month_voice_outbound', hd.month_voice_outbound,
            'voice_outbound_cap', COALESCE(hd.cap_voice_notes_per_month, 0),
            'tasks_cap', COALESCE(hd.cap_tasks_per_month, 500),
            'messages_cap', COALESCE(hd.cap_messages_per_month, 5000)
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
-- DONE
-- ============================================
-- After running this migration:
-- 1. Dashboard now includes today's real-time events from usage_events
-- 2. Date boundaries use PKT (Asia/Karachi) instead of UTC
-- 3. current_month_voice_notes added to usage output
-- 4. Dashboard data will match WhatsApp usage report accuracy
