-- Migration 021: Message History for Conversation Context
-- Stores recent inbound and outbound messages per user thread
-- so the AI Agent can understand context when users reply to messages.

-- ============================================
-- 1. CREATE MESSAGE_HISTORY TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS message_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES households(id) ON DELETE CASCADE,
  user_number TEXT NOT NULL,       -- the user's WhatsApp number (always the human, not HomeOps)
  direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  content TEXT,                    -- message text content
  message_type TEXT DEFAULT 'text', -- text, voice_note, system
  intent TEXT,                     -- classified intent (for inbound after AI processing)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fetching recent conversation by user number
CREATE INDEX idx_message_history_user_recent ON message_history(user_number, created_at DESC);

-- Index for household-level queries
CREATE INDEX idx_message_history_household ON message_history(household_id, created_at DESC);

-- ============================================
-- 2. AUTO-CLEANUP: DELETE MESSAGES OLDER THAN 24 HOURS
-- ============================================
-- This keeps the table small. Only recent context matters.
-- Run via pg_cron or a scheduled workflow.

-- Function to clean old messages
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
-- 3. RLS POLICIES
-- ============================================
ALTER TABLE message_history ENABLE ROW LEVEL SECURITY;

-- Service role can do everything (used by n8n)
CREATE POLICY "service_role_all" ON message_history
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================
-- 4. TABLE COMMENTS
-- ============================================
COMMENT ON TABLE message_history IS 'Recent message history per user for AI conversation context (auto-cleaned after 24h)';
COMMENT ON COLUMN message_history.user_number IS 'WhatsApp number of the human user (not HomeOps number)';
COMMENT ON COLUMN message_history.direction IS 'inbound = user to HomeOps, outbound = HomeOps to user';
COMMENT ON COLUMN message_history.content IS 'Message text content (truncated to 500 chars for context)';
COMMENT ON COLUMN message_history.message_type IS 'text, voice_note (transcribed), or system';
COMMENT ON COLUMN message_history.intent IS 'AI-classified intent for inbound messages';
