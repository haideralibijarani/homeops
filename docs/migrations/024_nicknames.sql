-- Migration 024: Add Nicknames to Members and Staff
-- Run in Supabase SQL Editor
--
-- Changes:
-- 1. Add nicknames TEXT column to members table (comma-separated)
-- 2. Add nicknames TEXT column to staff table (comma-separated)
-- 3. Update subscription_dashboard view to include nicknames
--
-- Usage:
--   Nicknames are stored as comma-separated strings (e.g., "Babu, Bashu")
--   Used for matching when users refer to people by nicknames
--   Managed via signup form (optional) and manage_household WhatsApp command

-- ============================================
-- 1. Add nicknames columns
-- ============================================

ALTER TABLE members ADD COLUMN IF NOT EXISTS nicknames TEXT DEFAULT NULL;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS nicknames TEXT DEFAULT NULL;

-- ============================================
-- 2. Add comments
-- ============================================

COMMENT ON COLUMN members.nicknames IS 'Comma-separated nicknames for recognition (e.g., "Babu, Bashu"). Optional.';
COMMENT ON COLUMN staff.nicknames IS 'Comma-separated nicknames for recognition (e.g., "Babu, Bashu"). Optional.';

-- ============================================
-- DONE
-- ============================================
-- After running this migration:
-- 1. members.nicknames and staff.nicknames columns are available
-- 2. Signup form accepts optional nicknames during member/staff creation
-- 3. Admin can manage nicknames via WhatsApp (manage_household edit)
-- 4. Resolve All Assignees matches against nicknames for task assignment
