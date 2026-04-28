-- ============================================================
--  SentinelDB  |  Module 3: Stored Procedures & Views
-- ============================================================
--
--  DBMS CONCEPT: Stored Procedure vs Function vs Trigger
--
--  FUNCTION:   Returns a value. Called inside SQL queries.
--              SELECT my_function(arg);
--
--  PROCEDURE:  Performs actions (INSERT/UPDATE/etc).
--              Does NOT return a value. Called with CALL.
--              CALL my_procedure(arg);
--              Can COMMIT/ROLLBACK inside (functions cannot).
--
--  TRIGGER:    A function that runs automatically on events.
--              You never call it manually.
--
--  Use procedures for business logic that:
--    - spans multiple tables
--    - needs explicit transaction control
--    - must be reusable from the app layer
-- ============================================================


-- ============================================================
--  PROCEDURE 1: Compute Risk Score & Auto-Suspend
--
--  Business logic: recalculate a user's risk score based on
--  their recent transaction history, then suspend them if
--  score crosses the critical threshold (85).
--
--  Call from Python: cursor.callproc('sp_evaluate_user_risk', [user_id])
--  Or from psql:     CALL sp_evaluate_user_risk(3);
--
--  DBMS CONCEPTS:
--    - TRANSACTION blocks (BEGIN / COMMIT / ROLLBACK)
--    - EXCEPTION handling
--    - Multiple UPDATE statements in one atomic unit
--    - OUT parameters for returning status
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_evaluate_user_risk(
    p_user_id       INT,
    OUT p_new_score NUMERIC,
    OUT p_action    TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_score         NUMERIC := 0;
    v_alert_count   INT;
    v_high_alerts   INT;
    v_daily_total   NUMERIC;
    v_spend_limit   NUMERIC;
    v_current_status VARCHAR;
BEGIN
    -- Verify user exists
    SELECT Account_Status, Daily_Spending_Limit
    INTO   v_current_status, v_spend_limit
    FROM   Users
    WHERE  UserID = p_user_id
    FOR UPDATE;    -- LOCK the row so concurrent calls don't race

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % does not exist', p_user_id;
    END IF;

    -- --------------------------------------------------------
    --  Score Component 1: Alert history (last 30 days)
    --  Every Medium alert = +5 pts
    --  Every High alert   = +15 pts
    --  Every Critical     = +25 pts
    -- --------------------------------------------------------
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE Severity IN ('High', 'Critical'))
    INTO v_alert_count, v_high_alerts
    FROM Fraud_Alerts
    WHERE UserID = p_user_id
    AND   Alert_Timestamp >= NOW() - INTERVAL '30 days';

    v_score := v_score
             + (v_alert_count - v_high_alerts) * 5   -- medium alerts
             + v_high_alerts * 20;                    -- high/critical alerts

    -- --------------------------------------------------------
    --  Score Component 2: Today's spending vs limit
    --  If they've spent > 80% of limit today → +10 pts
    --  If they've spent > 100% (exceeded limit) → +20 pts
    -- --------------------------------------------------------
    SELECT COALESCE(SUM(Amount), 0)
    INTO   v_daily_total
    FROM   Transactions
    WHERE  UserID        = p_user_id
    AND    Txn_Timestamp >= CURRENT_DATE
    AND    Txn_Status    = 'Completed';

    IF v_spend_limit > 0 THEN
        IF v_daily_total > v_spend_limit THEN
            v_score := v_score + 20;
        ELSIF v_daily_total > v_spend_limit * 0.8 THEN
            v_score := v_score + 10;
        END IF;
    END IF;

    -- --------------------------------------------------------
    --  Score Component 3: Any Critical alert in last 24h?
    --  If yes, slam 30 points on top.
    -- --------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM Fraud_Alerts
        WHERE  UserID    = p_user_id
        AND    Severity  = 'Critical'
        AND    Alert_Timestamp >= NOW() - INTERVAL '24 hours'
    ) THEN
        v_score := v_score + 30;
    END IF;

    -- Cap score at 100
    v_score := LEAST(v_score, 100);
    p_new_score := v_score;

    -- --------------------------------------------------------
    --  Update User record
    -- --------------------------------------------------------
    UPDATE Users
    SET
        Risk_Score = v_score,
        Risk_Level = CASE
                        WHEN v_score >= 75 THEN 'High'
                        WHEN v_score >= 40 THEN 'Medium'
                        ELSE 'Low'
                     END,
        Account_Status = CASE
                            WHEN v_score >= 85 AND Account_Status = 'Active'
                            THEN 'Suspended'
                            ELSE Account_Status
                         END
    WHERE UserID = p_user_id
    RETURNING Account_Status INTO v_current_status;

    -- Determine what action was taken
    IF v_score >= 85 THEN
        p_action := 'SUSPENDED — risk score ' || ROUND(v_score, 0)::TEXT || ' exceeded threshold (85)';

        -- Log the auto-suspension as a critical alert
        INSERT INTO Fraud_Alerts (UserID, Alert_Type, Severity, Description)
        VALUES (
            p_user_id,
            'AUTO_SUSPENSION',
            'Critical',
            'Account auto-suspended. Risk score: ' || ROUND(v_score, 0)::TEXT || '. ' ||
            'Alerts last 30d: ' || v_alert_count::TEXT || ' (of which ' || v_high_alerts::TEXT || ' High/Critical). ' ||
            'Today''s spend: ' || v_daily_total::TEXT || ' of limit ' || v_spend_limit::TEXT
        );
    ELSIF v_score >= 40 THEN
        p_action := 'FLAGGED — risk score ' || ROUND(v_score, 0)::TEXT || ' is elevated';
    ELSE
        p_action := 'OK — risk score ' || ROUND(v_score, 0)::TEXT || ' is normal';
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- In procedures, we can explicitly rollback
        RAISE NOTICE 'Error evaluating risk for user %: %', p_user_id, SQLERRM;
        RAISE;
