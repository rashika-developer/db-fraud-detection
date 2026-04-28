-- ============================================================
--  SentinelDB  |  Module 2: Triggers (PL/pgSQL)
-- ============================================================
--
--  DBMS CONCEPT: What is a Trigger?
--  A trigger is a function the DB engine calls AUTOMATICALLY
--  when a specific event (INSERT / UPDATE / DELETE) happens
--  on a specific table. You never call a trigger manually.
--
--  Trigger anatomy:
--    1. TRIGGER FUNCTION  — written in PL/pgSQL, contains logic
--    2. TRIGGER BINDING   — attaches the function to a table/event
--
--  Special variables inside trigger functions:
--    NEW  — the new row being inserted or updated
--    OLD  — the old row (available in UPDATE and DELETE triggers)
--    TG_OP — the operation: 'INSERT', 'UPDATE', or 'DELETE'
--
--  BEFORE vs AFTER triggers:
--    BEFORE: fires before the row hits the table. You can
--            modify NEW or abort with RETURN NULL.
--    AFTER:  fires after the row is committed. Good for logging
--            or inserting into other tables.
-- ============================================================


-- ============================================================
--  TRIGGER 1: Velocity Check
--
--  RULE: If a user makes more than 5 transactions within
--  any rolling 10-minute window, flag it as fraud.
--
--  WHY IN THE DB? If this logic lived in the app layer, a
--  clever attacker could bypass it by hitting the DB directly.
--  Inside the DB, there's no way around the trigger.
--
--  DBMS CONCEPTS USED:
--    - COUNT() aggregate inside a subquery
--    - NOW() - INTERVAL '10 minutes' for time arithmetic
--    - PERFORM to call a procedure without capturing output
-- ============================================================

CREATE OR REPLACE FUNCTION fn_velocity_check()
RETURNS TRIGGER AS $$
DECLARE
    v_txn_count     INT;
    v_alert_desc    TEXT;
BEGIN
    -- Count how many transactions this user has made in the last 10 minutes
    -- We query BEFORE the current INSERT is finalized, so count >= 5 means
    -- this insert makes it 6 (the threshold).
    SELECT COUNT(*)
    INTO   v_txn_count
    FROM   Transactions
    WHERE  UserID        = NEW.UserID
    AND    Txn_Timestamp >= NOW() - INTERVAL '10 minutes';

    IF v_txn_count >= 5 THEN
        v_alert_desc := 'Velocity breach: ' || (v_txn_count + 1)::TEXT || 
                        ' transactions in 10 minutes. Latest TxnID will be ' || NEW.TxnID::TEXT || 
                        '. Amount: ' || NEW.Amount::TEXT;

        -- Insert a fraud alert
        INSERT INTO Fraud_Alerts (TxnID, UserID, Alert_Type, Severity, Description)
        VALUES (
            NEW.TxnID,
            NEW.UserID,
            'VELOCITY_BREACH',
            'High',
            v_alert_desc
        );

        -- Flag the transaction itself
        NEW.Is_Flagged := TRUE;

        -- Bump the user's risk score by 15 points (cap at 100)
        UPDATE Users
        SET    Risk_Score = LEAST(Risk_Score + 15, 100),
               Risk_Level = CASE
                                WHEN LEAST(Risk_Score + 15, 100) >= 75 THEN 'High'
                                WHEN LEAST(Risk_Score + 15, 100) >= 40 THEN 'Medium'
                                ELSE 'Low'
                            END
        WHERE  UserID = NEW.UserID;
    END IF;

    -- RETURN NEW is mandatory for BEFORE triggers.
    -- Returning the (possibly modified) NEW row lets it proceed.
    -- RETURN NULL would cancel the INSERT entirely.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bind the function to the Transactions table
CREATE OR REPLACE TRIGGER trg_velocity_check
    BEFORE INSERT ON Transactions       -- fires BEFORE each new row
    FOR EACH ROW                        -- once per row (not once per statement)
    EXECUTE FUNCTION fn_velocity_check();


-- ============================================================
--  TRIGGER 2: Geospatial Anomaly (Impossible Travel)
--
--  RULE: If a user's last transaction was in City A and this
--  new transaction is in City B, check: could a person
--  physically travel that distance in the time gap?
--  We use the Haversine formula to compute great-circle
--  distance between two lat/lng points.
--
--  Assumed max travel speed: 900 km/h (commercial flight).
--  If distance / time_gap > 900 km/h → impossible → fraud.
--
--  DBMS CONCEPTS USED:
--    - EXTRACT(EPOCH FROM ...) converts interval to seconds
--    - Math functions: RADIANS(), SIN(), COS(), SQRT(), ASIN()
--    - LIMIT 1 + ORDER BY to get the most recent row
--    - Conditional logic with IF / ELSIF
-- ============================================================

