# SentinelDB - Complete Test Scenarios & Validation Guide

## Overview
This document details all fraud detection test scenarios with expected outcomes, SQL commands, and validation steps.

**Prerequisites:**
- PostgreSQL running with sentineldb database loaded
- All SQL files (01-04) executed in order
- Python dependencies installed: `pip install -r requirements.txt`

---

## Test Scenarios Summary

| # | Scenario | Trigger | Expected | Priority |
|---|----------|---------|----------|----------|
| 1 | Velocity Breach | 6+ txns in 10min | VELOCITY_BREACH alert | P0 Critical |
| 2 | Impossible Travel | 1756 km in 0 hours | IMPOSSIBLE_TRAVEL alert | P0 Critical |
| 3 | Blacklist Match (IP) | Blacklisted IP used | BLACKLIST_MATCH alert | P0 Critical |
| 4 | Blacklist Match (Merchant) | Blacklisted merchant | BLACKLIST_MATCH alert | P0 Critical |
| 5 | Risk Evaluation | Score ≥ 85 | AUTO_SUSPENSION | P1 High |
| 6 | Alert Review | Mark alert reviewed | Risk restoration | P2 Medium |
| 7 | Dashboard Views | Query vw_active_alerts | Real-time data | P2 Medium |
| 8 | End-to-End | Multiple txns + risk eval | Complete workflow | P1 High |

---

## TEST 1: Velocity Breach Detection

### Scenario
User makes 6 transactions within 10 minutes → trigger flags for fraud

### Test Setup
```sql
-- Ensure we have a fresh user
DELETE FROM Fraud_Alerts WHERE UserID = 1;
DELETE FROM Transactions WHERE UserID = 1;

-- Clear sample data and start fresh
SELECT COUNT(*) FROM Transactions WHERE UserID = 1;
```

### Execute Test
```sql
-- Insert 6 rapid transactions for User 1
BEGIN;

INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type, Location_City, Latitude, Longitude) VALUES
  (1, 1, 100.00,  'Shop A', 'Purchase', 'Coimbatore', 11.0168, 76.9558),
  (1, 1, 200.00,  'Shop B', 'Purchase', 'Coimbatore', 11.0168, 76.9558),
  (1, 1, 300.00,  'Shop C', 'Purchase', 'Coimbatore', 11.0168, 76.9558),
  (1, 1, 400.00,  'Shop D', 'Purchase', 'Coimbatore', 11.0168, 76.9558),
  (1, 1, 500.00,  'Shop E', 'Purchase', 'Coimbatore', 11.0168, 76.9558),
  (1, 1, 600.00,  'Shop F', 'Purchase', 'Coimbatore', 11.0168, 76.9558);

COMMIT;
```

### Verify Results
```sql
-- Check that 6th transaction is flagged
SELECT TxnID, UserID, Amount, Is_Flagged, Txn_Timestamp 
FROM Transactions 
WHERE UserID = 1 
ORDER BY Txn_Timestamp DESC 
LIMIT 6;

-- Expect: Last (most recent) transaction has Is_Flagged = TRUE
```

### Validation
```sql
-- Check fraud alerts
SELECT AlertID, Alert_Type, Severity, Description, Alert_Timestamp
FROM Fraud_Alerts
WHERE UserID = 1
ORDER BY Alert_Timestamp DESC;

-- Expected:
-- ✅ Alert_Type = 'VELOCITY_BREACH'
-- ✅ Severity = 'High'
-- ✅ Description contains "6 transactions in 10 minutes"
-- ✅ Most recent alert timestamp

-- Check user risk score increased
SELECT UserID, Name, Risk_Score, Risk_Level, Account_Status
FROM Users
WHERE UserID = 1;

-- Expected:
-- ✅ Risk_Score increased (originally 10.00, now +15 = 25.00)
-- ✅ Risk_Level may still be 'Low' (unless ≥40)
```

### Success Criteria
- ✅ 6th transaction flagged (Is_Flagged = TRUE)
- ✅ VELOCITY_BREACH alert created with severity 'High'
- ✅ User risk score +15
- ✅ Alert description accurate

---

## TEST 2: Impossible Travel Detection

### Scenario
User appears in two locations 1756 km apart with zero time gap → impossible travel fraud

