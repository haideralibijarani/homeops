-- Migration 017: Voice notes payment tracking on staff table
-- Adds columns to track pending voice note activation payments
-- for Essential plan add-on (PKR 7,000/staff/month).

-- ============================================
-- 1. STAFF: Voice payment tracking columns
-- ============================================

-- Whether a voice activation payment is pending for this staff
ALTER TABLE staff ADD COLUMN IF NOT EXISTS voice_payment_pending BOOLEAN DEFAULT false;

-- Payment reference provided by admin (e.g., "TXN12345")
ALTER TABLE staff ADD COLUMN IF NOT EXISTS voice_payment_ref TEXT;

-- URL of payment proof screenshot (Twilio MediaUrl)
ALTER TABLE staff ADD COLUMN IF NOT EXISTS voice_payment_proof_url TEXT;

-- When the voice activation was requested (for tracking/expiry)
ALTER TABLE staff ADD COLUMN IF NOT EXISTS voice_payment_requested_at TIMESTAMPTZ;

-- ============================================
-- 2. COMMENTS
-- ============================================

COMMENT ON COLUMN staff.voice_payment_pending IS 'True when admin requested voice activation on Essential plan but payment not yet verified';
COMMENT ON COLUMN staff.voice_payment_ref IS 'Payment reference number provided by admin for voice activation';
COMMENT ON COLUMN staff.voice_payment_proof_url IS 'URL of payment proof screenshot from Twilio MediaUrl';
COMMENT ON COLUMN staff.voice_payment_requested_at IS 'When voice activation was requested, for tracking pending payments';
