-- Migration 016: Drop dead/unused columns across all tables
-- Removes 12 columns that are not referenced in any workflow.
-- Also updates subscription_dashboard view and drops orphaned index.

-- ============================================
-- 1. HOUSEHOLDS: Drop 6 dead columns
-- ============================================

-- subscription_plan: Empty column, superseded by plan_tier
ALTER TABLE households DROP COLUMN IF EXISTS subscription_plan;

-- address: Never used in any workflow
ALTER TABLE households DROP COLUMN IF EXISTS address;

-- payment_method/provider/customer_id: Not used in any workflow
-- (pending_signups.payment_method is separate and IS used)
ALTER TABLE households DROP COLUMN IF EXISTS payment_method;
ALTER TABLE households DROP COLUMN IF EXISTS payment_provider;
ALTER TABLE households DROP COLUMN IF EXISTS payment_provider_customer_id;

-- stripe_subscription_id: Stripe never implemented
DROP INDEX IF EXISTS idx_households_stripe_subscription;
ALTER TABLE households DROP COLUMN IF EXISTS stripe_subscription_id;

-- ============================================
-- 2. MEMBERS: Drop 1 dead column
-- ============================================

-- language_pref: Members always get English text, value never used
ALTER TABLE members DROP COLUMN IF EXISTS language_pref;

-- ============================================
-- 3. TASKS: Drop 1 dead column
-- ============================================

-- escalated_at: Never set, never read
ALTER TABLE tasks DROP COLUMN IF EXISTS escalated_at;

-- ============================================
-- 4. PENDING_SIGNUPS: Drop 4 dead columns
-- ============================================

-- language_settings_json: Dead since migration 012 simplified languages
ALTER TABLE pending_signups DROP COLUMN IF EXISTS language_settings_json;

-- billing_cycle: Always 'monthly', never read by any workflow
ALTER TABLE pending_signups DROP COLUMN IF EXISTS billing_cycle;

-- stripe_session_id/customer_id: Stripe never implemented
DROP INDEX IF EXISTS idx_pending_signups_stripe_session;
ALTER TABLE pending_signups DROP COLUMN IF EXISTS stripe_session_id;
ALTER TABLE pending_signups DROP COLUMN IF EXISTS stripe_customer_id;

-- ============================================
-- 5. UPDATE SUBSCRIPTION DASHBOARD VIEW
-- ============================================

-- Remove subscription_plan reference, add cap columns instead
DROP VIEW IF EXISTS subscription_dashboard;

CREATE OR REPLACE VIEW subscription_dashboard AS
SELECT
  h.id,
  h.name as household_name,
  h.subscriber_name,
  h.subscriber_whatsapp,
  h.subscriber_email,
  h.subscription_status,
  h.plan_tier,
  h.subscribed_at,
  h.subscription_expires_at,
  h.last_payment_at,
  h.last_payment_amount,
  h.trial_ends_at,
  h.grace_period_ends_at,
  h.cap_tasks_per_day,
  h.cap_messages_per_month,
  CASE
    WHEN h.subscription_status = 'trial' THEN h.trial_ends_at - NOW()
    WHEN h.subscription_status IN ('active', 'past_due') THEN h.subscription_expires_at - NOW()
    ELSE INTERVAL '0 days'
  END as time_remaining,
  (SELECT COUNT(*) FROM tasks t WHERE t.household_id = h.id) as total_tasks,
  (SELECT COUNT(*) FROM members m WHERE m.household_id = h.id) as total_members,
  (SELECT COUNT(*) FROM staff s WHERE s.household_id = h.id) as total_staff
FROM households h;

GRANT SELECT ON subscription_dashboard TO authenticated;
