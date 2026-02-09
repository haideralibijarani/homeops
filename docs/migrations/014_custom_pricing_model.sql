-- Migration 014: Custom pricing model
-- Replaces fixed plan tiers (starter/family/premium) with customizable pricing.
-- Base PKR 15,000 (3 people) + PKR 5,000/extra person + PKR 5,000/staff voice notes.
-- No member limit.

-- 1. Update households.plan_tier CHECK to accept 'custom'
ALTER TABLE households DROP CONSTRAINT IF EXISTS households_plan_tier_check;
ALTER TABLE households ADD CONSTRAINT households_plan_tier_check
  CHECK (plan_tier IN ('starter', 'family', 'premium', 'custom'));

-- Set existing households to custom (optional - only if you want to migrate)
-- UPDATE households SET plan_tier = 'custom', max_members = 999 WHERE plan_tier IN ('starter', 'family', 'premium');

-- 2. Update pending_signups.selected_plan CHECK to accept 'custom'
ALTER TABLE pending_signups DROP CONSTRAINT IF EXISTS pending_signups_selected_plan_check;
ALTER TABLE pending_signups ADD CONSTRAINT pending_signups_selected_plan_check
  CHECK (selected_plan IN ('starter', 'family', 'premium', 'custom'));

-- 3. Update payments.plan CHECK to accept 'custom'
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_plan_check;
ALTER TABLE payments ADD CONSTRAINT payments_plan_check
  CHECK (plan IN ('monthly', 'annual', 'starter', 'family', 'premium', 'custom'));

-- 4. Update get_plan_price function to handle 'custom'
CREATE OR REPLACE FUNCTION get_plan_price(plan_name TEXT)
RETURNS DECIMAL(10,2) AS $$
BEGIN
  RETURN CASE plan_name
    WHEN 'starter' THEN 15000.00
    WHEN 'family' THEN 25000.00
    WHEN 'premium' THEN 35000.00
    WHEN 'custom' THEN 15000.00  -- Base price; actual total varies per household
    ELSE 0.00
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 5. Update comments
COMMENT ON COLUMN households.plan_tier IS 'Plan type: custom (base+addons), or legacy starter/family/premium';
COMMENT ON COLUMN households.max_members IS 'Maximum household people. 999 = unlimited (custom plan)';
