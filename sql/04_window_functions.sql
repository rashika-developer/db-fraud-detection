-- ============================================================
--  SentinelDB  |  Module 4: Window Functions & Analytical SQL
-- ============================================================
--
--  DBMS CONCEPT: Window Functions
--  Unlike GROUP BY which collapses rows into one summary row,
--  window functions compute values ACROSS rows while keeping
--  each row intact. Think of it as "calculate something about
--  a group, but still show every individual row."
--
--  Syntax:
--    function_name() OVER (
--        PARTITION BY column   -- grouping (like GROUP BY)
--        ORDER BY column       -- ordering within each group
--        ROWS/RANGE BETWEEN .. -- frame (optional)
--    )
--
--  Key window functions used here:
--    ROW_NUMBER()  - sequential rank within partition
--    RANK()        - rank with gaps for ties
--    LAG()         - value from the PREVIOUS row
--    LEAD()        - value from the NEXT row
--    SUM() OVER()  - running total
--    AVG() OVER()  - moving average
-- ============================================================


-- ============================================================
--  QUERY 1: Transaction Sequence with Running Total
--  For each user, show every transaction with:
--    - its sequence number (ROW_NUMBER)
--    - running total spent so far
--    - time gap from previous transaction (LAG)
--
--  Used by: dashboard transaction detail page
-- ============================================================
SELECT
    t.TxnID,
    t.UserID,
    u.Name                              AS User_Name,
    t.Amount,
    t.Merchant,
    t.Location_City,
    t.Txn_Timestamp,
    t.Is_Flagged,

    -- ROW_NUMBER: sequential count per user, newest first
    ROW_NUMBER() OVER (
        PARTITION BY t.UserID
        ORDER BY t.Txn_Timestamp DESC
    )                                   AS Txn_Sequence,

    -- SUM OVER: running total of amount per user (oldest to newest)
    SUM(t.Amount) OVER (
        PARTITION BY t.UserID
        ORDER BY t.Txn_Timestamp
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                   AS Running_Total,

    -- LAG: previous transaction amount for the same user
    LAG(t.Amount) OVER (
        PARTITION BY t.UserID
        ORDER BY t.Txn_Timestamp
    )                                   AS Prev_Amount,

    -- LAG on timestamp → compute gap in minutes
    ROUND(
        EXTRACT(EPOCH FROM (
            t.Txn_Timestamp -
            LAG(t.Txn_Timestamp) OVER (
                PARTITION BY t.UserID
                ORDER BY t.Txn_Timestamp
            )
        )) / 60.0,
    2)                                  AS Mins_Since_Last_Txn,

    -- Flag if this amount is 3x larger than the previous one (spike)
    CASE
        WHEN t.Amount > 3 * LAG(t.Amount) OVER (
                PARTITION BY t.UserID
                ORDER BY t.Txn_Timestamp)
        THEN TRUE
        ELSE FALSE
    END                                 AS Is_Spending_Spike

FROM Transactions t
JOIN Users u ON t.UserID = u.UserID
ORDER BY t.UserID, t.Txn_Timestamp DESC;


-- ============================================================
--  QUERY 2: Velocity Detection (pure SQL, no trigger)
--  Count transactions per user in every 10-minute window.
--  Uses COUNT() OVER with a RANGE frame based on timestamps.
--
--  DBMS CONCEPT: RANGE vs ROWS frame
--    ROWS BETWEEN N PRECEDING AND CURRENT ROW
--      → literally N rows before current row
--    RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
--      → all rows whose ORDER BY value is within 10 min of current row
--  For time-based windows, RANGE is correct.
-- ============================================================
SELECT
    TxnID,
    UserID,
    Amount,
    Txn_Timestamp,
    COUNT(*) OVER (
        PARTITION BY UserID
        ORDER BY Txn_Timestamp
        RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
    )                                   AS Txns_In_Last_10_Min,
    SUM(Amount) OVER (
        PARTITION BY UserID
        ORDER BY Txn_Timestamp
        RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
    )                                   AS Amount_In_Last_10_Min
FROM Transactions
ORDER BY UserID, Txn_Timestamp;


-- ============================================================
--  QUERY 3: Percentile Ranking of Users by Risk Score
--  Shows where each user stands relative to all users.
--  Useful for the "Top Risk Users" panel on the dashboard.
--
--  DBMS CONCEPTS:
--    PERCENT_RANK() → 0 to 1 percentile rank
--    NTILE(4)       → divides users into 4 quartiles
-- ============================================================
SELECT
    u.UserID,
    u.Name,
    u.Risk_Score,
    u.Risk_Level,
    u.Account_Status,

    -- Rank by risk score descending (1 = most risky)
    RANK() OVER (ORDER BY u.Risk_Score DESC)            AS Risk_Rank,

    -- Percentile: 1.0 = most risky, 0.0 = least risky
    ROUND(
        PERCENT_RANK() OVER (ORDER BY u.Risk_Score)::NUMERIC,
    4)                                                  AS Risk_Percentile,

    -- Quartile: 4 = top risk quartile, 1 = safest
    NTILE(4) OVER (ORDER BY u.Risk_Score)               AS Risk_Quartile,

    COUNT(fa.AlertID)                                   AS Total_Alerts,
    COUNT(fa.AlertID) FILTER (
        WHERE fa.Severity = 'Critical')                 AS Critical_Alerts
FROM Users u
LEFT JOIN Fraud_Alerts fa ON u.UserID = fa.UserID
GROUP BY u.UserID, u.Name, u.Risk_Score, u.Risk_Level, u.Account_Status
ORDER BY u.Risk_Score DESC;


-- ============================================================
--  QUERY 4: Geospatial Sequence — Distance Between Consecutive Txns
--  Uses LAG to pull previous lat/lng, then applies Haversine.
--  This is the pure-SQL version of the trigger's geo logic —
--  useful for batch analysis of historical data.
-- ============================================================
WITH geo_pairs AS (
    SELECT
        TxnID,
        UserID,
        Amount,
        Location_City,
        Latitude,
        Longitude,
        Txn_Timestamp,
        LAG(Latitude)       OVER (PARTITION BY UserID ORDER BY Txn_Timestamp) AS Prev_Lat,
        LAG(Longitude)      OVER (PARTITION BY UserID ORDER BY Txn_Timestamp) AS Prev_Lng,
        LAG(Location_City)  OVER (PARTITION BY UserID ORDER BY Txn_Timestamp) AS Prev_City,
        LAG(Txn_Timestamp)  OVER (PARTITION BY UserID ORDER BY Txn_Timestamp) AS Prev_Time
    FROM Transactions
    WHERE Latitude IS NOT NULL AND Longitude IS NOT NULL
),
distances AS (
    SELECT
        TxnID,
        UserID,
        Location_City,
        Prev_City,
        Txn_Timestamp,
        Prev_Time,
        -- Haversine distance in km
        6371 * 2 * ASIN(SQRT(
            SIN(RADIANS(Latitude  - Prev_Lat) / 2)^2 +
            COS(RADIANS(Prev_Lat)) * COS(RADIANS(Latitude)) *
            SIN(RADIANS(Longitude - Prev_Lng) / 2)^2
        ))                                                          AS Distance_KM,
        -- Time gap in hours
        EXTRACT(EPOCH FROM (Txn_Timestamp - Prev_Time)) / 3600.0   AS Time_Gap_Hrs
    FROM geo_pairs
    WHERE Prev_Lat IS NOT NULL
)
SELECT
    TxnID,
    UserID,
    Prev_City,
    Location_City                   AS Current_City,
    ROUND(Distance_KM::NUMERIC, 1)  AS Distance_KM,
    ROUND(Time_Gap_Hrs::NUMERIC, 2) AS Time_Gap_Hrs,
    ROUND((Distance_KM /
           NULLIF(Time_Gap_Hrs, 0))::NUMERIC, 0) AS Implied_Speed_KMH,
    CASE
        WHEN (Distance_KM / NULLIF(Time_Gap_Hrs, 0)) > 900
        THEN '⚠ IMPOSSIBLE TRAVEL'
        WHEN (Distance_KM / NULLIF(Time_Gap_Hrs, 0)) > 500
        THEN '⚡ SUSPICIOUS SPEED'
        ELSE '✓ Normal'
    END                             AS Travel_Assessment
FROM distances
ORDER BY Implied_Speed_KMH DESC NULLS LAST;


-- ============================================================
--  QUERY 5: Alert Trend — Daily counts by type (for chart)
--  Used by the Streamlit dashboard to render line charts.
-- ============================================================
SELECT
    DATE(Alert_Timestamp)       AS Alert_Date,
    Alert_Type,
    Severity,
    COUNT(*)                    AS Count,
    COUNT(DISTINCT UserID)      AS Unique_Users_Affected
FROM Fraud_Alerts
WHERE Alert_Timestamp >= NOW() - INTERVAL '30 days'
GROUP BY DATE(Alert_Timestamp), Alert_Type, Severity
ORDER BY Alert_Date DESC, Count DESC;


-- ============================================================
--  QUERY 6: Merchant Risk Profile
--  Which merchants appear most in flagged transactions?
--  Useful for populating / suggesting Blacklist entries.
-- ============================================================
SELECT
    t.Merchant,
    t.Merchant_ID,
    COUNT(*)                            AS Total_Transactions,
    COUNT(*) FILTER (WHERE t.Is_Flagged = TRUE)  AS Flagged_Count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE t.Is_Flagged = TRUE) / COUNT(*),
    1)                                  AS Flag_Rate_Pct,
    SUM(t.Amount)                       AS Total_Volume,
    AVG(t.Amount)                       AS Avg_Amount,
    MAX(t.Amount)                       AS Max_Amount,
    COUNT(DISTINCT t.UserID)            AS Unique_Users
FROM Transactions t
WHERE t.Merchant IS NOT NULL
GROUP BY t.Merchant, t.Merchant_ID
HAVING COUNT(*) >= 1
ORDER BY Flag_Rate_Pct DESC, Flagged_Count DESC;
