-- Migration 005: Onboarding System
-- Run this in Supabase SQL Editor after migrations 001-004

-- ============================================
-- PART 1: New pending_signups table
-- ============================================

CREATE TABLE IF NOT EXISTS pending_signups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Subscriber info
  subscriber_name TEXT NOT NULL,
  subscriber_whatsapp TEXT NOT NULL,
  subscriber_email TEXT NOT NULL,

  -- Household info
  household_name TEXT NOT NULL,
  timezone TEXT DEFAULT 'Asia/Karachi',
  address TEXT,
  language_pref TEXT DEFAULT 'en',

  -- Members to create (JSON array)
  -- Format: [{"name": "...", "whatsapp": "...", "role": "member"}, ...]
  members_json JSONB DEFAULT '[]'::JSONB,

  -- Plan selection
  selected_plan TEXT NOT NULL CHECK (selected_plan IN ('starter', 'family', 'premium')),
  billing_cycle TEXT DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly')),

  -- Stripe session tracking
  stripe_session_id TEXT,
  stripe_customer_id TEXT,

  -- Status tracking
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'payment_started', 'completed', 'expired', 'cancelled')),

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
  completed_at TIMESTAMPTZ
);

-- Indexes for pending_signups
CREATE INDEX IF NOT EXISTS idx_pending_signups_whatsapp ON pending_signups(subscriber_whatsapp);
CREATE INDEX IF NOT EXISTS idx_pending_signups_stripe_session ON pending_signups(stripe_session_id);
CREATE INDEX IF NOT EXISTS idx_pending_signups_status ON pending_signups(status);
CREATE INDEX IF NOT EXISTS idx_pending_signups_expires_at ON pending_signups(expires_at);

-- ============================================
-- PART 2: Households table additions
-- ============================================

-- Stripe subscription tracking
ALTER TABLE households ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT;

-- Plan tier (starter, family, premium)
ALTER TABLE households ADD COLUMN IF NOT EXISTS plan_tier TEXT DEFAULT 'starter'
  CHECK (plan_tier IN ('starter', 'family', 'premium'));

-- Member limit based on plan
ALTER TABLE households ADD COLUMN IF NOT EXISTS max_members INTEGER DEFAULT 3;

-- Onboarding tracking
ALTER TABLE households ADD COLUMN IF NOT EXISTS onboarded_at TIMESTAMPTZ;
ALTER TABLE households ADD COLUMN IF NOT EXISTS onboarding_source TEXT DEFAULT 'whatsapp';

-- Language preference
ALTER TABLE households ADD COLUMN IF NOT EXISTS language_pref TEXT DEFAULT 'en';

-- Address
ALTER TABLE households ADD COLUMN IF NOT EXISTS address TEXT;

-- Index for Stripe subscription lookup
CREATE INDEX IF NOT EXISTS idx_households_stripe_subscription ON households(stripe_subscription_id);

-- ============================================
-- PART 3: Helper function to auto-expire signups
-- ============================================

CREATE OR REPLACE FUNCTION expire_old_signups()
RETURNS INTEGER AS $$
DECLARE
  expired_count INTEGER;
BEGIN
  UPDATE pending_signups
  SET status = 'expired'
  WHERE status IN ('pending', 'payment_started')
    AND expires_at < NOW();

  GET DIAGNOSTICS expired_count = ROW_COUNT;
  RETURN expired_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Update payments table plan check
-- ============================================

-- Update plan check to include new plan tiers
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_plan_check;
ALTER TABLE payments ADD CONSTRAINT payments_plan_check
  CHECK (plan IN ('monthly', 'annual', 'starter', 'family', 'premium'));

-- ============================================
-- PART 5: Permissions
-- ============================================

GRANT ALL ON pending_signups TO authenticated;
GRANT EXECUTE ON FUNCTION expire_old_signups() TO authenticated;

-- ============================================
-- Comments
-- ============================================

COMMENT ON TABLE pending_signups IS 'Temporary storage for signup data while waiting for payment completion';
COMMENT ON COLUMN pending_signups.members_json IS 'JSON array of additional members: [{"name": "...", "whatsapp": "..."}]';
COMMENT ON COLUMN pending_signups.status IS 'pending=awaiting payment, payment_started=redirected to Stripe, completed=household created, expired=24h timeout, cancelled=user cancelled';
COMMENT ON COLUMN households.plan_tier IS 'starter=3 members, family=6 members, premium=12 members';
COMMENT ON COLUMN households.max_members IS 'Maximum household members allowed by plan';
