# SentinelDB - Transaction Types & Examples

## Overview

The SentinelDB fraud detection system monitors **4 primary transaction types**. Each type has specific fraud patterns, triggers, and real-world examples.

---

## 1️⃣ PURCHASE Transactions

### Definition
Point-of-sale or merchant purchases using a debit/credit card at physical or online retail locations.

### Key Characteristics
- **Merchant Field**: Populated (retailer name)
- **Location**: City and GPS coordinates recorded
- **Amount**: Typically smaller amounts (₹100 - ₹50,000)
- **Fraud Risk**: Velocity breaches, impossible travel, blacklisted merchants

### Real-World Examples

#### Example 1.1: Normal Daily Shopping
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES 
  (1, 1, 450.00, 'Reliance Fresh', 'Coimbatore', 11.0168, 76.9558, 'Purchase');
```
**Scenario**: Arjun buys groceries at his local supermarket  
**Risk Level**: Low (home location, trusted device, normal merchant)

---

#### Example 1.2: Department Store Purchase
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES 
  (1, 1, 2850.00, 'FBB Bangalore', 'Bangalore', 12.9716, 77.5946, 'Purchase');
```
**Scenario**: Arjun buys clothing while traveling to Bangalore  
**Risk Level**: Low-Medium (new location, but legitimate merchant)

---

#### Example 1.3: Multiple Rapid-Fire Purchases (Velocity Breach)
```sql
-- 6 transactions in 10 minutes → FRAUD ALERT
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 100.00, 'Store A', 'Purchase'),
  (1, 1, 200.00, 'Store B', 'Purchase'),
  (1, 1, 300.00, 'Store C', 'Purchase'),
  (1, 1, 400.00, 'Store D', 'Purchase'),
  (1, 1, 500.00, 'Store E', 'Purchase'),
  (1, 1, 600.00, 'Store F', 'Purchase');  -- 6th txn triggers alert
```
**Scenario**: Fraudster using stolen card at multiple stores  
**Risk Level**: **CRITICAL** (velocity breach detected)  
**Detection**: `fn_velocity_check()` trigger fires on 6th transaction

---

#### Example 1.4: Blacklisted Merchant Purchase
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES 
  (1, 1, 5000.00, 'Dark Market', 'DARK_MKT_001', 'Purchase');
```
**Scenario**: Card used at a known darknet marketplace  
**Risk Level**: **HIGH** (blacklisted merchant)  
**Detection**: `fn_blacklist_check()` trigger blocks transaction (RETURN NULL)

---

### Purchase Transaction Patterns Detected by SentinelDB

| Pattern | Trigger | Action | Risk |
|---------|---------|--------|------|
| 6+ txns in 10 min | `fn_velocity_check()` | Alert Medium | 5 pts |
| Same merchant, different locations | Analytics view | Alert Low | 2 pts |
| Purchase > daily limit | `sp_evaluate_user_risk()` | Alert High | 20 pts |
| Known bad merchant | `fn_blacklist_check()` | BLOCK | Critical |

---

## 2️⃣ WITHDRAWAL Transactions

### Definition
Cash withdrawals from ATMs or bank tellers. Highest fraud risk due to irreversibility.

### Key Characteristics
- **Merchant Field**: "HDFC Bank ATM", "SBI Branch", etc.
- **Amount**: Usually round numbers (₹1000, ₹5000, ₹10000)
- **Location**: ATM or branch coordinates
- **Fraud Risk**: Large single withdrawals, impossible travel, blacklisted ATMs

### Real-World Examples

#### Example 2.1: Normal ATM Withdrawal
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type, Merchant_ID) 
VALUES 
  (1, 2, 5000.00, 'HDFC Bank ATM', 'Coimbatore', 11.0168, 76.9558, 'Withdrawal', 'ATM_CB_001');
```
**Scenario**: Arjun withdraws cash from ATM near his home  
**Risk Level**: Low (trusted location, normal amount)

---

