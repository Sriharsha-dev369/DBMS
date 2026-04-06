-- Migration 008: PL/pgSQL proration function
-- Calculates the credit owed when a customer changes plans mid-billing-cycle.
-- Key DBMS concepts:
--   * PL/pgSQL scalar function (callable in SELECT or within transactions)
--   * NUMERIC(12,2) precision for currency — never FLOAT
--   * EXTRACT(EPOCH) for timezone-safe date arithmetic (avoids DST edge cases)
--   * RAISE EXCEPTION for input validation at the DB layer
--   * IMMUTABLE — deterministic for same inputs, optimizer can cache/fold
-- ============================================================

-- @UP

CREATE OR REPLACE FUNCTION calculate_proration(
    p_plan_price     NUMERIC(12,2),
    p_period_start   TIMESTAMPTZ,
    p_period_end     TIMESTAMPTZ,
    p_change_date    TIMESTAMPTZ
) RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
AS $$
DECLARE
    v_total_seconds     DOUBLE PRECISION;
    v_remaining_seconds DOUBLE PRECISION;
BEGIN
    -- Guard: period must be a forward interval
    v_total_seconds := EXTRACT(EPOCH FROM p_period_end - p_period_start);
    IF v_total_seconds <= 0 THEN
        RAISE EXCEPTION 'period_end must be after period_start';
    END IF;

    -- Guard: change_date must fall within [period_start, period_end]
    IF p_change_date < p_period_start OR p_change_date > p_period_end THEN
        RAISE EXCEPTION 'change_date must be within the billing period';
    END IF;

    -- Remaining time from change_date to period_end
    v_remaining_seconds := EXTRACT(EPOCH FROM p_period_end - p_change_date);

    -- Credit = price * (remaining / total), rounded to 2 decimal places
    RETURN ROUND((p_plan_price * (v_remaining_seconds / v_total_seconds))::NUMERIC, 2);
END;
$$;

-- Grant to app role (created after migration 005's blanket GRANT)
GRANT EXECUTE ON FUNCTION calculate_proration(NUMERIC, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ)
    TO saasledger_app;


-- @DOWN

REVOKE EXECUTE ON FUNCTION calculate_proration(NUMERIC, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ)
    FROM saasledger_app;

DROP FUNCTION IF EXISTS calculate_proration(NUMERIC, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ);
