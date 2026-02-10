-- Migration 025: Pending Actions Cleanup
-- Run in Supabase SQL Editor
--
-- Changes:
-- 1. Add missing columns (thread_key, clarifying_question) to schema
-- 2. Mark all expired pending_actions
-- 3. Delete very old rows
-- 4. Add index for faster cleanup queries

-- ============================================
-- 1. Add missing columns (if not already present from manual creation)
-- ============================================

ALTER TABLE pending_actions ADD COLUMN IF NOT EXISTS thread_key TEXT;
ALTER TABLE pending_actions ADD COLUMN IF NOT EXISTS clarifying_question TEXT;

-- Index for cleanup queries and thread-based lookups
CREATE INDEX IF NOT EXISTS idx_pending_actions_thread_status
  ON pending_actions(thread_key, status) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_pending_actions_expires
  ON pending_actions(expires_at) WHERE status = 'pending';

-- ============================================
-- 2. Mark all expired pending_actions (one-time cleanup)
-- ============================================

UPDATE pending_actions
SET status = 'expired'
WHERE status = 'pending'
  AND expires_at < NOW();

-- ============================================
-- 3. Delete very old rows (> 30 days)
-- ============================================

DELETE FROM pending_actions
WHERE created_at < NOW() - INTERVAL '30 days';

-- ============================================
-- DONE
-- ============================================
-- After running this migration:
-- 1. All expired pending_actions are now marked as 'expired'
-- 2. Old rows (> 30 days) are deleted
-- 3. WF2-PROCESSOR Process Pending Result now marks:
--    - Stale/overridden actions as 'expired'
--    - Consumed follow-ups as 'completed'
-- 4. WF8-USAGE-AGGREGATOR daily cleanup now:
--    - Marks pending actions past expires_at as 'expired'
--    - Deletes completed/expired rows older than 7 days
--    - Deletes message_history older than 48 hours
