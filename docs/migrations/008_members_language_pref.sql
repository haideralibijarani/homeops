-- Migration 008: Add language_pref to members table
-- Enables individual language preferences for household members
-- Part of multi-language/market support feature
--
-- Language options:
--   'en' = English (default)
--   'ur' = Urdu/Roman Urdu
--   NULL = Inherit from household.language_pref

-- Add language_pref column to members table
ALTER TABLE members
ADD COLUMN IF NOT EXISTS language_pref TEXT DEFAULT NULL;

-- Add comment explaining the field
COMMENT ON COLUMN members.language_pref IS
'Individual language preference: en=English, ur=Urdu/Roman Urdu. NULL inherits from household.language_pref';

-- Verify the column was added (optional check)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'members' AND column_name = 'language_pref'
  ) THEN
    RAISE NOTICE 'Migration 008: members.language_pref column added successfully';
  ELSE
    RAISE EXCEPTION 'Migration 008: Failed to add language_pref column';
  END IF;
END $$;
