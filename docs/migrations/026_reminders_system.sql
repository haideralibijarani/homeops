-- Migration 026: Reminders System
-- Adds a separate reminders table with full lifecycle support
-- Run in Supabase SQL Editor

-- =============================================================
-- 1. Create reminders table
-- =============================================================
CREATE TABLE IF NOT EXISTS reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,

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

-- =============================================================
-- 2. Indexes
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_reminders_household ON reminders(household_id);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON reminders(status);
CREATE INDEX IF NOT EXISTS idx_reminders_fire ON reminders(remind_at, status) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_reminders_nudge ON reminders(status, last_sent_at) WHERE status = 'sent';
CREATE INDEX IF NOT EXISTS idx_reminders_target_member ON reminders(target_member_id);
CREATE INDEX IF NOT EXISTS idx_reminders_target_staff ON reminders(target_staff_id);

-- =============================================================
-- 3. RLS
-- =============================================================
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role_all_reminders" ON reminders;
CREATE POLICY "service_role_all_reminders" ON reminders FOR ALL USING (true) WITH CHECK (true);

-- =============================================================
-- 4. RPC: get_due_reminders()
-- Returns scheduled reminders whose fire time has arrived
-- =============================================================
CREATE OR REPLACE FUNCTION get_due_reminders()
RETURNS SETOF reminders AS $$
  SELECT * FROM reminders
  WHERE status = 'scheduled'
    AND remind_at <= NOW()
  ORDER BY remind_at ASC
  LIMIT 50;
$$ LANGUAGE sql SECURITY DEFINER;

-- =============================================================
-- 5. RPC: get_unacked_reminders()
-- Returns sent one-time reminders that need follow-up nudges
-- =============================================================
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

-- =============================================================
-- 6. Update usage_events CHECK constraint
-- =============================================================
ALTER TABLE usage_events DROP CONSTRAINT IF EXISTS usage_events_event_type_check;
ALTER TABLE usage_events ADD CONSTRAINT usage_events_event_type_check
  CHECK (event_type IN (
    'message_inbound', 'message_outbound',
    'voice_note_inbound', 'voice_note_outbound',
    'task_created', 'task_completed',
    'reminder_created', 'reminder_sent', 'reminder_cancelled',
    'stt_transcription', 'tts_generation',
    'ai_classification', 'ai_call'
  ));
