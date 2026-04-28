# ============================================================
#  SentinelDB  |  Module 5: Python Application Layer
#  File: app/sentinel_db.py
# ============================================================
#
#  TECH STACK EXPLAINED:
#
#  psycopg2
#    The most popular PostgreSQL adapter for Python.
#    It translates Python calls into the PostgreSQL wire
#    protocol. Always use parameterized queries (%s) —
#    NEVER format SQL strings with f-strings or .format()
#    because that opens you to SQL Injection attacks.
#
#  SQL Injection Example (NEVER do this):
#    BAD:  cursor.execute(f"SELECT * FROM Users WHERE Name = '{name}'")
#    If name = "'; DROP TABLE Users; --" → your table is gone.
#    GOOD: cursor.execute("SELECT * FROM Users WHERE Name = %s", (name,))
#    psycopg2 escapes the value safely.
#
#  Connection Pooling (psycopg2.pool):
#    Creating a new DB connection for every request is slow
#    (~50–100ms each). A pool keeps N connections alive and
#    reuses them. SimpleConnectionPool gives min/max limits.
# ============================================================

import psycopg2
import psycopg2.pool
import psycopg2.extras   # for RealDictCursor (rows as dicts)
from contextlib import contextmanager
from datetime import datetime
from typing import Optional, List, Dict, Any
import logging
import os

# Configure logging — in production, log to a file
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger('SentinelDB')


# ============================================================
#  DATABASE CONFIGURATION
#  In production, load these from environment variables.
#  NEVER hardcode credentials in source code.
# ============================================================
DB_CONFIG = {
    'host':     os.getenv('DB_HOST',     'localhost'),
    'port':     int(os.getenv('DB_PORT', '5432')),
    'dbname':   os.getenv('DB_NAME',     'sentineldb'),
    'user':     os.getenv('DB_USER',     'postgres'),
    'password': os.getenv('DB_PASSWORD', 'POSTGRES'),
}


# ============================================================
#  DATABASE MANAGER CLASS
#  Wraps psycopg2 with a connection pool and helper methods.
# ============================================================
class DatabaseManager:
    """
    Manages PostgreSQL connections using a connection pool.
    Use as a context manager or call methods directly.
    """

    def __init__(self, min_conn: int = 1, max_conn: int = 10):
        """
        Initialize connection pool.
        min_conn: connections kept alive even when idle
        max_conn: maximum simultaneous connections
        """
        try:
            self._pool = psycopg2.pool.SimpleConnectionPool(
                min_conn,
                max_conn,
                **DB_CONFIG
            )
            logger.info(f"Connection pool created (min={min_conn}, max={max_conn})")
        except psycopg2.Error as e:
            logger.error(f"Failed to create connection pool: {e}")
            raise

    @contextmanager
    def get_connection(self):
        """
        Context manager that borrows a connection from the pool,
        yields it, then returns it when done.

        Usage:
            with db.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
        """
        conn = self._pool.getconn()
        try:
            yield conn
            conn.commit()          # auto-commit on success
        except Exception as e:
            conn.rollback()        # auto-rollback on error
            logger.error(f"Transaction rolled back: {e}")
            raise
        finally:
            self._pool.putconn(conn)   # always return to pool

    @contextmanager
    def get_cursor(self, dict_cursor: bool = True):
        """
        Shortcut: yields a cursor directly.
        dict_cursor=True → rows returned as dicts (column: value)
        dict_cursor=False → rows returned as tuples
        """
        with self.get_connection() as conn:
            cursor_factory = psycopg2.extras.RealDictCursor if dict_cursor else None
            with conn.cursor(cursor_factory=cursor_factory) as cur:
                yield cur

    def close(self):
        """Close all connections in the pool."""
        self._pool.closeall()
        logger.info("Connection pool closed")