END;
$$;


-- ============================================================
--  PROCEDURE 2: Bulk Risk Evaluation (runs for ALL users)
--
--  Called nightly by a scheduler (cron / pg_cron).
--  Loops through all Active users and calls sp_evaluate_user_risk.
--
--  DBMS CONCEPTS:
--    - Cursor / FOR loop over a query result
--    - Calling one procedure from another
--    - RAISE NOTICE for logging
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_bulk_risk_evaluation()
LANGUAGE plpgsql
AS $$
DECLARE
    v_user          RECORD;
    v_score         NUMERIC;
    v_action        TEXT;
    v_processed     INT := 0;
    v_suspended     INT := 0;
BEGIN
    RAISE NOTICE 'Starting bulk risk evaluation at %', NOW();

    -- Loop over every Active or Flagged user
    FOR v_user IN
        SELECT UserID, Name FROM Users
        WHERE  Account_Status IN ('Active', 'Flagged')
        ORDER  BY Risk_Score DESC   -- process highest risk first
    LOOP
        CALL sp_evaluate_user_risk(v_user.UserID, v_score, v_action);
        v_processed := v_processed + 1;

        IF v_action LIKE 'SUSPENDED%' THEN
            v_suspended := v_suspended + 1;
            RAISE NOTICE 'User % (%) → %', v_user.UserID, v_user.Name, v_action;
        END IF;
    END LOOP;

    RAISE NOTICE 'Bulk evaluation complete. Processed: %, Suspended: %',
                 v_processed, v_suspended;
END;
$$;


