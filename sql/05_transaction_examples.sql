-- ============================================================
--  SentinelDB  |  Module 5: Transaction Examples
--  File: sql/05_transaction_examples.sql
-- ============================================================
--
--  READY-TO-RUN EXAMPLES for all 4 transaction types
--  Use these to test fraud detection triggers and procedures
--
--  Transaction Types:
--  1. Purchase      - Retail/Point-of-Sale transactions
--  2. Withdrawal    - ATM or bank cash withdrawals
--  3. Transfer      - Bank transfers, UPI, peer-to-peer
--  4. Online        - E-commerce, subscriptions, digital goods
-- ============================================================


-- ============================================================
--  SECTION 1: PURCHASE TRANSACTIONS
-- ============================================================

-- Example 1.1: Normal daily shopping (LOW RISK)
-- User: Arjun Sharma, Location: Coimbatore, Device: Trusted iPhone
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 1, 450.00, 'Reliance Fresh', 'Coimbatore', 11.0168, 76.9558, 'Purchase');

-- Example 1.2: Department store during travel (MEDIUM RISK)
-- New location but legitimate merchant
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 1, 2850.00, 'FBB Bangalore', 'Bangalore', 12.9716, 77.5946, 'Purchase');

-- Example 1.3: Multiple stores in quick succession (⚠️ TRIGGERS VELOCITY CHECK)
-- Purchases 1-5: Build up velocity
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 100.00, 'Store A', 'Purchase'),
  (1, 1, 200.00, 'Store B', 'Purchase'),
  (1, 1, 300.00, 'Store C', 'Purchase'),
  (1, 1, 400.00, 'Store D', 'Purchase'),
  (1, 1, 500.00, 'Store E', 'Purchase');

-- Purchase 6: TRIGGERS ALERT (velocity breach = 6+ in 10 min)
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 600.00, 'Store F', 'Purchase');

-- Example 1.4: Purchase at blacklisted merchant (🚫 TRIGGERS BLOCK)
-- Expected: Transaction inserted but immediately blocked/flagged by fn_blacklist_check()
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES (1, 1, 5000.00, 'Dark Marketplace', 'DARK_MKT_001', 'Purchase');


-- ============================================================
--  SECTION 2: WITHDRAWAL TRANSACTIONS
-- ============================================================

-- Example 2.1: Normal ATM withdrawal (LOW RISK)
-- Home location, trusted device, reasonable amount
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type, Merchant_ID) 
VALUES (1, 2, 5000.00, 'HDFC Bank ATM', 'Coimbatore', 11.0168, 76.9558, 'Withdrawal', 'ATM_CB_001');

-- Example 2.2: Large withdrawal (MEDIUM RISK)
-- Exceeds daily limit slightly
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 2, 45000.00, 'HDFC Bank Branch', 'Bangalore', 12.9716, 77.5946, 'Withdrawal');

-- Example 2.3: Impossible travel scenario (🚨 TRIGGERS CRITICAL ALERT)
-- Transaction 1: Coimbatore at 2:00 PM
INSERT INTO Transactions (UserID, DeviceID, Amount, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 1, 500.00, 'Coimbatore', 11.0168, 76.9558, 'Purchase');

-- Transaction 2: Mumbai at 2:15 PM (same time, 1756 km away - IMPOSSIBLE)
-- This triggers fn_geospatial_check() with severity CRITICAL
INSERT INTO Transactions (UserID, DeviceID, Amount, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 1, 10000.00, 'Mumbai', 19.0760, 72.8777, 'Withdrawal');

-- Example 2.4: Multiple ATM withdrawals rapid succession (⚠️ VELOCITY CONCERN)
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 2, 2000.00, 'HDFC ATM 1', 'Withdrawal'),
  (1, 2, 2000.00, 'SBI ATM 2', 'Withdrawal'),
  (1, 2, 2000.00, 'ICICI ATM 3', 'Withdrawal');

-- Example 2.5: Withdrawal from blacklisted ATM (🚫 TRIGGERS BLOCK)
-- Device 5 is from unknown/suspicious device
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES (5, 5, 15000.00, 'Compromised ATM', 'ATM_SKIMMED_42', 'Withdrawal');


-- ============================================================
--  SECTION 3: TRANSFER TRANSACTIONS
-- ============================================================

