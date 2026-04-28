-- ============================================================
--  SentinelDB  |  Module 1: Schema & Normalization (3NF)
-- ============================================================
--
--  DBMS CONCEPT: Why PostgreSQL?
--  PostgreSQL is a full ACID-compliant RDBMS. ACID means:
--    A - Atomicity   : a transaction is all-or-nothing
--    C - Consistency : data always stays in a valid state
--    I - Isolation   : concurrent transactions don't corrupt each other
--    D - Durability  : committed data survives crashes
--
--  These 4 guarantees are CRITICAL for a banking system.
--  MySQL also works but PostgreSQL has better support for
--  PL/pgSQL (stored procedure language) and window functions.
-- ============================================================

-- Start fresh (for development/testing only)
DROP TABLE IF EXISTS Audit_Log       CASCADE;
DROP TABLE IF EXISTS Fraud_Alerts    CASCADE;
DROP TABLE IF EXISTS Transactions    CASCADE;
DROP TABLE IF EXISTS Devices         CASCADE;
DROP TABLE IF EXISTS Blacklist       CASCADE;
DROP TABLE IF EXISTS Users           CASCADE;

-- ============================================================
--  DBMS CONCEPT: Normalization — 1NF → 2NF → 3NF
--
--  1NF: Every column holds atomic (indivisible) values.
--       No repeating groups. Every row is unique.
--       BAD:  users(id, name, card1, card2, card3)
--       GOOD: users(id, name) + cards(id, user_id, card_no)
--
--  2NF: Must be in 1NF + every non-key attribute depends
--       on the WHOLE primary key (no partial dependencies).
--       Only matters when you have composite primary keys.
--
--  3NF: Must be in 2NF + no transitive dependencies.
--       BAD:  transactions(txn_id, user_id, user_city, amount)
--       user_city depends on user_id, not on txn_id directly.
--       FIX:  move user_city into the Users table.
--
--  Our schema is in 3NF. Every column in every table
--  depends ONLY on its own table's primary key.
-- ============================================================