-- ============================================================
--  PROCEDURE 3: Manual Alert Review
--
--  Called when an analyst marks an alert as reviewed.
--  If the user has no unreviewed alerts left, their risk
--  score gets reduced by 10 points (trust restored).
--
--  DBMS CONCEPTS:
--    - UPDATE with subquery
--    - Conditional logic after DML
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_review_alert(
    p_alert_id  INT,
    p_analyst   VARCHAR DEFAULT 'system'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id           INT;
    v_unreviewed_count  INT;
BEGIN
    -- Mark the alert as reviewed
    UPDATE Fraud_Alerts
    SET    Is_Reviewed = TRUE
    WHERE  AlertID = p_alert_id
    RETURNING UserID INTO v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alert % not found', p_alert_id;
    END IF;

    -- Log the review action
    INSERT INTO Audit_Log (Table_Name, Operation, Record_ID, New_Values)
    VALUES ('Fraud_Alerts', 'UPDATE', p_alert_id,
            'Reviewed by ' || p_analyst || ' at ' || NOW()::TEXT);

    -- Count remaining unreviewed alerts for this user
    SELECT COUNT(*) INTO v_unreviewed_count
    FROM   Fraud_Alerts
    WHERE  UserID = v_user_id AND Is_Reviewed = FALSE;

    -- If all clear, slightly reduce risk score
    IF v_unreviewed_count = 0 THEN
        UPDATE Users
        SET    Risk_Score = GREATEST(Risk_Score - 10, 0),
               Risk_Level = CASE
                               WHEN GREATEST(Risk_Score - 10, 0) >= 75 THEN 'High'
                               WHEN GREATEST(Risk_Score - 10, 0) >= 40 THEN 'Medium'
                               ELSE 'Low'
                            END,
               Account_Status = CASE
                                   WHEN Account_Status = 'Suspended'
                                        AND GREATEST(Risk_Score - 10, 0) < 85
                                   THEN 'Active'
                                   ELSE Account_Status
                                END
        WHERE  UserID = v_user_id;

        RAISE NOTICE 'All alerts reviewed for user %. Risk score reduced.', v_user_id;
    END IF;
END;
$$;


-- ============================================================
--  VIEWS — Named stored queries
--
--  DBMS CONCEPT: A VIEW is a saved SELECT query. It looks
--  like a table to the app but it's computed on the fly.
--
--  Benefits:
--    1. Security: expose only certain columns to the app
--    2. Simplicity: complex joins written once, reused forever
--    3. Abstraction: if schema changes, update only the view
--
--  MATERIALIZED VIEW (bonus): like a view but the result is
--  stored on disk and refreshed manually. Much faster for
--  expensive analytics queries run by the dashboard.
-- ============================================================

-- View 1: Active fraud alerts with user and transaction info
CREATE OR REPLACE VIEW vw_active_alerts AS
SELECT
    fa.AlertID,
    fa.Alert_Timestamp,
    fa.Alert_Type,
    fa.Severity,
    fa.Description,
    fa.Is_Reviewed,
    u.UserID,
    u.Name          AS User_Name,
    u.Email,
    u.Account_Status,
    u.Risk_Score,
    u.Risk_Level,
    t.Amount,
    t.Merchant,
    t.Location_City,
    t.Txn_Type,
    t.Txn_Timestamp
FROM  Fraud_Alerts fa
JOIN  Users u ON fa.UserID = u.UserID
LEFT  JOIN Transactions t ON fa.TxnID = t.TxnID
ORDER BY fa.Alert_Timestamp DESC;


-- View 2: User risk summary (for the dashboard's overview panel)
CREATE OR REPLACE VIEW vw_user_risk_summary AS
SELECT
    u.UserID,
    u.Name,
    u.Email,
    u.Account_Status,
    u.Risk_Level,
    u.Risk_Score,
    u.Daily_Spending_Limit,
    COUNT(DISTINCT t.TxnID)                             AS Total_Transactions,
    COALESCE(SUM(t.Amount) FILTER (
        WHERE t.Txn_Timestamp >= CURRENT_DATE), 0)      AS Today_Spent,
    COUNT(fa.AlertID) FILTER (
        WHERE fa.Is_Reviewed = FALSE)                   AS Unreviewed_Alerts,
    COUNT(fa.AlertID) FILTER (
        WHERE fa.Severity = 'Critical')                 AS Critical_Alerts,
    MAX(t.Txn_Timestamp)                                AS Last_Transaction
FROM  Users u
LEFT  JOIN Transactions t  ON u.UserID = t.UserID
LEFT  JOIN Fraud_Alerts fa ON u.UserID = fa.UserID
GROUP BY u.UserID, u.Name, u.Email, u.Account_Status,
         u.Risk_Level, u.Risk_Score, u.Daily_Spending_Limit;


-- Materialized View: Daily fraud stats (refresh once a day)
CREATE MATERIALIZED VIEW IF NOT EXISTS mvw_daily_fraud_stats AS
SELECT
    DATE(fa.Alert_Timestamp)    AS Alert_Date,
    fa.Alert_Type,
    fa.Severity,
    COUNT(*)                    AS Alert_Count,
    COUNT(DISTINCT fa.UserID)   AS Affected_Users,
    AVG(t.Amount)               AS Avg_Txn_Amount
FROM  Fraud_Alerts fa
LEFT  JOIN Transactions t ON fa.TxnID = t.TxnID
GROUP BY DATE(fa.Alert_Timestamp), fa.Alert_Type, fa.Severity
ORDER BY Alert_Date DESC, Alert_Count DESC;

-- To refresh: REFRESH MATERIALIZED VIEW mvw_daily_fraud_stats;
-- Schedule this daily with pg_cron or a cron job.
