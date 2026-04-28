# 🛡️ SentinelDB — Real-Time Fraud Detection System
### DBMS College Project | PostgreSQL + Python + Streamlit

---

## Project Structure

```
sentineldb/
│
├── sql/
│   ├── 01_schema.sql           ← Tables, constraints, indexes (3NF)
│   ├── 02_triggers.sql         ← Velocity, Geo, Blacklist, Audit triggers
│   ├── 03_procedures_views.sql ← Stored procedures + Views
│   └── 04_window_functions.sql ← Analytical SQL queries
│
├── app/
│   └── sentinel_db.py          ← Python DB layer (psycopg2)
│
├── dashboard/
│   └── app.py                  ← Streamlit web dashboard
│
├── requirements.txt
└── README.md
```

---

## Setup Guide (Step by Step)

### Step 1 — Install PostgreSQL
Download from: https://www.postgresql.org/download/
- Windows: use the installer, remember your password
- Default port: 5432

### Step 2 — Create the database
Open pgAdmin or psql terminal:
```sql
CREATE DATABASE sentineldb;
```

### Step 3 — Load the SQL files in order
In pgAdmin: open each file, select the sentineldb database, click Run (F5).
Or via terminal:
```bash
psql -U postgres -d sentineldb -f sql/01_schema.sql
psql -U postgres -d sentineldb -f sql/02_triggers.sql
psql -U postgres -d sentineldb -f sql/03_procedures_views.sql
psql -U postgres -d sentineldb -f sql/04_window_functions.sql
```

### Step 4 — Install Python dependencies
```bash
pip install -r requirements.txt
```

### Step 5 — Configure database credentials
In `app/sentinel_db.py`, update DB_CONFIG or set environment variables:
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=sentineldb
export DB_USER=postgres
export DB_PASSWORD=your_password
```

### Step 6 — Run the dashboard
```bash
streamlit run dashboard/app.py
```
Open browser at: http://localhost:8501

> **Note:** The dashboard runs in MOCK DATA mode by default.
> Set `USE_MOCK_DATA = False` in `dashboard/app.py` to use live PostgreSQL.

---

## DBMS Concepts Covered (For Your Viva)

### 1. Normalization (3NF)
- **1NF**: All columns atomic. No repeating groups.
- **2NF**: No partial dependencies (all non-keys depend on the full PK).
- **3NF**: No transitive dependencies (columns depend only on PK, not on other non-keys).
- Example: `Location_City` in Transactions is the city of the transaction, not the user's home city — no transitive dependency.

### 2. ACID Properties
| Property | How SentinelDB Uses It |
|----------|----------------------|
| Atomicity | A transaction insert + trigger insert to Fraud_Alerts are one atomic unit |
| Consistency | CHECK constraints ensure valid statuses, amounts > 0 |
| Isolation | FOR UPDATE locks user row during risk evaluation |
| Durability | PostgreSQL WAL (Write-Ahead Log) ensures data survives crashes |

### 3. Triggers
| Trigger | Event | Type | Purpose |
|---------|-------|------|---------|
| trg_velocity_check | INSERT on Transactions | BEFORE | Flag rapid transactions |
| trg_geospatial_check | INSERT on Transactions | BEFORE | Detect impossible travel |
| trg_blacklist_check | INSERT on Transactions | BEFORE | Block blacklisted IPs/merchants |
| trg_audit_users | UPDATE on Users | AFTER | Log all sensitive changes |

### 4. Stored Procedures
| Procedure | Purpose |
|-----------|---------|
| sp_evaluate_user_risk | Compute risk score, auto-suspend if score > 85 |
| sp_bulk_risk_evaluation | Loop through all users, run nightly |
| sp_review_alert | Mark alert reviewed, restore trust if all clear |

### 5. Views vs Materialized Views
- **VIEW** (`vw_active_alerts`, `vw_user_risk_summary`): Computed live on every query. Always fresh.
- **MATERIALIZED VIEW** (`mvw_daily_fraud_stats`): Result stored on disk. Must be refreshed manually. Much faster for heavy analytics.

### 6. Window Functions
| Function | Used For |
|----------|----------|
| `LAG()` | Compare current transaction to previous one (geo check, spend spike) |
| `ROW_NUMBER()` | Sequence transactions per user |
| `SUM() OVER()` | Running total of spending |
| `PERCENT_RANK()` | Rank users by risk score |
| `NTILE(4)` | Split users into risk quartiles |

### 7. Indexes
- **B-Tree Index** (default): Used on `Email`, `Account_Status`, `IP_Address`
- **Composite Index**: `(UserID, Txn_Timestamp DESC)` — speeds up "get user's recent transactions"
- Primary keys get indexes automatically

### 8. Haversine Formula (in SQL)
Used in both the trigger and the window function query to compute great-circle distance between two GPS coordinates:
```
d = 2R × arcsin(√(sin²(Δlat/2) + cos(lat1)·cos(lat2)·sin²(Δlng/2)))
```
Where R = 6371 km (Earth's radius).

### 9. Transaction Control
- `BEGIN` / `COMMIT` / `ROLLBACK` — explicit transaction blocks
- `FOR UPDATE` — pessimistic row lock during risk score update
- `ON DELETE CASCADE` / `RESTRICT` / `SET NULL` — referential integrity actions

### 10. Three-Tier Architecture
```
[Streamlit Dashboard] ← Presentation Layer
        ↕