### Test Setup
```sql
-- Get User 2's last transaction location (should be Chennai)
SELECT UserID, Location_City, Latitude, Longitude, Txn_Timestamp
FROM Transactions
WHERE UserID = 2
ORDER BY Txn_Timestamp DESC
LIMIT 1;

-- Expected: Chennai (13.0827, 80.2707)
```

### Execute Test
```sql
-- Insert transaction from Delhi (instant travel from Chennai)
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type, Location_City, Latitude, Longitude)
VALUES (2, 3, 15000.00, 'Mystery Shop', 'Online', 'Delhi', 28.6139, 77.2090);
```

### Verify Results
```sql
-- Check transaction flagged
SELECT TxnID, UserID, Location_City, Latitude, Longitude, Is_Flagged, Txn_Timestamp
FROM Transactions
WHERE UserID = 2 AND Location_City = 'Delhi'
ORDER BY Txn_Timestamp DESC
LIMIT 1;

-- Expected: Is_Flagged = TRUE
```

### Validation
```sql
-- Check fraud alerts
SELECT AlertID, Alert_Type, Severity, Description, Alert_Timestamp
FROM Fraud_Alerts
WHERE UserID = 2 AND Alert_Type = 'IMPOSSIBLE_TRAVEL'
ORDER BY Alert_Timestamp DESC
LIMIT 1;

-- Expected:
-- ✅ Alert_Type = 'IMPOSSIBLE_TRAVEL'
-- ✅ Severity = 'Critical'
-- ✅ Description = 'Impossible travel: 1756 km from Chennai to Delhi in X hours (Y km/h implied speed)'
-- ✅ Implied speed should be very high (> 900 km/h)

-- Check user risk score
SELECT UserID, Name, Risk_Score, Risk_Level
FROM Users
WHERE UserID = 2;

-- Expected:
-- ✅ Risk_Score increased (+25 points)
-- ✅ Risk_Level = 'High' (if score ≥ 75)
```

### Success Criteria
- ✅ Transaction flagged (Is_Flagged = TRUE)
- ✅ IMPOSSIBLE_TRAVEL alert created with severity 'Critical'
- ✅ Description shows distance, cities, time, and implied speed
- ✅ Haversine formula correctly calculated distance (≈1756 km)
- ✅ User risk score +25
- ✅ User risk level elevated to 'High'

---

## TEST 3: Blacklist Match - IP Address

### Scenario
Device with blacklisted IP (Tor exit node 185.220.101.5) attempts transaction → blocked

### Test Setup
```sql
-- Verify Device 5 has blacklisted IP
SELECT DeviceID, UserID, IP_Address
FROM Devices
WHERE DeviceID = 5;

-- Expected: IP_Address = '185.220.101.5' (Tor exit node)

-- Verify IP is in blacklist
SELECT BlacklistID, Entity_Type, Entity_Value, Reason
FROM Blacklist
WHERE Entity_Type = 'IP' AND Entity_Value = '185.220.101.5';

-- Expected: Found in blacklist
```

### Execute Test
```sql
-- Try to insert transaction from Device 5 (blacklisted IP)
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type)
VALUES (5, 5, 9999.00, 'Online Payment', 'Online');

-- Note: This INSERT may return NULL (transaction blocked)
-- OR may succeed but be flagged
```

### Verify Results
```sql
-- Check if transaction was blocked (NULL return)
SELECT COUNT(*) as txn_count
FROM Transactions
WHERE UserID = 5;

-- Expected: Count should not increase (transaction blocked)

-- OR if transaction inserted, check if it was blocked
SELECT TxnID, UserID, DeviceID, Is_Flagged
FROM Transactions
WHERE UserID = 5
ORDER BY Txn_Timestamp DESC
LIMIT 1;

-- Expected: Either no transaction or transaction with special flag
```

### Validation
```sql
-- Check fraud alerts
SELECT AlertID, Alert_Type, Severity, Description, Alert_Timestamp
FROM Fraud_Alerts
WHERE UserID = 5 AND Alert_Type = 'BLACKLIST_MATCH'
ORDER BY Alert_Timestamp DESC
LIMIT 1;

-- Expected:
-- ✅ Alert_Type = 'BLACKLIST_MATCH'
-- ✅ Severity = 'Critical'
-- ✅ Description = 'Blacklisted IP address: 185.220.101.5'

-- Verify user has no transaction in main table (if RETURN NULL worked)
SELECT COUNT(*) FROM Transactions WHERE UserID = 5;
```

