-- Migration 006: Onboarding System v2 - Whitelist & Manual Activation
-- Run this in Supabase SQL Editor after migration 005

-- ============================================
-- PART 1: Owner Whitelist Table
-- ============================================

CREATE TABLE IF NOT EXISTS owner_whitelist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whatsapp TEXT NOT NULL UNIQUE,
  name TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup
CREATE INDEX IF NOT EXISTS idx_owner_whitelist_whatsapp ON owner_whitelist(whatsapp);

-- RLS: Only service role can access
ALTER TABLE owner_whitelist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role only for whitelist"
  ON owner_whitelist FOR ALL
  USING (auth.role() = 'service_role');

-- Grant to authenticated for n8n access via service key
GRANT ALL ON owner_whitelist TO authenticated;

COMMENT ON TABLE owner_whitelist IS 'Phone numbers that auto-activate without payment (for testing/owner use)';

-- ============================================
-- PART 2: App Config Table
-- ============================================

CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Only service role can access
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role only for config"
  ON app_config FOR ALL
  USING (auth.role() = 'service_role');

-- Grant to authenticated for n8n access via service key
GRANT ALL ON app_config TO authenticated;

-- Insert default config values
INSERT INTO app_config (key, value, description) VALUES
  ('admin_activate_secret', 'CHANGE_THIS_' || gen_random_uuid()::TEXT, 'Secret key for admin activation endpoint - CHANGE THIS!'),
  ('payment_jazzcash', '03XX-XXXXXXX', 'JazzCash account number for payments'),
  ('payment_easypaisa', '03XX-XXXXXXX', 'EasyPaisa account number for payments'),
  ('payment_bank_name', 'Bank Name', 'Bank name for transfers'),
  ('payment_bank_account', 'XXXX-XXXXXXXXXX', 'Bank account number'),
  ('payment_bank_title', 'Account Title', 'Bank account title')
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE app_config IS 'Application configuration and secrets';

-- ============================================
-- PART 3: Update pending_signups status constraint
-- ============================================

-- Add 'awaiting_payment' status for manual activation flow
ALTER TABLE pending_signups DROP CONSTRAINT IF EXISTS pending_signups_status_check;
ALTER TABLE pending_signups ADD CONSTRAINT pending_signups_status_check
  CHECK (status IN ('pending', 'payment_started', 'awaiting_payment', 'completed', 'expired', 'cancelled'));

-- Update comment on members_json to reflect new format
COMMENT ON COLUMN pending_signups.members_json IS
  'JSON array of additional people: [{"name": "...", "whatsapp": "...", "role": "member|staff", "language_pref": "en|ur"}]';

-- Extend expiry for manual payment flow (7 days instead of 24 hours for awaiting_payment)
-- This is handled in the workflow, not a DB constraint

-- ============================================
-- PART 4: Helper function to check whitelist
-- ============================================

CREATE OR REPLACE FUNCTION is_whitelisted(phone_number TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM owner_whitelist
    WHERE whatsapp = phone_number
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION is_whitelisted(TEXT) TO authenticated;

COMMENT ON FUNCTION is_whitelisted IS 'Check if a phone number is in the owner whitelist';

-- ============================================
-- PART 5: Helper function to get config value
-- ============================================

CREATE OR REPLACE FUNCTION get_config(config_key TEXT)
RETURNS TEXT AS $$
DECLARE
  config_value TEXT;
BEGIN
  SELECT value INTO config_value
  FROM app_config
  WHERE key = config_key;

  RETURN config_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_config(TEXT) TO authenticated;

COMMENT ON FUNCTION get_config IS 'Get a configuration value by key';

-- ============================================
-- PART 6: Insert sample whitelist entries (CUSTOMIZE THESE!)
-- ============================================

-- IMPORTANT: Replace these with your actual test phone numbers!
-- Format: +[country code][number] (E.164 format)

-- INSERT INTO owner_whitelist (whatsapp, name, notes) VALUES
--   ('+923001234567', 'Owner Name', 'Owner account - full testing'),
--   ('+923009876543', 'Family Test', 'Family member testing');

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Verify tables created:
-- SELECT * FROM owner_whitelist;
-- SELECT * FROM app_config;

-- Test whitelist function:
-- SELECT is_whitelisted('+923001234567');

-- Test config function:
-- SELECT get_config('admin_activate_secret');

-- Check updated status constraint:
-- SELECT conname, pg_get_constraintdef(oid)
-- FROM pg_constraint
-- WHERE conrelid = 'pending_signups'::regclass AND contype = 'c';
