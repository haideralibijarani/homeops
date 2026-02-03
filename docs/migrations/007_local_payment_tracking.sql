-- Migration 007: Local Payment Tracking for pending_signups
-- Run this in Supabase SQL Editor after migration 006
--
-- Purpose: Add columns to track local payment methods (JazzCash, EasyPaisa, Bank Transfer)
-- since Stripe is deferred to Phase 3 (global expansion)

-- ============================================
-- PART 1: Add payment tracking columns to pending_signups
-- ============================================

-- Which local payment method the user selected
ALTER TABLE pending_signups ADD COLUMN IF NOT EXISTS payment_method TEXT
  CHECK (payment_method IN ('jazzcash', 'easypaisa', 'bank_transfer', NULL));

-- User-provided transaction ID or reference number
ALTER TABLE pending_signups ADD COLUMN IF NOT EXISTS payment_reference TEXT;

-- Amount to pay based on selected plan (in PKR)
ALTER TABLE pending_signups ADD COLUMN IF NOT EXISTS payment_amount DECIMAL(10,2);

-- When admin verified the payment
ALTER TABLE pending_signups ADD COLUMN IF NOT EXISTS payment_confirmed_at TIMESTAMPTZ;

-- Admin notes about the payment verification
ALTER TABLE pending_signups ADD COLUMN IF NOT EXISTS admin_notes TEXT;

-- ============================================
-- PART 2: Indexes for payment tracking queries
-- ============================================

CREATE INDEX IF NOT EXISTS idx_pending_signups_payment_method
  ON pending_signups(payment_method)
  WHERE status = 'awaiting_payment';

CREATE INDEX IF NOT EXISTS idx_pending_signups_awaiting
  ON pending_signups(created_at DESC)
  WHERE status = 'awaiting_payment';

-- ============================================
-- PART 3: Update admin_activate_secret with provided value
-- ============================================

UPDATE app_config
SET value = 'ZazaBazooka1!2020',
    updated_at = NOW()
WHERE key = 'admin_activate_secret';

-- ============================================
-- PART 4: Helper function to get plan price
-- ============================================

CREATE OR REPLACE FUNCTION get_plan_price(plan_name TEXT)
RETURNS DECIMAL(10,2) AS $$
BEGIN
  RETURN CASE plan_name
    WHEN 'starter' THEN 15000.00
    WHEN 'family' THEN 25000.00
    WHEN 'premium' THEN 35000.00
    ELSE 0.00
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

GRANT EXECUTE ON FUNCTION get_plan_price(TEXT) TO authenticated;

COMMENT ON FUNCTION get_plan_price IS 'Get monthly price in PKR for a plan tier';

-- ============================================
-- PART 5: Comments
-- ============================================

COMMENT ON COLUMN pending_signups.payment_method IS 'Local payment method: jazzcash, easypaisa, or bank_transfer';
COMMENT ON COLUMN pending_signups.payment_reference IS 'Transaction ID provided by user for verification';
COMMENT ON COLUMN pending_signups.payment_amount IS 'Payment amount in PKR based on selected plan';
COMMENT ON COLUMN pending_signups.payment_confirmed_at IS 'Timestamp when admin verified the payment';
COMMENT ON COLUMN pending_signups.admin_notes IS 'Admin notes during payment verification';

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check new columns added:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'pending_signups'
-- ORDER BY ordinal_position;

-- Test price function:
-- SELECT get_plan_price('starter'), get_plan_price('family'), get_plan_price('premium');

-- Check admin secret was updated:
-- SELECT * FROM app_config WHERE key = 'admin_activate_secret';
