# ============================================================
#  SentinelDB  |  Module 6: Streamlit Dashboard
#  File: dashboard/app.py
#
#  Run with: streamlit run dashboard/app.py
#
#  TECH STACK: Streamlit
#  Streamlit is a Python library that turns Python scripts
#  into interactive web apps with zero HTML/CSS/JS.
#  Every time the user interacts (clicks, selects), the
#  entire script reruns from top to bottom.
#  st.session_state persists data across reruns.
#
#  Install: pip install streamlit psycopg2-binary pandas plotly
# ============================================================

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import sys
import os

# Add parent directory to path so we can import sentinel_db
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---- Page config (must be the first Streamlit call) --------
st.set_page_config(
    page_title="SentinelDB — Fraud Monitor",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ---- Custom CSS for a dark security-themed look ------------
st.markdown("""
<style>
    /* Dark background */
    .stApp { background-color: #0d1117; color: #c9d1d9; }

    /* Metric cards */
    div[data-testid="metric-container"] {
        background: #161b22;
        border: 1px solid #30363d;
        border-radius: 8px;
        padding: 16px;
    }

    /* Severity badges */
    .badge-critical { background:#ff4b4b; color:#fff; padding:2px 8px; border-radius:12px; font-size:12px; font-weight:bold; }
    .badge-high     { background:#ff8c00; color:#fff; padding:2px 8px; border-radius:12px; font-size:12px; font-weight:bold; }
    .badge-medium   { background:#ffd700; color:#000; padding:2px 8px; border-radius:12px; font-size:12px; }
    .badge-low      { background:#28a745; color:#fff; padding:2px 8px; border-radius:12px; font-size:12px; }

    /* Table styling */
    .dataframe { font-size: 13px; }

    /* Sidebar */
    section[data-testid="stSidebar"] { background-color: #161b22; }
</style>
""", unsafe_allow_html=True)


# ============================================================
#  MOCK DATA MODE
#  If PostgreSQL is not running, the dashboard uses mock data
#  so you can still demo the UI to your professor.
#  In production, replace get_mock_* with real DB calls.
# ============================================================
USE_MOCK_DATA = False  # Set to False when PostgreSQL is running

def get_mock_summary():
    return {
        'total_alerts': 47,
        'unreviewed': 12,
        'critical': 5,
        'high': 8,
        'affected_users': 9
    }

def get_mock_alerts():
    return pd.DataFrame([
        {'alertid': 1,  'alert_timestamp': '2024-01-15 10:23:11', 'alert_type': 'IMPOSSIBLE_TRAVEL',
         'severity': 'Critical', 'user_name': 'Ravi Kumar',    'amount': 15000, 'location_city': 'Delhi',   'is_reviewed': False, 'description': '1200 km from Chennai to Delhi in 0.1 hours (12000 km/h)'},
        {'alertid': 2,  'alert_timestamp': '2024-01-15 10:45:30', 'alert_type': 'VELOCITY_BREACH',
         'severity': 'High',     'user_name': 'Fraud Actor',   'amount': 500,   'location_city': 'Mumbai',  'is_reviewed': False, 'description': '7 transactions in 10 minutes'},
        {'alertid': 3,  'alert_timestamp': '2024-01-15 09:10:05', 'alert_type': 'BLACKLIST_MATCH',
         'severity': 'Critical', 'user_name': 'Fraud Actor',   'amount': 9999,  'location_city': None,      'is_reviewed': False, 'description': 'Blacklisted IP: 185.220.101.5 (Tor exit node)'},
        {'alertid': 4,  'alert_timestamp': '2024-01-15 08:55:00', 'alert_type': 'AUTO_SUSPENSION',
         'severity': 'Critical', 'user_name': 'Ravi Kumar',    'amount': None,  'location_city': None,      'is_reviewed': True,  'description': 'Account auto-suspended. Risk score: 92'},
        {'alertid': 5,  'alert_timestamp': '2024-01-15 07:30:22', 'alert_type': 'VELOCITY_BREACH',
         'severity': 'High',     'user_name': 'Priya Nair',    'amount': 3000,  'location_city': 'Chennai', 'is_reviewed': False, 'description': '6 transactions in 10 minutes'},
        {'alertid': 6,  'alert_timestamp': '2024-01-14 22:15:44', 'alert_type': 'IMPOSSIBLE_TRAVEL',
         'severity': 'Critical', 'user_name': 'Deepa Menon',   'amount': 50000, 'location_city': 'London',  'is_reviewed': False, 'description': '8200 km from Bangalore to London in 0.5 hours'},
    ])

def get_mock_users():
    return pd.DataFrame([
        {'userid': 1, 'name': 'Arjun Sharma',  'email': 'arjun@example.com',  'risk_score': 10, 'risk_level': 'Low',    'account_status': 'Active',    'unreviewed_alerts': 0, 'today_spent': 1700,  'daily_spending_limit': 50000},
        {'userid': 2, 'name': 'Priya Nair',    'email': 'priya@example.com',  'risk_score': 60, 'risk_level': 'Medium', 'account_status': 'Flagged',   'unreviewed_alerts': 2, 'today_spent': 18000, 'daily_spending_limit': 20000},
        {'userid': 3, 'name': 'Ravi Kumar',    'email': 'ravi@example.com',   'risk_score': 92, 'risk_level': 'High',   'account_status': 'Suspended', 'unreviewed_alerts': 1, 'today_spent': 5000,  'daily_spending_limit': 5000},
        {'userid': 4, 'name': 'Deepa Menon',   'email': 'deepa@example.com',  'risk_score': 45, 'risk_level': 'Medium', 'account_status': 'Active',    'unreviewed_alerts': 1, 'today_spent': 50000, 'daily_spending_limit': 100000},
        {'userid': 5, 'name': 'Fraud Actor',   'email': 'fraud@darkweb.com',  'risk_score': 98, 'risk_level': 'High',   'account_status': 'Suspended', 'unreviewed_alerts': 3, 'today_spent': 9999,  'daily_spending_limit': 1000},
    ])

def get_mock_trends():
    dates = pd.date_range(end=datetime.today(), periods=14).date
    rows = []
    for d in dates:
        for atype, cnt in [('VELOCITY_BREACH', 3), ('IMPOSSIBLE_TRAVEL', 2), ('BLACKLIST_MATCH', 1)]:
            rows.append({'alert_date': d, 'alert_type': atype, 'count': cnt + (hash(str(d)+atype) % 4)})
    return pd.DataFrame(rows)


# ============================================================
#  DATA LOADING (with caching)
#
#  TECH CONCEPT: st.cache_data
#  Streamlit reruns the script on every interaction.
#  @st.cache_data caches the function's return value so it
#  doesn't re-query the database on every click.
#  ttl=60 means cache expires after 60 seconds.
# ============================================================
@st.cache_data(ttl=60)
def load_alerts():
    if USE_MOCK_DATA:
        return get_mock_alerts()
    from sentinel_db import create_app
    app = create_app()
    data = app['alerts'].get_active_alerts(limit=200)
    app['db'].close()
    return pd.DataFrame(data)

@st.cache_data(ttl=60)
def load_users():
    if USE_MOCK_DATA:
        return get_mock_users()
    from sentinel_db import create_app
    app = create_app()
    data = app['users'].get_all_users()
    app['db'].close()
    return pd.DataFrame(data)

@st.cache_data(ttl=300)
def load_trends():
    if USE_MOCK_DATA:
        return get_mock_trends()
    from sentinel_db import create_app
    app = create_app()
    data = app['alerts'].get_alert_trends(days=14)
    app['db'].close()
    return pd.DataFrame(data)

@st.cache_data(ttl=30)
def load_summary():
    if USE_MOCK_DATA:
        return get_mock_summary()
    from sentinel_db import create_app
    app = create_app()
    data = app['alerts'].get_summary_stats()
    app['db'].close()
    return data


# ============================================================
#  SIDEBAR — Navigation & Filters
# ============================================================
with st.sidebar:
    st.image("https://img.icons8.com/color/96/shield.png", width=60)
    st.title("SentinelDB")
    st.caption("Real-Time Fraud Detection System")
    st.divider()

    page = st.radio(
        "Navigate",
        ["📊 Dashboard", "🚨 Fraud Alerts", "👤 User Risk Profiles",
         "📈 Analytics", "🔧 Simulate Transaction"],
        label_visibility="collapsed"
    )

    st.divider()
    st.caption(f"Last refreshed: {datetime.now().strftime('%H:%M:%S')}")
    if st.button("🔄 Refresh Data"):
        st.cache_data.clear()
        st.rerun()

    if USE_MOCK_DATA:
        st.warning("⚠️ Mock data mode\nConnect PostgreSQL to see live data")


# ============================================================
#  PAGE 1: DASHBOARD OVERVIEW
# ============================================================
if page == "📊 Dashboard":
    st.title("🛡️ SentinelDB — Fraud Detection Dashboard")
    st.caption("Real-time monitoring powered by PostgreSQL triggers & stored procedures")
    st.divider()

    # --- Summary metric cards ---
    summary = load_summary()
    col1, col2, col3, col4, col5 = st.columns(5)
    with col1:
        st.metric("🚨 Alerts (24h)",     summary['total_alerts'])
    with col2:
        st.metric("📋 Unreviewed",        summary['unreviewed'],
                  delta=f"-{summary['total_alerts'] - summary['unreviewed']} reviewed",
                  delta_color="inverse")
    with col3:
        st.metric("🔴 Critical",          summary['critical'])
    with col4:
        st.metric("🟠 High Severity",     summary['high'])
    with col5:
        st.metric("👥 Affected Users",    summary['affected_users'])

    st.divider()

    # --- Two column layout: chart + recent alerts table ---
    col_left, col_right = st.columns([3, 2])

    with col_left:
        st.subheader("Alert Trends (Last 14 Days)")
        trends_df = load_trends()
        if not trends_df.empty:
            fig = px.line(
                trends_df,
                x='alert_date', y='count',
                color='alert_type',
                markers=True,
                color_discrete_map={
                    'VELOCITY_BREACH':  '#ff8c00',
                    'IMPOSSIBLE_TRAVEL':'#ff4b4b',
                    'BLACKLIST_MATCH':  '#9b59b6'
                },
                template='plotly_dark',
                labels={'alert_date': 'Date', 'count': 'Alert Count', 'alert_type': 'Type'}
            )
            fig.update_layout(
                plot_bgcolor='#161b22',
                paper_bgcolor='#0d1117',
                font_color='#c9d1d9',
                legend=dict(orientation='h', yanchor='bottom', y=1.02)
            )
            st.plotly_chart(fig, use_container_width=True)

    with col_right:
        st.subheader("User Risk Distribution")
        users_df = load_users()
        if not users_df.empty:
            risk_counts = users_df['risk_level'].value_counts()
            fig2 = go.Figure(go.Pie(
                labels=risk_counts.index,
                values=risk_counts.values,
                hole=0.5,
                marker_colors=['#ff4b4b', '#ff8c00', '#28a745']
            ))
            fig2.update_layout(
                plot_bgcolor='#161b22',
                paper_bgcolor='#0d1117',
                font_color='#c9d1d9',
                showlegend=True,
                height=300
            )
            st.plotly_chart(fig2, use_container_width=True)


# ============================================================
#  PAGE 2: FRAUD ALERTS
# ============================================================
elif page == "🚨 Fraud Alerts":
    st.title("🚨 Fraud Alerts")

    alerts_df = load_alerts()

    # Filters
    col1, col2, col3 = st.columns(3)
    with col1:
        sev_filter = st.multiselect(
            "Severity", ['Critical', 'High', 'Medium', 'Low'],
            default=['Critical', 'High']
        )
    with col2:
        type_filter = st.multiselect(
            "Alert Type",
            alerts_df['alert_type'].unique().tolist() if not alerts_df.empty else []
        )
    with col3:
        show_reviewed = st.checkbox("Show reviewed alerts", value=False)

    # Apply filters
    filtered = alerts_df.copy()
    if sev_filter:
        filtered = filtered[filtered['severity'].isin(sev_filter)]
    if type_filter:
        filtered = filtered[filtered['alert_type'].isin(type_filter)]
    if not show_reviewed:
        filtered = filtered[filtered['is_reviewed'] == False]

    st.caption(f"Showing {len(filtered)} alerts")

    # Display each alert as an expander card
    for _, row in filtered.iterrows():
        sev_color = {
            'Critical': '🔴', 'High': '🟠', 'Medium': '🟡', 'Low': '🟢'
        }.get(row['severity'], '⚪')

        with st.expander(
            f"{sev_color} [{row['severity']}] {row['alert_type']} — "
            f"{row['user_name']} | {row['alert_timestamp']}"
        ):
            col1, col2, col3 = st.columns(3)
            with col1:
                st.write(f"**User:** {row['user_name']}")
                st.write(f"**Alert Type:** `{row['alert_type']}`")
                st.write(f"**Severity:** `{row['severity']}`")
            with col2:
                st.write(f"**Amount:** ₹{row['amount']:,.2f}" if row['amount'] else "**Amount:** N/A")
                st.write(f"**Location:** {row['location_city'] or 'N/A'}")
                st.write(f"**Reviewed:** {'✅ Yes' if row['is_reviewed'] else '❌ No'}")
            with col3:
                st.write("**Description:**")
                st.info(row['description'])

            if not row['is_reviewed']:
                if st.button(f"✅ Mark as Reviewed", key=f"review_{row['alertid']}"):
                    st.success("Alert marked as reviewed! (Connect DB to persist)")


# ============================================================
#  PAGE 3: USER RISK PROFILES
# ============================================================
elif page == "👤 User Risk Profiles":
    st.title("👤 User Risk Profiles")

    users_df = load_users()

    # Risk score bar chart
    st.subheader("Risk Score by User")
    fig = px.bar(
        users_df.sort_values('risk_score', ascending=True),
        x='risk_score', y='name',
        orientation='h',
        color='risk_level',
        color_discrete_map={'Low': '#28a745', 'Medium': '#ff8c00', 'High': '#ff4b4b'},
        template='plotly_dark',
        labels={'risk_score': 'Risk Score (0–100)', 'name': 'User'}
    )
    fig.update_layout(
        plot_bgcolor='#161b22', paper_bgcolor='#0d1117', font_color='#c9d1d9'
    )
    st.plotly_chart(fig, use_container_width=True)

    # User table
    st.subheader("User Details")
    display_cols = ['name', 'email', 'risk_score', 'risk_level',
                    'account_status', 'today_spent', 'daily_spending_limit', 'unreviewed_alerts']

    def color_status(val):
        colors = {'Active': 'color: #28a745', 'Flagged': 'color: #ff8c00', 'Suspended': 'color: #ff4b4b'}
        return colors.get(val, '')

    styled = users_df[display_cols].style.applymap(
        color_status, subset=['account_status']
    ).background_gradient(subset=['risk_score'], cmap='RdYlGn_r')

    st.dataframe(styled, use_container_width=True)


# ============================================================
#  PAGE 4: ANALYTICS
# ============================================================
elif page == "📈 Analytics":
    st.title("📈 Analytics")

    users_df  = load_users()
    alerts_df = load_alerts()

    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Alert Type Breakdown")
        if not alerts_df.empty:
            type_counts = alerts_df['alert_type'].value_counts().reset_index()
            type_counts.columns = ['alert_type', 'count']
            fig = px.pie(
                type_counts, values='count', names='alert_type',
                template='plotly_dark',
                color_discrete_sequence=px.colors.qualitative.Set2
            )
            fig.update_layout(paper_bgcolor='#0d1117', font_color='#c9d1d9')
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.subheader("Spending vs Limit")
        if not users_df.empty:
            fig = px.scatter(
                users_df,
                x='daily_spending_limit', y='today_spent',
                size='risk_score', color='risk_level',
                hover_name='name',
                color_discrete_map={'Low': '#28a745', 'Medium': '#ff8c00', 'High': '#ff4b4b'},
                template='plotly_dark',
                labels={'daily_spending_limit': 'Daily Limit (₹)', 'today_spent': 'Today Spent (₹)'}
            )
            # Add diagonal limit line
            max_val = max(users_df['daily_spending_limit'].max(), users_df['today_spent'].max())
            fig.add_shape(type='line', x0=0, y0=0, x1=max_val, y1=max_val,
                         line=dict(color='white', dash='dash'))
            fig.update_layout(paper_bgcolor='#0d1117', plot_bgcolor='#161b22', font_color='#c9d1d9')
            st.plotly_chart(fig, use_container_width=True)

    # DBMS Concept callout
    st.divider()
    st.subheader("📚 DBMS Concepts Powering This Dashboard")
    col1, col2, col3 = st.columns(3)
    with col1:
        st.info("**Triggers**\nVelocity Check, Geo Check, and Blacklist triggers fire automatically on every INSERT into Transactions — no app code needed.")
    with col2:
        st.info("**Stored Procedures**\n`sp_evaluate_user_risk` calculates risk scores and auto-suspends accounts. Called nightly via `sp_bulk_risk_evaluation`.")
    with col3:
        st.info("**Window Functions**\n`LAG()`, `SUM() OVER()`, and `PERCENT_RANK()` power the geospatial anomaly detection and transaction sequence analysis.")


# ============================================================
#  PAGE 5: SIMULATE TRANSACTION
# ============================================================
elif page == "🔧 Simulate Transaction":
    st.title("🔧 Simulate a Transaction")
    st.info("Insert a transaction and watch the trigger logic fire in real time.")

    users_df = load_users()
    user_options = {row['name']: row['userid'] for _, row in users_df.iterrows()}

    with st.form("txn_form"):
        col1, col2 = st.columns(2)
        with col1:
            selected_user = st.selectbox("User", list(user_options.keys()))
            amount        = st.number_input("Amount (₹)", min_value=1.0, value=1000.0, step=100.0)
            txn_type      = st.selectbox("Transaction Type", ['Purchase', 'Online', 'Withdrawal', 'Transfer'])
            merchant      = st.text_input("Merchant", "Example Store")
        with col2:
            city     = st.selectbox("Location", ['Coimbatore', 'Chennai', 'Mumbai', 'Delhi', 'Bangalore', 'London', 'Dubai'])
            city_coords = {
                'Coimbatore': (11.0168, 76.9558), 'Chennai': (13.0827, 80.2707),
                'Mumbai': (19.0760, 72.8777),     'Delhi': (28.6139, 77.2090),
                'Bangalore': (12.9716, 77.5946),  'London': (51.5074, -0.1278),
                'Dubai': (25.2048, 55.2708)
            }
            lat, lng = city_coords[city]
            st.write(f"📍 Coordinates: {lat}, {lng}")
            device_id = st.number_input("Device ID (optional)", min_value=0, value=0)

        submitted = st.form_submit_button("⚡ Submit Transaction")

    if submitted:
        st.subheader("Result")
        # Show what would happen
        col1, col2 = st.columns(2)
        with col1:
            st.write("**Transaction Details:**")
            st.json({
                "user": selected_user,
                "user_id": user_options[selected_user],
                "amount": amount,
                "type": txn_type,
                "merchant": merchant,
                "city": city,
                "lat": lat, "lng": lng
            })
        with col2:
            st.write("**Trigger Evaluation:**")
            user_row = users_df[users_df['name'] == selected_user].iloc[0]

            triggers_fired = []
            if user_row['unreviewed_alerts'] >= 2:
                triggers_fired.append(("VELOCITY_BREACH", "High", "User has recent velocity alerts"))
            if city in ['London', 'Dubai'] and user_row['risk_score'] > 0:
                triggers_fired.append(("IMPOSSIBLE_TRAVEL", "Critical",
                    f"Impossible travel: {city} is far from last known location"))
            if user_row['risk_score'] >= 85:
                triggers_fired.append(("AUTO_SUSPENSION", "Critical",
                    f"Risk score {user_row['risk_score']} >= 85"))

            if triggers_fired:
                for t_type, t_sev, t_desc in triggers_fired:
                    badge = '🔴' if t_sev == 'Critical' else '🟠'
                    st.error(f"{badge} **{t_type}** ({t_sev})\n\n{t_desc}")
            else:
                st.success("✅ No fraud triggers fired — transaction appears clean")

        st.info("Connect PostgreSQL to actually insert and see real trigger output.")