CREATE OR REPLACE FUNCTION fn_geospatial_check()
RETURNS TRIGGER AS $$
DECLARE
    v_last_lat      NUMERIC;
    v_last_lng      NUMERIC;
    v_last_city     VARCHAR;
    v_last_time     TIMESTAMP;
    v_time_gap_hrs  NUMERIC;
    v_distance_km   NUMERIC;
    v_speed_kmh     NUMERIC;
    v_alert_desc    TEXT;

    -- Haversine constants
    R CONSTANT NUMERIC := 6371;   -- Earth radius in km
    v_dlat  NUMERIC;
    v_dlng  NUMERIC;
    v_a     NUMERIC;
    v_c     NUMERIC;
BEGIN
    -- Only run the check if this transaction has location data
    IF NEW.Latitude IS NULL OR NEW.Longitude IS NULL THEN
        RETURN NEW;
    END IF;

    -- Get the user's PREVIOUS transaction with location data
    SELECT Latitude, Longitude, Location_City, Txn_Timestamp
    INTO   v_last_lat, v_last_lng, v_last_city, v_last_time
    FROM   Transactions
    WHERE  UserID    = NEW.UserID
    AND    Latitude  IS NOT NULL
    AND    Longitude IS NOT NULL
    ORDER  BY Txn_Timestamp DESC
    LIMIT  1;

    -- No previous geo-tagged transaction — nothing to compare
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- Skip if same city (common case, fast path)
    IF v_last_city = NEW.Location_City THEN
        RETURN NEW;
    END IF;

    -- --------------------------------------------------------
    --  Haversine Formula
    --  Computes the shortest distance between two points on
    --  the surface of a sphere (Earth).
    --
    --  dlat = lat2 - lat1  (in radians)
    --  dlng = lng2 - lng1  (in radians)
    --  a = sin²(dlat/2) + cos(lat1)·cos(lat2)·sin²(dlng/2)
    --  c = 2·arcsin(√a)
    --  distance = R × c
    -- --------------------------------------------------------
    v_dlat := RADIANS(NEW.Latitude  - v_last_lat);
    v_dlng := RADIANS(NEW.Longitude - v_last_lng);

    v_a := SIN(v_dlat/2)^2
         + COS(RADIANS(v_last_lat))
           * COS(RADIANS(NEW.Latitude))
           * SIN(v_dlng/2)^2;

    v_c := 2 * ASIN(SQRT(v_a));
    v_distance_km := R * v_c;

    -- Time gap in hours (EXTRACT EPOCH gives seconds)
    v_time_gap_hrs := EXTRACT(EPOCH FROM (NEW.Txn_Timestamp - v_last_time)) / 3600.0;

    -- Avoid division by zero (transactions at same second)
    IF v_time_gap_hrs < 0.001 THEN
        v_time_gap_hrs := 0.001;
    END IF;

    v_speed_kmh := v_distance_km / v_time_gap_hrs;

    -- Flag if implied speed > 900 km/h (faster than a plane)
    IF v_speed_kmh > 900 THEN
        v_alert_desc := 'Impossible travel: ' || ROUND(v_distance_km, 0)::TEXT || ' km from ' ||
                        COALESCE(v_last_city, 'Unknown') || ' to ' ||
                        COALESCE(NEW.Location_City, 'Unknown') || ' in ' ||
                        ROUND(v_time_gap_hrs, 1)::TEXT || ' hours (' ||
                        ROUND(v_speed_kmh, 0)::TEXT || ' km/h implied speed)';

        INSERT INTO Fraud_Alerts (TxnID, UserID, Alert_Type, Severity, Description)
        VALUES (NEW.TxnID, NEW.UserID, 'IMPOSSIBLE_TRAVEL', 'Critical', v_alert_desc);

        NEW.Is_Flagged := TRUE;

        UPDATE Users
        SET    Risk_Score = LEAST(Risk_Score + 25, 100),
               Risk_Level = 'High'
        WHERE  UserID = NEW.UserID;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_geospatial_check
    BEFORE INSERT ON Transactions
    FOR EACH ROW
    EXECUTE FUNCTION fn_geospatial_check();


-- ============================================================
--  TRIGGER 3: Blacklist Check
--
--  RULE: If the transaction's IP (via Device) or Merchant_ID
--  matches any entry in the Blacklist table, decline it.
--
--  This trigger RETURNS NULL to CANCEL the INSERT entirely
--  if a blacklist match is found — the transaction never
--  reaches the Transactions table.
--
--  DBMS CONCEPTS USED:
--    - EXISTS subquery (more efficient than COUNT for boolean checks)
--    - RETURN NULL to abort a BEFORE trigger
--    - Joining to another table (Devices) inside trigger logic
-- ============================================================

CREATE OR REPLACE FUNCTION fn_blacklist_check()
RETURNS TRIGGER AS $$
DECLARE
    v_device_ip     VARCHAR;
    v_is_blacklisted BOOLEAN := FALSE;
    v_reason        TEXT;
