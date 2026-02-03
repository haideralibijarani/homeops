-- Migration: Add problem tracking and creator type to tasks table
-- Run this in Supabase SQL Editor

-- Add problem_notes column to tasks table
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS problem_notes TEXT;

-- Add created_by_type to know if creator is member or staff (for notifications)
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS created_by_type TEXT
  CHECK (created_by_type IN ('member', 'staff'));

-- Add problem_reported_at timestamp
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS problem_reported_at TIMESTAMPTZ;

-- Add index for faster filtering by status
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_member_id ON tasks(assignee_member_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_staff_id ON tasks(assignee_staff_id);

-- Update status CHECK constraint to include 'problem' status
-- First drop the old constraint if it exists
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_status_check;

-- Add new constraint with 'problem' status
ALTER TABLE tasks ADD CONSTRAINT tasks_status_check
  CHECK (status IN ('pending', 'in_progress', 'completed', 'problem', 'cancelled'));

COMMENT ON COLUMN tasks.problem_notes IS 'Description of the problem reported by assignee';
COMMENT ON COLUMN tasks.problem_reported_at IS 'Timestamp when problem was reported';
