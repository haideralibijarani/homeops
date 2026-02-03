-- Migration: Add subscription management to households table
-- Run this in Supabase SQL Editor

-- Add subscriber details and subscription columns to households table
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscriber_name TEXT;
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscriber_whatsapp TEXT;
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscriber_email TEXT;
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscribed_at TIMESTAMPTZ;

-- Subscription status and plan
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial'
  CHECK (subscription_status IN ('trial', 'active', 'past_due', 'cancelled', 'expired'));
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscription_plan TEXT
  CHECK (subscription_plan IN ('monthly', 'annual', NULL));
ALTER TABLE households ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ;

-- Payment tracking
ALTER TABLE households ADD COLUMN IF NOT EXISTS last_payment_at TIMESTAMPTZ;
ALTER TABLE households ADD COLUMN IF NOT EXISTS last_payment_amount DECIMAL(10,2);
ALTER TABLE households ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE households ADD COLUMN IF NOT EXISTS payment_provider TEXT; -- 'stripe', 'jazzcash', 'easypaisa', etc.
ALTER TABLE households ADD COLUMN IF NOT EXISTS payment_provider_customer_id TEXT; -- External customer ID

-- Trial period
ALTER TABLE households ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ;

-- Grace period for failed payments (e.g., 3 days after due date)
ALTER TABLE households ADD COLUMN IF NOT EXISTS grace_period_ends_at TIMESTAMPTZ;

-- Create payments table for payment history
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'PKR',
  status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  payment_method TEXT,
  payment_provider TEXT,
  provider_payment_id TEXT, -- Transaction ID from payment provider
  provider_response JSONB, -- Full response from provider for debugging
  plan TEXT CHECK (plan IN ('monthly', 'annual')),
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  failure_reason TEXT
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_payments_household_id ON payments(household_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at);
CREATE INDEX IF NOT EXISTS idx_households_subscription_status ON households(subscription_status);
CREATE INDEX IF NOT EXISTS idx_households_subscription_expires_at ON households(subscription_expires_at);

-- Create function to check and update subscription status
CREATE OR REPLACE FUNCTION check_subscription_status()
RETURNS TRIGGER AS $$
BEGIN
  -- If subscription has expired and no grace period
  IF NEW.subscription_expires_at < NOW() AND
     (NEW.grace_period_ends_at IS NULL OR NEW.grace_period_ends_at < NOW()) THEN
    NEW.subscription_status := 'expired';
  -- If in grace period
  ELSIF NEW.subscription_expires_at < NOW() AND
        NEW.grace_period_ends_at IS NOT NULL AND
        NEW.grace_period_ends_at >= NOW() THEN
    NEW.subscription_status := 'past_due';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-update status on changes
DROP TRIGGER IF EXISTS trigger_check_subscription ON households;
CREATE TRIGGER trigger_check_subscription
  BEFORE UPDATE ON households
  FOR EACH ROW
  EXECUTE FUNCTION check_subscription_status();

-- View for subscription dashboard
CREATE OR REPLACE VIEW subscription_dashboard AS
SELECT
  h.id,
  h.name as household_name,
  h.subscriber_name,
  h.subscriber_whatsapp,
  h.subscriber_email,
  h.subscription_status,
  h.subscription_plan,
  h.subscribed_at,
  h.subscription_expires_at,
  h.last_payment_at,
  h.last_payment_amount,
  h.trial_ends_at,
  h.grace_period_ends_at,
  CASE
    WHEN h.subscription_status = 'trial' THEN h.trial_ends_at - NOW()
    WHEN h.subscription_status IN ('active', 'past_due') THEN h.subscription_expires_at - NOW()
    ELSE INTERVAL '0 days'
  END as time_remaining,
  (SELECT COUNT(*) FROM tasks t WHERE t.household_id = h.id) as total_tasks,
  (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as total_members,
  (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as total_staff
FROM households h;

-- Grant permissions
GRANT SELECT ON subscription_dashboard TO authenticated;
GRANT ALL ON payments TO authenticated;

COMMENT ON TABLE payments IS 'Payment history for household subscriptions';
COMMENT ON COLUMN households.subscription_status IS 'trial=new user, active=paid, past_due=in grace period, cancelled=user cancelled, expired=payment failed';