#### Example 2.2: Large Withdrawal (Spending Limit Breach)
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES 
  (1, NULL, 45000.00, 'HDFC Bank Branch', 'Bangalore', 12.9716, 77.5946, 'Withdrawal');
```
**Scenario**: Arjun withdraws ₹45,000 (exceeds daily ₹50,000 limit by small margin)  
**Risk Level**: Medium (large amount, possible over-limit)  
**Detection**: `sp_evaluate_user_risk()` evaluates against daily limit

---

#### Example 2.3: Impossible Travel + Withdrawal
```sql
-- Transaction 1: Purchase in Coimbatore at 2:00 PM
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Location_City, Latitude, Longitude, Txn_Type, Txn_Timestamp) 
VALUES 
  (1, 1, 500.00, 'Coimbatore', 11.0168, 76.9558, 'Purchase', NOW());

-- Transaction 2: Withdrawal in Mumbai at 2:15 PM (same day, 1756 km away)
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Location_City, Latitude, Longitude, Txn_Type, Txn_Timestamp) 
VALUES 
  (1, 1, 10000.00, 'Mumbai', 19.0760, 72.8777, 'Withdrawal', NOW() + INTERVAL '15 minutes');
```
**Scenario**: Fraudster tries to use stolen card in different city  
**Distance**: 1756 km  
**Time**: 15 minutes (impossible to travel)  
**Risk Level**: **CRITICAL**  
**Detection**: `fn_geospatial_check()` trigger fires on 2nd transaction

---

#### Example 2.4: Blacklisted ATM Withdrawal
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES 
  (5, 5, 15000.00, 'Compromised ATM', 'ATM_SKIMMED_42', 'Withdrawal');
```
**Scenario**: Withdrawal from ATM known to have skimming devices  
**Risk Level**: **HIGH**  
**Detection**: `fn_blacklist_check()` blocks transaction

---

### Withdrawal Transaction Patterns

| Pattern | Risk | Action |
|---------|------|--------|
| Single withdrawal > ₹50,000 | Medium | Alert + Risk eval |
| Withdrawal after online purchase (<1 min) | High | Alert + Monitor |
| 3+ ATM withdrawals in 30 min | Critical | Alert + Possible block |
| Withdrawal from blacklisted ATM | Critical | BLOCK |
| Withdrawal in impossible location | Critical | BLOCK + Investigation |

---

## 3️⃣ TRANSFER Transactions

### Definition
Bank-to-bank transfers, UPI payments, or peer-to-peer money transfers.

### Key Characteristics
- **Merchant Field**: Recipient account name or UPI ID
- **Amount**: Variable (₹100 - ₹100,000+)
- **Location**: Less relevant (digital transfer)
- **Fraud Risk**: Unknown recipients, high-value transfers, testing small amounts first

### Real-World Examples

#### Example 3.1: Normal Peer-to-Peer Transfer
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 2000.00, 'Priya Nair (UPI: priya@okhdfcbank)', 'Transfer');
```
**Scenario**: Arjun sends money to friend Priya  
**Risk Level**: Low (trusted recipient)

---

#### Example 3.2: Suspicious Transfer Pattern (Testing Limits)
```sql
-- Small test transfer
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 100.00, 'Unknown Account X', 'Transfer');

-- Repeat to different accounts
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 100.00, 'Unknown Account Y', 'Transfer'),
  (1, 1, 100.00, 'Unknown Account Z', 'Transfer');

-- Once confirmed working, large transfer
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 50000.00, 'Unknown Account X', 'Transfer');
```
**Scenario**: Fraudster testing if stolen card works by sending small amounts  
**Risk Level**: **HIGH** (multiple unknown recipients, pattern of testing)  
**Detection**: Analytics view alerts on velocity of unknown recipients

---

#### Example 3.3: High-Value Transfer
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 75000.00, 'Business Account - XYZ Corp', 'Transfer');
```
**Scenario**: Arjun transfers large amount to business partner  
**Risk Level**: Medium-High (large amount, needs verification)  
**Detection**: Risk score evaluates against history and daily limits