# ============================================================
#  TRANSACTION SERVICE
#  Business logic for inserting and reading transactions.
# ============================================================
class TransactionService:

    def __init__(self, db: DatabaseManager):
        self.db = db

    def insert_transaction(
        self,
        user_id:       int,
        amount:        float,
        txn_type:      str,
        merchant:      str       = None,
        merchant_id:   str       = None,
        location_city: str       = None,
        latitude:      float     = None,
        longitude:     float     = None,
        device_id:     int       = None,
        currency:      str       = 'INR',
    ) -> Dict[str, Any]:
        """
        Insert a new transaction. The triggers in PostgreSQL
        will automatically run fraud checks after this INSERT.

        Returns the inserted transaction row plus any alerts
        that were generated by the triggers.
        """
        sql = """
            INSERT INTO Transactions (
                UserID, DeviceID, Amount, Currency,
                Merchant, Merchant_ID,
                Location_City, Latitude, Longitude,
                Txn_Type
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING TxnID, Is_Flagged, Txn_Timestamp
        """
        params = (
            user_id, device_id, amount, currency,
            merchant, merchant_id,
            location_city, latitude, longitude,
            txn_type
        )

        with self.db.get_cursor() as cur:
            cur.execute(sql, params)
            result = cur.fetchone()
            txn_id     = result['txnid']
            is_flagged = result['is_flagged']

            # Fetch any alerts the triggers just created
            alerts = self._get_alerts_for_txn(cur, txn_id)

            logger.info(
                f"Transaction {txn_id} inserted | "
                f"User={user_id} | Amount={amount} | "
                f"Flagged={is_flagged} | Alerts={len(alerts)}"
            )

            return {
                'txn_id':    txn_id,
                'is_flagged': is_flagged,
                'alerts':    alerts,
                'timestamp': result['txn_timestamp'].isoformat()
            }

    def _get_alerts_for_txn(self, cur, txn_id: int) -> List[Dict]:
        """Fetch fraud alerts linked to a specific transaction."""
        cur.execute("""
            SELECT AlertID, Alert_Type, Severity, Description
            FROM   Fraud_Alerts
            WHERE  TxnID = %s
            ORDER  BY Alert_Timestamp DESC
        """, (txn_id,))
        return [dict(row) for row in cur.fetchall()]

    def get_user_transactions(
        self,
        user_id: int,
        limit: int = 50,
        flagged_only: bool = False
    ) -> List[Dict]:
        """Fetch recent transactions for a user."""
        sql = """
            SELECT
                t.TxnID, t.Amount, t.Currency, t.Merchant,
                t.Location_City, t.Txn_Type, t.Txn_Status,
                t.Is_Flagged, t.Txn_Timestamp,
                d.Device_Name, d.Device_Type, d.IP_Address
            FROM   Transactions t
            LEFT   JOIN Devices d ON t.DeviceID = d.DeviceID
            WHERE  t.UserID = %s
            {flagged_filter}
            ORDER  BY t.Txn_Timestamp DESC
            LIMIT  %s
        """.format(
            flagged_filter="AND t.Is_Flagged = TRUE" if flagged_only else ""
        )

        with self.db.get_cursor() as cur:
            cur.execute(sql, (user_id, limit))
            return [dict(row) for row in cur.fetchall()]

    def get_velocity_stats(self, user_id: int) -> Dict:
        """
        How many transactions has this user made in the last 10 min?
        Uses the window function query from Module 4.
        """
        sql = """
            SELECT
                COUNT(*)        AS txn_count_10min,
                SUM(Amount)     AS total_amount_10min,
                MAX(Txn_Timestamp) AS last_txn_time
            FROM Transactions
            WHERE UserID        = %s
            AND   Txn_Timestamp >= NOW() - INTERVAL '10 minutes'
            AND   Txn_Status    = 'Completed'
        """
        with self.db.get_cursor() as cur:
            cur.execute(sql, (user_id,))
            return dict(cur.fetchone())


