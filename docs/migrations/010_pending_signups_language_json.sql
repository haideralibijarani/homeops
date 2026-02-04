-- Migration 010: Add language_settings_json to pending_signups table
-- Stores granular language preferences during signup (before household creation)
--
-- JSON structure:
-- {
--   "tts_language_staff": "ur",      -- Voice notes for staff
--   "tts_language_members": "en",    -- Voice notes for members
--   "text_language_staff": "ur",     -- Text messages for staff
--   "text_language_members": "en",   -- Text messages for members
--   "digest_language": "en"          -- Daily digest language
-- }

ALTER TABLE pending_signups
ADD COLUMN IF NOT EXISTS language_settings_json JSONB DEFAULT NULL;

COMMENT ON COLUMN pending_signups.language_settings_json IS
'Granular language preferences: tts_language_staff/members, text_language_staff/members, digest_language';

-- Verify column was added
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pending_signups'
    AND column_name = 'language_settings_json'
  ) THEN
    RAISE NOTICE 'Migration 010: language_settings_json column added successfully';
  ELSE
    RAISE EXCEPTION 'Migration 010: Failed to add language_settings_json column';
  END IF;
END $$;