### Success Criteria
- ✅ Transaction blocked or alert logged (depending on implementation)
- ✅ BLACKLIST_MATCH alert created with severity 'Critical'
- ✅ Alert description identifies specific IP address
- ✅ User cannot proceed with transaction from blacklisted IP

---

## TEST 4: Blacklist Match - Merchant

### Scenario
Merchant flagged in blacklist (darknet marketplace) → transaction blocked

### Test Setup
```sql
-- Verify merchant is in blacklist
SELECT BlacklistID, Entity_Type, Entity_Value, Reason
FROM Blacklist
WHERE Entity_Type = 'Merchant' AND Entity_Value = 'DARK_MKT_001';

-- Expected: Found with reason
```

### Execute Test
```sql
-- Try transaction with blacklisted merchant
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type)
VALUES (1, 1, 5000.00, 'Illegal Service', 'DARK_MKT_001', 'Online');

-- Note: May be blocked or flagged depending on implementation
```

### Validation
```sql
-- Check fraud alerts
SELECT AlertID, Alert_Type, Severity, Description
FROM Fraud_Alerts
WHERE Alert_Type = 'BLACKLIST_MATCH' AND Description LIKE '%DARK_MKT_001%'
ORDER BY Alert_Timestamp DESC
LIMIT 1;

-- Expected:
-- ✅ Alert_Type = 'BLACKLIST_MATCH'
-- ✅ Severity = 'Critical'
-- ✅ Description = 'Blacklisted merchant: DARK_MKT_001'
```

### Success Criteria
- ✅ Alert logged for blacklisted merchant
- ✅ Transaction blocked or flagged
- ✅ Alert severity is 'Critical'

---

## TEST 5: Risk Evaluation & Auto-Suspension

### Scenario
User accumulates risk score ≥ 85 → automatically suspended

### Test Setup
```sql
-- Check User 5 (Fraud Actor) current status
SELECT UserID, Name, Risk_Score, Risk_Level, Account_Status
FROM Users
WHERE UserID = 5;

-- Expected: Risk_Score = 95.00 (likely ≥ 85)
```

### Execute Test
```sql
-- Manually evaluate user risk
CALL sp_evaluate_user_risk(5, NULL, NULL);

-- Wait for procedure to complete
```

### Validation
```sql
-- Check user status after evaluation
SELECT UserID, Name, Risk_Score, Risk_Level, Account_Status
FROM Users
WHERE UserID = 5;

-- Expected:
-- ✅ Risk_Score = (recalculated, likely still ≥ 85)
-- ✅ Risk_Level = 'High'
-- ✅ Account_Status = 'Suspended' (AUTO-SUSPENDED)

-- Check if auto-suspension alert was created
SELECT AlertID, Alert_Type, Severity, Description
FROM Fraud_Alerts
WHERE UserID = 5 AND Alert_Type = 'AUTO_SUSPENSION'
ORDER BY Alert_Timestamp DESC
LIMIT 1;

-- Expected:
-- ✅ AlertID exists
-- ✅ Alert_Type = 'AUTO_SUSPENSION'
-- ✅ Severity = 'Critical'
-- ✅ Description contains "Account auto-suspended. Risk score: 95"

-- Check audit log
SELECT LogID, Table_Name, Operation, Record_ID, Old_Values, New_Values
FROM Audit_Log
WHERE Table_Name = 'Users' AND Record_ID = 5 AND Operation = 'UPDATE'
ORDER BY Changed_At DESC
LIMIT 2;

-- Expected:
-- ✅ Recent UPDATE entry showing Account_Status changed to 'Suspended'
```

### Success Criteria
- ✅ Account_Status changed to 'Suspended'
- ✅ AUTO_SUSPENSION alert created with severity 'Critical'
- ✅ Audit log records the suspension
- ✅ Risk_Level = 'High'

---

## TEST 6: Alert Review & Trust Restoration

### Scenario
Analyst reviews an alert, marks it reviewed → if all clear, user risk decreases

### Test Setup
```sql
-- Find an unreviewed alert
SELECT AlertID, UserID, Alert_Type, Severity, Is_Reviewed
FROM Fraud_Alerts
WHERE Is_Reviewed = FALSE
ORDER BY Alert_Timestamp DESC
LIMIT 1;

-- Note the AlertID and UserID
```