---

#### Example 3.4: Suspicious Recipient (Blacklisted Account)
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES 
  (1, 1, 25000.00, 'Crime Network Account', 'CRIMINAL_ACC_88', 'Transfer');
```
**Scenario**: Transfer to known criminal account  
**Risk Level**: **CRITICAL**  
**Detection**: `fn_blacklist_check()` blocks (MERCHANT blacklist type)

---

### Transfer Transaction Patterns

| Pattern | Risk | Action |
|---------|------|--------|
| Series of small transfers to unknown accounts | High | Alert + Monitor |
| Single transfer > ₹100,000 | Medium | Alert + Risk eval |
| Transfer to blacklisted account | Critical | BLOCK |
| Transfer followed by ATM withdrawal | High | Alert (suspicious pattern) |
| Multiple transfers in 5 minutes | Medium | Alert + Velocity check |

---

## 4️⃣ ONLINE Transactions

### Definition
E-commerce purchases, subscription payments, online services, or digital goods.

### Key Characteristics
- **Merchant**: E-commerce platforms (Amazon, Flipkart, Netflix, etc.)
- **Amount**: Highly variable (₹10 - ₹100,000+)
- **Location**: Not applicable (digital, no physical location)
- **Fraud Risk**: Velocity breaches, account takeover, stolen card testing

### Real-World Examples

#### Example 4.1: Normal E-Commerce Purchase
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 1299.00, 'Amazon India - Headphones', 'Online');
```
**Scenario**: Arjun buys electronics from Amazon  
**Risk Level**: Low (established merchant, normal amount)

---

#### Example 4.2: Subscription Purchase
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (2, 3, 499.00, 'Netflix - Monthly Subscription', 'Online');
```
**Scenario**: Priya's recurring Netflix subscription  
**Risk Level**: Low (known merchant, recurring, predictable)

---

#### Example 4.3: Rapid Online Purchases (Velocity Breach)
```sql
-- Multiple online purchases in quick succession
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 3000.00, 'Flipkart - Laptop', 'Online'),
  (1, 1, 2500.00, 'Amazon - Camera', 'Online'),
  (1, 1, 1500.00, 'Myntra - Clothing', 'Online'),
  (1, 1, 999.00,  'eBay India - Electronics', 'Online'),
  (1, 1, 2000.00, 'Indigo Airlines - Booking', 'Online'),
  (1, 1, 5000.00, 'OYO Rooms - Hotel', 'Online');  -- 6th txn triggers alert
```
**Scenario**: Fraudster using stolen card for rapid online shopping spree  
**Risk Level**: **CRITICAL**  
**Detection**: `fn_velocity_check()` fires on 6th transaction

---

#### Example 4.4: Suspicious Online Purchase Pattern
```sql
-- Low-cost test purchases at different merchants
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1, 1, 50.00,   'Aliexpress - Test Item', 'Online'),
  (1, 1, 75.00,   'Shopee - Test Item', 'Online'),
  (1, 1, 100.00,  'eBay - Test Item', 'Online');

-- Then large purchase
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 50000.00, 'Flipkart - High-Value Electronics', 'Online');
```
**Scenario**: Testing if stolen card works before making large purchase  
**Risk Level**: **HIGH**  
**Detection**: Analytics pattern recognition

---

#### Example 4.5: Account Takeover - Unusual Online Purchase
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES 
  (1, 1, 25000.00, 'Gaming Store - Gift Cards', 'Online');
```
**Scenario**: Arjun (normally buys groceries) suddenly buys gift cards  
**Anomaly**: Out-of-character purchase behavior  
**Risk Level**: **MEDIUM-HIGH**  
**Detection**: Risk scoring + Historical behavior analysis

---

#### Example 4.6: Darknet Purchase (Blacklisted Merchant)
```sql
INSERT INTO Transactions 
  (UserID, DeviceID, Amount, Merchant, Merchant_ID, Txn_Type) 
VALUES 
  (5, 5, 3000.00, 'Illegal Marketplace', 'DARK_MARKET_XYZ', 'Online');
```
**Scenario**: Card used at known darknet site  
**Risk Level**: **CRITICAL**  
**Detection**: `fn_blacklist_check()` blocks transaction