# ============================================================
#  USER SERVICE
#  Business logic for reading users and calling procedures.
# ============================================================
class UserService:

    def __init__(self, db: DatabaseManager):
        self.db = db

    def get_all_users(self, status_filter: str = None) -> List[Dict]:
        """Fetch users with optional status filter."""
        sql = """
            SELECT * FROM vw_user_risk_summary
            {where}
            ORDER BY Risk_Score DESC
        """.format(
            where=f"WHERE Account_Status = %s" if status_filter else ""
        )

        with self.db.get_cursor() as cur:
            if status_filter:
                cur.execute(sql, (status_filter,))
            else:
                cur.execute(sql)
            return [dict(row) for row in cur.fetchall()]

    def get_user_by_id(self, user_id: int) -> Optional[Dict]:
        """Fetch a single user's full risk summary."""
        with self.db.get_cursor() as cur:
            cur.execute(
                "SELECT * FROM vw_user_risk_summary WHERE UserID = %s",
                (user_id,)
            )
            row = cur.fetchone()
            return dict(row) if row else None

    def evaluate_risk(self, user_id: int) -> Dict:
        """
        Call the sp_evaluate_user_risk stored procedure.

        DBMS CONCEPT: Calling procedures from Python
        Procedures with OUT parameters are called differently
        than regular queries. We use a SELECT on the procedure
        call or use psycopg2's callproc for functions.
        For procedures with OUT params, the cleanest approach
        is to wrap the CALL in a SELECT via a DO block or
        use a function wrapper.
        """
        sql = """
            DO $$
            DECLARE
                v_score  NUMERIC;
                v_action TEXT;
            BEGIN
                CALL sp_evaluate_user_risk(%s, v_score, v_action);
                RAISE NOTICE 'Score: %% | Action: %%', v_score, v_action;
            END;
            $$;
        """
        # Alternative: use a helper function that wraps the procedure
        sql_fn = """
            SELECT * FROM (
                SELECT
                    Risk_Score,
                    Account_Status,
                    Risk_Level
                FROM Users WHERE UserID = %s
            ) before_call;
        """
        with self.db.get_cursor() as cur:
            # Call the procedure
            cur.execute("CALL sp_evaluate_user_risk(%s, NULL, NULL)", (user_id,))

            # Fetch updated user state
            cur.execute(
                "SELECT UserID, Name, Risk_Score, Risk_Level, Account_Status FROM Users WHERE UserID = %s",
                (user_id,)
            )
            return dict(cur.fetchone())

    def get_high_risk_users(self, min_score: float = 75) -> List[Dict]:
        """Fetch users with risk score above threshold."""
        with self.db.get_cursor() as cur:
            cur.execute("""
                SELECT UserID, Name, Email, Risk_Score, Risk_Level,
                       Account_Status, Unreviewed_Alerts
                FROM   vw_user_risk_summary
                WHERE  Risk_Score >= %s
                ORDER  BY Risk_Score DESC
            """, (min_score,))
            return [dict(row) for row in cur.fetchall()]