### Execute Test
```sql
-- Mark alert as reviewed (analyst named 'system')
CALL sp_review_alert(1, 'analyst_name');

-- Get the UserID from the alert first
-- Then check User 3 (Ravi Kumar) status
```

### Validation
```sql
-- Check alert marked as reviewed
SELECT AlertID, Is_Reviewed, Alert_Timestamp
FROM Fraud_Alerts
WHERE AlertID = 1;

-- Expected: Is_Reviewed = TRUE

-- Check audit log for review
SELECT LogID, Table_Name, Operation, New_Values
FROM Audit_Log
WHERE Table_Name = 'Fraud_Alerts' AND Record_ID = 1 AND Operation = 'UPDATE'
ORDER BY Changed_At DESC
LIMIT 1;

-- Expected: New_Values = 'Reviewed by analyst_name at <timestamp>'

-- Check user risk score (may decrease by 10 if all alerts reviewed)
SELECT UserID, Name, Risk_Score, Risk_Level, Account_Status
FROM Users
WHERE UserID = 3;

-- Expected (if all alerts reviewed):
-- ✅ Risk_Score decreased by 10
-- ✅ Risk_Level may downgrade if < 40
-- ✅ Account_Status may become 'Active' if was 'Suspended' and score now < 85
```

### Success Criteria
- ✅ Alert marked as Is_Reviewed = TRUE
- ✅ Audit_Log entry created with reviewer name
- ✅ User risk score decreases if all alerts reviewed
- ✅ User status restored if score permits

---

## TEST 7: Dashboard Views (Real-Time Queries)

### Scenario
Verify views return correct aggregated data for dashboard

### Execute Queries

```sql
-- View 1: Active Alerts
SELECT *
FROM vw_active_alerts
LIMIT 10;

-- Expected columns: AlertID, UserID, UserName, Alert_Type, Severity, Description, Is_Reviewed, Alert_Timestamp
-- Expected: Should show recent critical alerts first
-- Expected: Is_Reviewed = FALSE items prominent


-- View 2: User Risk Summary
SELECT *
FROM vw_user_risk_summary
ORDER BY Risk_Score DESC;

-- Expected columns: UserID, Name, Email, Risk_Score, Risk_Level, Account_Status, Unreviewed_Alerts
-- Expected: Fraud Actor (Score=95) first
-- Expected: Unreviewed_Alerts count accurate
-- Expected: Suspended users visible


-- View 3: Daily Fraud Statistics
REFRESH MATERIALIZED VIEW mvw_daily_fraud_stats;

SELECT *
FROM mvw_daily_fraud_stats
ORDER BY alert_date DESC
LIMIT 14;

-- Expected columns: alert_date, alert_type, severity, count
-- Expected: Grouped by date and type
-- Expected: Critical/High severity alerts prominent
```

### Validation
```sql
-- Verify data accuracy
SELECT 
  COUNT(*) as total_alerts,
  COUNT(*) FILTER (WHERE Is_Reviewed = FALSE) as unreviewed,
  COUNT(*) FILTER (WHERE Severity = 'Critical') as critical,
  MAX(Alert_Timestamp) as latest_alert
FROM Fraud_Alerts
WHERE Alert_Timestamp >= NOW() - INTERVAL '24 hours';

-- Expected: Numbers match view results
```

### Success Criteria
- ✅ vw_active_alerts returns correct data
- ✅ vw_user_risk_summary shows risk profiles
- ✅ mvw_daily_fraud_stats (materialized) available
- ✅ Data aggregations correct
- ✅ Timestamps accurate

---

## TEST 8: End-to-End Workflow

### Scenario
Complete fraud detection workflow: Insert transactions → Triggers fire → Alerts created → Risk evaluated → User suspended → Alert reviewed

### Execute Complete Workflow