-- ============================================================
--  TABLE 1: Users
--  Stores customer identity and risk profile.
--
--  DBMS CONCEPT: Data Types
--  SERIAL      = auto-incrementing integer (PostgreSQL syntax)
--  VARCHAR(n)  = variable-length string, max n characters
--  NUMERIC(p,s)= fixed precision decimal. NEVER use FLOAT
--               for money — floats have rounding errors!
--  TIMESTAMP   = date + time, no timezone info
--  CHECK       = a constraint enforced by the DB engine itself
-- ============================================================
CREATE TABLE Users (
    UserID          SERIAL          PRIMARY KEY,
    Name            VARCHAR(100)    NOT NULL,
    Email           VARCHAR(150)    UNIQUE NOT NULL,
    Phone           VARCHAR(15),
    Account_Status  VARCHAR(20)     NOT NULL DEFAULT 'Active'
                    CHECK (Account_Status IN ('Active', 'Suspended', 'Flagged')),
    Risk_Level      VARCHAR(10)     NOT NULL DEFAULT 'Low'
                    CHECK (Risk_Level IN ('Low', 'Medium', 'High')),
    Risk_Score      NUMERIC(5,2)    NOT NULL DEFAULT 0.00
                    CHECK (Risk_Score BETWEEN 0 AND 100),
    Daily_Spending_Limit NUMERIC(12,2) NOT NULL DEFAULT 10000.00,
    Created_At      TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- DBMS CONCEPT: Indexes
-- An index is a separate data structure (usually a B-Tree)
-- that lets the DB find rows without scanning the whole table.
-- Primary keys get indexes automatically.
-- Add indexes on columns you frequently filter/join on.
CREATE INDEX idx_users_email  ON Users(Email);
CREATE INDEX idx_users_status ON Users(Account_Status);


-- ============================================================
--  TABLE 2: Devices
--  Maps users to their trusted hardware fingerprints.
--  Separate table (not inside Users) because one user can
--  have MANY devices — a classic 1-to-many relationship.
--  Storing device fields inside Users would violate 1NF.
-- ============================================================
CREATE TABLE Devices (
    DeviceID        SERIAL          PRIMARY KEY,
    UserID          INT             NOT NULL
                    REFERENCES Users(UserID) ON DELETE CASCADE,
    Device_Name     VARCHAR(100),
    Device_Type     VARCHAR(50)     NOT NULL
                    CHECK (Device_Type IN ('Mobile', 'Desktop', 'POS_Terminal', 'ATM', 'Unknown')),
    IP_Address      VARCHAR(45)     NOT NULL,   -- supports IPv6 (max 45 chars)
    Mac_Address     VARCHAR(17),
    Is_Trusted      BOOLEAN         NOT NULL DEFAULT FALSE,
    Last_Seen       TIMESTAMP       NOT NULL DEFAULT NOW(),
    Registered_At   TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- DBMS CONCEPT: REFERENCES (Foreign Key)
-- UserID in Devices REFERENCES UserID in Users.
-- This enforces Referential Integrity: you cannot insert a
-- Device with a UserID that doesn't exist in Users.
-- ON DELETE CASCADE means: if the User is deleted, all their
-- Devices are automatically deleted too.

CREATE INDEX idx_devices_user   ON Devices(UserID);
CREATE INDEX idx_devices_ip     ON Devices(IP_Address);


-- ============================================================
--  TABLE 3: Blacklist
--  Reference table of known-bad IPs and merchant IDs.
--  Kept separate so triggers can do fast lookups here
--  without scanning Transactions.
-- ============================================================
CREATE TABLE Blacklist (
    BlacklistID     SERIAL          PRIMARY KEY,
    Entity_Type     VARCHAR(20)     NOT NULL
                    CHECK (Entity_Type IN ('IP', 'Merchant', 'Device')),
    Entity_Value    VARCHAR(100)    NOT NULL,
    Reason          TEXT,
    Added_At        TIMESTAMP       NOT NULL DEFAULT NOW(),
    UNIQUE(Entity_Type, Entity_Value)   -- same entity can't be blacklisted twice
);

CREATE INDEX idx_blacklist_entity ON Blacklist(Entity_Type, Entity_Value);


-- ============================================================
--  TABLE 4: Transactions
--  The heart of the system. Every financial movement lands
--  here first — then triggers fire to check for fraud.
--
--  DBMS CONCEPT: Why store Location as latitude/longitude?
--  We need to compute distance between two transactions.
--  Storing a city name as VARCHAR would make distance
--  calculations impossible inside the DB. With lat/lng we
--  can use the Haversine formula right in SQL.
-- ============================================================
CREATE TABLE Transactions (
    TxnID           SERIAL          PRIMARY KEY,
    UserID          INT             NOT NULL
                    REFERENCES Users(UserID) ON DELETE RESTRICT,
    DeviceID        INT
                    REFERENCES Devices(DeviceID) ON DELETE SET NULL,
    Amount          NUMERIC(12,2)   NOT NULL CHECK (Amount > 0),
    Currency        VARCHAR(3)      NOT NULL DEFAULT 'INR',
    Merchant        VARCHAR(150),
    Merchant_ID     VARCHAR(50),
    Location_City   VARCHAR(100),
    Latitude        NUMERIC(9,6),   -- e.g. 11.004556
    Longitude       NUMERIC(9,6),   -- e.g. 76.961632
    Txn_Type        VARCHAR(30)     NOT NULL
                    CHECK (Txn_Type IN ('Purchase', 'Withdrawal', 'Transfer', 'Online')),
    Txn_Status      VARCHAR(20)     NOT NULL DEFAULT 'Completed'
                    CHECK (Txn_Status IN ('Completed', 'Pending', 'Declined', 'Reversed')),
    Is_Flagged      BOOLEAN         NOT NULL DEFAULT FALSE,
    Txn_Timestamp   TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- ON DELETE RESTRICT: prevents deleting a User who has Transactions.
-- This protects audit history — you can't erase a fraud trail.

CREATE INDEX idx_txn_user      ON Transactions(UserID);
CREATE INDEX idx_txn_timestamp ON Transactions(Txn_Timestamp);
CREATE INDEX idx_txn_flagged   ON Transactions(Is_Flagged);
-- Composite index: speeds up "get all transactions for user X after time T"
CREATE INDEX idx_txn_user_time ON Transactions(UserID, Txn_Timestamp DESC);


-- ============================================================
--  TABLE 5: Fraud_Alerts
--  Auto-populated by triggers. Bank analysts read this table.
--  Stores WHAT rule fired, WHICH transaction triggered it,
--  and the SEVERITY — enough for analysts to act on.
-- ============================================================
CREATE TABLE Fraud_Alerts (
    AlertID         SERIAL          PRIMARY KEY,
    TxnID           INT
                    REFERENCES Transactions(TxnID) ON DELETE SET NULL
                    DEFERRABLE INITIALLY DEFERRED,
    UserID          INT             NOT NULL
                    REFERENCES Users(UserID) ON DELETE CASCADE,
    Alert_Type      VARCHAR(50)     NOT NULL,
    Severity        VARCHAR(10)     NOT NULL DEFAULT 'Medium'
                    CHECK (Severity IN ('Low', 'Medium', 'High', 'Critical')),
    Description     TEXT,
    Is_Reviewed     BOOLEAN         NOT NULL DEFAULT FALSE,
    Alert_Timestamp TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alerts_user     ON Fraud_Alerts(UserID);
CREATE INDEX idx_alerts_reviewed ON Fraud_Alerts(Is_Reviewed);
CREATE INDEX idx_alerts_severity ON Fraud_Alerts(Severity);


-- ============================================================
--  TABLE 6: Audit_Log
--  Immutable record of all sensitive actions.
--  Populated by triggers on Users and Transactions.
--  DBMS CONCEPT: Audit logs should NEVER be deleted.
--  In production you'd also REVOKE DELETE on this table.
-- ============================================================
CREATE TABLE Audit_Log (
    LogID           SERIAL          PRIMARY KEY,
    Table_Name      VARCHAR(50)     NOT NULL,
    Operation       VARCHAR(10)     NOT NULL
                    CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE')),
    Record_ID       INT,
    Old_Values      TEXT,           -- JSON snapshot of old row
    New_Values      TEXT,           -- JSON snapshot of new row
    Changed_By      VARCHAR(100)    DEFAULT current_user,
    Changed_At      TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- ============================================================
--  SAMPLE DATA — enough to test every trigger
-- ============================================================

INSERT INTO Users (Name, Email, Phone, Risk_Level, Risk_Score, Daily_Spending_Limit) VALUES
  ('Arjun Sharma',   'arjun@example.com',   '9876543210', 'Low',    10.00, 50000.00),
  ('Priya Nair',     'priya@example.com',   '9123456789', 'Medium', 45.00, 20000.00),
  ('Ravi Kumar',     'ravi@example.com',    '9988776655', 'High',   78.00, 5000.00),
  ('Deepa Menon',    'deepa@example.com',   '9871234560', 'Low',    5.00,  100000.00),
  ('Fraud Actor',    'fraud@darkweb.com',   NULL,         'High',   95.00, 1000.00);

INSERT INTO Devices (UserID, Device_Name, Device_Type, IP_Address, Is_Trusted) VALUES
  (1, 'Arjun iPhone',    'Mobile',       '192.168.1.10',  TRUE),
  (1, 'Arjun Laptop',    'Desktop',      '192.168.1.11',  TRUE),
  (2, 'Priya Android',   'Mobile',       '10.0.0.5',      TRUE),
  (3, 'Ravi POS',        'POS_Terminal', '172.16.0.99',   FALSE),
  (5, 'Unknown Device',  'Unknown',      '185.220.101.5', FALSE);  -- known Tor exit node

INSERT INTO Blacklist (Entity_Type, Entity_Value, Reason) VALUES
  ('IP',       '185.220.101.5',  'Known Tor exit node used in past fraud'),
  ('IP',       '198.54.117.200', 'Reported phishing origin'),
  ('Merchant', 'DARK_MKT_001',   'Flagged darknet marketplace'),
  ('Device',   'UNKNOWN_DEV_99', 'Device used in card skimming');

-- Normal transactions for Arjun
INSERT INTO Transactions (UserID, DeviceID, Amount, Merchant, Location_City, Latitude, Longitude, Txn_Type) VALUES
  (1, 1, 500.00,   'Reliance Fresh',    'Coimbatore', 11.0168, 76.9558, 'Purchase'),
  (1, 1, 1200.00,  'Amazon India',      'Coimbatore', 11.0168, 76.9558, 'Online'),
  (2, 3, 3000.00,  'Flipkart',          'Chennai',    13.0827, 80.2707, 'Online'),
  (4, NULL, 50000.00, 'HDFC Bank ATM',  'Bangalore',  12.9716, 77.5946, 'Withdrawal');