[Python psycopg2 app] ← Application Layer
        ↕
[PostgreSQL engine]   ← Database Layer (triggers, procedures, views)
```

---

## Test Scenarios for Your Demo

### Test 1: Velocity Breach
```sql
-- Insert 6 transactions rapidly for the same user
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Txn_Type) VALUES
  (1,1,100,'Shop A','Purchase'),
  (1,1,200,'Shop B','Purchase'),
  (1,1,300,'Shop C','Purchase'),
  (1,1,400,'Shop D','Purchase'),
  (1,1,500,'Shop E','Purchase'),
  (1,1,600,'Shop F','Purchase');  -- 6th triggers the alert

SELECT * FROM Fraud_Alerts ORDER BY Alert_Timestamp DESC LIMIT 3;
```

### Test 2: Impossible Travel
```sql
-- User 2 was in Chennai, now instantly in Delhi
INSERT INTO Transactions (UserID, DeviceID, Amount, Location_City, Latitude, Longitude, Txn_Type)
VALUES (2, 3, 15000, 'Delhi', 28.6139, 77.2090, 'Online');

SELECT * FROM Fraud_Alerts WHERE Alert_Type = 'IMPOSSIBLE_TRAVEL';
```

### Test 3: Blacklist Match (transaction gets blocked)
```sql
-- DeviceID 5 has blacklisted IP 185.220.101.5
INSERT INTO Transactions (UserID, DeviceID, Amount, Txn_Type)
VALUES (5, 5, 9999, 'Online');

-- This INSERT is CANCELLED by the trigger (RETURN NULL)
-- But the alert is still logged:
SELECT * FROM Fraud_Alerts WHERE Alert_Type = 'BLACKLIST_MATCH';
```

### Test 4: Call risk evaluation procedure
```sql
CALL sp_evaluate_user_risk(3, NULL, NULL);
SELECT Name, Risk_Score, Risk_Level, Account_Status FROM Users WHERE UserID = 3;
```

### Test 5: View the active alerts dashboard
```sql
SELECT * FROM vw_active_alerts LIMIT 10;
SELECT * FROM vw_user_risk_summary ORDER BY Risk_Score DESC;
```

---

## Quick Reference: PL/pgSQL Syntax

```sql
-- Variable declaration
DECLARE
    v_count INT;
    v_name  VARCHAR;

-- Assignment
v_count := 5;
SELECT col INTO v_count FROM table WHERE ...;

-- Conditional
IF condition THEN
    ...
ELSIF other_condition THEN
    ...
ELSE
    ...
END IF;

-- Loop over query results
FOR rec IN SELECT * FROM table LOOP
    -- use rec.column_name
END LOOP;

-- Error handling
BEGIN
    ...
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
END;

-- Format strings
FORMAT('Hello %s, score is %s', name, score)
```