BEGIN
    -- Look up the IP of the device used in this transaction
    IF NEW.DeviceID IS NOT NULL THEN
        SELECT IP_Address INTO v_device_ip
        FROM   Devices
        WHERE  DeviceID = NEW.DeviceID;

        -- Check IP against blacklist
        IF EXISTS (
            SELECT 1 FROM Blacklist
            WHERE  Entity_Type  = 'IP'
            AND    Entity_Value = v_device_ip
        ) THEN
            v_is_blacklisted := TRUE;
            v_reason := 'Blacklisted IP address: ' || v_device_ip;
        END IF;
    END IF;

    -- Check merchant ID against blacklist
    IF NOT v_is_blacklisted AND NEW.Merchant_ID IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM Blacklist
            WHERE  Entity_Type  = 'Merchant'
            AND    Entity_Value = NEW.Merchant_ID
        ) THEN
            v_is_blacklisted := TRUE;
            v_reason := 'Blacklisted merchant: ' || NEW.Merchant_ID;
        END IF;
    END IF;

    IF v_is_blacklisted THEN
        -- Log the blocked attempt (even though txn never inserts)
        INSERT INTO Fraud_Alerts (TxnID, UserID, Alert_Type, Severity, Description)
        VALUES (NULL, NEW.UserID, 'BLACKLIST_MATCH', 'Critical', v_reason);

        -- RETURN NULL cancels the INSERT — blacklisted txns never land
        RAISE NOTICE 'Transaction blocked: %', v_reason;
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_blacklist_check
    BEFORE INSERT ON Transactions
    FOR EACH ROW
    EXECUTE FUNCTION fn_blacklist_check();


-- ============================================================
--  TRIGGER 4: Audit Log
--
--  RULE: Any UPDATE to Users (status change, spending limit
--  change, risk score change) must be recorded immutably.
--
--  This is an AFTER trigger — we log what actually happened,
--  not what was attempted, so we wait until the UPDATE lands.
--
--  DBMS CONCEPTS USED:
--    - AFTER UPDATE trigger
--    - ROW(...)::TEXT to snapshot a full row as text
--    - TG_OP to know the operation type
--    - column-level trigger condition (OF column_name)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_audit_users()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Audit_Log (Table_Name, Operation, Record_ID, Old_Values, New_Values)
    VALUES (
        'Users',
        TG_OP,
        NEW.UserID,
        -- Store old values as a readable key=value string
        'Status=' || OLD.Account_Status || ' | RiskLevel=' || OLD.Risk_Level || 
        ' | RiskScore=' || OLD.Risk_Score::TEXT || ' | SpendLimit=' || OLD.Daily_Spending_Limit::TEXT,
        'Status=' || NEW.Account_Status || ' | RiskLevel=' || NEW.Risk_Level || 
        ' | RiskScore=' || NEW.Risk_Score::TEXT || ' | SpendLimit=' || NEW.Daily_Spending_Limit::TEXT
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Only fires when these specific columns change (efficient!)
CREATE OR REPLACE TRIGGER trg_audit_users
    AFTER UPDATE OF Account_Status, Risk_Level, Risk_Score, Daily_Spending_Limit
    ON Users
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_users();


-- ============================================================
--  QUICK TEST QUERIES
--  Run these after loading to verify triggers fire correctly.
-- ============================================================

-- Test velocity: insert 6 transactions rapidly for UserID=1
-- INSERT INTO Transactions (UserID,DeviceID,Amount,Merchant,Txn_Type) VALUES
--   (1,1,100,'Shop A','Purchase'),
--   (1,1,200,'Shop B','Purchase'),
--   (1,1,300,'Shop C','Purchase'),
--   (1,1,400,'Shop D','Purchase'),
--   (1,1,500,'Shop E','Purchase'),
--   (1,1,600,'Shop F','Purchase');  -- This 6th one should fire the alert
-- SELECT * FROM Fraud_Alerts ORDER BY Alert_Timestamp DESC LIMIT 5;

-- Test impossible travel: UserID=2 was in Chennai, now in Mumbai instantly
-- INSERT INTO Transactions (UserID,DeviceID,Amount,Location_City,Latitude,Longitude,Txn_Type)
-- VALUES (2,3,5000,'Mumbai',19.0760,72.8777,'Online');
-- SELECT * FROM Fraud_Alerts WHERE Alert_Type='IMPOSSIBLE_TRAVEL';

-- Test blacklist: DeviceID=5 has a blacklisted IP
-- INSERT INTO Transactions (UserID,DeviceID,Amount,Txn_Type) VALUES (5,5,9999,'Online');
-- SELECT * FROM Fraud_Alerts WHERE Alert_Type='BLACKLIST_MATCH';