---

### Online Transaction Patterns

| Pattern | Risk | Action |
|---------|------|--------|
| 6+ online purchases in 10 min | Critical | Alert + Block |
| Low-value test purchases | High | Monitor + Risk eval |
| Unusual merchant category | Medium | Alert + Pattern analysis |
| High-value online purchase | Medium | Alert if unusual |
| Purchase from blacklisted merchant | Critical | BLOCK |
| Late-night/unusual-hours purchase | Low-Medium | Monitor if pattern |

---

## 📊 Transaction Type Comparison Matrix

| Aspect | Purchase | Withdrawal | Transfer | Online |
|--------|----------|-----------|----------|--------|
| **Merchant Field** | Populated | Bank/ATM name | Account/UPI | E-commerce site |
| **Location Data** | Yes (GPS) | Yes (ATM location) | No | No |
| **Typical Amount** | ₹100 - ₹50K | ₹1K - ₹50K | ₹100 - ₹100K+ | ₹10 - ₹100K+ |
| **Device Req'd** | Card/Mobile | Card/Mobile | Mobile/Web | Web/Mobile |
| **Reversible** | Yes (7-30 days) | Difficult | Difficult | Yes (up to 60 days) |
| **Fraud Risk** | Medium | High | High | Medium-High |
| **Velocity Breach** | Very likely | Possible | Likely | Very likely |
| **Impossible Travel** | Yes (geo-based) | Yes (geo-based) | No | No |
| **Blacklist Check** | Yes | Yes | Yes | Yes |
| **Risk Score Impact** | Medium | High | High | Medium |

---

## 🔍 Real-World Fraud Scenarios by Type

### Scenario A: Stolen Card at Shopping Mall
```
Transaction 1 (14:05): Purchase at Westside Delhi - ₹3500 - NORMAL
Transaction 2 (14:12): Purchase at Shopper's Stop Delhi - ₹2800 - NORMAL  
Transaction 3 (14:19): Purchase at FBB Delhi - ₹4200 - ALERT (3 in 14 min)
Transaction 4 (14:25): Purchase at Lifestyle Delhi - ₹3900 - ALERT (4 in 20 min)
Transaction 5 (14:31): Purchase at Nike Store Delhi - ₹5600 - ALERT (5 in 26 min)
Transaction 6 (14:38): Purchase at Bata Delhi - ₹2100 - ⚠️ CRITICAL (6 in 33 min) → VELOCITY BREACH
```
**Trigger**: `fn_velocity_check()` on 6th transaction  
**Action**: Alert Medium → Risk Score +5  
**Outcome**: User account flagged, transactions monitored

---

### Scenario B: Impossible Travel Fraud
```
Transaction 1 (15:30): Online purchase from Coimbatore (11.01°N, 76.95°E) - ₹2000
Transaction 2 (15:35): Withdrawal in Mumbai (19.07°N, 72.87°E) - ₹5000
Distance: 1756 km | Time: 5 minutes | Speed Required: 21,072 km/h (IMPOSSIBLE)
```
**Trigger**: `fn_geospatial_check()` on 2nd transaction  
**Action**: Alert Critical → Risk Score +20 → Account Suspended  
**Outcome**: Transaction blocked, user notified

---

### Scenario C: Account Takeover via Transfers
```
Day 1:
  14:00 - Transfer ₹100 to Unknown Acc A - SUCCESS (testing)
  14:05 - Transfer ₹100 to Unknown Acc B - SUCCESS  
  14:10 - Transfer ₹100 to Unknown Acc C - SUCCESS  

Day 2:
  09:00 - Transfer ₹50,000 to Unknown Acc A - FLAGGED (pattern detected)
  09:15 - Transfer ₹50,000 to Unknown Acc B - FLAGGED  
  09:30 - Transfer ₹50,000 to Unknown Acc C - ⚠️ POSSIBLE BLOCK
```
**Pattern**: Small test transfers followed by large transfers  
**Detection**: Analytics + Risk evaluation  
**Action**: Alert High → Require 2FA verification

