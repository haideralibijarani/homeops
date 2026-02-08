-- Migration 012: Drop unused/dead columns
-- These columns are either superseded by newer columns or functionally dead.

-- households: language_pref replaced by granular tts_language_staff etc.
ALTER TABLE households DROP COLUMN IF EXISTS language_pref;

-- NOTE: subscription_plan kept — subscription_dashboard view depends on it

-- households: members never receive voice notes (only staff do)
ALTER TABLE households DROP COLUMN IF EXISTS tts_language_members;

-- households: all text messages are always English (not configurable)
ALTER TABLE households DROP COLUMN IF EXISTS text_language_staff;
ALTER TABLE households DROP COLUMN IF EXISTS text_language_members;

-- households: digest feature is not implemented
ALTER TABLE households DROP COLUMN IF EXISTS digest_language;

-- tasks: assignee_id superseded by assignee_member_id / assignee_staff_id
ALTER TABLE tasks DROP COLUMN IF EXISTS assignee_id;

-- tasks: reminded_at superseded by last_reminder_at (migration 004)
ALTER TABLE tasks DROP COLUMN IF EXISTS reminded_at;

-- pending_signups: language_pref replaced by language_settings_json
ALTER TABLE pending_signups DROP COLUMN IF EXISTS language_pref;

-- pending_signups: address field is never written by the onboarding workflow
ALTER TABLE pending_signups DROP COLUMN IF EXISTS address;