-- Example 3.1: Normal peer-to-peer transfer (LOW RISK)
-- Known recipient, reasonable amount
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 2000.00, 'Priya Nair (UPI: priya@okhdfcbank)', 'Transfer');

-- Example 3.2: Testing pattern - small transfers to unknown accounts (⚠️ HIGH RISK PATTERN)
-- Attacker testing if stolen card works before large transfer
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 100.00, 'Unknown Account X', 'Transfer'),
  (1, 1, 100.00, 'Unknown Account Y', 'Transfer'),
  (1, 1, 100.00, 'Unknown Account Z', 'Transfer');

-- Example 3.3: Large transfer after testing (TRIGGERS ALERT)
-- Risk scoring should flag: testing pattern + large amount
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 50000.00, 'Unknown Account X', 'Transfer');

-- Example 3.4: High-value transfer to business account (MEDIUM RISK)
-- Large amount but legitimate recipient
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 75000.00, 'Business Account - XYZ Corp', 'Transfer');

-- Example 3.5: Transfer to blacklisted account (🚫 TRIGGERS BLOCK)
-- Known criminal account - fn_blacklist_check() blocks with MERCHANT blacklist
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES (1, 1, 25000.00, 'Crime Network Account', 'CRIMINAL_ACC_88', 'Transfer');

-- Example 3.6: Rapid transfers to multiple accounts (⚠️ VELOCITY + PATTERN)
-- Attacker spreading stolen funds quickly
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (2, 3, 10000.00, 'Account 1', 'Transfer'),
  (2, 3, 10000.00, 'Account 2', 'Transfer'),
  (2, 3, 10000.00, 'Account 3', 'Transfer'),
  (2, 3, 10000.00, 'Account 4', 'Transfer'),
  (2, 3, 10000.00, 'Account 5', 'Transfer'),
  (2, 3, 10000.00, 'Account 6', 'Transfer');


-- ============================================================
--  SECTION 4: ONLINE TRANSACTIONS
-- ============================================================

-- Example 4.1: Normal e-commerce purchase (LOW RISK)
-- Established merchant, single normal purchase
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 1299.00, 'Amazon India - Headphones', 'Online');

-- Example 4.2: Subscription payment (LOW RISK)
-- Recurring, predictable, established merchant
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (2, 3, 499.00, 'Netflix - Monthly Subscription', 'Online');

-- Example 4.3: Rapid online shopping spree (🚨 TRIGGERS VELOCITY BREACH)
-- Multiple purchases in quick succession from different merchants
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 3000.00, 'Flipkart - Laptop', 'Online'),
  (1, 1, 2500.00, 'Amazon - Camera', 'Online'),
  (1, 1, 1500.00, 'Myntra - Clothing', 'Online'),
  (1, 1, 999.00,  'eBay India - Electronics', 'Online'),
  (1, 1, 2000.00, 'Indigo Airlines - Booking', 'Online'),
  (1, 1, 5000.00, 'OYO Rooms - Hotel', 'Online');

-- Example 4.4: Testing pattern - small purchases before large buy (⚠️ HIGH RISK)
-- Typical fraudster pattern: test if card works, then large purchase
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 50.00,   'Aliexpress - Test Item', 'Online'),
  (1, 1, 75.00,   'Shopee - Test Item', 'Online'),
  (1, 1, 100.00,  'eBay - Test Item', 'Online');

-- After testing, large purchase
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 50000.00, 'Flipkart - Electronics', 'Online');

-- Example 4.5: Out-of-character purchase (MEDIUM-HIGH RISK)
-- User normally buys groceries, suddenly buying gaming gift cards
-- Requires historical data analysis - anomaly detection
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 25000.00, 'Gaming Store - Gift Cards', 'Online');

-- Example 4.6: Purchase from darknet marketplace (🚫 TRIGGERS BLOCK)
-- Blacklisted merchant - should be blocked by fn_blacklist_check()
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES (5, 5, 3000.00, 'Illegal Marketplace', 'DARK_MARKET_XYZ', 'Online');

-- Example 4.7: High-value online purchase (MEDIUM RISK)
-- Large single online transaction
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 99999.00, 'Premium Electronics Store', 'Online');


