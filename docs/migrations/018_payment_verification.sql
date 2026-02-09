-- Migration 018: Payment verification and expected amount tracking
-- Adds expected_monthly_amount to households, classification columns to payments,
-- and Postgres functions to calculate/store expected amounts.

-- ============================================
-- 1. HOUSEHOLDS: Expected monthly amount
-- ============================================

-- Single source of truth for what this household owes next month
ALTER TABLE households ADD COLUMN IF NOT EXISTS expected_monthly_amount DECIMAL(10,2);

COMMENT ON COLUMN households.expected_monthly_amount IS 'Expected monthly payment including base plan + add-ons (extra people, voice notes)';

-- ============================================
-- 2. PAYMENTS: Classification columns
-- ============================================

-- What was expected when this payment was made
ALTER TABLE payments ADD COLUMN IF NOT EXISTS expected_amount DECIMAL(10,2);

-- How the payment was classified relative to expected amount
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_classification TEXT
  CHECK (payment_classification IN ('full', 'base_only', 'partial', 'overpayment', 'unknown'));

-- What add-ons were activated by this payment
ALTER TABLE payments ADD COLUMN IF NOT EXISTS addons_activated JSONB;

-- Payment proof URL (screenshot from WhatsApp)
ALTER TABLE payments ADD COLUMN IF NOT EXISTS proof_url TEXT;

COMMENT ON COLUMN payments.expected_amount IS 'Expected monthly amount at time of payment for audit trail';
COMMENT ON COLUMN payments.payment_classification IS 'full=covers all, base_only=plan only, partial=incomplete, overpayment=exceeds expected';
COMMENT ON COLUMN payments.addons_activated IS 'JSON record of add-ons activated by this payment (e.g., voice staff names)';
COMMENT ON COLUMN payments.proof_url IS 'URL of payment proof screenshot from WhatsApp MediaUrl';

-- ============================================
-- 3. FUNCTION: calculate_expected_amount
-- ============================================

-- Returns a detailed breakdown of what a household should pay
CREATE OR REPLACE FUNCTION calculate_expected_amount(p_household_id UUID)
RETURNS TABLE (
  base_amount DECIMAL(10,2),
  extra_people_count INTEGER,
  extra_people_cost DECIMAL(10,2),
  voice_staff_count INTEGER,
  voice_cost DECIMAL(10,2),
  total_amount DECIMAL(10,2),
  breakdown TEXT
) AS $$
DECLARE
  v_plan_tier TEXT;
  v_base_price DECIMAL(10,2);
  v_included_people INTEGER;
  v_total_people INTEGER;
  v_member_count INTEGER;
  v_staff_count INTEGER;
  v_extra_people INTEGER;
  v_extra_cost DECIMAL(10,2);
  v_voice_count INTEGER;
  v_voice_price DECIMAL(10,2);
  v_voice_included BOOLEAN;
  v_total DECIMAL(10,2);
  v_parts TEXT[];
BEGIN
  -- Get plan tier
  SELECT h.plan_tier INTO v_plan_tier
  FROM households h WHERE h.id = p_household_id;

  IF v_plan_tier IS NULL THEN
    RETURN QUERY SELECT 0::DECIMAL(10,2), 0, 0::DECIMAL(10,2), 0, 0::DECIMAL(10,2), 0::DECIMAL(10,2), 'Household not found'::TEXT;
    RETURN;
  END IF;

  -- Get base price
  v_base_price := get_plan_price(v_plan_tier);

  -- Determine included people and voice pricing by plan
  CASE v_plan_tier
    WHEN 'essential' THEN
      v_included_people := 5;
      v_voice_included := false;
      v_voice_price := 7000.00;
    WHEN 'pro' THEN
      v_included_people := 8;
      v_voice_included := true;
      v_voice_price := 0.00;
    WHEN 'max' THEN
      v_included_people := 15;
      v_voice_included := true;
      v_voice_price := 0.00;
    ELSE
      -- Legacy plans: use essential pricing
      v_included_people := 5;
      v_voice_included := false;
      v_voice_price := 7000.00;
  END CASE;

  -- Count people (members + staff)
  SELECT COUNT(*) INTO v_member_count FROM members m WHERE m.household_id = p_household_id;
  SELECT COUNT(*) INTO v_staff_count FROM staff s WHERE s.household_id = p_household_id;
  v_total_people := v_member_count + v_staff_count;

  -- Extra people beyond included
  v_extra_people := GREATEST(0, v_total_people - v_included_people);
  v_extra_cost := v_extra_people * 5000.00;

  -- Voice staff count (enabled OR pending payment — both are billable)
  IF v_voice_included THEN
    v_voice_count := 0;
  ELSE
    SELECT COUNT(*) INTO v_voice_count
    FROM staff s
    WHERE s.household_id = p_household_id
      AND (s.voice_notes_enabled = true OR s.voice_payment_pending = true);
  END IF;

  -- Calculate total
  v_total := v_base_price + v_extra_cost + (v_voice_count * v_voice_price);

  -- Build breakdown string
  v_parts := ARRAY['Base ' || v_base_price::INTEGER::TEXT];
  IF v_extra_people > 0 THEN
    v_parts := v_parts || (v_extra_people || ' extra ' || CASE WHEN v_extra_people = 1 THEN 'person' ELSE 'people' END || ': ' || v_extra_cost::INTEGER::TEXT);
  END IF;
  IF v_voice_count > 0 THEN
    v_parts := v_parts || (v_voice_count || ' voice ' || CASE WHEN v_voice_count = 1 THEN 'staff' ELSE 'staff' END || ': ' || (v_voice_count * v_voice_price::INTEGER)::TEXT);
  END IF;

  RETURN QUERY SELECT
    v_base_price,
    v_extra_people,
    v_extra_cost,
    v_voice_count,
    (v_voice_count * v_voice_price),
    v_total,
    array_to_string(v_parts, ' + ');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION calculate_expected_amount(UUID) TO authenticated;

-- ============================================
-- 4. FUNCTION: recalculate_and_store_expected_amount
-- ============================================

-- Wrapper that calculates and persists the expected amount
CREATE OR REPLACE FUNCTION recalculate_and_store_expected_amount(p_household_id UUID)
RETURNS DECIMAL(10,2) AS $$
DECLARE
  v_total DECIMAL(10,2);
BEGIN
  SELECT cea.total_amount INTO v_total
  FROM calculate_expected_amount(p_household_id) cea;

  UPDATE households
  SET expected_monthly_amount = v_total
  WHERE id = p_household_id;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION recalculate_and_store_expected_amount(UUID) TO authenticated;

-- ============================================
-- 5. BACKFILL existing households
-- ============================================

-- Calculate and store expected amount for all active households
DO $$
DECLARE
  h RECORD;
BEGIN
  FOR h IN SELECT id FROM households WHERE subscription_status IN ('trial', 'active', 'past_due')
  LOOP
    PERFORM recalculate_and_store_expected_amount(h.id);
  END LOOP;
END;
$$;

-- ============================================
-- 6. COMMENTS
-- ============================================

COMMENT ON FUNCTION calculate_expected_amount IS 'Calculate expected monthly payment breakdown for a household (base + extra people + voice add-ons)';
COMMENT ON FUNCTION recalculate_and_store_expected_amount IS 'Calculate and persist expected_monthly_amount on households table';