# ============================================================
#  ALERT SERVICE
#  Business logic for reading and reviewing alerts.
# ============================================================
class AlertService:

    def __init__(self, db: DatabaseManager):
        self.db = db

    def get_active_alerts(
        self,
        severity:   str  = None,
        limit:      int  = 100,
        unreviewed: bool = True
    ) -> List[Dict]:
        """Fetch alerts from the vw_active_alerts view."""
        conditions = []
        params = []

        if unreviewed:
            conditions.append("Is_Reviewed = FALSE")
        if severity:
            conditions.append("Severity = %s")
            params.append(severity)

        where = "WHERE " + " AND ".join(conditions) if conditions else ""

        sql = f"""
            SELECT * FROM vw_active_alerts
            {where}
            LIMIT %s
        """
        params.append(limit)

        with self.db.get_cursor() as cur:
            cur.execute(sql, tuple(params))
            return [dict(row) for row in cur.fetchall()]

    def review_alert(self, alert_id: int, analyst: str = 'dashboard') -> bool:
        """Mark an alert as reviewed by calling the stored procedure."""
        with self.db.get_cursor() as cur:
            cur.execute(
                "CALL sp_review_alert(%s, %s)",
                (alert_id, analyst)
            )
            return True

    def get_alert_trends(self, days: int = 30) -> List[Dict]:
        """Fetch daily alert counts for dashboard charts."""
        with self.db.get_cursor() as cur:
            cur.execute("""
                SELECT
                    DATE(Alert_Timestamp)   AS alert_date,
                    Alert_Type,
                    Severity,
                    COUNT(*)                AS count
                FROM Fraud_Alerts
                WHERE Alert_Timestamp >= NOW() - INTERVAL '%s days'
                GROUP BY DATE(Alert_Timestamp), Alert_Type, Severity
                ORDER BY alert_date DESC
            """, (days,))
            return [dict(row) for row in cur.fetchall()]

    def get_summary_stats(self) -> Dict:
        """Summary numbers for the dashboard header cards."""
        with self.db.get_cursor() as cur:
            cur.execute("""
                SELECT
                    COUNT(*)                                        AS total_alerts,
                    COUNT(*) FILTER (WHERE Is_Reviewed = FALSE)    AS unreviewed,
                    COUNT(*) FILTER (WHERE Severity = 'Critical')  AS critical,
                    COUNT(*) FILTER (WHERE Severity = 'High')      AS high,
                    COUNT(DISTINCT UserID)                         AS affected_users
                FROM Fraud_Alerts
                WHERE Alert_Timestamp >= NOW() - INTERVAL '24 hours'
            """)
            return dict(cur.fetchone())


# ============================================================
#  FACTORY — creates and wires all services together
# ============================================================
def create_app() -> Dict[str, Any]:
    """
    Initialize the database and all service objects.
    Returns a dict of services ready to use.
    """
    db = DatabaseManager(min_conn=2, max_conn=10)
    return {
        'db':           db,
        'transactions': TransactionService(db),
        'users':        UserService(db),
        'alerts':       AlertService(db),
    }


# ============================================================
#  QUICK TEST — run with: python sentinel_db.py
# ============================================================
if __name__ == '__main__':
    print("Testing SentinelDB application layer...")

    try:
        app = create_app()
        txn_svc   = app['transactions']
        user_svc  = app['users']
        alert_svc = app['alerts']

        # Test 1: Insert a normal transaction
        print("\n[TEST 1] Inserting normal transaction...")
        result = txn_svc.insert_transaction(
            user_id=1, amount=500, txn_type='Purchase',
            merchant='Reliance Fresh', location_city='Coimbatore',
            latitude=11.0168, longitude=76.9558, device_id=1
        )
        print(f"  → TxnID={result['txn_id']} | Flagged={result['is_flagged']} | Alerts={len(result['alerts'])}")

        # Test 2: Simulate impossible travel (Chennai → Delhi instantly)
        print("\n[TEST 2] Simulating impossible travel...")
        result = txn_svc.insert_transaction(
            user_id=2, amount=15000, txn_type='Online',
            merchant='Mystery Shop', location_city='Delhi',
            latitude=28.6139, longitude=77.2090, device_id=3
        )
        print(f"  → TxnID={result['txn_id']} | Flagged={result['is_flagged']} | Alerts={len(result['alerts'])}")
        for alert in result['alerts']:
            print(f"    ⚠ [{alert['severity']}] {alert['alert_type']}: {alert['description'][:60]}...")

        # Test 3: Fetch summary stats
        print("\n[TEST 3] Alert summary (last 24h)...")
        stats = alert_svc.get_summary_stats()
        print(f"  → Total={stats['total_alerts']} | Unreviewed={stats['unreviewed']} | Critical={stats['critical']}")

        # Test 4: High risk users
        print("\n[TEST 4] High risk users...")
        risky = user_svc.get_high_risk_users(min_score=40)
        for u in risky:
            print(f"  → {u['name']} | Score={u['risk_score']} | Status={u['account_status']}")

        app['db'].close()
        print("\n✓ All tests passed!")

    except Exception as e:
        print(f"\n✗ Error: {e}")
        print("Make sure PostgreSQL is running and the schema is loaded.")