-- ============================================================
--  SECTION 5: CROSS-TYPE FRAUD SCENARIOS
-- ============================================================

-- Scenario A: Account takeover - rapid multi-type transactions
-- Attacker uses stolen card at multiple channels
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 500.00,   'Local Store', 'Purchase'),           -- Test 1
  (1, 1, 5000.00,  'ATM Withdrawal', 'Withdrawal'),       -- Test 2
  (1, 1, 10000.00, 'Online Shopping', 'Online');          -- Test 3

-- Scenario B: "Stripping" attack - withdraw cash after online purchase
-- Attacker tests online, then immediately withdraws if successful
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 100.00, 'Amazon - Test Purchase', 'Online');

INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 2, 25000.00, 'ATM Fast Withdrawal', 'Withdrawal');

-- Scenario C: Money mule network - transfer after receiving suspicious funds
-- User receives transfer, then transfers elsewhere
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 30000.00, 'Incoming Transfer (Suspicious)', 'Transfer');

INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 30000.00, 'Outgoing Transfer (Unknown Recipient)', 'Transfer');


-- ============================================================
--  SECTION 6: VALIDATION QUERIES
--  Run these to verify transaction processing
-- ============================================================

-- View all transactions for user 1
SELECT TxnID, UserID, Amount, Merchant, Txn_Type, Txn_Timestamp, Is_Flagged
FROM Transactions
WHERE UserID = 1
ORDER BY Txn_Timestamp DESC;

-- View fraud alerts generated
SELECT AlertID, UserID, Alert_Type, Severity, Description, Is_Reviewed, Alert_Timestamp
FROM Fraud_Alerts
ORDER BY Alert_Timestamp DESC;

-- View user risk profile
SELECT UserID, Risk_Level, Risk_Score, Daily_Spending_Limit, Account_Status
FROM Users
WHERE UserID IN (1, 2, 5);

-- View blacklist entries
SELECT BlacklistID, Entity_Type, Entity_Value, Reason, Added_At
FROM Blacklist
ORDER BY Added_At DESC;

-- Count transactions by type
SELECT Txn_Type, COUNT(*) as Total_Transactions, SUM(Amount) as Total_Amount
FROM Transactions
GROUP BY Txn_Type
ORDER BY Total_Transactions DESC;

-- View alerts by severity
SELECT Severity, COUNT(*) as Alert_Count
FROM Fraud_Alerts
GROUP BY Severity
ORDER BY 
  CASE Severity
    WHEN 'Critical' THEN 1
    WHEN 'High' THEN 2
    WHEN 'Medium' THEN 3
    WHEN 'Low' THEN 4
  END;

-- View unreviewed alerts (action items for analysts)
SELECT AlertID, UserID, Alert_Type, Severity, Description, Alert_Timestamp
FROM Fraud_Alerts
WHERE Is_Reviewed = FALSE
ORDER BY Severity DESC, Alert_Timestamp DESC;


-- ============================================================
--  SECTION 7: CLEANUP (for testing/resetting)
--  CAUTION: Only run in test environment
-- ============================================================

-- -- Delete test transactions (WARNING: destructive)
-- DELETE FROM Transactions WHERE UserID IN (1, 2, 5);
-- DELETE FROM Fraud_Alerts WHERE UserID IN (1, 2, 5);
-- DELETE FROM Audit_Log;

-- -- Reset sequence counters
-- ALTER SEQUENCE transactions_txnid_seq RESTART WITH 1;
-- ALTER SEQUENCE fraud_alerts_alertid_seq RESTART WITH 1;


-- ============================================================
--  TESTING CHECKLIST
-- ============================================================

-- After running these examples, verify:
-- [ ] 6+ Purchase txns fire velocity alert
-- [ ] Impossible travel (Coimbatore + Mumbai) fires geospatial alert
-- [ ] Blacklisted merchant blocks transaction (returns NULL)
-- [ ] Blacklisted IP blocks transaction
-- [ ] Risk scores update based on transaction type and frequency
-- [ ] Audit log records all operations
-- [ ] User risk levels change as alerts accumulate
-- [ ] Account status updates (Active → Flagged → Suspended)

-- ============================================================
--  Last Updated: 2026-04-28
--  Status: ✅ Ready for testing
-- ============================================================