---

### Scenario D: Testing Before Large Online Purchase
```
13:00 - Online purchase ₹50 at Aliexpress - SUCCESS
13:05 - Online purchase ₹75 at Shopee - SUCCESS
13:10 - Online purchase ₹100 at eBay - SUCCESS
13:15 - Online purchase ₹50,000 at Electronics Store - ⚠️ FLAGGED
```
**Pattern**: Escalating test purchases  
**Detection**: Velocity check + Amount anomaly  
**Action**: Alert Medium → Manual review

---

## 🛡️ Transaction Validation Checklist

### For Each Transaction Type:

#### Purchase
- [ ] Merchant name is valid (not blacklisted)
- [ ] Amount within daily limit
- [ ] Location coordinates make sense
- [ ] Not 6+ transactions in 10 minutes from same user
- [ ] Device is trusted or recently used
- [ ] IP address not blacklisted

#### Withdrawal
- [ ] ATM/bank location is valid
- [ ] Amount is reasonable (not exceeding daily limit by too much)
- [ ] Not immediately after large online purchase
- [ ] ATM not blacklisted
- [ ] No impossible travel from last transaction
- [ ] Device trusted

#### Transfer
- [ ] Recipient account exists
- [ ] Recipient not on blacklist
- [ ] Amount within user's daily limit
- [ ] Not testing pattern (multiple small transfers)
- [ ] Device is trusted
- [ ] Time of day is reasonable for user

#### Online
- [ ] Merchant domain is legitimate (not spoofed)
- [ ] Not 6+ purchases in 10 minutes
- [ ] Merchant not blacklisted
- [ ] Amount within daily online limit
- [ ] No suspicious pattern (test purchases before large buy)
- [ ] Device/IP not known for fraud

---

## 📝 SQL Examples for Testing Each Type

### Insert Test Transactions
```sql
-- Safe Purchase Transaction
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 1, 1500.00, 'Big Bazaar', 'Coimbatore', 11.0168, 76.9558, 'Purchase');

-- Safe Withdrawal
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) 
VALUES (1, 2, 5000.00, 'SBI ATM', 'Coimbatore', 11.0168, 76.9558, 'Withdrawal');

-- Safe Transfer
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 2000.00, 'Friend Account', 'Transfer');

-- Safe Online Purchase
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) 
VALUES (1, 1, 999.00, 'Amazon India', 'Online');
```

### Query Active Alerts
```sql
SELECT * FROM Fraud_Alerts 
WHERE Is_Reviewed = FALSE 
ORDER BY Severity DESC, Alert_Timestamp DESC;
```

### View User Risk Profile
```sql
SELECT * FROM vw_user_risk_summary 
WHERE UserID = 1;
```

---

## 🎯 Key Takeaways

1. **Each transaction type has unique fraud patterns**:
   - Purchase/Online: Velocity & Impossible travel
   - Withdrawal: Impossible travel & Large amounts
   - Transfer: Unknown recipients & Testing patterns
   - All: Blacklist checks

2. **Real-time detection happens via triggers**:
   - `fn_velocity_check()`: Catches rapid-fire fraud
   - `fn_geospatial_check()`: Catches impossible travel
   - `fn_blacklist_check()`: Catches known bad actors
   - `fn_audit_users()`: Maintains audit trail

3. **Risk scoring is multi-factor**:
   - Alert history (past suspicious activity)
   - Daily spending vs. limit
   - Recent critical alerts
   - Unusual behavior for user type

4. **Block happens at trigger level** (RETURN NULL), **but alerts go to analysts** for review

---

**Last Updated**: 2026-04-28  
**Transaction Types Documented**: 4  
**Real-World Examples**: 20+  
**Fraud Patterns Covered**: 15+  
**Status**: ✅ Production Ready
