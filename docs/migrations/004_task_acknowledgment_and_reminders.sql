-- Migration 004: Task Acknowledgment, Complexity, and Reminder Tracking
-- Run this in Supabase SQL Editor

-- 1. Update status CHECK constraint to include 'acknowledged'
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_status_check;
ALTER TABLE tasks ADD CONSTRAINT tasks_status_check
  CHECK (status IN ('pending', 'acknowledged', 'in_progress', 'completed', 'problem', 'cancelled'));

-- 2. Acknowledgment tracking
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;

-- 3. Task complexity (simple = auto-complete on ack, complex = needs explicit done)
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS task_complexity TEXT DEFAULT 'complex'
  CHECK (task_complexity IN ('simple', 'complex'));

-- 4. Reminder tracking columns
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS reminder_count INTEGER DEFAULT 0;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS last_reminder_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS max_reminders INTEGER DEFAULT 3;

-- 5. Index for reminder queries (overdue tasks not yet completed)
CREATE INDEX IF NOT EXISTS idx_tasks_due_at_status
  ON tasks(due_at, status)
  WHERE due_at IS NOT NULL AND status NOT IN ('completed', 'cancelled', 'problem');

-- 6. RPC function for WF4-REMINDERS to query overdue tasks
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

COMMENT ON COLUMN tasks.acknowledged_at IS 'Timestamp when assignee acknowledged the task';
COMMENT ON COLUMN tasks.task_complexity IS 'simple = auto-complete on ack, complex = needs explicit done';
COMMENT ON COLUMN tasks.reminder_count IS 'Number of reminders sent after due_at passed';
COMMENT ON COLUMN tasks.last_reminder_at IS 'Last reminder message sent at';
COMMENT ON COLUMN tasks.escalated_at IS 'When task was escalated to creator after max reminders';
COMMENT ON COLUMN tasks.max_reminders IS 'Maximum reminders before escalation (default 3)';