```sql
-- Phase 1: Setup
DELETE FROM Fraud_Alerts WHERE UserID IN (1, 2);
DELETE FROM Transactions WHERE UserID IN (1, 2);

-- Phase 2: Velocity Breach
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type, Location_City, Latitude, Longitude) VALUES
  (1, 1, 100.00, 'Store 1', 'Purchase', 'Bangalore', 12.9716, 77.5946),
  (1, 1, 150.00, 'Store 2', 'Purchase', 'Bangalore', 12.9716, 77.5946),
  (1, 1, 200.00, 'Store 3', 'Purchase', 'Bangalore', 12.9716, 77.5946),
  (1, 1, 250.00, 'Store 4', 'Purchase', 'Bangalore', 12.9716, 77.5946),
  (1, 1, 300.00, 'Store 5', 'Purchase', 'Bangalore', 12.9716, 77.5946),
  (1, 1, 350.00, 'Store 6', 'Purchase', 'Bangalore', 12.9716, 77.5946);

-- Phase 3: Check velocity alert
SELECT AlertID, Alert_Type, Severity FROM Fraud_Alerts WHERE UserID = 1 AND Alert_Type = 'VELOCITY_BREACH';

-- Phase 4: Impossible travel
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type, Location_City, Latitude, Longitude)
VALUES (2, 3, 50000.00, 'Jewelry Store', 'Online', 'London', 51.5074, -0.1278);

-- Phase 5: Check geo alert
SELECT AlertID, Alert_Type, Severity FROM Fraud_Alerts WHERE UserID = 2 AND Alert_Type = 'IMPOSSIBLE_TRAVEL';

-- Phase 6: Evaluate risk
CALL sp_evaluate_user_risk(1, NULL, NULL);
CALL sp_evaluate_user_risk(2, NULL, NULL);

-- Phase 7: Check auto-suspension
SELECT UserID, Account_Status, Risk_Score FROM Users WHERE UserID IN (1, 2);

-- Phase 8: Review an alert
SELECT AlertID FROM Fraud_Alerts WHERE UserID = 1 LIMIT 1;
-- Then: CALL sp_review_alert(<AlertID>, 'analyst');

-- Phase 9: Verify final state
SELECT * FROM vw_user_risk_summary WHERE UserID IN (1, 2);
SELECT COUNT(*) as unreviewed FROM Fraud_Alerts WHERE Is_Reviewed = FALSE;
```

### Validation Checklist
```
✅ Velocity alerts created for User 1
✅ Impossible travel alert created for User 2
✅ User risk scores updated
✅ Auto-suspension triggered if score ≥ 85
✅ AUTO_SUSPENSION alerts logged
✅ Alert review process works
✅ Dashboard views show current state
✅ Audit log complete
```

---

## Test Execution Checklist

- [ ] Database loaded with all 4 SQL files
- [ ] Sample data inserted (Users, Devices, Blacklist, Transactions)
- [ ] Python environment ready: `pip install -r requirements.txt`

### Run Tests
- [ ] **TEST 1** - Velocity Breach: Execute and verify
- [ ] **TEST 2** - Impossible Travel: Execute and verify
- [ ] **TEST 3** - Blacklist IP: Execute and verify
- [ ] **TEST 4** - Blacklist Merchant: Execute and verify
- [ ] **TEST 5** - Risk Evaluation: Execute and verify
- [ ] **TEST 6** - Alert Review: Execute and verify
- [ ] **TEST 7** - Dashboard Views: Execute and verify
- [ ] **TEST 8** - End-to-End: Execute and verify

### Automated Test
- [ ] Run: `python app/sentinel_db.py`
- [ ] Verify: All tests passed ✅

### Dashboard
- [ ] Run: `streamlit run dashboard/app.py`
- [ ] Verify: UI renders correctly
- [ ] Verify: Mock data mode works
- [ ] Verify: Live DB mode works (if DB available)

---

## Success Criteria Summary

| Test | Success Criteria |
|------|-----------------|
| **Velocity** | Alert created, severity='High', user risk +15 |
| **Geo** | Alert created, severity='Critical', user risk +25 |
| **Blacklist IP** | Alert created, transaction blocked/flagged |
| **Blacklist Merchant** | Alert created, transaction blocked/flagged |
| **Risk Eval** | User auto-suspended if score ≥ 85 |
| **Review** | Alert marked reviewed, risk restored if all clear |
| **Views** | Dashboard queries return current data |
| **E2E** | Complete workflow operates correctly |

**Overall:** 8/8 tests passing = ✅ Production Ready

---

**Test Scenarios Document**  
**Created:** 2026-04-28  
**Status:** ✅ READY FOR EXECUTION
