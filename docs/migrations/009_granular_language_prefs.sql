-- Migration 009: Add granular language preferences to households table
-- Enables separate language settings for TTS, text messages, and digest
-- for staff vs members
--
-- Settings:
--   tts_language_staff    - Voice notes for staff (default: 'ur' for Urdu)
--   tts_language_members  - Voice notes for members (default: 'en' for English)
--   text_language_staff   - Text messages for staff (default: 'ur' for Roman Urdu)
--   text_language_members - Text messages for members (default: 'en' for English)
--   digest_language       - Daily digest for all (default: 'en' for English)
--
-- Language codes:
--   'en' = English
--   'ur' = Urdu (native script for TTS, Roman Urdu for text)

-- Add TTS language for staff (voice notes)
ALTER TABLE households
ADD COLUMN IF NOT EXISTS tts_language_staff TEXT DEFAULT 'ur';

-- Add TTS language for members (voice notes)
ALTER TABLE households
ADD COLUMN IF NOT EXISTS tts_language_members TEXT DEFAULT 'en';

-- Add text message language for staff
ALTER TABLE households
ADD COLUMN IF NOT EXISTS text_language_staff TEXT DEFAULT 'ur';

-- Add text message language for members
ALTER TABLE households
ADD COLUMN IF NOT EXISTS text_language_members TEXT DEFAULT 'en';

-- Add daily digest language
ALTER TABLE households
ADD COLUMN IF NOT EXISTS digest_language TEXT DEFAULT 'en';

-- Add comments explaining each field
COMMENT ON COLUMN households.tts_language_staff IS
'Language for voice notes sent to staff: en=English, ur=Urdu. Default: ur';

COMMENT ON COLUMN households.tts_language_members IS
'Language for voice notes sent to members: en=English, ur=Urdu. Default: en';

COMMENT ON COLUMN households.text_language_staff IS
'Language for text messages sent to staff: en=English, ur=Roman Urdu. Default: ur';

COMMENT ON COLUMN households.text_language_members IS
'Language for text messages sent to members: en=English, ur=Roman Urdu. Default: en';

COMMENT ON COLUMN households.digest_language IS
'Language for daily digest summary: en=English, ur=Roman Urdu. Default: en';

-- Verify columns were added
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'households'
    AND column_name IN ('tts_language_staff', 'tts_language_members', 'text_language_staff', 'text_language_members', 'digest_language')
  ) THEN
    RAISE NOTICE 'Migration 009: Granular language preference columns added successfully';
  ELSE
    RAISE EXCEPTION 'Migration 009: Failed to add language preference columns';
  END IF;
END $$;
